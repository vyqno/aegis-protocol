// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IWorldIdGate - Interface for the AEGIS Protocol World ID sybil resistance
/// @notice Verifies World ID proofs for vault access control with TTL-based staleness checks,
///         per-action nullifiers, and signal == msg.sender anti-front-running
interface IWorldIdGate {
    // ================================================================
    //                           STRUCTS
    // ================================================================

    /// @notice Verification record for a user
    struct VerificationRecord {
        bool isVerified;
        uint256 verifiedAt;
        uint256 nullifierHash;
        uint256 expiresAt;
    }

    // ================================================================
    //                           ERRORS
    // ================================================================

    error ZeroAddress();
    error InvalidProof();
    error ProofExpired(uint256 verifiedAt, uint256 expiresAt);
    error NullifierAlreadyUsed(uint256 nullifierHash);
    error SignalMismatch(address expected, address received);
    error VerificationTTLOutOfBounds(uint256 ttl, uint256 min, uint256 max);
    error NotVerified(address user);
    error CallerNotVault(address caller);

    // ================================================================
    //                           EVENTS
    // ================================================================

    event IdentityVerified(
        address indexed user,
        uint256 indexed nullifierHash,
        uint256 expiresAt
    );
    event VerificationRevoked(address indexed user, uint256 indexed nullifierHash);
    event VerificationTTLUpdated(uint256 oldTTL, uint256 newTTL);
    event VaultRegistered(address indexed vault);
    event WorldIdContractUpdated(address indexed oldContract, address indexed newContract);
    event GroupIdUpdated(uint256 oldGroupId, uint256 newGroupId);
    event ActionIdUpdated(string oldActionId, string newActionId);

    // ================================================================
    //                      VERIFICATION
    // ================================================================

    /// @notice Verify a World ID proof for a user
    /// @param user The user address (must equal signal for anti-front-running)
    /// @param root The World ID Merkle root
    /// @param nullifierHash The nullifier hash (unique per user per action)
    /// @param proof The zero-knowledge proof array
    /// @dev signal MUST equal msg.sender to prevent front-running (VULN: signal==msg.sender)
    function verifyIdentity(
        address user,
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external;

    /// @notice Check if a user has a valid (non-expired) verification
    /// @param user The user address
    /// @return True if the user is verified and verification has not expired
    function isVerified(address user) external view returns (bool);

    /// @notice Get the full verification record for a user
    /// @param user The user address
    /// @return The VerificationRecord struct
    function getVerificationRecord(address user) external view returns (VerificationRecord memory);

    // ================================================================
    //                      CONFIGURATION
    // ================================================================

    /// @notice Set the verification TTL (time-to-live)
    /// @param ttl New TTL in seconds
    function setVerificationTTL(uint256 ttl) external;

    /// @notice Revoke a user's verification (forces re-verification)
    /// @param user The user address to revoke
    function revokeVerification(address user) external;
}
