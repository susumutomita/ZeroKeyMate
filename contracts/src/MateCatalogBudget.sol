// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICatalogAgeGate {
    function verifyOrderAge(bytes32, bytes32, uint256, bytes calldata, uint256[8] calldata)
        external view returns (bool);
}

/// @notice Atomic catalogue, age, count and shared-spend enforcement.
/// @dev LOCAL RESEARCH ONLY. Not deployed or wired into the x402 shop.
///      An owner authorizes immutable terms at deployment. Public rules and
///      payments are not private. A pinned age gate provides only age privacy.
contract MateCatalogBudget is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Order {
        bytes32 id;
        uint8 product; // 1: Mate Lager; 2: Mate Sparkling Water.
        uint32 quantity;
        address merchant;
        uint64 expiresAt;
        bytes32 paymentNonce;
    }
    struct Limits {
        uint256 total;
        uint256 perPurchase;
        uint32 purchases;
        uint64 expiresAt;
        uint8 products; // bit 0: beer, bit 1: water.
    }

    bytes32 private constant QUOTE_TYPEHASH = keccak256("Quote(bytes32 orderHash)");
    bytes32 private constant PURCHASE_TYPEHASH = keccak256("Purchase(address agent,bytes32 orderHash)");
    IERC20 public immutable token;
    address public immutable owner;
    ICatalogAgeGate public immutable ageGate;
    bytes32 public immutable ageGateCodeHash;
    uint256 public immutable budgetLimit;
    uint256 public immutable perPurchaseLimit;
    uint32 public immutable purchaseLimit;
    uint64 public immutable validUntil;
    uint8 public immutable allowedProducts;
    uint256 public spent;
    uint32 public purchaseCount;
    bool public stopped;
    mapping(address => bool) public agents;
    mapping(address => bool) public merchants;
    mapping(bytes32 => bool) public usedOrders;
    mapping(bytes32 => bool) public usedNonces;

    error LocalChainOnly();
    error InvalidPolicy();
    error Unauthorized();
    error BudgetStopped();
    error OrderExpired();
    error InvalidOrder();
    error ProductNotAllowed();
    error MerchantNotAllowed();
    error InvalidQuote();
    error InvalidAgent();
    error InvalidAgentSignature();
    error OrderReplayed();
    error BudgetExceeded();
    error PurchaseCountExceeded();
    error AgeNotVerified();
    error InsufficientFunds();
    error UnsupportedTokenBehavior();

    event Purchased(bytes32 indexed orderId, address indexed agent, address indexed merchant,
        bytes32 orderHash, uint8 product, uint32 quantity, uint256 amount, uint256 spentAfter, uint32 countAfter);
    event Stopped(address indexed owner);
    event Withdrawn(address indexed owner, uint256 amount);

    constructor(IERC20 token_, ICatalogAgeGate gate_, bytes32 gateCodeHash_,
        address[] memory agents_, address[] memory merchants_, Limits memory limits)
        EIP712("ZeroKey Mate Catalogue Budget", "1")
    {
        if (block.chainid != 31337) revert LocalChainOnly();
        if (address(token_).code.length == 0 || address(gate_).code.length == 0
            || gateCodeHash_ == bytes32(0) || address(gate_).codehash != gateCodeHash_
            || limits.total == 0 || limits.perPurchase == 0 || limits.perPurchase > limits.total
            || limits.purchases == 0 || limits.purchases > 100
            || limits.expiresAt <= block.timestamp || limits.expiresAt > block.timestamp + 1 days
            || limits.products == 0 || limits.products > 3
            || agents_.length == 0 || agents_.length > 16 || merchants_.length == 0 || merchants_.length > 16)
            revert InvalidPolicy();
        token=token_;owner=msg.sender;ageGate=gate_;ageGateCodeHash=gateCodeHash_;
        budgetLimit=limits.total;perPurchaseLimit=limits.perPurchase;
        purchaseLimit=limits.purchases;validUntil=limits.expiresAt;allowedProducts=limits.products;
        for (uint256 i; i<agents_.length; ++i) {
            address a=agents_[i];
            if(a==address(0)||a==msg.sender||a.code.length!=0||agents[a]) revert InvalidPolicy();
            agents[a]=true;
        }
        for (uint256 i; i<merchants_.length; ++i) {
            address m=merchants_[i];
            // A configured agent must not also attest its own merchant quote.
            if(m==address(0)||m==address(this)||merchants[m]||agents[m]) revert InvalidPolicy();
            merchants[m]=true;
        }
    }

    function orderHash(Order calldata o) public view returns(bytes32) {
        (string memory sku,uint256 amount,uint256 age)=_product(o);
        // Same ZKM-AGE-ORDER-1 encoding as the physical-card circuit input.
        // The payer is THIS budget, not an address selected by the agent.
        return keccak256(abi.encode("ZKM-AGE-ORDER-1",block.chainid,address(ageGate),o.id,
            sku,uint256(o.quantity),address(this),o.merchant,address(token),amount,
            uint256(o.expiresAt),o.paymentNonce,age));
    }

    function quoteDigest(Order calldata o) public view returns(bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(QUOTE_TYPEHASH,orderHash(o))));
    }
    function purchaseDigest(address agent,Order calldata o) public view returns(bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(PURCHASE_TYPEHASH,agent,orderHash(o))));
    }

    function execute(Order calldata o,address agent,bytes calldata agentSignature,
        bytes calldata merchantSignature,bytes calldata ageProof,uint256[8] calldata ageInputs)
        external nonReentrant
    {
        if(stopped) revert BudgetStopped();
        if(block.timestamp>=validUntil||block.timestamp>=o.expiresAt
            ||o.expiresAt>validUntil||o.expiresAt>block.timestamp+900) revert OrderExpired();
        if(o.id==bytes32(0)||o.paymentNonce==bytes32(0)) revert InvalidOrder();
        (,uint256 amount,uint256 age)=_product(o);
        if((allowedProducts & uint8(1 << (o.product-1)))==0) revert ProductNotAllowed();
        if(!merchants[o.merchant]) revert MerchantNotAllowed();
        if(!agents[agent]) revert InvalidAgent();
        if(usedOrders[o.id]||usedNonces[o.paymentNonce]) revert OrderReplayed();
        if(amount>perPurchaseLimit||amount>budgetLimit-spent) revert BudgetExceeded();
        if(purchaseCount>=purchaseLimit) revert PurchaseCountExceeded();
        if(!SignatureChecker.isValidSignatureNow(o.merchant,quoteDigest(o),merchantSignature)) revert InvalidQuote();
        (address signer,ECDSA.RecoverError error,)=ECDSA.tryRecover(purchaseDigest(agent,o),agentSignature);
        if(error!=ECDSA.RecoverError.NoError||signer!=agent) revert InvalidAgentSignature();
        if(age!=0) {
            if(address(ageGate).codehash!=ageGateCodeHash) revert AgeNotVerified();
            try ageGate.verifyOrderAge(orderHash(o),o.paymentNonce,o.expiresAt,ageProof,ageInputs)
                returns(bool valid) {if(!valid) revert AgeNotVerified();}
            catch {revert AgeNotVerified();}
        } else {
            if(ageProof.length!=0) revert InvalidOrder();
            for(uint256 i;i<8;++i) if(ageInputs[i]!=0) revert InvalidOrder();
        }
        usedOrders[o.id]=true;usedNonces[o.paymentNonce]=true;
        spent+=amount;purchaseCount+=1;
        _transferExact(o.merchant,amount);
        emit Purchased(o.id,agent,o.merchant,orderHash(o),o.product,o.quantity,amount,spent,purchaseCount);
    }

    function revokeAll() external nonReentrant {if(msg.sender!=owner) revert Unauthorized();_stop();}
    function withdraw(uint256 amount) external nonReentrant {
        if(msg.sender!=owner) revert Unauthorized();
        if(amount==0) revert InvalidOrder();
        _stop();_transferExact(owner,amount);emit Withdrawn(owner,amount);
    }
    function _stop() private {if(!stopped) {stopped=true;emit Stopped(owner);}}
    function _product(Order calldata o) private pure returns(string memory sku,uint256 amount,uint256 age) {
        if(o.quantity==0||o.quantity>5) revert InvalidOrder();
        if(o.product==1) return("mate-lager",uint256(o.quantity)*100000,20);
        if(o.product==2) return("mate-sparkling-water",uint256(o.quantity)*50000,0);
        revert InvalidOrder();
    }
    function _transferExact(address recipient,uint256 amount) private {
        uint256 beforeFrom=token.balanceOf(address(this));uint256 beforeTo=token.balanceOf(recipient);
        if(beforeFrom<amount) revert InsufficientFunds();
        token.safeTransfer(recipient,amount);
        if(token.balanceOf(address(this))!=beforeFrom-amount||token.balanceOf(recipient)!=beforeTo+amount)
            revert UnsupportedTokenBehavior();
    }
}
