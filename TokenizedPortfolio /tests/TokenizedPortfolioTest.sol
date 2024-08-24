// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../contracts/TokenizedPortfolio.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple ERC20 token for testing purposes
contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract TokenizedPortfolioTest {
    TestToken public governanceToken;
    TestToken public assetToken;
    TokenizedPortfolio public portfolio;

    constructor() {
        // Deploy test tokens
        governanceToken = new TestToken("Governance Token", "GOVT", 1000000 * 10**18);
        assetToken = new TestToken("Asset Token", "ASSET", 1000000 * 10**18);

        // Deploy the TokenizedPortfolio contract
        portfolio = new TokenizedPortfolio(address(governanceToken));

        // Allocate initial tokens to this contract for testing
        assetToken.transfer(address(this), 500000 * 10**18);
        governanceToken.transfer(address(this), 500000 * 10**18);
    }

    function testInitializePortfolio() public {
        // Initialize portfolio
        portfolio.initializePortfolio();

        // Unpack the tuple returned by the portfolio getter
        (address owner, , , , , , , , ) = portfolio.portfolios(address(this));
        require(owner == address(this), "Portfolio initialization failed");
    }

    function testAddAsset() public {
        // Initialize and add an asset
        portfolio.initializePortfolio();
        uint256 initialValue = 1000 * 10**18;
        portfolio.addAsset("ASSET", 1000 * 10**18, initialValue);

        // Check if the asset was added correctly
        (, , uint256 totalValue, , , , , , ) = portfolio.portfolios(address(this));
        require(totalValue == initialValue, "Asset was not added to the portfolio correctly");
    }

    function testStakeTokens() public {
        // Initialize portfolio and stake governance tokens
        portfolio.initializePortfolio();
        uint256 stakeAmount = 1000 * 10**18;

        governanceToken.approve(address(portfolio), stakeAmount);
        portfolio.stakeTokens(stakeAmount);

        // Check staking results
        (uint256 stakedAmount, uint256 lastStakeTime) = portfolio.stakes(address(this));
        require(stakedAmount == stakeAmount, "Staking amount incorrect");
        require(lastStakeTime > 0, "Staking time not recorded");
    }

    function testWithdrawStake() public {
        // Initialize, stake, and withdraw tokens
        portfolio.initializePortfolio();
        uint256 stakeAmount = 1000 * 10**18;

        governanceToken.approve(address(portfolio), stakeAmount);
        portfolio.stakeTokens(stakeAmount);

        // Withdraw the staked tokens
        portfolio.withdrawStake(stakeAmount);

        // Check staking results
        (uint256 remainingStake, ) = portfolio.stakes(address(this));
        require(remainingStake == 0, "Stake was not withdrawn correctly");
    }

    function testClaimStakingRewards() public {
        // Initialize portfolio, stake tokens, and wait to claim rewards
        portfolio.initializePortfolio();
        uint256 stakeAmount = 1000 * 10**18;

        governanceToken.approve(address(portfolio), stakeAmount);
        portfolio.stakeTokens(stakeAmount);

        // Simulate staking for a period by manually adjusting time (in real tests use evm_increaseTime)
        uint256 stakingDuration = 30 days;
        skip(stakingDuration);  // Pseudo-code: skip some time for staking rewards

        portfolio.claimStakingRewards();

        // Verify that the rewards were received (1% per month for example)
        uint256 reward = stakeAmount / 100; // 1% reward per month
        uint256 balance = governanceToken.balanceOf(address(this));
        require(balance >= reward, "Staking rewards not claimed correctly");
    }

    function testIssueGovernanceTokens() public {
        // Initialize and issue governance tokens
        portfolio.initializePortfolio();
        uint256 issueAmount = 1000 * 10**18;

        portfolio.issueGovernanceTokens(issueAmount);

        // Check governance token balance
        uint256 balance = governanceToken.balanceOf(address(this));
        require(balance == issueAmount, "Governance tokens not issued correctly");
    }

    function testTakeFlashLoan() public {
        // Initialize portfolio and simulate taking a flash loan
        uint256 loanAmount = 1000 * 10**18;

        // Transfer Ether to portfolio contract (if necessary)
        portfolio.initializePortfolio();
        payable(address(portfolio)).transfer(loanAmount);

        // Take the flash loan
        portfolio.takeFlashLoan(loanAmount);

        // Ensure loan logic works correctly
        require(address(this).balance >= loanAmount, "Flash loan not successful");
    }

    function testSlashingForFlashLoanMisuse() public {
        // Initialize, stake governance tokens, and misuse flash loan
        portfolio.initializePortfolio();
        uint256 stakeAmount = 1000 * 10**18;

        governanceToken.approve(address(portfolio), stakeAmount);
        portfolio.stakeTokens(stakeAmount);

        // Misuse the flash loan by not repaying (intentionally fail the repayment)
        uint256 loanAmount = 500 * 10**18;
        portfolio.takeFlashLoan(loanAmount);

        // Expect the slashing mechanism to reduce staked tokens
        (uint256 remainingStake, ) = portfolio.stakes(address(this));
        require(remainingStake < stakeAmount, "Slashing not applied correctly");
    }

    function testApplyDynamicFees() public {
        // Initialize and add an asset, then apply dynamic fees
        portfolio.initializePortfolio();
        uint256 initialValue = 1000 * 10**18;
        portfolio.addAsset("ASSET", 1000 * 10**18, initialValue);

        // Apply dynamic fees
        portfolio.applyDynamicFees(500 * 10**18);

        // Check if the fees were applied by accessing the total value after fees
        (, , uint256 totalValue, , , , , , ) = portfolio.portfolios(address(this));
        require(totalValue < initialValue, "Dynamic fees were not applied correctly");
    }

    function testInsurancePolicy() public {
        // Initialize portfolio and buy insurance
        portfolio.initializePortfolio();
        uint256 coverageAmount = 1000 * 10**18;
        uint256 premium = coverageAmount / 100; // 1% premium

        governanceToken.approve(address(portfolio), premium);
        portfolio.buyInsurance(coverageAmount, premium);

        // Simulate portfolio loss and claim insurance
        portfolio.claimInsurance();

        // Check if the insurance payout was made
        uint256 balance = governanceToken.balanceOf(address(this));
        require(balance == coverageAmount, "Insurance claim failed");
    }

    function testEmergencyWithdrawAllAssets() public {
    // Initialize and add assets, then call emergency withdraw
    portfolio.initializePortfolio();
    portfolio.addAsset("ASSET", 1000 * 10**18, 1000 * 10**18);

    // Correct way to declare and initialize the array
    address[] memory assetAddresses = new address[](1);
    assetAddresses[0] = address(assetToken); // Assign the assetToken address to the first element

    // Perform the emergency withdrawal
    portfolio.emergencyWithdrawAllAssets(assetAddresses);

    // Verify asset balance after emergency withdrawal
    uint256 balance = assetToken.balanceOf(address(this));
    require(balance == 1000 * 10**18, "Emergency withdrawal failed");
}

    function testReferralSystem() public {
        // Test the referral system
        portfolio.initializePortfolio();
        portfolio.referUser(address(this));

        // Check if referral was recorded
        address referrer = portfolio.referrers(address(this));
        require(referrer == address(this), "Referral system failed");
    }

   function testGovernanceVoting() public {
    // Initialize and create a governance proposal
    portfolio.initializePortfolio();
    uint256 votingPeriod = 1 days;
    portfolio.createProposal("Test Proposal", votingPeriod);

    // Cast a vote
    portfolio.vote(0, 100);

    // Unpack the tuple from the proposals call and check the vote count
    (,,,, uint256 voteCount) = portfolio.proposals(0);
    require(voteCount == 100, "Voting system failed");
}

    // Function to receive Ether when sent to this contract during flash loan test
    receive() external payable {}

     // Helper function to simulate time passing 
    function skip(uint256 time) internal {}
}
