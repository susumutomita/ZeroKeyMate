// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice A single-token, proof-gated spending account. Testnet research software.
/// @dev The immutable attestor verifies ProveKit offchain. This is explicitly NOT
///      an onchain ProveKit verifier. A compromised attestor can bypass private
///      policy checks, but cannot forge the owner or agent's required signatures.
contract MateVault is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Grant {
        address owner;
        address agent;
        bytes32 policyHash;
        uint64 validUntil;
        uint256 nonce;
    }

    struct Delegation {
        address owner;
        address agent;
        bytes32 policyHash;
        uint64 validUntil;
        uint64 spent;
        bool revoked;
    }

    struct Action {
        bytes32 mandateId;
        address recipient;
        uint64 amount;
        uint8 service;
        bytes32 nonce;
        uint64 expiresAt;
        bytes32 requestHash;
        uint64 spentBefore;
    }

    bytes32 public constant GRANT_TYPEHASH = keccak256(
        "Grant(address owner,address agent,bytes32 policyHash,uint64 validUntil,uint256 nonce)"
    );
    bytes32 public constant EXECUTION_TYPEHASH = keccak256("Execution(bytes32 actionHash)");
    bytes32 public constant PROOF_TYPEHASH = keccak256("ProofApproval(bytes32 actionHash,bytes32 proofHash)");
    IERC20 public immutable token;
    address public immutable attestor;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public ownerNonces;
    mapping(bytes32 => Delegation) public delegations;
    mapping(bytes32 => mapping(bytes32 => bool)) public usedNonces;

    error InvalidConfiguration();
    error InvalidGrant();
    error InvalidOwnerSignature();
    error InvalidAgentSignature();
    error InvalidProofApproval();
    error InvalidNonce();
    error Expired();
    error Revoked();
    error Unauthorized();
    error InvalidAction();
    error StaleSpendState();
    error InsufficientBalance();
    error UnsupportedTokenBehavior();

    event Deposited(address indexed owner, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);
    event Granted(bytes32 indexed mandateId, address indexed owner, address indexed agent, bytes32 policyHash, uint64 validUntil);
    event DelegationRevoked(bytes32 indexed mandateId);
    event Executed(bytes32 indexed mandateId, bytes32 indexed actionHash, bytes32 indexed nonce, address recipient, uint64 amount, uint8 service, bytes32 proofHash, uint64 spentAfter);

    constructor(IERC20 paymentToken, address proofAttestor) EIP712("ZeroKey Mate", "1") {
        if (address(paymentToken).code.length == 0 || proofAttestor == address(0)
            || block.chainid > type(uint64).max) revert InvalidConfiguration();
        token = paymentToken;
        attestor = proofAttestor;
    }

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAction();
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token.balanceOf(address(this)) - beforeBalance != amount) revert UnsupportedTokenBehavior();
        balances[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAction();
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        balances[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function grantDigest(Grant calldata grant) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            GRANT_TYPEHASH, grant.owner, grant.agent, grant.policyHash, grant.validUntil, grant.nonce
        )));
    }

    /// @notice Anyone can relay a grant; only its owner can authorize it.
    function register(Grant calldata grant, bytes calldata ownerSignature) external nonReentrant returns (bytes32 id) {
        if (grant.owner == address(0) || grant.agent == address(0) || grant.owner == grant.agent
            || grant.policyHash == bytes32(0)) revert InvalidGrant();
        if (block.timestamp >= grant.validUntil) revert Expired();
        if (grant.nonce != ownerNonces[grant.owner]) revert InvalidNonce();
        id = grantDigest(grant);
        if (!SignatureChecker.isValidSignatureNow(grant.owner, id, ownerSignature)) revert InvalidOwnerSignature();
        ownerNonces[grant.owner] = grant.nonce + 1;
        delegations[id] = Delegation(grant.owner, grant.agent, grant.policyHash, grant.validUntil, 0, false);
        emit Granted(id, grant.owner, grant.agent, grant.policyHash, grant.validUntil);
    }

    function revoke(bytes32 id) external {
        Delegation storage delegation = delegations[id];
        if (delegation.owner != msg.sender) revert Unauthorized();
        delegation.revoked = true;
        emit DelegationRevoked(id);
    }

    /// @dev Canonical 177-byte preimage is shared with the iPhone and Noir circuit.
    function actionHash(Action calldata action) public view returns (bytes32) {
        return sha256(abi.encodePacked(
            bytes8("ZKM-ACT1"), uint64(block.chainid), address(this),
            action.mandateId, action.recipient, action.nonce, action.expiresAt,
            action.requestHash, action.spentBefore, action.amount, action.service
        ));
    }

    function execute(Action calldata action, bytes32 proofHash, bytes calldata agentSignature, bytes calldata proofApproval)
        external nonReentrant
    {
        Delegation storage delegation = delegations[action.mandateId];
        if (delegation.owner == address(0)) revert InvalidGrant();
        if (delegation.revoked) revert Revoked();
        if (block.timestamp >= delegation.validUntil || block.timestamp >= action.expiresAt
            || action.expiresAt > delegation.validUntil) revert Expired();
        if (action.recipient == address(0) || action.recipient == address(this) || action.amount == 0
            || action.service > 1 || action.nonce == bytes32(0) || action.requestHash == bytes32(0)
            || proofHash == bytes32(0)) revert InvalidAction();
        if (usedNonces[action.mandateId][action.nonce]) revert InvalidNonce();
        if (action.spentBefore != delegation.spent) revert StaleSpendState();
        if (balances[delegation.owner] < action.amount) revert InsufficientBalance();

        bytes32 digest = actionHash(action);
        bytes32 execution = _hashTypedDataV4(keccak256(abi.encode(EXECUTION_TYPEHASH, digest)));
        if (!SignatureChecker.isValidSignatureNow(delegation.agent, execution, agentSignature)) revert InvalidAgentSignature();
        bytes32 approval = _hashTypedDataV4(keccak256(abi.encode(PROOF_TYPEHASH, digest, proofHash)));
        if (!SignatureChecker.isValidSignatureNow(attestor, approval, proofApproval)) revert InvalidProofApproval();

        usedNonces[action.mandateId][action.nonce] = true;
        delegation.spent += action.amount;
        balances[delegation.owner] -= action.amount;
        token.safeTransfer(action.recipient, action.amount);
        emit Executed(action.mandateId, digest, action.nonce, action.recipient,
            action.amount, action.service, proofHash, delegation.spent);
    }
}
