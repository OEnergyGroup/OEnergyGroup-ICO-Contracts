pragma solidity ^0.4.18;

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
      OwnershipTransferred(owner, newOwner);
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

 /* New ERC23 contract interface */
 
contract ERC223 {
  uint public totalSupply;
  function balanceOf(address who) public view returns (uint);
  
  function name() public view returns (string _name);
  function symbol() public view returns (string _symbol);
  function decimals() public view returns (uint256 _decimals);
  function totalSupply() public view returns (uint256 _supply);

  function transfer(address to, uint value) public returns (bool ok);
  function transfer(address to, uint value, bytes data) public returns (bool ok);
  
  event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
}

contract ContractReceiver {
    function tokenFallback(address _from, uint _value, bytes _data) public returns (bool success);
}

contract ERC223Token is ERC223,SafeMath,Ownable {

  mapping(address => uint) balances;
  
  string public name;
  string public symbol;
  uint256 public decimals;
  uint256 public totalSupply;
  
  mapping(address => uint) public balancesRefused;
  uint256 public curs = 4;
  uint256 public decimalsCurs = 0;
  uint256 public CAP;
  uint256 public totalSuccess;
  address public Agent;
  uint256 public minCAP;
  bool public finalized;
  bool public registrationSuccessful;
  address public buyBack;
  address public sale;
  
  /**
   * @dev The function can be called only by agent.
   */
  modifier onlyAgent() {
    assert(msg.sender == Agent);
    _;
  }
  
  /** 
   * @dev Modified allowing execution only if the crowdsale is currently running
   */
  modifier inState(State state) {
    require(getState() == state);
    _;
  }
  
  /** State machine
   *
   * - Preparing: All contract initialization calls and variables have not been set yet
   * - Funding: Active crowdsale
   * - Success: Minimum funding goal reached
   * - Failure: Minimum funding goal not reached before ending time
   * - Finalized: The finalized has been called and succesfully executed
   */
  enum State{Unknown, Preparing, Funding, Success, Failure, Finalized}

  // Function to access name of token .
  function name() public view returns (string _name) {
      return name;
  }
  // Function to access symbol of token .
  function symbol() public view returns (string _symbol) {
      return symbol;
  }
  // Function to access decimals of token .
  function decimals() public view returns (uint256 _decimals) {
      return decimals;
  }
  // Function to access total supply of tokens .
  function totalSupply() public view returns (uint256 _totalSupply) {
      return totalSupply;
  }
  
  
  // Function that is called when a user or another contract wants to transfer funds .
  function transfer(address _to, uint _value, bytes _data) public returns (bool success) {
    if(!registrationSuccessful){
      if (getState() == State.Failure){
        require (Agent == _to && balancesRefused[msg.sender] == _value); 
      }else if (getState() == State.Finalized){
        require (sale == _to || buyBack == _to); 
      }else {
        revert();
      }
    }
    if(isContract(_to)) {
        return transferToContract(_to, _value, _data);
    }
    else {
        return transferToAddress(_to, _value, _data);
    }
  }
  
  // Standard function transfer similar to ERC20 transfer with no _data .
  // Added due to backwards compatibility reasons .
  function transfer(address _to, uint _value) public returns (bool success) {
    if(!registrationSuccessful){
      if (getState() == State.Failure){
        require (Agent == _to && balanceOf(msg.sender) == _value); 
      }else if (getState() == State.Finalized){
        require (sale == _to || buyBack == _to); 
      }else {
        revert();
      }
    }
    //standard function transfer similar to ERC20 transfer with no _data
    //added due to backwards compatibility reasons
    bytes memory empty;
    if(isContract(_to)) {
        return transferToContract(_to, _value, empty);
    }
    else {
        return transferToAddress(_to, _value, empty);
    }
  }

  //assemble the given address bytecode. If bytecode exists then the _addr is a contract.
  function isContract(address _addr) private view returns (bool is_contract) {
      uint length;
      assembly {
            //retrieve the size of the code on target address, this needs assembly
            length := extcodesize(_addr)
      }
      return (length>0);
  }

  //function that is called when transaction target is an address
  function transferToAddress(address _to, uint _value, bytes _data) private returns (bool success) {
    if (balanceOf(msg.sender) < _value) revert();
    balances[msg.sender] = safeSub(balanceOf(msg.sender), _value);
    balances[_to] = safeAdd(balanceOf(_to), _value);
    Transfer(msg.sender, _to, _value, _data);
    return true;
  }
  
  //function that is called when transaction target is a contract
  function transferToContract(address _to, uint _value, bytes _data) private returns (bool success) {
    if (balanceOf(msg.sender) < _value) revert();
    balances[msg.sender] = safeSub(balanceOf(msg.sender), _value);
    if(registrationSuccessful){
      balances[_to] = safeAdd(balanceOf(_to), _value);
    } else {
      totalSupply = safeSub(totalSupply, _value);
      if (getState() == State.Failure){
        _value = balancesRefused[msg.sender];
        balancesRefused[msg.sender] = 0;
      }
    }
    ContractReceiver receiver = ContractReceiver(_to);
    if(receiver.tokenFallback(msg.sender, _value, _data)){
      Transfer(msg.sender, _to, _value, _data);
      return true;
    }else{
      revert();
    }
}


  function balanceOf(address _owner) public view returns (uint balance) {
    return balances[_owner];
  }
 
  /**
   * @dev Check if the ICO goal was reached.
   * @return true if the crowdsale has raised enough money to be a success
   */
  function isCrowdsaleFull() public constant returns (bool) {
    if(totalSuccess >= minCAP){
      return true;  
    }
    return false;
  }
  
  /** 
   * @dev Crowdfund state machine management.
   * @return State current state
   */
  function getState() public constant returns (State) {
    if (finalized && totalSuccess > minCAP ) return State.Finalized;
    else if ( address(Agent) == 0 ) return State.Preparing;
    else if (!finalized) return State.Funding;
    else return State.Failure;
  }
  
}

