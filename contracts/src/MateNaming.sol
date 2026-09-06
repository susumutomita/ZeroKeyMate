// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Interfaces from the public ENSv2 contract ABI, pinned in config/ens-sepolia.json.
interface IMateENSResolver {
    function initialize(address admin, uint256 roleBitmap, bytes[] calldata setters) external;
    function setAddr(bytes32 node, address value) external;
    function setText(bytes32 node, string calldata key, string calldata value) external;
    function authorizeTextRoles(bytes calldata name, string calldata key, address account, bool grant) external returns (bool);
    function grantRootRoles(uint256 roleBitmap, address account) external returns (bool);
    function revokeRootRoles(uint256 roleBitmap, address account) external returns (bool);
}
contract MateProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory initialization) ERC1967Proxy(implementation, initialization) {}
}
/// @notice Creates a real ENSv2 PermissionedResolver with no persistent factory privilege.
/// @dev Names must separately be registered in their real ENSv2 parent registry.
contract MateResolverFactory {
    address public immutable implementation;
    uint256 public constant RECORD_ROLES = uint256(1) | (uint256(1) << 4);
    uint256 public constant OWNER_ROLES = RECORD_ROLES | (RECORD_ROLES << 128);
    mapping(bytes32 => address) public resolvers;
    error InvalidInput();
    event ResolverCreated(bytes32 indexed salt, bytes32 indexed node, address resolver, address owner, address agent);
    constructor(address resolverImplementation) {
        if (resolverImplementation.code.length == 0) revert InvalidInput();
        implementation = resolverImplementation;
    }
    function saltOf(bytes32 node, address owner, address agent) public pure returns (bytes32) {
        return keccak256(abi.encode(node, owner, agent));
    }
    function create(bytes calldata dnsName, bytes32 node, address owner, address agent) external returns (address resolver) {
        if (node == bytes32(0) || owner == address(0) || agent == address(0) || owner == agent
            || dnsName.length < 3 || dnsName.length > 255 || _namehash(dnsName, 0) != node) revert InvalidInput();
        bytes32 salt = saltOf(node, owner, agent);
        resolver = resolvers[salt];
        if (resolver != address(0)) return resolver;
        bytes[] memory empty = new bytes[](0);
        resolver = address(new MateProxy{salt:salt}(implementation,
            abi.encodeCall(IMateENSResolver.initialize, (address(this), OWNER_ROLES, empty))));
        resolvers[salt] = resolver;
        IMateENSResolver target = IMateENSResolver(resolver);
        target.setAddr(node, agent);
        target.setText(node, "agent-context", "ZeroKey Mate. A personal companion with owner-approved, proof-gated delegation.");
        target.authorizeTextRoles(dnsName, "avatar", agent, true);
        target.grantRootRoles(OWNER_ROLES, owner);
        target.revokeRootRoles(OWNER_ROLES, address(this));
        emit ResolverCreated(salt, node, resolver, owner, agent);
    }
    function _namehash(bytes calldata name, uint256 offset) private pure returns (bytes32) {
        if (offset >= name.length) revert InvalidInput();
        uint256 length = uint8(name[offset]);
        if (length == 0) {
            if (offset + 1 != name.length) revert InvalidInput();
            return bytes32(0);
        }
        if (length > 63 || offset + 1 + length >= name.length) revert InvalidInput();
        bytes32 parent = _namehash(name, offset + 1 + length);
        bytes32 label = keccak256(name[offset + 1:offset + 1 + length]);
        return keccak256(abi.encodePacked(parent, label));
    }
}
