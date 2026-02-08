// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

/// @title MockCCIPRouter - Test mock for Chainlink CCIP Router
/// @notice Simulates CCIP send/receive for testing StrategyRouter
contract MockCCIPRouter is IRouterClient {
    uint256 private _messageCounter;
    uint256 public fixedFee = 0.01 ether;
    bool public shouldRevert;

    // Track sent messages for assertions
    struct SentMessage {
        uint64 destChainSelector;
        bytes receiver;
        bytes data;
        uint256 value;
    }
    SentMessage[] public sentMessages;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setFixedFee(uint256 _fee) external {
        fixedFee = _fee;
    }

    /// @inheritdoc IRouterClient
    function isChainSupported(uint64) external pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IRouterClient
    function getFee(
        uint64,
        Client.EVM2AnyMessage memory
    ) external view override returns (uint256) {
        return fixedFee;
    }

    /// @inheritdoc IRouterClient
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32) {
        require(!shouldRevert, "MockCCIPRouter: forced revert");
        require(msg.value >= fixedFee, "MockCCIPRouter: insufficient fee");

        _messageCounter++;
        bytes32 messageId = keccak256(abi.encodePacked(_messageCounter, block.timestamp));

        sentMessages.push(SentMessage({
            destChainSelector: destinationChainSelector,
            receiver: message.receiver,
            data: message.data,
            value: msg.value
        }));

        return messageId;
    }

    /// @notice Simulate CCIP delivery to a receiver contract
    /// @param receiver The receiver contract address
    /// @param sourceChainSelector The source chain
    /// @param sender The sender address on source chain
    /// @param data The message payload
    function simulateDelivery(
        address receiver,
        uint64 sourceChainSelector,
        address sender,
        bytes calldata data
    ) external {
        _messageCounter++;
        bytes32 messageId = keccak256(abi.encodePacked(_messageCounter, block.timestamp));

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(sender),
            data: data,
            destTokenAmounts: tokenAmounts
        });

        IAny2EVMMessageReceiver(receiver).ccipReceive(message);
    }

    /// @notice Get the number of sent messages
    function getSentMessageCount() external view returns (uint256) {
        return sentMessages.length;
    }

    /// @notice Accept ETH for fee payments
    receive() external payable {}
}
