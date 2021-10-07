//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./BetToken.sol";
import "./AggregatorV3Interface.sol";

contract PredictionMarket is Initializable, OwnableUpgradeable {
    uint256 public latestConditionIndex;
    uint256 public fee;
    uint256 public adminFeeRate;
    uint256 public ownerFeeRate;
    uint256 public marketCreationFee;

    address public operatorAddress;
    address public ethUsdOracleAddress;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    mapping(uint256 => ConditionInfo) public conditions;

    //oracle address -> interval -> index
    mapping(address => mapping(uint256 => uint256)) public autoGeneratedMarkets;
    bool private _paused;

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
        address conditionOwner;
    }

    event ConditionPrepared(
        address conditionOwner,
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
        uint256 indexed etHStaked,
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
    event NewMarketGenerated(
        uint256 indexed conditionIndex,
        address indexed oracle
    );
    event SetOperator(address operatorAddress);
    event SetMarketExpirationFee(uint256 adminFeeRate, uint256 ownerFeeRate);
    event SetMarketCreationFee(uint256 feeRate);
    event UpdateEthUsdOracleAddress(address oracle);
    event Paused(address account);
    event Unpaused(address account);

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "ERR_INVALID_OPERATOR");
        _;
    }

    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    modifier whenMarketActive(uint256 _conditionIndex) {
        uint256 betEndTime = (conditions[_conditionIndex].settlementTime * 90) /
            100;
        require(block.timestamp <= betEndTime, "ERR_INVALID_SETTLEMENT_TIME");

        _;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @notice Construct a new Prediction Market contract
     * @param _ethUsdOracleAddress The address of ETH-USD oracle.
     */
    // solhint-disable-next-line
    function initialize(address _ethUsdOracleAddress) external initializer {
        __Ownable_init();
        __PredictionMarket_init_unchained(_ethUsdOracleAddress);
    }

    // solhint-disable-next-line
    function __PredictionMarket_init_unchained(address _ethUsdOracleAddress)
        internal
        initializer
    {
        require(
            _ethUsdOracleAddress != address(0),
            "ERR_ZERO_ADDRESS_FOR_ORACLE"
        );

        ethUsdOracleAddress = _ethUsdOracleAddress;

        adminFeeRate = 80;
        ownerFeeRate = 20;
        marketCreationFee = 5; //in dollars

        operatorAddress = msg.sender;
        _paused = false;
        _status = _NOT_ENTERED;
    }

    function setOperator(address _operatorAddress) external onlyOwner {
        require(_operatorAddress != address(0), "ERR_INVALID_OPERATOR_ADDRESS");
        operatorAddress = _operatorAddress;
        emit SetOperator(operatorAddress);
    }

    function setEthUsdOracleAddress(address _ethUsdOracleAddress)
        external
        onlyOwner
    {
        require(_ethUsdOracleAddress != address(0), "ERR_INVALID_ADDRESS");
        ethUsdOracleAddress = _ethUsdOracleAddress;
        emit UpdateEthUsdOracleAddress(ethUsdOracleAddress);
    }

    function setMarketExpirationFee(
        uint256 _adminFeeRate,
        uint256 _ownerFeeRate
    ) external onlyOwner {
        require(_adminFeeRate > 0 && _ownerFeeRate > 0, "ERR_FEE_TOO_LOW");
        require(
            _adminFeeRate <= 1000 && _ownerFeeRate <= 1000,
            "ERR_FEE_TOO_HIGH"
        );

        adminFeeRate = _adminFeeRate;
        ownerFeeRate = _ownerFeeRate;
        emit SetMarketExpirationFee(adminFeeRate, ownerFeeRate);
    }

    function setMarketCreationFee(uint256 _fee) external onlyOwner {
        require(_fee > 0 && _fee <= 1000, "ERR_INVALID_FEE");
        marketCreationFee = _fee;
        emit SetMarketCreationFee(marketCreationFee);
    }

    function execute(address oracle, uint256 interval) external onlyOperator {
        require(oracle != address(0), "ERR_INVALID_CONDITION_INDEX");

        uint256 index = autoGeneratedMarkets[oracle][interval];
        require(index != 0, "ERR_INITIALIZE_MARKET");

        //settle and claim for previous index
        claimFor(payable(msg.sender), index);

        //prepare new condition
        int256 triggerPrice = getPrice(oracle);
        uint256 newIndex = _prepareCondition(
            oracle,
            interval,
            triggerPrice,
            false
        );

        autoGeneratedMarkets[oracle][interval] = newIndex;
        emit NewMarketGenerated(newIndex, oracle);
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    function togglePause(bool pause) external {
        require(
            msg.sender == operatorAddress || msg.sender == owner(),
            "ERR_INVALID_ADDRESS_ACCESS"
        );
        if (pause) _pause();
        else _unpause();
    }

    function safeTransferETH(address to, uint256 value) internal {
        // solhint-disable-next-line
        (bool success, ) = payable(to).call{value: value}(new bytes(0));

        // solhint-disable-next-line
        require(
            success,
            "TransferHelper::safeTransferETH: ETH transfer failed"
        );
    }

    function getMarketCreationFee() public view returns (uint256 toDeduct) {
        int256 latestPrice = getPrice(ethUsdOracleAddress);
        toDeduct = (marketCreationFee * 1 ether) / uint256(latestPrice);
    }

    function _deductMarketCreationFee() internal returns (uint256 toDeduct) {
        toDeduct = getMarketCreationFee();
        require(msg.value >= toDeduct, "ERR_PROVIDE_FEE");
        safeTransferETH(owner(), toDeduct);
    }

    function prepareCondition(
        address _oracle,
        uint256 _settlementTimePeriod,
        int256 _triggerPrice,
        bool _initialize
    ) public payable whenNotPaused returns (uint256) {
        _deductMarketCreationFee();
        return
            _prepareCondition(
                _oracle,
                _settlementTimePeriod,
                _triggerPrice,
                _initialize
            );
    }

    function _prepareCondition(
        address _oracle,
        uint256 _settlementTimePeriod,
        int256 _triggerPrice,
        bool _initialize
    ) internal nonReentrant returns (uint256) {
        require(_oracle != address(0), "ERR_INVALID_ORACLE_ADDRESS");
        require(_settlementTimePeriod >= 300, "ERR_INVALID_SETTLEMENT_TIME");

        latestConditionIndex = latestConditionIndex + 1;
        ConditionInfo storage conditionInfo = conditions[latestConditionIndex];

        conditionInfo.market = IAggregatorV3Interface(_oracle).description();
        conditionInfo.oracle = _oracle;
        conditionInfo.settlementTime = _settlementTimePeriod + block.timestamp;
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
        conditionInfo.conditionOwner = msg.sender;

        //to prevent double initialisation of auto generated markets
        if (
            _initialize &&
            autoGeneratedMarkets[_oracle][_settlementTimePeriod] == 0
        ) {
            autoGeneratedMarkets[_oracle][
                _settlementTimePeriod
            ] = latestConditionIndex;
        }

        emit ConditionPrepared(
            msg.sender,
            latestConditionIndex,
            _oracle,
            conditionInfo.settlementTime,
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
        uint256 ethStakedForAbove = BetToken(conditionInfo.highBetToken)
            .totalSupply();
        uint256 ethStakedForBelow = BetToken(conditionInfo.lowBetToken)
            .totalSupply();

        uint256 totalEthStaked = ethStakedForAbove + ethStakedForBelow;

        aboveProbabilityRatio = totalEthStaked > 0
            ? (ethStakedForAbove * (1e18)) / (totalEthStaked)
            : 0;
        belowProbabilityRatio = totalEthStaked > 0
            ? (ethStakedForBelow * (1e18)) / (totalEthStaked)
            : 0;
    }

    function userTotalETHStaked(uint256 _conditionIndex, address userAddress)
        external
        view
        returns (uint256 totalEthStaked)
    {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];
        uint256 ethStakedForAbove = BetToken(conditionInfo.highBetToken)
            .balanceOf(userAddress);
        uint256 ethStakedForBelow = BetToken(conditionInfo.lowBetToken)
            .balanceOf(userAddress);

        totalEthStaked = ethStakedForAbove + ethStakedForBelow;
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
    )
        public
        payable
        whenNotPaused
        nonReentrant
        whenMarketActive(_conditionIndex)
    {
        ConditionInfo storage conditionInfo = conditions[_conditionIndex];

        require(_user != address(0), "ERR_INVALID_ADDRESS");

        require(
            conditionInfo.oracle != address(0),
            "ERR_INVALID_ORACLE_ADDRESS"
        );

        require(msg.value >= _amount && _amount != 0, "ERR_INVALID_AMOUNT");
        require(
            (_prediction == 0) || (_prediction == 1),
            "ERR_INVALID_PREDICTION"
        ); //prediction = 0 (price will be below), if 1 (price will be above)

        uint256 userETHStaked = _amount;
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

    function getPrice(address oracle)
        internal
        view
        returns (int256 latestPrice)
    {
        (, latestPrice, , , ) = IAggregatorV3Interface(oracle)
            .latestRoundData();
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

        uint256 total = conditionInfo.totalStakedAbove +
            conditionInfo.totalStakedBelow;

        conditionInfo.totalEthClaimable = _transferFees(
            total,
            conditionInfo.conditionOwner
        );

        conditionInfo.settledPrice = getPrice(conditionInfo.oracle);

        emit ConditionSettled(
            _conditionIndex,
            conditionInfo.settledPrice,
            block.timestamp
        );
    }

    function _transferFees(uint256 totalAmount, address conditionOwner)
        internal
        returns (uint256 afterFeeAmount)
    {
        uint256 _fees = (totalAmount * (adminFeeRate + ownerFeeRate)) / (1000);
        afterFeeAmount = totalAmount - (_fees);

        uint256 ownerFees = (_fees * (ownerFeeRate)) / 1000;
        safeTransferETH(owner(), _fees - (ownerFees));
        safeTransferETH(conditionOwner, ownerFees);
    }

    function claim(uint256 _conditionIndex) public {
        //call claim with msg.sender as _for
        claimFor(payable(msg.sender), _conditionIndex);
    }

    function claimFor(address payable _userAddress, uint256 _conditionIndex)
        public
        whenNotPaused
        nonReentrant
    {
        require(_userAddress != address(0), "ERR_INVALID_USER_ADDRESS");
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
                conditionInfo.totalEthClaimable,
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
                conditionInfo.totalEthClaimable,
                conditionInfo.totalStakedBelow,
                userStake
            );
        } else {
            safeTransferETH(
                conditionInfo.conditionOwner,
                conditionInfo.totalEthClaimable
            );
            totalWinnerRedeemable = 0;
            conditionInfo.totalEthClaimable = 0;
        }

        highBetToken.burnAll(_userAddress);
        lowBetToken.burnAll(_userAddress);

        if (totalWinnerRedeemable > 0) {
            _userAddress.transfer(totalWinnerRedeemable);
            conditionInfo.totalEthClaimable =
                conditionInfo.totalEthClaimable -
                (totalWinnerRedeemable);
        }

        emit UserClaimed(_conditionIndex, _userAddress, totalWinnerRedeemable);
    }

    function getClaimAmount(
        uint256 totalPayout,
        uint256 winnersTotalETHStaked,
        uint256 userStake
    ) internal pure returns (uint256 totalWinnerRedeemable) {
        totalWinnerRedeemable =
            (totalPayout * userStake) /
            winnersTotalETHStaked;
    }

    function getBalance(uint256 _conditionIndex, address _user)
        external
        view
        returns (uint256 lbtBalance, uint256 hbtBalance)
    {
        ConditionInfo storage condition = conditions[_conditionIndex];
        lbtBalance = BetToken(condition.lowBetToken).balanceOf(_user);
        hbtBalance = BetToken(condition.highBetToken).balanceOf(_user);
    }
}
