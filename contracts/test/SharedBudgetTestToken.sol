// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Explicit local test double, NOT USDC or a production payment integration.
contract SharedBudgetTestToken is ERC20 {
    bool public paused;
    bool public chargeFee;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackRejected;
    error TransfersPaused();
    constructor() ERC20("LOCAL TEST TOKEN", "LOCAL") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function configure(bool paused_, bool chargeFee_) external {
        paused = paused_; chargeFee = chargeFee_;
    }
    function configureCallback(address target, bytes calldata data) external {
        callbackTarget = target; callbackData = data;
    }
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            if (paused) revert TransfersPaused();
            if (callbackTarget != address(0)) {
                (bool success,) = callbackTarget.call(callbackData);
                callbackRejected = !success;
            }
            if (chargeFee && amount > 1) {
                super._update(from, to, amount - 1);
                super._update(from, address(0), 1);
                return;
            }
        }
        super._update(from, to, amount);
    }
}
