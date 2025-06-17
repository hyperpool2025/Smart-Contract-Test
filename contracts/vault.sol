// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ILendingProtocol.sol";

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        _status = _NOT_ENTERED;
    }

    modifier isHuman() {
        require(tx.origin == msg.sender, "sorry humans only");
        _;
    }
}
contract USDCVault is ERC4626, Ownable, ReentrancyGuard {
    IERC20 public immutable usdc;
    ILendingProtocol public currentProtocol;
    address public treasury;
    bool public active = true;

    mapping(address => uint256) public initialDeposits;

    event ProtocolRestaked(address newProtocol);

    constructor(
        address _usdc,
        address _treasury,
        address _protocol
    )
        ERC20("Vault aToken", "vaUSDC")
        ERC4626(IERC20(_usdc))
        Ownable(address(msg.sender))
    {
        usdc = IERC20(_usdc);
        treasury = _treasury;
        currentProtocol = ILendingProtocol(_protocol);
    }

    modifier onlyTreasury() {
        require(msg.sender == treasury, "Only treasury can call");
        _;
    }
    //make sure contract is active
    modifier whenActive() {
        require(active == true, "Smart contract is curently inactive");
        _;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public override isHuman nonReentrant whenActive returns (uint256 shares) {
        require(assets > 0, "Amount must be > 0");
        require(usdc.balanceOf(msg.sender)>=assets,"Insuffient USDC balance");
        usdc.transferFrom(msg.sender, address(this), assets);
        usdc.approve(address(currentProtocol), assets);
        currentProtocol.supply(address(usdc), assets, address(this), 0);

        shares = assets;
        _mint(receiver, shares);
        uint256 initialDeposit = initialDeposits[receiver];
        initialDeposit += assets;
        initialDeposits[receiver] = initialDeposit;

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override isHuman nonReentrant whenActive returns (uint256 shares) {
        require(assets > 0, "Amount must be > 0");
        require(balanceOf(owner) >= assets, "Insufficient shares");

        uint256 totalBalance = currentProtocol.balanceOf(
            address(usdc),
            address(this)
        );
        uint256 userShare = (totalBalance * assets) / totalSupply();

        uint256 initial = (initialDeposits[owner] * assets) / balanceOf(owner);
        uint256 profit = userShare > initial ? userShare - initial : 0;
        uint256 fee = (profit * 5) / 100;
        uint256 payout = userShare - fee;

        // Withdraw from protocol
        currentProtocol.withdraw(address(usdc), userShare, address(this));

        if (fee > 0) usdc.transfer(treasury, fee);
        usdc.transfer(receiver, payout);

        _burn(owner, assets);
        initialDeposits[owner] -= initial;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function restake(address newProtocol) external onlyOwner() {
        uint256 balance = currentProtocol.balanceOf(
            address(usdc),
            address(this)
        );
        currentProtocol.withdraw(address(usdc), balance, address(this));

        usdc.approve(newProtocol, balance);
        ILendingProtocol(newProtocol).supply(
            address(usdc),
            balance,
            address(this),
            0
        );

        currentProtocol = ILendingProtocol(newProtocol);

        emit ProtocolRestaked(newProtocol);
    }

    function getInitialDeposit(address user) external view returns (uint256) {
        return initialDeposits[user];
    }

    function getAvailableBalance(address user) external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        uint256 vaultBalance = currentProtocol.balanceOf(
            address(usdc),
            address(this)
        );
        uint256 full = (vaultBalance * balanceOf(user)) / totalSupply();
        uint256 initial = initialDeposits[user];
        uint256 profit = full > initial ? full - initial : 0;
        uint256 fee = (profit * 5) / 100;
        return full - fee;
    }
    function getTotalVolume() external view returns (uint256) {
        uint256 totalBalance = currentProtocol.balanceOf(
            address(usdc),
            address(this)
        );
        return totalBalance;
    }

    //used to pause/start the contract's functionalities
    function changeActiveStatus() external onlyOwner {
        if (active) {
            active = false;
        } else {
            active = true;
        }
    }

    //change treasury wallet
    function changeTreasury(address newTresury) external onlyOwner(){
        require(newTresury!=treasury,"Same address ditected");
        treasury=newTresury;
    }
}
