//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

/**
 * @title BetToken
 */
contract BetToken is ERC20Pausable {
    uint256 public totalHolders;
    address public predictionMarket;

    event Mint(address indexed _to, uint256 _value);
    event Burn(address indexed _to, uint256 _value);

    /**
     * @dev The PositionToken constructor sets initial values.
     * @param _name string The name of the Position Token.
     * @param _symbol string The symbol of the Position Token.
     */
    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        // _setupDecimals(8);
        predictionMarket = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than PredictionMarket.
     */
    modifier onlyPredictionMarket() {
        require(msg.sender == predictionMarket, "PREDICTION_MARKET_ONLY");
        _;
    }

    /**
     * @dev Mints position tokens for a user.
     * @param _to address The address of beneficiary.
     * @param _value uint256 The amount of tokens to be minted.
     */
    function mint(address _to, uint256 _value)
        public
        onlyPredictionMarket
        whenNotPaused
    {
        _mint(_to, _value);
        if (balanceOf(_to) == _value) totalHolders++;
        emit Mint(_to, _value);
    }

    /**
     * @dev Burns position tokens of a user.
     * @param _from address The address of beneficent.
     * @param _value uint256 The amount of tokens to be burned.
     */
    function burn(address _from, uint256 _value)
        public
        onlyPredictionMarket
        whenNotPaused
    {
        _burn(_from, _value);
        if (balanceOf(_from) == 0) totalHolders--;
        emit Burn(_from, _value);
    }

    function burnAll(address _from) public onlyPredictionMarket whenNotPaused {
        uint256 _value = balanceOf(_from);
        if (_value == 0) return;
        totalHolders--;
        _burn(_from, _value);
        emit Burn(_from, _value);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool success)
    {
        if (balanceOf(recipient) == 0) totalHolders++;
        if (balanceOf(msg.sender) == amount) totalHolders--;
        success = super.transfer(recipient, amount);
        require(success, "ERR_TRANSFER_FAILED");
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool success) {
        if (balanceOf(recipient) == 0) totalHolders++;
        if (balanceOf(sender) == amount) totalHolders--;

        success = super.transferFrom(sender, recipient, amount);
        require(success, "ERR_TRANSFER_FROM_FAILED");
    }
}
