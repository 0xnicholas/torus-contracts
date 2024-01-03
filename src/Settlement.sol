
pragma solidity ^0.8.23;

import "solmate/src/utils/SafeCastLib.sol";
import "openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./VaultRelayer.sol";
import "./interfaces/IAuth.sol";
import "./interfaces/IVault.sol";
import "./libraries/Interaction.sol";
import "./libraries/Order.sol";
import "./libraries/Trade.sol";
import "./libraries/Transfer.sol";
import "./mixins/Signing.sol";
import "./mixins/StorageAccessible.sol";


contract Settlement is Signing, ReentrancyGuard, StorageAccessible {

    using Order for bytes;
    using Transfer for IVault;
    using SafeCastLib for int256;
    using SafeCastLib for uint256;
    using SafeCastLib for uint256;
    // using SafeMath for uint256;

    IAuth public immutable authenticator;
    IVault public immutable vault;
    VaultRelayer public immutable vaultRelayer;

    mapping(bytes => uint256) public filledAmount;

    event Trade(
        address indexed owner,
        ERC20 sellToken,
        ERC20 buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 feeAmount,
        bytes orderUid
    );

    event Interaction(address indexed target, uint256 value, bytes4 selector);

    event Settlement(address indexed solver);

    event OrderInvalidated(address indexed owner, bytes orderUid);

    constructor(Auth authenticator_, IVault vault_) {
        authenticator = authenticator_;
        vault = vault_;
        VaultRelayer = new VaultRelayer(vault_);
    }

    receive() external payable {

    }

    modifier onlySovler() {
        require(authenticator.isSolver(msg.sender), "Torus: not a solver");
        _;
    }

    modifier onlyInteraction() {
        require(address(this) == msg.sender, "Torus: not an interaction");
    }

    /// Settle the specified orders at a clearing price. 
    function settle(
        ERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        Trade.Data[] calldata trades,
        Interaction.Data[][3] calldata interactions
    ) external nonReentrant onlySovler {
        executeInteractions(interaction[0]);

        (
            Transfer.Data[] memory inTransfers,
            Transfer.Data[] memory outTransfers
        ) = computeTradeExecutions(tokens, clearingPrices, trades);

        vaultRelayer.transferFromAccounts(inTransfers);

        executeInteractions(interactions[1]);

        vault.transferToAccounts(outTransfers);

        executeInteractions(interactions[2]);

        emit Settlement(msg.sender);
    }

    /// Settle an order directly against Balancer V2 pools.
    function swap(
        IVault.BatchSwapStep[] calldata swaps,
        ERC20[] calldata tokens,
        Trade.Data calldata trade
    ) external nonReentrant onlySovler {
        RecoveredOrder memory recoveredOrder = allocateRecoveredOrder();
        Order.Data memory order = recoveredOrder.data;
        recoverOrderFromTrade(recoveredOrder, tokens, trade);

        IVault.SwapKind kind = order.kind == Order.KIND_SELL
            ? IVault.SwapKind.GIVEN_IN
            : IVault.SwapKind.GIVEN_OUT;

        IVault.FundManagement memory funds;
        funds.sender = recoveredOrder.owner;
        funds.fromInternalBalance = 
            order.sellTokenBalance = Order.BALANCE_INTERNAL;
        funds.recipient = payable(recoveredOrder.receiver);
        funds.toInternalBalance = 
            order.buyTokenBalance = Order.BALANCE_INTERNAL;

        int256[] memory limits = new int256[](tokens.length);
        uint256 limitAmount = trade.executedAmount;

        if (order.kind == Order.KIND_SELL) {
            require(limitAmount >= order.buyAmount, "Torus: limit too low");
            limits[trade.sellTokenIndex] = order.sellAmount.toInt256();
            limits[trade.buyTokenIndex] = -limitAmount.toInt256();
        } else {
            require(limitAmount <= order.sellAmount, "Torus: limit too high");
            limits[trade.sellTokenIndex] = limitAmount.toInt256();
            limits[trade.buyTokenIndex] = -order.buyAmount.toInt256();
        }

        Transfer.Data memory feeTransfer;
        feeTransfer.account = recoveredOrder.owner;
        feeTransfer.token = order.sellToken;
        feeTransfer.amount = order.feeAmount;
        feeTransfer.balance = order.sellTokenBalance;

        int256[] memory tokenDeltas = vaultRelayer.batchSwapWithFee(
            kind,
            swaps,
            tokens,
            funds,
            limits,
            order.validTo,
            feeTransfer
        );

        bytes memory orderUid = recoveredOrder.uid;
        uint256 executedSellAmount = tokenDeltas[trade.sellTokenIndex].toUint256();
        uint256 executedBuyAmount = (-tokenDeltas[trade.buyTokenIndex]).toUint256();

        require(filledAmount[orderUid] == 0, "Torus: order filled");
        if (order.kind == Order.KIND_SELL) {
            require(
                executedSellAmount == order.sellAmount,
                "Torus: sell amount not respected"
            );
            filledAmount[orderUid] = order.sellAmount;
        } else {
            require(
                executedBuyAmount == order.buyAmount,
                "Torus: buy amount not respected"
            );
            filledAmount[orderUid] = order.buyAmount;
        }

        emit Trade(
            recoveredOrder.owner,
            order.sellToken,
            order.buyToken,
            executedSellAmount,
            executedBuyAmount,
            order.feeAmount,
            orderUid
        );
        emit Settlement(msg.sender);
    }

    /// Invalidate onchain an order that has been signed offline.
    function invalidateOrder(bytes calldata orderUid) external {
        (, address owner, ) = orderUid.extractOrderUidParams();
        require(owner == msg.sender, "Torus: caller does not own order");
        filledAmount[orderUid] = uint256(-1);
        emit OrderInvalidated(owner, orderUid);
    }

    function freeFilledAmountStorage(
        bytes[] calldata orderUids
    ) external onlyInteraction {
        freeOrderStorage(filledAmount, orderUids);
    }

    function freePreSignatureStorage(
        bytes[] calldata orderUids
    ) external onlyInteraction {
        freeOrderStorage(preSignature, orderUids);
    }

    /// Process all trades one at a time returning the computed net in and
    /// out transfers for the trades.
    function computeTradeExecutions(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        Trade.Data[] calldata trades
    )
        internal
        returns (
            Transfer.Data[] memory inTransfers,
            Transfer.Data[] memory outTransfers
        )
    {
        RecoveredOrder memory recoveredOrder = allocateRecoveredOrder();

        inTransfers = new Transfer.Data[](trades.length);
        outTransfers = new Transfer.Data[](trades.length);

        for (uint256 i; i < trades.length; ++i) {
            Trade.Data calldata trade = trades[i];

            recoverOrderFromTrade(recoveredOrder, tokens, trade);
            computeTradeExecution(
                recoveredOrder,
                clearingPrices[trade.sellTokenIndex],
                clearingPrices[trade.buyTokenIndex],
                trade.executedAmount,
                inTransfers[i],
                outTransfers[i]
            );
        }
    }

    /// Compute the in and out transfer amounts for a single trade.
    /// This function reverts if:
    /// - The order has expired
    /// - The order's limit price is not respected
    /// - The order gets over-filled
    /// - The fee discount is larger than the executed fee
    function computeTradeExecution(
        RecoveredOrder memory recoveredOrder,
        uint256 sellPrice,
        uint256 buyPrice,
        uint256 executedAmount,
        Transfer.Data memory inTransfer,
        Transfer.Data memory outTransfer
    ) internal {
        Order.Data memory order = recoveredOrder.data;
        bytes memory orderUid = recoveredOrder.uid;

        require(order.validTo >= block.timestamp, "Torus: order expired");

        require(
            order.sellAmount.mul(sellPrice) >= order.buyAmount.mul(buyPrice),
            "Torus: limit price not respected"
        );

        uint256 executedSellAmount;
        uint256 executedBuyAmount;
        uint256 executedFeeAmount;
        uint256 currentFilledAmount;

        if (order.kind == Order.KIND_SELL) {
            if (order.partiallyFillable) {
                executedSellAmount = executedAmount;
                executedFeeAmount = order.feeAmount.mul(executedSellAmount).div(
                    order.sellAmount
                );
            } else {
                executedSellAmount = order.sellAmount;
                executedFeeAmount = order.feeAmount;
            }

            executedBuyAmount = executedSellAmount.mul(sellPrice).ceilDiv(
                buyPrice
            );

            currentFilledAmount = filledAmount[orderUid].add(
                executedSellAmount
            );
            require(
                currentFilledAmount <= order.sellAmount,
                "Torus: order filled"
            );
        } else {
            if (order.partiallyFillable) {
                executedBuyAmount = executedAmount;
                executedFeeAmount = order.feeAmount.mul(executedBuyAmount).div(
                    order.buyAmount
                );
            } else {
                executedBuyAmount = order.buyAmount;
                executedFeeAmount = order.feeAmount;
            }

            executedSellAmount = executedBuyAmount.mul(buyPrice).div(sellPrice);

            currentFilledAmount = filledAmount[orderUid].add(executedBuyAmount);
            require(
                currentFilledAmount <= order.buyAmount,
                "Torus: order filled"
            );
        }

        executedSellAmount = executedSellAmount.add(executedFeeAmount);
        filledAmount[orderUid] = currentFilledAmount;

        emit Trade(
            recoveredOrder.owner,
            order.sellToken,
            order.buyToken,
            executedSellAmount,
            executedBuyAmount,
            executedFeeAmount,
            orderUid
        );

        inTransfer.account = recoveredOrder.owner;
        inTransfer.token = order.sellToken;
        inTransfer.amount = executedSellAmount;
        inTransfer.balance = order.sellTokenBalance;

        outTransfer.account = recoveredOrder.receiver;
        outTransfer.token = order.buyToken;
        outTransfer.amount = executedBuyAmount;
        outTransfer.balance = order.buyTokenBalance;
    }

    /// Execute a list of arbitrary contract calls from this contract.
     function executeInteractions(
        Interaction.Data[] calldata interactions
    ) internal {
        for (uint256 i; i < interactions.length; ++i) {
            Interaction.Data calldata interaction = interactions[i];

            // To prevent possible attack on user funds, we explicitly disable
            // any interactions with the vault relayer contract.
            require(
                interaction.target != address(vaultRelayer),
                "Torus: forbidden interaction"
            );
            Interaction.execute(interaction);

            emit Interaction(
                interaction.target,
                interaction.value,
                Interaction.selector(interaction)
            );
        }
    }

    /// Claims refund for the specified storage and order UIDs.
    function freeOrderStorage(
        mapping(bytes => uint256) storage orderStorage,
        bytes[] calldata orderUids
    ) internal {
        for (uint256 i; i < orderUids.length; ++i) {
            bytes calldata orderUid = orderUids[i];

            (, , uint32 validTo) = orderUid.extractOrderUidParams();

            require(validTo < block.timestamp, "Torus: order still valid");

            orderStorage[orderUid] = 0;
        }
    }

}