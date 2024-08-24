// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Import ERC20 interface and SafeERC20 utility from OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Importing Chainlink's AggregatorV3Interface
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title TokenizedPortfolio
 * @dev A tokenized portfolio for managing multiple assets, transferring, rebalancing, checking risk, staking, flash loans, governance tokens, dynamic fees, insurance, referral system, and governance voting.
 */
contract TokenizedPortfolio {
    using SafeERC20 for IERC20;

    struct Asset {
        string symbol;
        uint256 amount;
        uint256 value;
    }

    struct Portfolio {
        address owner;
        uint256 totalValue;
        uint256 totalShares;
        Asset[] assets;
        uint256[] historicalValues;
        uint256 lastUpdateTimestamp;
        uint256 minValueThreshold;
        uint256 maxValueThreshold;
        uint256 managementFee;
        uint256 performanceFee;
        uint256 riskScore; // Tracks risk score
    }

    struct StakeInfo {
        uint256 amount;
        uint256 lastStakeTime;
    }

    struct InsurancePolicy {
        bool isActive;
        uint256 coverageAmount;
        uint256 premiumPaid;
        uint256 policyStartDate;
    }

    struct Proposal {
        string description;
        uint256 voteCount;
        bool executed;
        uint256 createdAt;
        uint256 votingDeadline;
    }

    mapping(address => Portfolio) public portfolios;
    mapping(address => StakeInfo) public stakes;
    mapping(address => InsurancePolicy) public insurancePolicies;
    mapping(string => address) public priceFeeds;
    mapping(address => address) public referrers;
    Proposal[] public proposals;

    IERC20 public immutable governanceToken;
    uint256 public governanceTokenSupply;
    uint256 public totalStaked;
    uint256 public flashLoanFee = 0.05 ether; // Flash loan fee is 5%
    uint256 public totalVotes; // Track total votes for governance

    event AssetUpdated(
        address indexed owner,
        string assetSymbol,
        uint256 oldValue,
        uint256 newValue
    );

    event FeesApplied(
        address indexed owner,
        uint256 managementFee,
        uint256 performanceFee
    );

    event Withdrawn(address indexed owner, address to, string assetSymbol, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event FlashLoanTaken(address indexed borrower, uint256 amount);
    event GovernanceTokensIssued(address indexed user, uint256 amount);
    event ProposalCreated(uint256 proposalId, string description, uint256 votingDeadline);
    event VoteCast(uint256 proposalId, address voter, uint256 votes);
    event InsurancePurchased(address indexed user, uint256 coverageAmount, uint256 premium);
    event InsuranceClaimed(address indexed user, uint256 coverageAmount);
    event StakingRewardClaimed(address indexed user, uint256 rewardAmount);
    event SlashedForFlashLoanMisuse(address indexed user, uint256 amount);

    constructor(address _governanceToken) {
        governanceToken = IERC20(_governanceToken);
    }

    /**
     * @dev Initializes a new portfolio with an owner.
     */
    function initializePortfolio() external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == address(0), "Portfolio already exists.");

        portfolio.owner = msg.sender;
        portfolio.totalValue = 0;
        portfolio.lastUpdateTimestamp = block.timestamp;
        portfolio.minValueThreshold = 0;
        portfolio.maxValueThreshold = type(uint256).max;
        portfolio.managementFee = 0;
        portfolio.performanceFee = 0;
        portfolio.totalShares = 1_000_000;
    }

    /**
     * @dev Adds an asset to the portfolio.
     */
    function addAsset(
        string memory assetSymbol,
        uint256 assetAmount,
        uint256 assetValue
    ) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");

        portfolio.totalValue += assetValue;
        portfolio.assets.push(Asset(assetSymbol, assetAmount, assetValue));

        emit AssetUpdated(msg.sender, assetSymbol, 0, assetValue);
    }

    /**
     * @dev Adds a price feed for a specific asset symbol.
     */
    function setPriceFeed(string memory assetSymbol, address priceFeed) external {
        require(priceFeeds[assetSymbol] == address(0), "Price feed already set.");
        priceFeeds[assetSymbol] = priceFeed;
    }

    /**
     * @dev Updates the value of an asset using a Chainlink oracle.
     */
    function updateAssetValueWithOracle(string memory assetSymbol) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");

        Asset storage asset = _findAsset(portfolio, assetSymbol);
        uint256 oldValue = asset.value;

        uint256 oraclePrice = getLatestPrice(assetSymbol);
        require(oraclePrice > 0, "Invalid oracle price");

        uint256 newValue = oraclePrice * asset.amount;
        portfolio.totalValue = portfolio.totalValue - oldValue + newValue;
        asset.value = newValue;

        emit AssetUpdated(msg.sender, assetSymbol, oldValue, newValue);
    }

    /**
     * @dev Gets the latest price of an asset from a Chainlink oracle.
     */
    function getLatestPrice(string memory assetSymbol) public view returns (uint256) {
        address priceFeedAddress = priceFeeds[assetSymbol];
        require(priceFeedAddress != address(0), "No price feed for asset");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");

        return uint256(price) * 1e10; // Convert to 18 decimals
    }

    /**
     * @dev Allows users to stake tokens into the portfolio.
     */
    function stakeTokens(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");

        governanceToken.safeTransferFrom(msg.sender, address(this), amount);
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].lastStakeTime = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Withdraws staked tokens.
     */
    function withdrawStake(uint256 amount) external {
        require(stakes[msg.sender].amount >= amount, "Insufficient staked balance");
        require(amount > 0, "Amount must be greater than 0");

        stakes[msg.sender].amount -= amount;
        governanceToken.safeTransfer(msg.sender, amount);
        totalStaked -= amount;
    }

    /**
     * @dev Issues governance tokens to portfolio holders.
     */
    function issueGovernanceTokens(uint256 amount) external {
        require(governanceTokenSupply + amount <= governanceToken.totalSupply(), "Exceeds max supply");
        require(portfolios[msg.sender].owner == msg.sender, "Not portfolio owner");

        governanceTokenSupply += amount;
        governanceToken.safeTransfer(msg.sender, amount);

        emit GovernanceTokensIssued(msg.sender, amount);
    }

    /**
     * @dev Flash loan logic, which requires the loan and fee to be repaid within the same transaction.
     */
    function takeFlashLoan(uint256 amount) external {
        require(amount <= address(this).balance, "Insufficient liquidity");

        uint256 fee = (amount * flashLoanFee) / 1 ether;
        uint256 repayment = amount + fee;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Loan transfer failed");

        emit FlashLoanTaken(msg.sender, amount);

        require(msg.sender.balance >= repayment, "Flash loan repayment failed");
    }

    /**
     * @dev Slashing mechanism to penalize users who misuse flash loans.
     */
    function slashForFlashLoanMisuse(address user, uint256 amount) internal {
        stakes[user].amount -= amount;
        require(stakes[user].amount >= 0, "Insufficient staked amount for slashing");

        emit SlashedForFlashLoanMisuse(user, amount);
    }

    /**
     * @dev Withdraw an asset from the portfolio.
     */
    function withdrawAsset(
        address assetAddress,
        address to,
        string memory assetSymbol,
        uint256 amount
    ) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");

        Asset storage asset = _findAsset(portfolio, assetSymbol);
        require(asset.amount >= amount, "Insufficient asset balance.");

        asset.amount -= amount;
        portfolio.totalValue -= (asset.value * amount) / asset.amount;

        IERC20(assetAddress).safeTransfer(to, amount);

        emit Withdrawn(msg.sender, to, assetSymbol, amount);
    }

    /**
     * @dev Emergency withdrawal of all assets by the portfolio owner.
     */
    function emergencyWithdrawAllAssets(address[] memory assetAddresses) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");

        for (uint256 i = 0; i < assetAddresses.length; i++) {
            Asset storage asset = portfolio.assets[i];
            require(asset.amount > 0, "No assets available to withdraw");

            uint256 amountToWithdraw = asset.amount;
            asset.amount = 0;
            IERC20(assetAddresses[i]).safeTransfer(msg.sender, amountToWithdraw);

            emit Withdrawn(msg.sender, msg.sender, asset.symbol, amountToWithdraw);
        }
    }

    /**
     * @dev Rebalances the portfolio.
     */
    function rebalancePortfolio(
        string[] memory assetSymbols,
        uint256[] memory targetRatios
    ) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");
        require(assetSymbols.length == targetRatios.length, "Array lengths mismatch.");

        uint256 totalValue = portfolio.totalValue;

        for (uint256 i = 0; i < assetSymbols.length; i++) {
            Asset storage asset = _findAsset(portfolio, assetSymbols[i]);
            uint256 targetValue = (totalValue * targetRatios[i]) / 100;
            asset.value = targetValue;
        }
    }

    /**
     * @dev Checks if the portfolio violates predefined risk thresholds.
     */
    function checkRisk() external view returns (bool) {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");

        if (portfolio.totalValue < portfolio.minValueThreshold) {
            return false;
        }

        if (portfolio.totalValue > portfolio.maxValueThreshold) {
            return false;
        }

        return true;
    }

    /**
     * @dev Referral system to reward users for referring others.
     */
    function referUser(address newUser) external {
        require(referrers[newUser] == address(0), "User already referred");

        referrers[newUser] = msg.sender;
        // Reward both referrer and new user (could be governance tokens)
    }

    /**
     * @dev Create a new governance proposal with a time-locked voting deadline.
     */
    function createProposal(string memory description, uint256 votingPeriod) external {
        uint256 votingDeadline = block.timestamp + votingPeriod;
        proposals.push(Proposal({
            description: description,
            voteCount: 0,
            executed: false,
            createdAt: block.timestamp,
            votingDeadline: votingDeadline
        }));

        emit ProposalCreated(proposals.length - 1, description, votingDeadline);
    }

    /**
     * @dev Cast a vote on a governance proposal if the voting deadline is still active.
     */
    function vote(uint256 proposalId, uint256 votes) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.votingDeadline, "Voting period has ended.");
        require(votes > 0, "Must cast at least 1 vote");
        require(proposal.executed == false, "Proposal already executed");

        totalVotes += votes;
        proposal.voteCount += votes;

        emit VoteCast(proposalId, msg.sender, votes);
    }

    /**
     * @dev Allows users to buy an insurance policy for their portfolio.
     */
    function buyInsurance(uint256 coverageAmount, uint256 premium) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");
        require(premium == coverageAmount / 100, "Incorrect premium amount");

        insurancePolicies[msg.sender] = InsurancePolicy({
            isActive: true,
            coverageAmount: coverageAmount,
            premiumPaid: premium,
            policyStartDate: block.timestamp
        });

        emit InsurancePurchased(msg.sender, coverageAmount, premium);
    }

    /**
     * @dev Claims insurance for the portfolio.
     */
    function claimInsurance() external {
        InsurancePolicy storage policy = insurancePolicies[msg.sender];
        require(policy.isActive, "No active insurance policy");

        // Logic to determine eligibility (e.g., portfolio value dropped below a threshold)
        policy.isActive = false;
        governanceToken.safeTransfer(msg.sender, policy.coverageAmount);

        emit InsuranceClaimed(msg.sender, policy.coverageAmount);
    }

    /**
     * @dev Reward long-term stakers based on the staking duration.
     */
    function claimStakingRewards() external {
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.amount > 0, "No staked tokens");

        uint256 stakingDuration = block.timestamp - stakeInfo.lastStakeTime;
        uint256 rewardMultiplier = stakingDuration / 30 days; // Example: 1x reward for every 30 days

        uint256 rewardAmount = stakeInfo.amount * rewardMultiplier / 100; // Example: 1% reward per month
        governanceToken.safeTransfer(msg.sender, rewardAmount);

        emit StakingRewardClaimed(msg.sender, rewardAmount);
    }

    /**
     * @dev Applies dynamic management and performance fees.
     */
    function applyDynamicFees(uint256 performanceBonusThreshold) external {
        Portfolio storage portfolio = portfolios[msg.sender];
        require(portfolio.owner == msg.sender, "Not portfolio owner.");

        uint256 managementFee = (portfolio.totalValue * portfolio.managementFee) / 100;
        uint256 performanceFee = calculatePerformanceFee(portfolio);

        if (portfolio.totalValue > performanceBonusThreshold) {
            performanceFee += (portfolio.totalValue * 5) / 100; // Bonus fee
        }

        portfolio.totalValue -= (managementFee + performanceFee);

        emit FeesApplied(msg.sender, managementFee, performanceFee);
    }

    /**
     * @dev Internal function to calculate performance fees.
     */
    function calculatePerformanceFee(Portfolio storage portfolio) internal view returns (uint256) {
        return (portfolio.totalValue * portfolio.performanceFee) / 100;
    }

    /**
     * @dev Internal function to find an asset by symbol.
     */
    function _findAsset(Portfolio storage portfolio, string memory assetSymbol) internal view returns (Asset storage) {
        for (uint256 i = 0; i < portfolio.assets.length; i++) {
            if (keccak256(abi.encodePacked(portfolio.assets[i].symbol)) == keccak256(abi.encodePacked(assetSymbol))) {
                return portfolio.assets[i];
            }
        }
        revert("Asset not found");
    }
}
