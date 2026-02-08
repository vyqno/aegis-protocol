// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IWorldIdGate} from "../interfaces/IWorldIdGate.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title IWorldID - World ID on-chain verifier interface
/// @notice Minimal interface for calling World ID's verifyProof
interface IWorldID {
    /// @notice Verify a World ID zero-knowledge proof
    /// @param root The Merkle root of the World ID identity set
    /// @param groupId The World ID group (e.g., Orb-verified = 1)
    /// @param signalHash Hash of the signal (typically user's address)
    /// @param nullifierHash Unique nullifier per user per action
    /// @param externalNullifierHash Hash of the external nullifier (action identifier)
    /// @param proof The ZK proof elements
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view;
}

/// @title WorldIdGate - Sybil-Resistant Access Control for AEGIS Protocol
/// @notice Verifies World ID proofs for vault access control with TTL-based staleness checks,
///         anti-front-running (signal == msg.sender or authorized vault), and revocation support.
/// @dev Key security properties:
///      - signal MUST be msg.sender for direct calls (anti-front-running, CRITICAL-001)
///      - Authorized vaults may call on behalf of users (vault passes end-user address)
///      - Verification is idempotent: if user is already verified and not expired, returns early
///      - Revoked users CAN re-verify with a new proof (HIGH-001)
///      - hashToField matches World ID reference: uint256(keccak256(value)) >> 8 (MEDIUM-002)
contract WorldIdGate is IWorldIdGate, Ownable2Step, Pausable {
    // ================================================================
    //                          CONSTANTS
    // ================================================================

    /// @notice Minimum verification TTL (1 hour)
    uint256 public constant MIN_TTL = 1 hours;

    /// @notice Maximum verification TTL (30 days)
    uint256 public constant MAX_TTL = 30 days;

    // ================================================================
    //                       STATE VARIABLES
    // ================================================================

    /// @notice World ID on-chain verifier contract
    IWorldID public worldId;

    /// @notice World ID group ID (e.g., 1 for Orb-verified)
    uint256 public groupId;

    /// @notice Hash of the action identifier (external nullifier)
    uint256 public externalNullifierHash;

    /// @notice Verification time-to-live in seconds
    uint256 public verificationTTL;

    /// @notice Nullifier tracking to prevent double-signaling
    mapping(uint256 => bool) public nullifierHashes;

    /// @notice Per-user verification records
    mapping(address => VerificationRecord) private _records;

    /// @notice Authorized vault contracts that may call verifyIdentity on behalf of users
    mapping(address => bool) private _authorizedVaults;

    // ================================================================
    //                         CONSTRUCTOR
    // ================================================================

    /// @notice Deploy WorldIdGate with World ID configuration
    /// @param _worldId The World ID verifier contract address (cannot be zero)
    /// @param _groupId The World ID group ID
    /// @param _actionId The action identifier string (hashed to externalNullifierHash)
    /// @param _ttl Initial verification TTL in seconds (must be within MIN_TTL..MAX_TTL)
    constructor(
        address _worldId,
        uint256 _groupId,
        string memory _actionId,
        uint256 _ttl
    ) Ownable(msg.sender) {
        if (_worldId == address(0)) revert ZeroAddress();
        if (_ttl < MIN_TTL || _ttl > MAX_TTL) revert VerificationTTLOutOfBounds(_ttl, MIN_TTL, MAX_TTL);

        worldId = IWorldID(_worldId);
        groupId = _groupId;
        externalNullifierHash = _hashToField(abi.encodePacked(_actionId));
        verificationTTL = _ttl;
    }

    // ================================================================
    //                      VERIFICATION
    // ================================================================

    /// @inheritdoc IWorldIdGate
    /// @dev Idempotent: returns early if user is already verified and not expired.
    ///      For direct calls: user MUST equal msg.sender (anti-front-running, CRITICAL-001).
    ///      For vault-mediated calls: vault must be registered via registerVault().
    function verifyIdentity(
        address user,
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external override whenNotPaused {
        // If already verified and not expired, return early (idempotent)
        if (_isVerified(user)) return;

        // Anti-front-running: signal must be msg.sender OR caller is authorized vault
        if (msg.sender != user && !_authorizedVaults[msg.sender]) {
            revert SignalMismatch(user, msg.sender);
        }

        // Prevent double-signaling (nullifier uniqueness)
        if (nullifierHashes[nullifierHash]) {
            revert NullifierAlreadyUsed(nullifierHash);
        }

        // Verify the World ID ZK proof
        worldId.verifyProof(
            root,
            groupId,
            _hashToField(abi.encodePacked(user)),
            nullifierHash,
            externalNullifierHash,
            proof
        );

        // Record verification state
        nullifierHashes[nullifierHash] = true;
        uint256 expiresAt = block.timestamp + verificationTTL;
        _records[user] = VerificationRecord({
            isVerified: true,
            verifiedAt: block.timestamp,
            nullifierHash: nullifierHash,
            expiresAt: expiresAt
        });

        emit IdentityVerified(user, nullifierHash, expiresAt);
    }

    /// @inheritdoc IWorldIdGate
    /// @dev Returns false if: not verified, revoked, or TTL expired (MEDIUM-001 staleness check)
    function isVerified(address user) external view override returns (bool) {
        return _isVerified(user);
    }

    /// @inheritdoc IWorldIdGate
    function getVerificationRecord(address user) external view override returns (VerificationRecord memory) {
        return _records[user];
    }

    // ================================================================
    //                      CONFIGURATION
    // ================================================================

    /// @inheritdoc IWorldIdGate
    /// @dev TTL must be within [MIN_TTL, MAX_TTL] bounds
    function setVerificationTTL(uint256 ttl) external override onlyOwner {
        if (ttl < MIN_TTL || ttl > MAX_TTL) revert VerificationTTLOutOfBounds(ttl, MIN_TTL, MAX_TTL);
        emit VerificationTTLUpdated(verificationTTL, ttl);
        verificationTTL = ttl;
    }

    /// @inheritdoc IWorldIdGate
    /// @dev Revoked users CAN re-verify with a new World ID proof (HIGH-001).
    ///      Old nullifier stays used; user gets a new nullifier from new proof.
    function revokeVerification(address user) external override onlyOwner {
        VerificationRecord storage record = _records[user];
        uint256 oldNullifier = record.nullifierHash;
        record.isVerified = false;
        emit VerificationRevoked(user, oldNullifier);
    }

    /// @notice Register a vault as authorized to call verifyIdentity on behalf of users
    /// @param vault The vault contract address (cannot be zero)
    function registerVault(address vault) external onlyOwner {
        if (vault == address(0)) revert ZeroAddress();
        _authorizedVaults[vault] = true;
        emit VaultRegistered(vault);
    }

    /// @notice Remove a vault from authorized callers
    /// @param vault The vault contract address
    function removeVault(address vault) external onlyOwner {
        _authorizedVaults[vault] = false;
    }

    /// @notice Update the World ID verifier contract address
    /// @param _worldId The new World ID contract address (cannot be zero)
    function setWorldIdContract(address _worldId) external onlyOwner {
        if (_worldId == address(0)) revert ZeroAddress();
        emit WorldIdContractUpdated(address(worldId), _worldId);
        worldId = IWorldID(_worldId);
    }

    /// @notice Update the World ID group ID
    /// @param _groupId The new group ID
    function setGroupId(uint256 _groupId) external onlyOwner {
        emit GroupIdUpdated(groupId, _groupId);
        groupId = _groupId;
    }

    /// @notice Update the action identifier (recalculates externalNullifierHash)
    /// @param _actionId The new action identifier string
    function setActionId(string calldata _actionId) external onlyOwner {
        emit ActionIdUpdated("", _actionId);
        externalNullifierHash = _hashToField(abi.encodePacked(_actionId));
    }

    // ================================================================
    //                        PAUSABLE
    // ================================================================

    /// @notice Pause verification (owner only, independent from vault pause)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause verification
    function unpause() external onlyOwner {
        _unpause();
    }

    // ================================================================
    //                      VIEW FUNCTIONS
    // ================================================================

    /// @notice Check if an address is an authorized vault
    /// @param vault The address to check
    /// @return True if the address is an authorized vault
    function isAuthorizedVault(address vault) external view returns (bool) {
        return _authorizedVaults[vault];
    }

    // ================================================================
    //                    INTERNAL FUNCTIONS
    // ================================================================

    /// @notice Internal verification check with staleness (MEDIUM-001)
    /// @param user The user address
    /// @return True if verified, not revoked, and TTL not expired
    function _isVerified(address user) internal view returns (bool) {
        VerificationRecord memory record = _records[user];
        if (!record.isVerified) return false;
        if (block.timestamp > record.expiresAt) return false;
        return true;
    }

    /// @notice Hash bytes to a field element matching World ID's reference implementation (MEDIUM-002)
    /// @param value The bytes to hash
    /// @return The field element (uint256(keccak256(value)) >> 8)
    function _hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}
