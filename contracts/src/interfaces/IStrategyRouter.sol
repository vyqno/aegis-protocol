// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IStrategyRouter - Interface for the AEGIS Protocol cross-chain strategy router
/// @notice Routes capital across chains via CCIP, executes strategies via 1inch,
///         and enforces cumulative transfer limits per time window
interface IStrategyRouter {
    // ================================================================
    //                           STRUCTS
    // ================================================================

    /// @notice Strategy execution parameters from CRE workflow
    struct StrategyParams {
        address targetProtocol;
        uint64 destinationChainSelector;
        uint256 amount;
        bytes strategyData;       // ABI-encoded strategy-specific params
        bytes1 actionType;        // 0x01=deposit, 0x02=withdraw, 0x03=rebalance
    }

    /// @notice Transfer limit tracking per time window
    struct TransferWindow {
        uint256 transferred;      // Amount transferred in current window
        uint256 windowStart;      // Start timestamp of current window
    }

    /// @notice Cross-chain message tracking for replay protection
    struct CrossChainMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        address sender;
        uint256 nonce;
        bool processed;
    }

    // ================================================================
    //                           ERRORS
    // ================================================================

    error ZeroAddress();
    error ZeroAmount();
    error InvalidChainSelector(uint64 selector);
    error InvalidSourceChain(uint64 received, uint64 expected);
    error InvalidSourceSender(address received, address expected);
    error TransferLimitExceeded(uint256 requested, uint256 remaining);
    error InvalidActionType(bytes1 actionType);
    error SelectorNotWhitelisted(bytes4 selector);
    error MessageAlreadyProcessed(bytes32 messageId);
    error InsufficientFee(uint256 required, uint256 provided);
    error CircuitBreakerActive();
    error CallerNotAuthorized(address caller);
    error NonceAlreadyUsed(uint256 nonce);

    // ================================================================
    //                           EVENTS
    // ================================================================

    event StrategyExecuted(
        bytes32 indexed reportId,
        address indexed targetProtocol,
        bytes1 actionType,
        uint256 amount
    );
    event CrossChainMessageSent(
        bytes32 indexed ccipMessageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        uint256 amount,
        uint256 nonce
    );
    event CrossChainMessageReceived(
        bytes32 indexed ccipMessageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 nonce
    );
    event TransferLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event TransferWindowDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event AllowedChainUpdated(uint64 indexed chainSelector, bool allowed);
    event AllowedSenderUpdated(uint64 indexed chainSelector, address indexed sender, bool allowed);
    event SwapSelectorWhitelisted(bytes4 indexed selector, bool allowed);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event RiskRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // ================================================================
    //                      STRATEGY EXECUTION
    // ================================================================

    /// @notice Execute a strategy based on CRE report data
    /// @param params The strategy execution parameters
    /// @param reportId The CRE report ID for tracking
    function executeStrategy(StrategyParams calldata params, bytes32 reportId) external;

    /// @notice Bridge assets to another chain via CCIP
    /// @param destinationChainSelector The CCIP destination chain selector
    /// @param receiver The receiver address on the destination chain
    /// @param amount The amount to bridge
    /// @return ccipMessageId The CCIP message ID
    function bridgeAssets(
        uint64 destinationChainSelector,
        address receiver,
        uint256 amount
    ) external payable returns (bytes32 ccipMessageId);

    // ================================================================
    //                        VIEW FUNCTIONS
    // ================================================================

    /// @notice Get the remaining transfer budget for the current window
    /// @return remaining Amount that can still be transferred
    function getRemainingTransferBudget() external view returns (uint256 remaining);

    /// @notice Check if a chain selector is allowed for cross-chain messages
    /// @param chainSelector The CCIP chain selector
    /// @return True if the chain is allowed
    function isChainAllowed(uint64 chainSelector) external view returns (bool);

    /// @notice Get the current CCIP nonce
    /// @return The current nonce value
    function getCurrentNonce() external view returns (uint256);
}
