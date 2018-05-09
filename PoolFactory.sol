pragma solidity ^0.4.23;


import "./Pool.sol";
import "./Libraries.sol";

contract PoolFactory {

    using SafeMath for uint256;

    event NewPoolCreated(
        address indexed creator,
        address indexed pool,
        uint256 _poolFees,
        uint256 _hardCap,
        uint256 _maximumPerParticipant,
        uint256 _minimumPerParticipant,
        bool _whitelisting,
        bool _feesInTokens,
        uint256 _fundBlockFees
    );
    
    event NewDealSet(address _addr,uint256 fees);
    event DealRevoked(address _addr);
    
    address private owner;
    uint256 private fundBlockFees = 200; //that's 0.2%

    mapping(address => bool) specialDeal;
    mapping(address => uint256) specialDealValue;

    modifier onlyOwner(){
        require(owner == msg.sender);
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    function createPool(
        uint256 _poolFees,
        uint256 _hardCap,
        uint256 _maximumPerParticipant,
        uint256 _minimumPerParticipant,
        bool _whitelisting,
        bool _feesInTokens
    ) external {
        uint256 _fundBlockFees = getFees(msg.sender);
        
        Pool pool = new Pool(
            msg.sender,
            _fundBlockFees,
            _poolFees,
            _hardCap,
            _maximumPerParticipant,
            _minimumPerParticipant,
            _whitelisting,
            _feesInTokens
        );

        emit NewPoolCreated(
        msg.sender,
        pool,
        _poolFees,
        _hardCap,
        _maximumPerParticipant,
        _minimumPerParticipant,
        _whitelisting,
        _feesInTokens,
        _fundBlockFees
        );
    }

    function() public payable {}

    function collectFunds(address _addr) external onlyOwner {
        _addr.transfer(address(this).balance);
    }

    function collectPartialFunds(
        address _addr,
        uint256 _amount
    ) external onlyOwner {
        require(address(this).balance <= _amount);
        _addr.transfer(_amount);
    }

    function setNewFees(uint256 _newFees) external onlyOwner {
        //this allow us to change fees, but guarantee you a maximum of 0.2%
        //we will take the fees down, we just want to support the platform not get rich from it.
        //if you want to donate, we will gladly accept it and make a use of it toward crypto ! just donate to this Factory, I'll collect later
        require(_newFees <= 200);
        fundBlockFees = _newFees;
    }

    function getFees(address _addr) public view returns (uint256){
        if (specialDeal[_addr] && specialDealValue[_addr] < fundBlockFees) {
            return specialDealValue[_addr];
        } else {
            return fundBlockFees;
        }
    }

    function setSpecialDeal(address _addr, uint256 _fees) external onlyOwner{
        require(_fees < 200);
        specialDeal[_addr] = true;
        specialDealValue[_addr] = _fees;
        emit NewDealSet(_addr,_fees);
    }

    function removeSpecialDeal(address _addr) external onlyOwner{
        specialDeal[_addr] = false;
        emit DealRevoked(_addr);
    }

}
