pragma solidity ^0.4.23;

import "./Libraries.sol";


contract ERC2X {
    function balanceOf(address who) public view returns (uint);

    function transfer(address to, uint tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
}


contract Pool {

    using SafeMath for uint256;

    event NewDeposit(address _addr, uint256 _amount);
    event AdminStatusChanged(address _addr, address _admin, bool _newStatus);

    event WhitelistingAdded(address _addr, address[] _address);

    event PoolPaidOut(
        address _addr,
        address _paidAddress,
        uint256 _amount,
        uint256 _balance
    );
    event PoolCancelled(address _addr);
    event Withdraw(address _addr, uint256 _amount);

    event TokensConfirmed(address _addr, address _contractAddress, uint256 _amount);
    event TokensRefreshed(address _addr, address _contractAddress, uint256 _amount);

    event TokensClaimed(address _addr, uint256 tokens);


    //fundBlock Stuff
    address private factory;
    uint256 private fundBlockFees;

    //owner stuff
    address private owner;

    //admins
    mapping(address => bool) private admins;


    //Pool Stuff
    bool private whitelistActivated;
    bool private feesInTokens;
    uint256 private paidBalance;
    uint256 private totalBalance;
    uint256 private totalBalanceBaseForTokens;
    address private paidAddress;
    uint256 private poolFees;
    uint256 private hardCap;
    uint256 private maxPerParticipant;
    uint256 private minPerParticipant;

    PoolLibrary.State private pState;

    mapping(address => ParticipantsLibrary.participant) private participants;
    mapping(address => bool) private whitelist;


    //tokens Stuff
    address private erc2XContractAddress;
    uint256 private totalTokens;
    uint256 private totalClaimedTokens;

    constructor(
        address _owner,
        uint256 _fundBlockFees,
        uint256 _poolFees,
        uint256 _hardCap,
        uint256 _maxPerParticipant,
        uint256 _minPerParticipant,
        bool _whitelisting,
        bool _feesInTokens
    ) public areParamsValid(
        _poolFees,
        _hardCap,
        _maxPerParticipant,
        _minPerParticipant
    ) {
        factory = msg.sender;
        require(_owner != msg.sender);
        owner = _owner;
        poolFees = _poolFees;
        feesInTokens = _feesInTokens;
        hardCap = _hardCap;
        maxPerParticipant = _maxPerParticipant;
        minPerParticipant = _minPerParticipant;
        whitelistActivated = _whitelisting;
        fundBlockFees = _fundBlockFees;
        pState = PoolLibrary.State.Active;
    }

    modifier areParamsValid(
        uint256 _poolFees,
        uint256 _hardCap,
        uint256 _maxPerParticipant,
        uint256 _minPerParticipant
    ){
        //we limit fees to 50%, for some reason ;) we only take maximum 0.2% remember ;)
        require(_poolFees <= 50000);
        require(_hardCap > 0);
        require(_hardCap >= _maxPerParticipant);
        require(_maxPerParticipant >= _minPerParticipant);
        _;
    }

    modifier canDeposit() {
        ParticipantsLibrary.participant storage participant = participants[msg.sender];
        uint256 futureParticipantBalance = participant.balance.add(msg.value);
        // check against balance
        require(address(this).balance <= hardCap);
        // check against maxPerContributor
        require(futureParticipantBalance <= maxPerParticipant);
        // check against minPerParticipant
        require(futureParticipantBalance >= minPerParticipant);

        _;
    }

    modifier isActive(){
        require(pState == PoolLibrary.State.Active);
        _;
    }

    modifier isFinished(){
        require(pState == PoolLibrary.State.Finished);
        _;
    }

    modifier isPaidOut(){
        require(pState == PoolLibrary.State.PaidOut);
        _;
    }

    modifier isCancelled(){
        require(pState == PoolLibrary.State.Cancelled);
        _;
    }

    modifier isActiveOrCancelled(){
        require(
            pState == PoolLibrary.State.Active
            || pState == PoolLibrary.State.Cancelled
        );

        _;
    }

    modifier isWhiteListed(){
        // check against whitelist if exsits
        require(!whitelistActivated
        || whitelist[msg.sender]
        || owner == msg.sender
        || admins[msg.sender]);
        _;
    }

    modifier onlyAdminsOrOwner(){
        require(owner == msg.sender || admins[msg.sender]);
        _;
    }

    modifier onlyOwner(){
        require(owner == msg.sender);
        _;
    }

    //owner functions



    function manageAdmin(
        address _addr,
        bool _newStatus
    ) external onlyOwner {
        admins[_addr] = _newStatus;
        emit AdminStatusChanged(msg.sender, _addr, _newStatus);
    }

    //admins functions

    function changeWhiteListStatus(
        address[] _addresses
    ) external isActive onlyAdminsOrOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = true;
        }

        emit WhitelistingAdded(msg.sender, _addresses);
    }

    function cancel()
    external isActive onlyAdminsOrOwner {
        pState = PoolLibrary.State.Cancelled;
        emit PoolCancelled(msg.sender);
    }

    function sendFunds(address _address)
    external isActive onlyAdminsOrOwner {

        require(address(this).balance > 0);
        paidAddress = _address;
        pState = PoolLibrary.State.PaidOut;

        totalBalance = address(this).balance;
        totalBalanceBaseForTokens = address(this).balance;

        //our fees = 0.2% (maximum 0.2%)
        uint256 fundBlockShares = address(this).balance.mul(fundBlockFees).div(100000);

        //pool fees
        uint256 ownerFees = address(this).balance.mul(poolFees).div(100000);

        //if fees are paid in tokens, we transfert fees to the owner's participant account.
        if (feesInTokens) {
            ParticipantsLibrary.participant storage participant = participants[owner];
            participant.balance = participant.balance.add(ownerFees);
            totalBalanceBaseForTokens = totalBalanceBaseForTokens.add(ownerFees);
            ownerFees = 0;
        }


        if (fundBlockShares > 0) {
            factory.transfer(fundBlockShares);
        }

        if (ownerFees > 0) {
            owner.transfer(ownerFees);
        }

        paidBalance = address(this).balance;

        //what's left get sent to the indicated address
        paidAddress.transfer(address(this).balance);
        emit PoolPaidOut(msg.sender, _address, paidBalance, totalBalance);

    }


    function confirmToken(address _addr)
    external onlyAdminsOrOwner isPaidOut {

        erc2XContractAddress = _addr;

        ERC2X erc2xContract = ERC2X(erc2XContractAddress);

        totalTokens = erc2xContract.balanceOf(address(this));

        require(totalTokens > 0);

        pState = PoolLibrary.State.Finished;

        emit TokensConfirmed(msg.sender, erc2XContractAddress, totalTokens);
    }

    function refreshTokenBalance()
    external onlyAdminsOrOwner isFinished {
        ERC2X erc20Contract = ERC2X(erc2XContractAddress);
        uint256 currentTokensBalance = erc20Contract.balanceOf(address(this));
        require(currentTokensBalance > 0);
        totalTokens = currentTokensBalance.add(totalClaimedTokens);

        emit TokensRefreshed(msg.sender, erc2XContractAddress, totalTokens);
    }


    //participants functions

    function() public payable {
        require(msg.value == 0);
    }

    function deposit() public payable isActive canDeposit isWhiteListed {
        ParticipantsLibrary.participant storage participant = participants[msg.sender];
        participant.balance = participant.balance.add(msg.value);

        emit NewDeposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount)
    external isActiveOrCancelled {

        ParticipantsLibrary.participant storage participant = participants[msg.sender];
        uint256 futureParticipantBalance = participant.balance.sub(_amount);
        require(
            futureParticipantBalance == 0
            || futureParticipantBalance >= minPerParticipant
        );

        participant.balance = futureParticipantBalance;

        msg.sender.transfer(_amount);

        emit Withdraw(msg.sender, _amount);
    }

    function claimTokens(address _addr) internal isFinished {
        require(totalClaimedTokens < totalTokens);

        ParticipantsLibrary.participant storage participant = participants[_addr];

        uint256 tokensLeftToClaim = getTokensLeftToClaim(_addr);

        require(tokensLeftToClaim > 0);

        participant.claimedTokens = participant.claimedTokens.add(tokensLeftToClaim);

        totalClaimedTokens = totalClaimedTokens.add(tokensLeftToClaim);

        ERC2X erc2xContract = ERC2X(erc2XContractAddress);

        if (erc2xContract.transfer(_addr, tokensLeftToClaim)) {
            emit TokensClaimed(_addr, tokensLeftToClaim);
        } else {
            participant.claimedTokens = participant.claimedTokens.sub(tokensLeftToClaim);
            totalClaimedTokens = totalClaimedTokens.sub(tokensLeftToClaim);
        }
    }

    function claimMyTokens() external isFinished {
        claimTokens(msg.sender);
    }

    function claimSomeoneTokens(address _addr)
    external isFinished {
        claimTokens(_addr);
    }

    //views

    function getTokensLeftToClaim(address _addr) public view returns (uint256){
        ParticipantsLibrary.participant storage participant = participants[_addr];
        return (
        participant
        .balance
        .mul(totalTokens)
        .div(totalBalanceBaseForTokens)
        .sub(participant.claimedTokens)
        );
    }

    function getParticipantRecap(address _addr)
    external view returns (uint256, uint256, uint256){

        return (
        participants[_addr].balance,
        getTokensLeftToClaim(_addr),
        participants[_addr].claimedTokens
        );
    }


    function isAdminOrOwnerOrWhiteListed(address _addr) external view returns (
        bool,
        bool,
        bool
    ){
        return (
        _addr == owner,
        admins[_addr],
        whitelist[_addr]
        );
    }

    function getTokensInformation() external view returns (
        address,
        uint256,
        uint256) {
        return (
        erc2XContractAddress,
        totalTokens,
        totalClaimedTokens);

    }


    function getContractPublicInfo() external view returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        bool,
        PoolLibrary.State,
        uint256,
        address,
        address,
        bool,
        uint256
    ){
        return (
        address(this).balance,
        poolFees,
        fundBlockFees,
        hardCap,
        maxPerParticipant,
        minPerParticipant,
        whitelistActivated,
        pState,
        totalBalance,
        owner,
        paidAddress,
        feesInTokens,
        totalBalanceBaseForTokens
        );
    }

}
