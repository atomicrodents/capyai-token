// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@layerzero-labs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

contract CapyEthToken is ERC20, ERC20Burnable, Pausable, Ownable, ReentrancyGuard, NonblockingLzApp {
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

    // LayerZero variables
    mapping(uint16 => bytes) public trustedRemoteLookup;
    uint16 public constant ETHEREUM_CHAIN_ID = 1;
    uint16 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant POLYGON_CHAIN_ID = 137;
    uint16 public constant SOLANA_CHAIN_ID = 168; // LayerZero chain ID for Solana

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TaxRateUpdated(uint256 newRate);
    event MaxTransferAmountUpdated(uint256 newAmount);

    constructor(
        address _lzEndpoint,
        address _treasuryWallet,
        address _developmentWallet,
        address _marketingWallet,
        address _teamWallet
    ) ERC20("Capy AI", "CAPYAI") NonblockingLzApp(_lzEndpoint) {
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

    // LayerZero bridge functions
    function bridge(
        uint16 _dstChainId,
        bytes calldata _destination,
        uint256 _amount
    ) public payable {
        require(_amount > 0, "Must bridge more than 0");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        // Burn tokens on this chain
        _burn(msg.sender, _amount);
        
        bytes memory payload = abi.encode(msg.sender, _amount);
        _lzSend(_dstChainId, payload, payable(msg.sender), address(0x0), bytes(""), msg.value);
        
        emit BridgeTransfer(msg.sender, _dstChainId.toString(), address(0), _amount);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        require(trustedRemoteLookup[_srcChainId].length != 0, "Source chain not trusted");
        
        (address toAddress, uint256 amount) = abi.decode(_payload, (address, uint256));
        
        // Mint tokens on this chain
        _mint(toAddress, amount);
        
        emit TokensBridged(toAddress, amount, _srcChainId.toString());
    }

    // Trust management for LayerZero
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external onlyOwner {
        trustedRemoteLookup[_remoteChainId] = _path;
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

        uint256 receiveAmount = amount - taxAmount;

        super._transfer(sender, recipient, receiveAmount);
        if (taxAmount > 0) {
            super._transfer(sender, treasuryWallet, taxAmount);
        }
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

    function toggleExemption(address account) external onlyOwner {
        isExemptFromLimit[account] = !isExemptFromLimit[account];
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}