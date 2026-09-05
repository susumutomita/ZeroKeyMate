// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/// @dev Test fixture used ONLY by local contract tests, never a production payment asset.
contract TestToken is ERC20 {
    constructor() ERC20("Local test units", "TEST") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}
