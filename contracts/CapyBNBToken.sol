// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@layerzero-labs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

contract CapyBNBToken is ERC20, ERC20Burnable, Pausable, Ownable, ReentrancyGuard, NonblockingLzApp {
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
    address public treasuryWallet;
    address public developmentWallet;
    address public marketingWallet;
    address public teamWallet;

    // Vesting tracking
    mapping(address => uint256) public vestedAmount;

    // LayerZero variables for cross-chain
    mapping(uint16 => bytes) public trustedRemoteLookup;
    uint16 public constant ETHEREUM_CHAIN_ID = 1;
    uint16 public constant BASE_CHAIN_ID = 8453;
    uint16 public constant POLYGON_CHAIN_ID = 137;
    uint16 public constant BSC_CHAIN_ID = 56;

    // Staking variables
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakingStart;
    mapping(address => uint256) public lastClaimTime;
    uint256 public rewardRate = 10; // 10 tokens per day per 1000 staked (1%)
    uint256 public constant STAKING_PERIOD = 1 days;
    uint256 public minStakeAmount = 1000 * 10**18; // 1000 tokens minimum

    // Transfer limits and tax
    uint256 public maxTransferAmount = 1_000_000 * 10**18; // 1M tokens
    mapping(address => bool) public isExemptFromLimit;
    uint256 public transferTaxRate = 2; // 2% tax on transfers

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event BridgeTransfer(address indexed from, uint16 dstChainId, bytes toAddress, uint256 amount);

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

        treasuryWallet = _treasuryWallet;
        developmentWallet = _developmentWallet;
        marketingWallet = _marketingWallet;
        teamWallet = _teamWallet;

        teamVestingStart = block.timestamp;
        developmentVestingStart = block.timestamp;
        marketingVestingStart = block.timestamp;

        // Initial minting
        _mint(msg.sender, LIQUIDITY_ALLOCATION * 10**decimals());
        _mint(address(this), STAKING_ALLOCATION * 10**decimals());
        _mint(address(this), DEVELOPMENT_ALLOCATION * 10**decimals());
        _mint(address(this), MARKETING_ALLOCATION * 10**decimals());
        _mint(address(this), TEAM_ALLOCATION * 10**decimals());

        // Set exemptions
        isExemptFromLimit[msg.sender] = true;
        isExemptFromLimit[address(this)] = true;
    }

    // LayerZero bridge functions
    function bridge(uint16 dstChainId, bytes memory toAddress, uint256 amount) external payable {
        require(amount > 0, "Zero amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        
        bytes memory payload = abi.encode(toAddress, amount);
        _lzSend(dstChainId, payload, payable(msg.sender), address(0x0), bytes(""), msg.value);
        
        emit BridgeTransfer(msg.sender, dstChainId, toAddress, amount);
    }

    function _nonblockingLzReceive(uint16 srcChainId, bytes memory, uint64, bytes memory payload) internal override {
        (bytes memory toAddressBytes, uint256 amount) = abi.decode(payload, (bytes, uint256));
        address toAddress;
        assembly {
            toAddress := mload(add(toAddressBytes, 20))
        }
        
        _mint(toAddress, amount);
    }

    // Staking functions
    function stake(uint256 amount) external nonReentrant {
        require(amount >= minStakeAmount, "Below minimum stake");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        stakingStart[msg.sender] = block.timestamp;
        lastClaimTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked");

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

    // Vesting functions
    function claimVestedTokens() external {
        uint256 claimableAmount = 0;
        
        if (msg.sender == teamWallet) {
            require(block.timestamp >= teamVestingStart + TEAM_CLIFF_PERIOD, "Team tokens locked");
            claimableAmount = calculateVestedAmount(TEAM_ALLOCATION, teamVestingStart, TEAM_VESTING_DURATION);
        } else if (msg.sender == developmentWallet) {
            claimableAmount = calculateVestedAmount(DEVELOPMENT_ALLOCATION, developmentVestingStart, DEVELOPMENT_VESTING_DURATION);
        } else if (msg.sender == marketingWallet) {
            claimableAmount = calculateVestedAmount(MARKETING_ALLOCATION, marketingVestingStart, MARKETING_VESTING_PERIOD);
        }

        require(claimableAmount > 0, "No tokens to claim");
        require(claimableAmount > vestedAmount[msg.sender], "Already claimed");

        uint256 amount = claimableAmount - vestedAmount[msg.sender];
        vestedAmount[msg.sender] = claimableAmount;
        _transfer(address(this), msg.sender, amount);
    }

    function calculateVestedAmount(uint256 allocation, uint256 start, uint256 duration) internal view returns (uint256) {
        if (block.timestamp < start) return 0;
        if (block.timestamp >= start + duration) return allocation * 10**decimals();

        return (allocation * 10**decimals() * (block.timestamp - start)) / duration;
    }

    // Admin functions
    function setTrustedRemote(uint16 _chainId, bytes calldata _trustedRemote) external onlyOwner {
        trustedRemoteLookup[_chainId] = _trustedRemote;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Transfer function overrides
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused(), "Token paused");
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "Transfer from zero");
        require(recipient != address(0), "Transfer to zero");

        if (!isExemptFromLimit[sender] && !isExemptFromLimit[recipient]) {
            require(amount <= maxTransferAmount, "Exceeds max transfer");
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
}
