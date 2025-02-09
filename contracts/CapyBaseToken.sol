// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CapyBaseToken is ERC20, ERC20Burnable, Pausable, Ownable, ReentrancyGuard {
    // Constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000; // 1 billion tokens
    uint256 public constant LIQUIDITY_ALLOCATION = 400_000_000; // 40%
    uint256 public constant STAKING_ALLOCATION = 250_000_000; // 25%
    uint256 public constant DEVELOPMENT_ALLOCATION = 150_000_000; // 15%
    uint256 public constant MARKETING_ALLOCATION = 100_000_000; // 10%
    uint256 public constant TEAM_ALLOCATION = 100_000_000; // 10%

    // Vesting timestamps
    uint256 public immutable teamVestingStart;
    uint256 public constant TEAM_VESTING_DURATION = 730 days; // 2 years
    uint256 public constant TEAM_CLIFF_PERIOD = 365 days; // 1 year

    // Development and Marketing vesting
    uint256 public immutable developmentVestingStart;
    uint256 public constant DEVELOPMENT_VESTING_DURATION = 730 days; // 2 years

    uint256 public immutable marketingVestingStart;
    uint256 public constant MARKETING_VESTING_PERIOD = 90 days; // Quarterly vesting

    // Addresses for allocations
    address public developmentWallet;
    address public marketingWallet;
    address public teamWallet;

    // Vesting tracking
    mapping(address => uint256) public vestedAmount;

    // Bridge variables
    mapping(address => bool) public bridgeAddresses;
    event BridgeTransfer(address indexed from, string destinationChain, address indexed to, uint256 amount);
    event TokensBridged(address indexed to, uint256 amount, string sourceChain);

    // Staking variables
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakingStart;
    mapping(address => uint256) public lastClaimTime;

    uint256 public rewardRate = 10; // 10 tokens per day per 1000 staked (1%)
    uint256 public constant STAKING_PERIOD = 1 days;
    uint256 public minStakeAmount = 100 * 10**18; // Minimum 100 tokens

    // Anti-whale mechanism
    uint256 public maxTransferAmount;
    mapping(address => bool) public isExemptFromLimit;

    // Tax mechanism for liquidity/development
    uint256 public transferTaxRate = 2; // 2% tax
    address public treasuryWallet;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TaxRateUpdated(uint256 newRate);
    event MaxTransferAmountUpdated(uint256 newAmount);

    constructor(
        address _treasuryWallet,
        address _developmentWallet,
        address _marketingWallet,
        address _teamWallet
    ) ERC20("Capy AI", "CAPYAI") {
        require(_treasuryWallet != address(0), "Zero address");
        require(_developmentWallet != address(0), "Zero address");
        require(_marketingWallet != address(0), "Zero address");
        require(_teamWallet != address(0), "Zero address");

        uint256 totalSupply = INITIAL_SUPPLY * 10**decimals();

        // Mint initial liquidity allocation
        _mint(msg.sender, LIQUIDITY_ALLOCATION * 10**decimals());

        // Set up vesting wallets
        treasuryWallet = _treasuryWallet;
        developmentWallet = _developmentWallet;
        marketingWallet = _marketingWallet;
        teamWallet = _teamWallet;

        // Initialize vesting timestamps
        teamVestingStart = block.timestamp;
        developmentVestingStart = block.timestamp;
        marketingVestingStart = block.timestamp;

        // Set max transfer amount to 1% of total supply
        maxTransferAmount = totalSupply / 100;

        // Setup exempt addresses
        isExemptFromLimit[msg.sender] = true;
        isExemptFromLimit[address(this)] = true;
        isExemptFromLimit[_treasuryWallet] = true;
        isExemptFromLimit[_developmentWallet] = true;
        isExemptFromLimit[_marketingWallet] = true;
        isExemptFromLimit[_teamWallet] = true;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Staking functions
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount >= minStakeAmount, "Below minimum stake amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        if (stakedBalance[msg.sender] > 0) {
            claimRewards();
        }

        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        stakingStart[msg.sender] = block.timestamp;
        lastClaimTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked amount");

        claimRewards();
        stakedBalance[msg.sender] -= amount;
        _transfer(address(this), msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() public {
        uint256 rewards = calculateRewards(msg.sender);
        if (rewards > 0) {
            lastClaimTime[msg.sender] = block.timestamp;
            _mint(msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards);
        }
    }

    function calculateRewards(address user) public view returns (uint256) {
        if (stakedBalance[user] == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastClaimTime[user];
        return (stakedBalance[user] * rewardRate * timeElapsed) / (1000 * STAKING_PERIOD);
    }

    // Bridge functions
    function addBridge(address bridge) external onlyOwner {
        bridgeAddresses[bridge] = true;
    }

    function removeBridge(address bridge) external onlyOwner {
        bridgeAddresses[bridge] = false;
    }

    function bridgeTokens(string calldata destinationChain, address to, uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        emit BridgeTransfer(msg.sender, destinationChain, to, amount);
    }

    function receiveBridgedTokens(address to, uint256 amount) external nonReentrant whenNotPaused {
        require(bridgeAddresses[msg.sender], "Only bridge can mint");
        _mint(to, amount);
        emit TokensBridged(to, amount, "Base");
    }

    // Transfer override with tax and anti-whale
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(sender != address(0), "Transfer from zero");
        require(recipient != address(0), "Transfer to zero");

        if (!isExemptFromLimit[sender] && !isExemptFromLimit[recipient]) {
            require(amount <= maxTransferAmount, "Transfer amount exceeds limit");
        }

        uint256 taxAmount = 0;
        if (!isExemptFromLimit[sender] && !isExemptFromLimit[recipient]) {
            taxAmount = (amount * transferTaxRate) / 100;
        }

        if (taxAmount > 0) {
            super._transfer(sender, treasuryWallet, taxAmount);
        }
        super._transfer(sender, recipient, amount - taxAmount);
    }

    // Admin functions
    function setTransferTaxRate(uint256 newRate) external onlyOwner {
        require(newRate <= 10, "Tax rate too high"); // Max 10%
        transferTaxRate = newRate;
        emit TaxRateUpdated(newRate);
    }

    function setMaxTransferAmount(uint256 newAmount) external onlyOwner {
        maxTransferAmount = newAmount;
        emit MaxTransferAmountUpdated(newAmount);
    }

    function setTreasuryWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Zero address");
        treasuryWallet = newWallet;
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        rewardRate = newRate;
    }

    function setMinStakeAmount(uint256 newAmount) external onlyOwner {
        minStakeAmount = newAmount;
    }

    function setExemptFromLimit(address account, bool exempt) external onlyOwner {
        isExemptFromLimit[account] = exempt;
    }

    function withdrawStuckTokens(address token) external onlyOwner {
        require(token != address(this), "Cannot withdraw staking token");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }

    // Vesting claim functions
    function claimTeamTokens() external {
        require(msg.sender == teamWallet, "Not team wallet");
        require(block.timestamp >= teamVestingStart + TEAM_CLIFF_PERIOD, "Cliff period not ended");

        uint256 totalVestingTime = block.timestamp - (teamVestingStart + TEAM_CLIFF_PERIOD);
        if (totalVestingTime > TEAM_VESTING_DURATION) {
            totalVestingTime = TEAM_VESTING_DURATION;
        }

        uint256 totalVestable = TEAM_ALLOCATION * 10**decimals();
        uint256 vestedTokens = (totalVestable * totalVestingTime) / TEAM_VESTING_DURATION;
        uint256 claimable = vestedTokens - vestedAmount[teamWallet];

        require(claimable > 0, "No tokens to claim");
        vestedAmount[teamWallet] += claimable;
        _mint(teamWallet, claimable);
    }

    function claimDevelopmentTokens() external {
        require(msg.sender == developmentWallet, "Not development wallet");

        uint256 totalVestingTime = block.timestamp - developmentVestingStart;
        if (totalVestingTime > DEVELOPMENT_VESTING_DURATION) {
            totalVestingTime = DEVELOPMENT_VESTING_DURATION;
        }

        uint256 totalVestable = DEVELOPMENT_ALLOCATION * 10**decimals();
        uint256 vestedTokens = (totalVestable * totalVestingTime) / DEVELOPMENT_VESTING_DURATION;
        uint256 claimable = vestedTokens - vestedAmount[developmentWallet];

        require(claimable > 0, "No tokens to claim");
        vestedAmount[developmentWallet] += claimable;
        _mint(developmentWallet, claimable);
    }

    function claimMarketingTokens() external {
        require(msg.sender == marketingWallet, "Not marketing wallet");

        uint256 periods = (block.timestamp - marketingVestingStart) / MARKETING_VESTING_PERIOD;
        uint256 totalVestable = MARKETING_ALLOCATION * 10**decimals();
        uint256 vestedTokens = (totalVestable * periods) / 8; // 8 quarters in 2 years
        uint256 claimable = vestedTokens - vestedAmount[marketingWallet];

        require(claimable > 0, "No tokens to claim");
        vestedAmount[marketingWallet] += claimable;
        _mint(marketingWallet, claimable);
    }
}
