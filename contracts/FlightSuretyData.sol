pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/
    struct InsurancePolicy {
        bytes32 flightKey;
        address passenger;
        uint256 policyPrice; // in wei
        uint256 policyPayout; // in wei
        bool active;
    }

    address private contractOwner; // Account used to deploy contract
    address private appContract; // App contract required to make certain calls
    bool private operational = true; // Blocks all state changes throughout the contract if false
    mapping(address => bool) airlines;
    mapping(address => uint256) airlineFunds; // need to expose function that tells that airline is active
    // we want to, once we know a flight has some status, look up the policies on that flight and pay everyone
    mapping(bytes32 => InsurancePolicy[]) internal flightInsurancePolicies; // policies taken out on a flight
    mapping(bytes32 => bool) passengerFlightInsured;
    mapping(address => uint256) passengerCredits;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor(address _appContract) public {
        contractOwner = msg.sender;
        appContract = _appContract;
        airlines[msg.sender] = true;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireAppContract() {
        require(
            msg.sender == appContract,
            "Caller is not the FlightSurety app"
        );
        _;
    }

    modifier requireAirline() {
        require(airlines[msg.sender], "Caller must be a registered airline");
        _;
    }

    modifier requireAirlineIsFunded(address airline) {
        require(
            airlineFunds[airline] > 10 ether,
            "Operation not allowed - airline is not fully funded"
        );
        _;
    }

    modifier requireTimeIsInFuture(uint256 timestamp) {
        require(
            timestamp > now,
            "Operation not allowed - time must be in the future"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address airline) external requireAppContract {
        if (airlines[airline] == false) {
            airlines[airline] = true;
        }
    }

    /**
     * @dev Passenger buy insurance for a flight
     *
     */
    function buy(
        string flightCode,
        address airline,
        uint256 timestamp,
        address passenger,
        uint256 policyAmount
    )
        external
        payable
        requireAppContract
        requireAirlineIsFunded(airline)
        requireTimeIsInFuture(timestamp)
    {
        // extract up to 1 ether - move this logic to the app
        // uint returnAmount = msg.value > 1 ether ? msg.value - 1 ether : 0;
        // uint policyAmount = returnAmount > 0 ? 1 ether : msg.value;

        // TODO: I don't really know how to manage the payable aspect of this thing

        // do i need to do anything to execute the transfer of funds to this contract?
        bytes32 flightKey = getFlightKey(airline, flightCode, timestamp);
        bytes32 passengerFlightKey = getPassengerFlightKey(
            passenger,
            flightKey
        );

        require(
            passengerFlightInsured[passengerFlightKey] == false,
            "Passenger already has insurance for this flight"
        );

        flightInsurancePolicies[flightKey].push(
            InsurancePolicy(
                flightKey,
                passenger,
                policyAmount,
                2 * policyAmount,
                true
            )
        );
        passengerFlightInsured[passengerFlightKey] = true;
    }

    /**
     *  @dev Credits payouts to insurees
        who calls this? app contract? for now, yes
        TODO: update this thing to get the flight key and clear the passengerFlightInsurance
    */
    function creditInsurees(
        string flightCode,
        address airline,
        uint256 timestamp
    ) external {
        bytes32 flightKey = getFlightKey(airline, flightCode, timestamp);
        for (
            uint256 index = 0;
            index < flightInsurancePolicies[flightKey].length;
            index++
        ) {
            if (flightInsurancePolicies[flightKey][index].active) {
                flightInsurancePolicies[flightKey][index].active = false;

                bytes32 passengerFlightKey = getPassengerFlightKey(
                    flightInsurancePolicies[flightKey][index].passenger,
                    flightKey
                );

                // this needs to just enable the funds to be withdrawn
                passengerCredits[
                    flightInsurancePolicies[flightKey][index].passenger
                ] += flightInsurancePolicies[flightKey][index].policyPayout;
                delete passengerFlightInsured[passengerFlightKey];
                // Confirm this transfers in wei
                // flightInsurancePolicies[flightKey][index].passenger.transfer(flightInsurancePolicies[flightKey][index].policyPayout);
            }
        }
        delete flightInsurancePolicies[flightKey];
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(address passenger) external pure {
        uint256 amt = passengerCredits[passenger];
        delete passengerCredits[passenger];
        passenger.transfer(amt);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     * this is for airlines to put up funds for thier flights
     */
    function fund() public payable requireAirline {
        // Idk what to do here. I need to take the funds and allocate them to the airline
        airlineFunds[msg.sender] += msg.value;
    }

    function isAirlineFunded(address airline) public returns (bool funded) {
        funded = airlineFunds[airline] >= 10 ether;
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    function getPassengerFlightKey(address passenger, bytes32 flightKey)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(passenger, flightKey));
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    function() external payable {
        fund();
    }
}
