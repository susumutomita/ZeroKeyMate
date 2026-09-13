// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface IAuthorizationToken is IERC20 {
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}

/// @notice A fixed-price, fixed-merchant, expiring testnet purchase permission.
/// @dev ERC-1271 cannot update a spending counter. Instead each of at most N
///      fixed-price payments has one mandatory token authorization nonce. The
///      USDC contract consumes each nonce atomically, enforcing total <= N*price
///      even through direct token calls or additional funding. This relies on
///      the configured token's EIP-3009 replay protection and ERC-1271 support.
///      Age verification remains the separate order-bound shop/phone protocol.
contract MatePurchaseAccount is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Payment {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
        uint32 slot;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    uint256 public constant PRICE = 100000;
    bytes32 public constant SLOT_DOMAIN = keccak256("ZeroKeyMate purchase slot v1");
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant TRANSFER_TYPEHASH = keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)");
    bytes32 private constant REVOKE_TYPEHASH = keccak256("Revoke(uint256 nonce,uint64 expiresAt)");
    bytes32 private constant WITHDRAW_TYPEHASH = keccak256("Withdraw(uint256 amount,uint256 nonce,uint64 expiresAt)");

    IAuthorizationToken public immutable token;
    address public immutable factory;
    address public owner;
    address public agent;
    address public merchant;
    uint32 public maxPurchases;
    uint64 public validUntil;
    bool public revoked;
    uint256 public adminNonce;

    error InvalidPermission();
    error InvalidAdminAuthorization();
    event Revoked();
    event Withdrawn(address indexed owner, uint256 amount);

    constructor(IAuthorizationToken token_, address factory_) EIP712("ZeroKeyMate Purchase Account", "1") {
        if ((block.chainid != 5042002 && block.chainid != 31337) || address(token_).code.length == 0
            || (block.chainid == 5042002 && address(token_) != 0x3600000000000000000000000000000000000000)
            || factory_ == address(0)) revert InvalidPermission();
        token = token_; factory = factory_;
        // Seal the implementation. Only a new clone has an empty owner slot.
        owner = address(this);
    }

    function initialize(address owner_, address agent_, address merchant_, uint32 maxPurchases_, uint64 validUntil_) external {
        if (msg.sender != factory || owner != address(0)
            || owner_ == address(0) || agent_ == address(0) || merchant_ == address(0)
            || owner_ == agent_ || agent_.code.length != 0 || merchant_ == address(this)
            || maxPurchases_ == 0 || maxPurchases_ > 100
            || validUntil_ <= block.timestamp || validUntil_ > block.timestamp + 1 days)
            revert InvalidPermission();
        owner = owner_; agent = agent_; merchant = merchant_;
        maxPurchases = maxPurchases_; validUntil = validUntil_;
    }

    function slotNonce(uint32 slot) public view returns (bytes32) {
        if (slot >= maxPurchases) revert InvalidPermission();
        return keccak256(abi.encode(SLOT_DOMAIN, block.chainid, address(this), slot));
    }

    /// @dev No generic owner-signature fallback, arbitrary call or token approve.
    ///      A signature authorizes only this exact USDC transfer and slot.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (revoked || block.timestamp >= validUntil || signature.length != 320) return 0xffffffff;
        Payment memory p = abi.decode(signature, (Payment));
        if (p.from != address(this) || p.to != merchant || p.value != PRICE || p.slot >= maxPurchases
            || p.validAfter >= block.timestamp || p.validBefore <= block.timestamp
            || p.validBefore > validUntil || p.validBefore <= p.validAfter
            || p.validBefore - p.validAfter > 301 || p.nonce != slotNonce(p.slot)
            || token.authorizationState(address(this), p.nonce)) return 0xffffffff;
        bytes32 domain = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("USDC"), keccak256("2"), block.chainid, address(token)));
        bytes32 value = keccak256(abi.encode(TRANSFER_TYPEHASH, p.from, p.to, p.value, p.validAfter, p.validBefore, p.nonce));
        bytes32 expected = keccak256(abi.encodePacked("\x19\x01", domain, value));
        if (hash != expected) return 0xffffffff;
        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(hash, p.v, p.r, p.s);
        return error == ECDSA.RecoverError.NoError && recovered == agent ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    /// @notice Anyone may sponsor the owner's exact, short-lived revocation.
    function revoke(uint256 nonce, uint64 expiresAt, bytes calldata signature) external nonReentrant {
        _authorize(keccak256(abi.encode(REVOKE_TYPEHASH, nonce, expiresAt)), nonce, expiresAt, signature);
        revoked = true;
        emit Revoked();
    }

    /// @notice Return funds only to the owner and permanently stop new purchases.
    function withdraw(uint256 amount, uint256 nonce, uint64 expiresAt, bytes calldata signature) external nonReentrant {
        if (amount == 0) revert InvalidAdminAuthorization();
        _authorize(keccak256(abi.encode(WITHDRAW_TYPEHASH, amount, nonce, expiresAt)), nonce, expiresAt, signature);
        revoked = true;
        IERC20(address(token)).safeTransfer(owner, amount);
        emit Revoked();
        emit Withdrawn(owner, amount);
    }

    function _authorize(bytes32 value, uint256 nonce, uint64 expiresAt, bytes calldata signature) private {
        if (nonce != adminNonce || expiresAt <= block.timestamp || expiresAt > block.timestamp + 300
            || !SignatureChecker.isValidSignatureNow(owner, _hashTypedDataV4(value), signature))
            revert InvalidAdminAuthorization();
        adminNonce = nonce + 1;
    }
}

/// @notice Public factory for an owner's explicitly signed, immutable permission.
contract MatePurchaseAccountFactory is EIP712, ReentrancyGuard {
    struct Permission {
        address owner;
        address agent;
        address merchant;
        uint32 maxPurchases;
        uint64 validUntil;
        bytes32 salt;
    }
    bytes32 private constant PERMISSION_TYPEHASH = keccak256("PurchasePermission(address owner,address agent,address merchant,uint32 maxPurchases,uint64 validUntil,bytes32 salt)");
    IAuthorizationToken public immutable token;
    address public immutable implementation;
    error InvalidOwnerSignature();
    event AccountCreated(address indexed account, address indexed owner, address indexed agent, bytes32 permissionHash);

    constructor(IAuthorizationToken token_) EIP712("ZeroKeyMate Purchase Permission", "1") {
        if ((block.chainid != 5042002 && block.chainid != 31337) || address(token_).code.length == 0)
            revert InvalidOwnerSignature();
        token = token_;
        implementation = address(new MatePurchaseAccount(token_, address(this)));
    }

    function permissionHash(Permission calldata p) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(PERMISSION_TYPEHASH, p.owner, p.agent, p.merchant,
            p.maxPurchases, p.validUntil, p.salt)));
    }
    function predict(Permission calldata p) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, permissionHash(p), address(this));
    }
    function create(Permission calldata p, bytes calldata ownerSignature) external nonReentrant returns (address account) {
        bytes32 digest = permissionHash(p);
        if (p.salt == bytes32(0) || !SignatureChecker.isValidSignatureNow(p.owner, digest, ownerSignature))
            revert InvalidOwnerSignature();
        account = predict(p);
        // Idempotent relay cannot reset expiry, revocation or consumed slots.
        if (account.code.length != 0) return account;
        account = Clones.cloneDeterministic(implementation, digest);
        MatePurchaseAccount(account).initialize(p.owner, p.agent, p.merchant, p.maxPurchases, p.validUntil);
        emit AccountCreated(account, p.owner, p.agent, digest);
    }
}
