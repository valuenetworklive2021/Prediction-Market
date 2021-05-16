//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./BetToken.sol";
import "./AggregatorV3Interface.sol";

contract PredictionMarket is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    uint256 public latestConditionIndex;

    uint256 public fee;
    uint256 public feeRate;
    address operatorAddress;

    mapping(uint256 => ConditionInfo) public conditions;

    struct ConditionInfo {
        string market;
        address oracle;
        int256 triggerPrice;
        uint256 settlementTime;
        bool isSettled;
        int256 settledPrice;
        address lowBetToken;
        address highBetToken;
        uint256 totalStakedAbove;
        uint256 totalStakedBelow;
        uint256 totalEthClaimable;
    }

    event ConditionPrepared(
        uint256 indexed conditionIndex,
        address indexed oracle,
        uint256 indexed settlementTime,
        int256 triggerPrice,
        address lowBetTokenAddress,
        address highBetTokenAddress
    );
    event UserPrediction(
        uint256 indexed conditionIndex,
        address indexed userAddress,
        uint256 indexed ETHStaked,
        uint8 prediction,
        uint256 timestamp
    );
    event UserClaimed(
        uint256 indexed conditionIndex,
        address indexed userAddress,
        uint256 indexed winningAmount
    );
    event ConditionSettled(
        uint256 indexed conditionIndex,
        int256 indexed settledPrice,
        uint256 timestamp
    );
    event OperatorSet(address operatorAddress);
    event FeeSet(uint256 feeRate);

    constructor() {
        feeRate = 10;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "ERR_INVALID_OPERATOR");
        _;
    }

    function setOperator(address _operatorAddress) external onlyOwner {
        require(_operatorAddress != address(0), "ERR_INVALID_OPERATOR_ADDRESS");
        operatorAddress = _operatorAddress;
        emit OperatorSet(operatorAddress);
    }

    function setFee(uint256 _feeRate) external onlyOwner {
        feeRate = _feeRate;
        emit FeeSet(feeRate);
    }

    function execute(uint256 conditionIndex, uint256 interval)
        external
        payable
        nonReentrant
        onlyOperator
    {
        ConditionInfo storage condition = conditions[conditionIndex];
        require(condition.oracle != address(0), "ERR_INVALID_CONDITION_INDEX");
        require(interval >= 300, "ERR_SETTLEMENT_TIME_INTERVAL");

        //settle and claim for previous index
        claimFor(msg.sender, conditionIndex);

        //prepare new condition
        int256 triggerPrice = getPrice(condition.oracle);
        uint256 newIndex =
            prepareCondition(
                condition.oracle,
                block.timestamp + interval,
                triggerPrice
            );

        //betOnConditionFor admin
        uint256 amount0 = msg.value.div(2);

        betOnConditionFor(msg.sender, newIndex, 0, amount0);
        betOnConditionFor(msg.sender, newIndex, 1, msg.value.sub(amount0));
    }

    function prepareCondition(
        address _oracle,
        uint256 _settlementTime,
        int256 _triggerPrice
    ) public whenNotPaused returns (uint256) {
        require(_oracle != address(0), "ERR_INVALID_ORACLE_ADDRESS");
        require(
            _settlementTime > block.timestamp,
            "ERR_INVALID_SETTLEMENT_TIME"
        );
        latestConditionIndex = latestConditionIndex.add(1);
        ConditionInfo storage conditionInfo = conditions[latestConditionIndex];

        conditionInfo.market = IAggregatorV3Interface(_oracle).description();
        conditionInfo.oracle = _oracle;
        conditionInfo.settlementTime = _settlementTime;
        conditionInfo.triggerPrice = _triggerPrice;
        conditionInfo.isSettled = false;
        conditionInfo.lowBetToken = address(
            new BetToken(
                "Low Bet Token",
                string(abi.encodePacked("LBT-", conditionInfo.market))
            )
        );
        conditionInfo.highBetToken = address(
            new BetToken(
                "High Bet Token",
                string(abi.encodePacked("HBT-", conditionInfo.market))
            )
        );
        emit ConditionPrepared(
            latestConditionIndex,
            _oracle,
            _settlementTime,
            _triggerPrice,
            conditionInfo.lowBetToken,
            conditionInfo.highBetToken
        );

        return latestConditionIndex;
    }

    function probabilityRatio(uint256 _conditionIndex)
        external
        view
        returns (uint256 aboveProbabilityRatio, uint256 belowProbabilityRatio)
    {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];
        if (conditionInfo.isSettled) {
            return (0, 0);
        }
        uint256 ethStakedForAbove =
            BetToken(conditionInfo.highBetToken).totalSupply();
        uint256 ethStakedForBelow =
            BetToken(conditionInfo.lowBetToken).totalSupply();

        uint256 totalEthStaked = ethStakedForAbove.add(ethStakedForBelow);

        aboveProbabilityRatio = totalEthStaked > 0
            ? ethStakedForAbove.mul(1e18).div(totalEthStaked)
            : 0;
        belowProbabilityRatio = totalEthStaked > 0
            ? ethStakedForBelow.mul(1e18).div(totalEthStaked)
            : 0;
    }

    function userTotalETHStaked(uint256 _conditionIndex, address userAddress)
        external
        view
        returns (uint256 totalEthStaked)
    {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];
        uint256 ethStakedForAbove =
            BetToken(conditionInfo.highBetToken).balanceOf(userAddress);
        uint256 ethStakedForBelow =
            BetToken(conditionInfo.lowBetToken).balanceOf(userAddress);

        totalEthStaked = ethStakedForAbove.add(ethStakedForBelow);
    }

    function betOnCondition(uint256 _conditionIndex, uint8 _prediction)
        external
        payable
    {
        //call betOncondition
        betOnConditionFor(msg.sender, _conditionIndex, _prediction, msg.value);
    }

    function betOnConditionFor(
        address _user,
        uint256 _conditionIndex,
        uint8 _prediction,
        uint256 _amount
    ) public payable whenNotPaused {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];

        require(_user != address(0), "ERR_INVALID_ADDRESS");

        require(
            conditionInfo.oracle != address(0),
            "ERR_INVALID_ORACLE_ADDRESS"
        );
        require(
            block.timestamp < conditionInfo.settlementTime,
            "ERR_INVALID_SETTLEMENT_TIME"
        );

        require(msg.value >= _amount, "ERR_INVALID_AMOUNT");
        uint256 userETHStaked = _amount;
        require(userETHStaked > 0 wei, "ERR_INVALID_BET_AMOUNT");
        require(
            (_prediction == 0) || (_prediction == 1),
            "ERR_INVALID_PREDICTION"
        ); //prediction = 0 (price will be below), if 1 (price will be above)

        if (_prediction == 0) {
            BetToken(conditionInfo.lowBetToken).mint(_user, userETHStaked);
        } else {
            BetToken(conditionInfo.highBetToken).mint(_user, userETHStaked);
        }
        emit UserPrediction(
            _conditionIndex,
            _user,
            userETHStaked,
            _prediction,
            block.timestamp
        );
    }

    function settleCondition(uint256 _conditionIndex) public whenNotPaused {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];
        require(
            conditionInfo.oracle != address(0),
            "ERR_INVALID_ORACLE_ADDRESS"
        );
        require(
            block.timestamp >= conditionInfo.settlementTime,
            "ERR_INVALID_SETTLEMENT_TIME"
        );
        require(!conditionInfo.isSettled, "ERR_CONDITION_ALREADY_SETTLED");

        conditionInfo.isSettled = true;
        conditionInfo.totalStakedAbove = BetToken(conditionInfo.highBetToken)
            .totalSupply();
        conditionInfo.totalStakedBelow = BetToken(conditionInfo.lowBetToken)
            .totalSupply();

        uint256 _fees = conditionInfo.totalEthClaimable.div(1000).mul(feeRate);

        conditionInfo.totalEthClaimable = conditionInfo
            .totalStakedAbove
            .add(conditionInfo.totalStakedBelow)
            .sub(_fees);

        fee = fee.add(_fees);
        conditionInfo.settledPrice = getPrice(conditionInfo.oracle);

        emit ConditionSettled(
            _conditionIndex,
            conditionInfo.settledPrice,
            block.timestamp
        );
    }

    function getPrice(address oracle)
        internal
        view
        returns (int256 latestPrice)
    {
        (, latestPrice, , , ) = IAggregatorV3Interface(oracle)
            .latestRoundData();
    }

    function claim(uint256 _conditionIndex) public {
        //require for non zero address
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];
        require(
            conditionInfo.oracle != address(0),
            "ERR_INVALID_ORACLE_ADDRESS"
        );
        //call claim with msg.sender as _for
        claimFor(msg.sender, _conditionIndex);
    }

    function claimFor(address payable _userAddress, uint256 _conditionIndex)
        public
        whenNotPaused
        nonReentrant
    {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];

        BetToken lowBetToken = BetToken(conditionInfo.lowBetToken);
        BetToken highBetToken = BetToken(conditionInfo.highBetToken);
        if (!conditionInfo.isSettled) {
            settleCondition(_conditionIndex);
        }

        uint256 totalWinnerRedeemable;
        //Amount Redeemable including winnerRedeemable & user initial Stake
        if (conditionInfo.settledPrice > conditionInfo.triggerPrice) {
            //Users who predicted above price wins
            uint256 userStake = highBetToken.balanceOf(_userAddress);

            if (userStake == 0) {
                return;
            }
            totalWinnerRedeemable = getClaimAmount(
                conditionInfo.totalStakedBelow,
                conditionInfo.totalStakedAbove,
                userStake
            );
        } else if (conditionInfo.settledPrice < conditionInfo.triggerPrice) {
            //Users who predicted below price wins
            uint256 userStake = lowBetToken.balanceOf(_userAddress);

            if (userStake == 0) {
                return;
            }
            totalWinnerRedeemable = getClaimAmount(
                conditionInfo.totalStakedAbove,
                conditionInfo.totalStakedBelow,
                userStake
            );
        } else {
            fee = fee.add(conditionInfo.totalEthClaimable);
            totalWinnerRedeemable = 0;
        }

        highBetToken.burnAll(_userAddress);
        lowBetToken.burnAll(_userAddress);

        _userAddress.transfer(totalWinnerRedeemable);

        emit UserClaimed(_conditionIndex, _userAddress, totalWinnerRedeemable);
    }

    function claimFees() external whenNotPaused onlyOwner {
        if (fee != 0) {
            fee = 0;
            address _to = owner();
            payable(_to).transfer(fee);
        }
    }

    function getClaimAmount(
        uint256 totalPayout,
        uint256 winnersTotalETHStaked,
        uint256 userStake
    ) internal view returns (uint256 totalWinnerRedeemable) {
        uint256 userProportion = userStake.mul(1e18).div(winnersTotalETHStaked);
        uint256 winnerPayout = totalPayout.mul(userProportion).div(1e18);

        uint256 winnerRedeemable = (winnerPayout.div(1000)).mul(1000 - feeRate);
        totalWinnerRedeemable = winnerRedeemable.add(userStake);
    }

    function getBalance(uint256 _conditionIndex, address _user)
        external
        view
        returns (uint256 LBTBalance, uint256 HBTBalance)
    {
        ConditionInfo storage condition = conditions[_conditionIndex];
        LBTBalance = BetToken(condition.lowBetToken).balanceOf(_user);
        HBTBalance = BetToken(condition.highBetToken).balanceOf(_user);
    }
}
