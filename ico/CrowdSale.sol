pragma solidity ^0.4.21;

/**
 * @title Ownable contract - base contract with an owner
 */
contract Ownable {
  
  address public owner;
  address public newOwner;

  event OwnershipTransferred(address indexed _from, address indexed _to);
  
  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    assert(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function transferOwnership(address _newOwner) public onlyOwner {
    assert(_newOwner != address(0));      
    newOwner = _newOwner;
  }

  /**
   * @dev Accept transferOwnership.
   */
  function acceptOwnership() public {
    if (msg.sender == newOwner) {
      emit OwnershipTransferred(owner, newOwner);
      owner = newOwner;
    }
  }
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
contract SafeMath {

  function safeSub(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x - y;
    assert(z <= x);
	  return z;
  }

  function safeAdd(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x + y;
	  assert(z >= x);
	  return z;
  }
	
  function safeDiv(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x / y;
    return z;
  }
	
  function safeMul(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x * y;
    assert(x == 0 || z / x == y);
    return z;
  }

  function min(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x <= y ? x : y;
    return z;
  }

  function max(uint256 x, uint256 y) internal pure returns (uint256) {
    uint256 z = x >= y ? x : y;
    return z;
  }
}

/**
 * @title Haltable
 * @dev Abstract contract that allows children to implement an
 * emergency stop mechanism. Differs from Pausable by causing a throw when in halt mode.
 */
contract Haltable is Ownable {
  bool public halted;

  modifier stopInEmergency {
    assert(!halted);
    _;
  }

  modifier onlyInEmergency {
    assert(halted);
    _;
  }

  /**
   *@dev Called by the owner on emergency, triggers stopped state
   */
  function halt() external onlyOwner {
    halted = true;
  }

  /**
   * @dev Called by the owner on end of emergency, returns to normal state
   */
  function unhalt() external onlyOwner onlyInEmergency {
    halted = false;
  }
}


/** 
 * @title Killable OilTokenCrowdsale contract
 */
contract Killable is Ownable {
  function kill() public onlyOwner {
    selfdestruct(owner);
  }
}

/* Token Contract interface */
contract ERC223 {
  uint public totalSupply;
  function balanceOf(address who) public view returns (uint);
  
  function name() public view returns (string _name);
  function symbol() public view returns (string _symbol);
  function decimals() public view returns (uint256 _decimals);
  function totalSupply() public view returns (uint256 _supply);

  function transfer(address to, uint value) public returns (bool ok);
  function transfer(address to, uint value, bytes data) public returns (bool ok);
  
  function transferForICO(address _to, uint _value) public returns (bool success);
  function mint(address _to, uint _value, bytes _data) public returns (bool success);
  function releaseTokenTransfer() public;
  function releasePrivilege() public;
  
  function setAddrForPrivilege(address _owner) public;
  function getAddrForPrivilege(address _owner) public returns (bool success);
  
  event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
}


/** 
 * @title OilTokenCrowdsale contract - contract for token sales.
 */
contract OilTokenCrowdsale is Haltable, SafeMath, Killable {
  
  /* The token we are selling */
  ERC223 public token;

  /* Wei will be transfered on this address */
  address public multisigWallet;

  /* the UNIX timestamp start date of the crowdsale */
  uint public startsAt;
  
  /* the number of tokens already sold through this contract*/
  uint public tokensSold = 0;
  
  /* How many wei of funding we have raised */
  uint public weiRaised = 0;
  
  /* How many usd of funding we have raised */
  uint public usdRaised = 0;
  
  /* How many unique addresses that have invested */
  uint public investorCount = 0;
  
  /* Miminal tokens funding goal in USD cents, if this goal isn't reached during ICO, refund will begin */
  uint public MIN_ICO_GOAL;

  /* Cap of tokens */
  uint public CAP;
  
  /* USD to Ether rate in cents */
  uint public exchangeRate;
  
  /* How much ETH each address has invested to this crowdsale */
  mapping (address => uint256) public investedAmountOf;
  
  /* How much tokens this crowdsale has credited for each investor address */
  mapping (address => uint256) public tokenAmountOf;
  
  /* The address that can change the exchange rate */
  address public cryptoAgent;
  
  /* How much wei we have returned back to the contract after a failed crowdfund. */
  uint public loadedRefund = 0;
  
  /* How much wei we have given back to investors. */
  uint public weiRefunded = 0;

  /** How many tokens he charged for each investor's address in a particular period */
  mapping (uint => mapping (address => uint256)) public tokenAmountOfPeriod;
  
  struct Stage {
    // UNIX timestamp when the stage begins
    uint start;
    // UNIX timestamp when the stage is over
    uint end;
    // Token price in USD
    uint price;
    // Cap of period
    uint cap;
    // Token sold in period
    uint tokenSold;
  }
  
  /** Stages **/
  Stage[] public stages;
  uint public periodStage;
  uint public currentPeriod;
  uint startICO;
  uint daystartICO;
  
  /** State machine
   *
   * - Preparing: All contract initialization calls and variables have not been set yet
   * - Funding: Active crowdsale
   * - Success: Minimum funding goal reached
   * - Failure: Minimum funding goal not reached before ending time
   * - Finalized: The finalized has been called and succesfully executed
   */
  enum State{Unknown, Preparing, PreFunding,Funding, Success, Failure, Finalized,Refunding}
  
  // A new investment was made
  event Invested(address investor, uint weiAmount, uint tokenAmount);
  
  // A new exchangeRate
  event ExchangeRateChanged(uint oldValue, uint newValue);
  
  // A new price
  event priceChanged(uint oldValue, uint newValue, uint period);
  
  // Refund was processed for a contributor
  event Refund(address investor, uint weiAmount);
  
  /** 
   * @dev Modified allowing execution only if the crowdsale is currently running
   */
  modifier inState(State state) {
    require(getState() == state);
    _;
  }
  
  /**
   * @dev The function can be called only by cryptoAgent.
   */
  modifier onlyCryptoAgent() {
    assert(msg.sender == cryptoAgent);
    _;
  }
  
  /**
   * @dev Constructor
   * @param _token CryptoSlots token address
   * @param _multisigWallet team wallet
   * @param _startsAt token ICO start date
   * @param _CAP token ICO
   * @param _MIN_ICO_GOAL usd in cents ICO  
   * @param _price start price token in usd cents
   * @param _preSaleCAP cap of PRE-Sale
   * @param _dayPreSale dya of PRE-Sale
   * @param _periodStage Stage period
   * @param _daystartICO the UNIX timestamp start date ICO
   */
  function OilTokenCrowdsale(address _token, address _multisigWallet, uint _startsAt, uint _CAP, uint _MIN_ICO_GOAL, uint _price, uint _preSaleCAP, uint _dayPreSale, uint _periodStage, uint _daystartICO) public {
    require(_multisigWallet != 0x0);
    require(_startsAt >= block.timestamp);
    require(_MIN_ICO_GOAL > 0);
    require(_CAP > 0);

    token = ERC223(_token);
    multisigWallet = _multisigWallet;
    startsAt = _startsAt;
    CAP = _CAP*10**token.decimals();
    MIN_ICO_GOAL = _MIN_ICO_GOAL;
    daystartICO = _daystartICO;
    currentPeriod = 0;
    periodStage = _periodStage*1 days;
    startICO = startsAt+_dayPreSale*1 days+daystartICO*1 days;
    stages.push(Stage(startsAt,startsAt+_dayPreSale*1 days,_price,_preSaleCAP*10**token.decimals(),0));
    stages.push(Stage(startICO,startICO+periodStage,_price+200,18000000*10**token.decimals(),0));
    stages.push(Stage(startICO+periodStage,startICO+2*periodStage,_price+400,33000000*10**token.decimals(),0));
    stages.push(Stage(startICO+2*periodStage,startICO+3*periodStage,_price+500,CAP,0));
  }
  
  
  /**
   * Buy tokens from the contract
   */
  function() public payable {
    investInternal(msg.sender);
  }

  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   *
   */
  function investInternal(address receiver) private stopInEmergency {
    require(msg.value > 0);
	  
    require(getState() == State.PreFunding || getState() == State.Funding);
    
    uint weiAmount = msg.value;
    
    // Determine in what period we hit
    currentPeriod = getStage();
    
    // Calculating the number of tokens
    uint tokenAmount = calculateTokens(weiAmount,currentPeriod);
    if(currentPeriod == 0){
      require(tokenAmount >= 1000*10**token.decimals());
    }else{
      require(tokenAmount >= 10*10**token.decimals());
    }
    stages[currentPeriod].tokenSold = safeAdd(tokenAmount,stages[currentPeriod].tokenSold );
    
    uint _tokenHolder = token.balanceOf(address(token));
    require(safeAdd(safeSub(CAP,_tokenHolder),tokenAmount) <= stages[currentPeriod].cap);
    
    if (stages[currentPeriod].cap == safeAdd(safeSub(CAP,_tokenHolder),tokenAmount) && currentPeriod != 3){
      updateStage(currentPeriod);
    }
    
    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }
    
    tokenAmountOfPeriod[currentPeriod][receiver]=safeAdd(tokenAmountOfPeriod[currentPeriod][receiver],tokenAmount);
	
    // Update investor
    investedAmountOf[receiver] = safeAdd(investedAmountOf[receiver],weiAmount);
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver],tokenAmount);
    if(currentPeriod == 0){
      bool privilege = token.getAddrForPrivilege(receiver);
      if(tokenAmountOf[receiver] >= (200000*10**token.decimals()) && !privilege){
        token.setAddrForPrivilege(receiver);
      }
    }
    // Update totals
    weiRaised = safeAdd(weiRaised,weiAmount);
    tokensSold = safeAdd(tokensSold,tokenAmount);
    usdRaised = safeAdd(usdRaised,weiToUsdCents(weiAmount));

    assignTokens(receiver, tokenAmount);

    // send ether to the fund collection wallet
    multisigWallet.transfer(weiAmount);

    // Tell us invest was success
    emit Invested(receiver, weiAmount, tokenAmount);
	
  }
 
  /**
   * Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   * @param _tokenAmount tokens
   *
   */
  function investCryptoAgent(address receiver, uint _tokenAmount) public onlyCryptoAgent stopInEmergency {
	  
    require(getState() == State.PreFunding || getState() == State.Funding);
    
    // Determine in what period we hit
    currentPeriod = getStage();
    
    // Calculating the number of tokens
    uint tokenAmount = _tokenAmount;
    if(currentPeriod == 0){
      require(tokenAmount >= 1000*10**token.decimals());
    }else{
      require(tokenAmount >= 10*10**token.decimals());
    }
    stages[currentPeriod].tokenSold = safeAdd(tokenAmount,stages[currentPeriod].tokenSold );
    
    uint _tokenHolder = token.balanceOf(address(token));
     require(safeAdd(safeSub(CAP,_tokenHolder),tokenAmount) <= stages[currentPeriod].cap);
    
    if (stages[currentPeriod].cap == safeAdd(safeSub(CAP,_tokenHolder),tokenAmount) && currentPeriod != 3){
      updateStage(currentPeriod);
    }
    
    if(tokenAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }
    
    tokenAmountOfPeriod[currentPeriod][receiver]=safeAdd(tokenAmountOfPeriod[currentPeriod][receiver],tokenAmount);
	
    // Update investor
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver],tokenAmount);
    if(currentPeriod == 0){
      bool privilege = token.getAddrForPrivilege(receiver);
      if(tokenAmountOf[receiver] >= (200000*10**token.decimals()) && !privilege){
        token.setAddrForPrivilege(receiver);
      }
    }
    // Update totals
    tokensSold = safeAdd(tokensSold,tokenAmount);
    usdRaised = safeAdd(usdRaised,tokenToUsdCents(tokenAmount,currentPeriod));

    assignTokens(receiver, tokenAmount);
    // Tell us invest was success
    emit Invested(receiver, 0, tokenAmount);
    
	
  }
  
  /**
   * Create new tokens or transfer issued tokens to the investor depending on the cap model.
   */
  function assignTokens(address receiver, uint tokenAmount) private {
     token.transferForICO(receiver, tokenAmount);
  }
   
  /**
   *  @dev Check if the pre ICO goal was reached.
   * @return true if the preICO has raised enough money to be a success
   */
   function isMinimumGoalReached() public constant returns (bool reached) {
     return usdRaised >= MIN_ICO_GOAL;
  }
   
  /**
   * @dev Finalize a succcesful crowdsale.
   */
  function finalizeCrowdsale() public onlyOwner stopInEmergency {
    token.releaseTokenTransfer();
  }
  
  function releasePrivilegeCrowdsale() public onlyOwner stopInEmergency {
    token.releasePrivilege();
  }
  
  /**
   * @dev Allow to change the team multisig address in the case of emergency.
   */
  function setMultisig(address addr) public onlyOwner {
    require(addr != 0x0);
    multisigWallet = addr;
  }
  
  /**
   * @dev Allow crowdsale owner to change the token address.
   */
  function setToken(address addr) public onlyOwner {
    require(addr != 0x0);
    token = ERC223(addr);
  }
  
  /** 
   * @dev Crowdfund state machine management.
   * @return State current state
   */
  function getState() public constant returns (State) {
    bool MinimumGoalReached = isMinimumGoalReached();
    if (address(token) == 0 || address(multisigWallet) == 0 || block.timestamp < startsAt) return State.Preparing;
    else if (block.timestamp >= stages[0].start && block.timestamp <= stages[0].end) return State.PreFunding;
    else if (block.timestamp >= startsAt && MinimumGoalReached) return State.Funding;
    else if (!MinimumGoalReached && weiRaised > 0 && loadedRefund >= weiRaised) return State.Refunding;
    else return State.Failure;
  }
  
  /**
   * @dev Method for setting USD to Ether
   * @param value USD amout in cents for 1 Ether
   */
  function setExchangeRate(uint value) public onlyCryptoAgent {
    uint exchangeRateOld = exchangeRate;
    exchangeRate = value;
    emit ExchangeRateChanged(exchangeRateOld, value);
  }
  
  /**
   * @dev Method for setting Price in USD cents
   * @param value USD amout in cents 
   * @param period period
   */
  function setPrice(uint value,uint period) public onlyOwner {
    uint priceOld = stages[period].price;
    stages[period].price = value;
    emit priceChanged(priceOld, value,period);
  }
  
  /**
   * @dev Converts wei value into USD cents according to current exchange rate
   * @param weiValue wei value to convert
   * @return USD cents equivalent of the wei value
   */
  function weiToUsdCents(uint weiValue) internal constant returns (uint) {
    return safeDiv(safeMul(weiValue, exchangeRate), 1e18);
  }
   
  /**
   * @dev Converts token amount value into USD cents according to current exchange rate
   * @param tokenAmount wei value to convert
   * @param period period
   * @return USD cents equivalent of the wei value
   */
  function tokenToUsdCents(uint tokenAmount, uint period) internal constant returns (uint) {
    return safeDiv(safeMul(tokenAmount, stages[period].price), 10 ** token.decimals());
  }
  /**
   * @dev Calculating tokens count
   * @param weiAmount invested
   * @param period period
   * @return tokens amount
   */
  function calculateTokens(uint weiAmount,uint period) internal constant returns (uint) {
    uint usdAmount = weiToUsdCents(weiAmount);
    uint multiplier = 10 ** token.decimals();
    //require (usdAmount >= stages[period].price);
    return safeDiv(safeMul(multiplier, usdAmount),stages[period].price);
  }
  
  /** 
   * @dev Gets the current stage.
   * @return uint current stage
   */
  function getStage() private constant returns (uint){
    for (uint i = 0; i < stages.length; i++) {
      if (block.timestamp >= stages[i].start && block.timestamp < stages[i].end) {
        return i;
      }
    }
    return stages.length-1;
  }
  
  /** 
   * @dev Updates the ICO steps if the cap is reached.
   */
  function updateStage(uint number) private {
    require(number>=0);
    uint time = block.timestamp;
    uint j = 0;
    stages[number].end = time;
    uint _time = time;
    if(number == 0){
      _time = _time + daystartICO*1 days;
      startsAt = _time;
    }
    for (uint i = number+1; i < stages.length; i++) {
      stages[i].start = _time+periodStage*j;
      stages[i].end = _time+periodStage*(j+1);
      j++;
    }
  }
  
  /**
   * @dev Set the addres that can call setExchangeRate function.
   * @param _cryptoAgent crowdsale contract address
   */
  function setCryptoAgent(address _cryptoAgent) public onlyOwner {
    cryptoAgent = _cryptoAgent;
  }
  
  /**
   * @dev Allow load refunds back on the contract for the refunding.
   */
  function loadRefund() public payable inState(State.Failure) {
    require(msg.value > 0);
    loadedRefund = safeAdd(loadedRefund, msg.value);
  }
  
  /**
   * @dev Investors can claim refund.
   */
  function refund() public inState(State.Refunding) {
    uint256 weiValue = investedAmountOf[msg.sender];
    if (weiValue == 0){
      revert();
    }
    investedAmountOf[msg.sender] = 0;
    weiRefunded = safeAdd(weiRefunded, weiValue);
    emit Refund(msg.sender, weiValue);
    msg.sender.transfer(weiValue);
  }
  
  function collect(uint256 _sum, address _addr) public onlyOwner {
    require(_sum > 0);
    address contractAddr = this;
    require(contractAddr.balance >= _sum);
    _addr.transfer(_sum);
  }
  
  function mintToken(address _to, uint256 _sum) public onlyOwner {
    require(_sum > 0);
    bytes memory empty;
    token.mint(_to,_sum*10**token.decimals(),empty);
  }
}
