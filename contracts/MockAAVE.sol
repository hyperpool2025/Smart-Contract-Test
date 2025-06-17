// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockAToken.sol";
import "./ILendingProtocol.sol";

contract MockAAVE is ILendingProtocol {
    MockAToken public aToken;
    IERC20 public usdc;

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
        aToken = new MockAToken("Mock aUSDC", "aUSDC");
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        require(asset == address(usdc), "Only USDC");
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "USDC transfer failed"
        );
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        require(asset == address(usdc), "Only USDC");
        aToken.burn(msg.sender, amount);
        require(usdc.transfer(to, amount), "USDC transfer failed");
        return amount;
    }

    function balanceOf(
        address asset,
        address user
    ) external view override returns (uint256) {
        require(asset == address(usdc), "Only USDC");
        return aToken.balanceOf(user);
    }
    function mintYield(address to, uint256 amount) external {
        aToken.mint(to, amount);
    }
}
