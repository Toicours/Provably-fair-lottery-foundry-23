// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle contract
 * @author Fromage
 * @notice This contract creates a sample rafle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );
    /**
     * we put uint256 because RaffleState is an enum
     *     that can be converted to uint256
     */

    /**
     * Type declarations
     */
    enum RaffleState {
        OPEN, // 0
        CALCULATING_WINNER // 1
    }

    // Constant state variable
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // Immutable state variables
    uint256 private immutable i_entranceFee;
    // @dev interval of time between raffles in seconds
    uint256 private immutable i_interval;
    // coordinator contract is of type VRFCoordinatorV2Interface
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    // Creating a dynamic array of addresses. Mapping cannot be looped through
    // Has to be payable to be able to send ETH to the winner
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;

    RaffleState private s_raffleState;

    /**
     * Events
     */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        // typecast address into a type of VRFCoordinatorV2Interface
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent"); // Do not use require
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        // add msg sender to the s_players array
        s_players.push(payable(msg.sender));

        // emit EnteredRaffled event with msg.sender as player
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that Chainlink Automation nodes
     * call to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The interval has passed between raffle runs
     * 2. The raffle is in OPEN state
     * 3. The contract has ETH (aka players have entered)
     * 4. The subscription is funded withs enough LINK to pay the node operator
     */
    function checkUpkeep(
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        // returns true if the interval has passed
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        // returns true if s_raffleState = RaffleState.OPEN
        bool isOpen = RaffleState.OPEN == s_raffleState;
        // returns true if ETH in contract > 0
        bool hasBalance = address(this).balance > 0;
        // check if there are players
        bool hasPlayers = s_players.length > 0;
        // returns true if all conditions are met
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // 0x0 means blank bytes object
    }

    // 1. Get a random number
    // 2. Use the random number to pick a winner
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        // check if it's time for an upkeep
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        // Change the state of the Raffle while calculating
        s_raffleState = RaffleState.CALCULATING_WINNER;
        // 1. First call: Request RNG (Random Number Generation)
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // Gas lane or KeyHash, it varies depending on the speed and chain
            i_subscriptionId, // ID of the subscription, funded with LINK
            REQUEST_CONFIRMATIONS, // number of block confirmations before the request can be processed
            i_callbackGasLimit, // gas limit for callback to not overspend
            NUM_WORDS // Number of random numbers
        );
        // Emit requestId
        emit RequestedRaffleWinner(requestId);
        // 2. Callback function: Get the random number
    }

    function fulfillRandomWords(
        uint256,
        /* requestId */ uint256[] memory randomWords
    ) internal override {
        // 1. Use the random number to pick a winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        // reset the players array
        s_players = new address payable[](0);
        // Update the timestamp to start the clock over for a new lottery
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        // .call returns 2 values 1) a boolean indicating success or failure 2) the return data of the call which is a byte array.
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter functions
     */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayersArray() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
