// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Multiple agent keys, one immutable spending ceiling, one owner stop.
/// @dev LOCAL-CHAIN RESEARCH ONLY. Not the deployed iPhone/Arc checkout.
///      No attestor, fake proof, generic execution, ERC-1271 fallback or allowance.
///      Checking the shared counter and transferring the token are one transaction.
///      Limits and recipients are PUBLIC. This does not prove private policies.
contract MateSharedBudget is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Payment {
        address agent;
        address token;
        address recipient;
        uint256 amount;
        bytes32 nonce;
        uint64 expiresAt;
        bytes32 requestHash;
    }

    bytes32 public constant PAYMENT_TYPEHASH = keccak256(
        "Payment(address agent,address token,address recipient,uint256 amount,bytes32 nonce,uint64 expiresAt,bytes32 requestHash)"
    );
    IERC20 public immutable token;
    address public immutable owner;
    uint256 public immutable budgetLimit;
    uint256 public immutable perPaymentLimit;
    uint64 public immutable validUntil;
    uint256 public spent;
    bool public stopped;
    mapping(address => bool) public agents;
    mapping(address => bool) public merchants;
    mapping(address => mapping(bytes32 => bool)) public usedNonces;

    error LocalChainOnly();
    error InvalidPolicy();
    error Unauthorized();
    error BudgetStopped();
    error PaymentExpired();
    error UnknownAgent();
    error RecipientNotAllowed();
    error InvalidPayment();
    error InvalidSignature();
    error PaymentReplayed();
    error PerPaymentLimitExceeded();
    error SharedBudgetExceeded();
    error InsufficientFunds();
    error UnsupportedTokenBehavior();

    event Authorized(address indexed owner, address indexed token, uint256 budgetLimit,
        uint256 perPaymentLimit, uint64 validUntil);
    event AgentAllowed(address indexed agent);
    event MerchantAllowed(address indexed merchant);
    event Paid(address indexed agent, address indexed recipient, bytes32 indexed nonce,
        bytes32 requestHash, uint256 amount, uint256 spentAfter);
    event Stopped(address indexed owner, uint256 spent);
    event Withdrawn(address indexed owner, uint256 amount);

    /// @dev The owner's deployment transaction authorizes these immutable terms.
    ///      Funding is a separate ERC-20 transfer; more funding NEVER resets spent.
    constructor(IERC20 token_, address[] memory agents_, address[] memory merchants_,
        uint256 budgetLimit_, uint256 perPaymentLimit_, uint64 validUntil_)
        EIP712("ZeroKey Mate Shared Budget", "1")
    {
        if (block.chainid != 31337) revert LocalChainOnly();
        if (address(token_).code.length == 0 || budgetLimit_ == 0 || perPaymentLimit_ == 0
            || perPaymentLimit_ > budgetLimit_ || validUntil_ <= block.timestamp
            || validUntil_ > block.timestamp + 1 days || agents_.length == 0
            || agents_.length > 16 || merchants_.length == 0 || merchants_.length > 16)
            revert InvalidPolicy();
        token = token_;
        owner = msg.sender;
        budgetLimit = budgetLimit_;
        perPaymentLimit = perPaymentLimit_;
        validUntil = validUntil_;
        for (uint256 i; i < agents_.length; ++i) {
            address agent = agents_[i];
            if (agent == address(0) || agent == msg.sender || agent.code.length != 0 || agents[agent])
                revert InvalidPolicy();
            agents[agent] = true;
            emit AgentAllowed(agent);
        }
        for (uint256 i; i < merchants_.length; ++i) {
            address merchant = merchants_[i];
            if (merchant == address(0) || merchant == address(this) || merchants[merchant])
                revert InvalidPolicy();
            merchants[merchant] = true;
            emit MerchantAllowed(merchant);
        }
        emit Authorized(owner, address(token), budgetLimit, perPaymentLimit, validUntil);
    }

    function remainingBudget() external view returns (uint256) {
        return budgetLimit - spent;
    }

    function paymentDigest(Payment calldata payment) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(PAYMENT_TYPEHASH, payment.agent,
            payment.token, payment.recipient, payment.amount, payment.nonce,
            payment.expiresAt, payment.requestHash)));
    }

    /// @notice Anyone can relay; only an allowed agent can sign an exact payment.
    function execute(Payment calldata payment, bytes calldata signature) external nonReentrant {
        if (stopped) revert BudgetStopped();
        if (block.timestamp >= validUntil || block.timestamp >= payment.expiresAt
            || payment.expiresAt > validUntil) revert PaymentExpired();
        if (!agents[payment.agent]) revert UnknownAgent();
        if (!merchants[payment.recipient]) revert RecipientNotAllowed();
        if (payment.token != address(token) || payment.amount == 0
            || payment.nonce == bytes32(0) || payment.requestHash == bytes32(0)) revert InvalidPayment();
        if (usedNonces[payment.agent][payment.nonce]) revert PaymentReplayed();
        if (payment.amount > perPaymentLimit) revert PerPaymentLimitExceeded();
        if (payment.amount > budgetLimit - spent) revert SharedBudgetExceeded();
        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(paymentDigest(payment), signature);
        if (error != ECDSA.RecoverError.NoError || recovered != payment.agent) revert InvalidSignature();

        // Effects precede the external call; a failed transfer rolls BOTH back.
        usedNonces[payment.agent][payment.nonce] = true;
        spent += payment.amount;
        _transferExact(payment.recipient, payment.amount);
        emit Paid(payment.agent, payment.recipient, payment.nonce, payment.requestHash,
            payment.amount, spent);
    }

    /// @notice Irreversible for this budget, including all unmined signed actions.
    /// @dev Effective when mined, not at the moment a UI button is pressed.
    function revokeAll() external nonReentrant {
        if (msg.sender != owner) revert Unauthorized();
        _stop();
    }

    /// @notice Only the owner can recover funds; withdrawal also stops every agent.
    function withdraw(uint256 amount) external nonReentrant {
        if (msg.sender != owner) revert Unauthorized();
        if (amount == 0) revert InvalidPayment();
        _stop();
        _transferExact(owner, amount);
        emit Withdrawn(owner, amount);
    }

    function _stop() private {
        if (!stopped) {
            stopped = true;
            emit Stopped(owner, spent);
        }
    }

    function _transferExact(address recipient, uint256 amount) private {
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 recipientBefore = token.balanceOf(recipient);
        if (balanceBefore < amount) revert InsufficientFunds();
        token.safeTransfer(recipient, amount);
        if (token.balanceOf(address(this)) != balanceBefore - amount
            || token.balanceOf(recipient) != recipientBefore + amount) revert UnsupportedTokenBehavior();
    }
}
