// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// Local test fixture only. This is not a deployed USDC implementation or proof.
contract TestAuthorizationToken is ERC20, EIP712 {
    bytes32 private constant TRANSFER = keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)");
    mapping(address => mapping(bytes32 => bool)) public authorizationState;
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    constructor() ERC20("USDC", "TEST") EIP712("USDC", "2") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function transferWithAuthorization(address from, address to, uint256 value, uint256 validAfter,
        uint256 validBefore, bytes32 nonce, bytes calldata signature) external {
        require(block.timestamp > validAfter && block.timestamp < validBefore, "OutsideWindow");
        require(!authorizationState[from][nonce], "NonceUsed");
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(TRANSFER, from, to, value, validAfter, validBefore, nonce)));
        require(SignatureChecker.isValidSignatureNow(from, digest, signature), "InvalidSignature");
        authorizationState[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }
}
