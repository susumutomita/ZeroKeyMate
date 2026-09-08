// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/// @notice Minimal immutable ENS address/profile resolver for one name.
/// @dev The ENS registry controls ownership and selection of this resolver.
///      A name owner can choose another resolver using the registry's own permissions.
contract MateNameResolver {
    bytes32 public immutable node;
    address public immutable account;
    constructor(bytes32 nameNode, address mate) {
        require(nameNode != bytes32(0) && mate != address(0), "Invalid name");
        node=nameNode;account=mate;
    }
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id==0x01ffc9a7 || id==0x3b3b57de || id==0x59d1d43c;
    }
    function addr(bytes32 nameNode) external view returns (address) {
        return nameNode==node ? account : address(0);
    }
    function text(bytes32 nameNode, string calldata key) external view returns (string memory) {
        if(nameNode==node && keccak256(bytes(key))==keccak256("description")) return "ZeroKey Mate companion on Sepolia";
        return "";
    }
}

contract MateResolverFactory {
    mapping(bytes32 => address) public resolvers;
    function create(bytes32 node,address account) external returns (address resolver) {
        bytes32 key=keccak256(abi.encode(node,account));
        resolver=resolvers[key];
        if(resolver==address(0)) {
            resolver=address(new MateNameResolver{salt:key}(node,account));
            resolvers[key]=resolver;
        }
    }
}