/** 
 * @title Georesurs contract - standard ERC20 token with Short Hand Attack and approve() race condition mitigation.
 */
contract Georesurs is ERC223Token {

  /** Name and symbol were updated. */
  event UpdatedTokenInformation(string newName, string newSymbol);
  /** Information about the change exchange rate. */
  event updateCurs(uint blockNumber, uint256 totalSupply);

  
  /**
   * Construct the token.
   * @param _name Token name
   * @param _symbol Token symbol - should be all caps
   * @param _decimals Number of decimal places
   */
   
  function Georesurs(string _name, string _symbol, uint _decimals) public {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    CAP = 6000000*10**_decimals;
    minCAP = 4000000*10**_decimals;
  }   
  
  function tokenFallback(address _from, uint _value, bytes _data) public onlyAgent returns (bool success){
    uint token = safeDiv(safeMul(_value,curs),10**decimalsCurs);
    uint amount = safeAdd(token,totalSupply); 
    if(amount > CAP) return false;
    totalSupply = safeAdd(totalSupply,token);
    balances[_from] = safeAdd(balanceOf(_from), token);
    balancesRefused[_from] = safeAdd(balancesRefused[_from], _value);
    Transfer(this, _from, token, _data);
    return true;
  }
  
  /**
   * Owner can update token information here.
   *
   * It is often useful to conceal the actual token association, until
   * the token operations, like central issuance or reissuance have been completed.
   *
   * This function allows the token owner to rename the token after the operations
   * have been completed and then point the audience to use the token contract.
   *
   * @param _name Token name
   * @param _symbol Token symbol 
   */
  function setTokenInformation(string _name, string _symbol) public onlyOwner {
    name = _name;
    symbol = _symbol;
    UpdatedTokenInformation(name, symbol);
  }
  
  /**
   * @param _curs new curs
   * @param _decimalsCurs new decimalsCurs
   */
  function changeCurs(uint256 _curs,uint256 _decimalsCurs) public onlyOwner {
    curs = _curs;
    decimalsCurs = _decimalsCurs;
    updateCurs(block.number, totalSupply);
  } 
  
  /**
   * @param _CAP new CAP
   */
  function changeCap(uint256 _CAP) public onlyOwner {
    CAP = _CAP;
  }

  /**
   * @param _Agent contract address
   */
  function setAgent(address _Agent) public onlyOwner {
    Agent = _Agent;
  }
  
  /**
   * @param _registrationSuccessful new registrationSuccessful
   */
  function changeRegistrationSuccessful(bool _registrationSuccessful) public onlyOwner {
    registrationSuccessful = _registrationSuccessful;
  }
  /**
   * @param _buyBack contract address
   * @param _sale contract address
   */
  function setAccount(address _buyBack, address _sale) public onlyOwner {
    buyBack = _buyBack;
    sale = _sale;
  }
  
  /**
   * @dev Finalize a succcesful crowdsale.
   */
  function finalize() public onlyOwner {
    require(!finalized);
    finalized = true;
    totalSuccess = totalSupply;
  }
  
}
