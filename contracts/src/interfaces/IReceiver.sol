// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReceiver {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
