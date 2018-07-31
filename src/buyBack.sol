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

/**
 * @title buyBack contract 
 */
contract buyBack is Ownable, SafeMath {
    
  mapping (address => uint256) public balances;
  address public Agent;
  uint256 public curs = 1;
  uint256 public decimalsCurs = 4;
  uint256 public startDate;
  uint256 public endDate;
  
    
   /**
   * @dev The function can be called only by crowdsale agent.
   */
  modifier onlyAgent() {
    assert(msg.sender == Agent);
    _;
  }
  
  event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
  
  function() public payable {
    
  }
  function tokenFallback(address _from, uint _value, bytes _data) public onlyAgent returns (bool success){
    require(block.timestamp > startDate && block.timestamp < endDate);
    uint amount = safeDiv(safeMul(_value*10**18,curs),10**decimalsCurs);
    require(amount<= this.balance);
    balances[_from] = safeAdd(balances[_from],_value);
    _from.transfer(amount);
    Transfer(this, _from, amount, _data);
    return true;
  }
  
  /**
   * @dev 
   * @param _Agent contract address
   */
  function setAgent(address _Agent) public onlyOwner {
    Agent = _Agent;
  }
  
  /**
   * @param _curs new curs
   * @param _decimalsCurs new decimalsCurs
   */
  function changeCurs(uint256 _curs,uint256 _decimalsCurs) public onlyOwner {
    curs = _curs;
    decimalsCurs = _decimalsCurs;
  }
  
  /**
   * @param _startDate new startDate
   * @param _endDate new endDate
   */
  function changeDate(uint256 _startDate,uint256 _endDate) public onlyOwner {
    startDate = _startDate;
    endDate = _endDate;
  } 
  
  function collect(uint256 _sum, address _addr) public onlyOwner {
    require(_sum > 0);
    require(this.balance >= _sum);
    _addr.transfer(_sum);
  }
}
