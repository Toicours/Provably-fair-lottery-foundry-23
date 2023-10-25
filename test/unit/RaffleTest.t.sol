// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    // raffle is of type Raffle
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            ,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetWorkConfig();
        // give PLAYER some ETH
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        /**
         * since RaffleState is a type of enum, we basically say that
         * for any Raffle contract get the OPEN value in the RaffleState type
         */

        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //////////////////
    // enterRaffle //
    /////////////////
    modifier prank() {
        vm.prank(PLAYER);
        _;
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testRaffleRevertsWhenYouDontPayEnough() public prank {
        /**
         * Check that Raffle properly reverts when sending less than minimum
         */
        // Arrange

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public prank {
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0); // get player at index 0
        assert(playerRecorded == PLAYER);
    }

    // Check that entering the raffle emits an event
    function testEmitEventOnEntrance() public prank {
        // checks topic 0 (always checked), 1,2,3, data and then the emitter address
        vm.expectEmit(true, false, false, false, address(raffle));

        emit EnteredRaffle(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating()
        public
        raffleEnteredAndTimePassed
    {
        // call performUpKeep to change raffle state to calculating
        raffle.performUpkeep("");

        // vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    //////////////////
    // checkUpkeep //
    /////////////////

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        // assert that upkeepNeeded is NOT false (so true)
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange
        // call performUpKeep which should be
        // in a calculating state since we warped with the modifier
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        //Act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING_WINNER);
        assert(upKeepNeeded == false);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed() public prank {
        // Arrange
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        //Act
        // store the bool value that checkUpkeep returns
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        // check that upkeepNeeded is false
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        // check that upkeepNeeded is true
        assert(upkeepNeeded);
    }

    ////////////////////
    // PerformUpkeep //
    ///////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange

        // Act & Assert
        /**
         * Expect not revert is not possible in foundry but
         * it doesn't matter
         * if raffle.performUpkeep("); doesn't revert,
         * it means the test passed
         */
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        // Act & Assert
        /**
         * Here we use expect  revert with abi.encodeWithSelector
         * We pass the error message that we expect to be returned
         * and then we pass the parameters of the error.
         */
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        /**
         * call performUpkeep. since expectRevert expects
         * that the transaction is going to fail with
         * the error message we passed
         */
        raffle.performUpkeep("");
    }

    // What if I need to test using the output of an event?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange (done with modifier)
        // Act & Assert
        /**
         * we want to capture the emitted requestId
         * recordLogs will save the log outputs in a
         * datastructure we can access with getRecordedLogs
         * https://book.getfoundry.sh/cheatcodes/record-logs
         * https://book.getfoundry.sh/cheatcodes/get-recorded-logs
         *
         */
        vm.recordLogs();
        raffle.performUpkeep(""); // emits the requestId
        /**
         * Be careful of the Capital V, Vm must be imported from forge-vm
         */
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * The entries array will have all the logs emited, so we must figure out where our requestId is on those entries
         */
        bytes32 requestId = entries[1].topics[1]; // we know that the requestId is the second topic of the second log. the 0 topic refers to the entire event, the 1 topic refers to the requestId only

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        /**
         * Check that the requestId is
         *     greater than 0, meaning that it was actually generated
         */
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // check that raffleState equals 1, meaning calculating
    }

    /////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    )
        public
        // by specifying randomRequestId as a parameter, it tells fundry to fuzz test with multiple combination of numbers, 256 in total
        raffleEnteredAndTimePassed
        skipFork
    {
        //
        // Arrange
        /**
         * have the Mock contract call fulfillRandomWords
         * we want to make sure that it always reverts if performUpkeep
         * hasn't been called
         */
        vm.expectRevert("nonexistent request");
        /// expected error message
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsPicksAwinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        /**
         * 1. Enter the Lottery a few times
         * 2. Move time up so that checkUpkeep returns true
         * 3. call performUpkeep
         * 3. Request randomWords
         * 4. call fulfillRandomWords by pretending to be the Chainlink node
         *
         */
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); // wrap i in uint160 to convert it to a a player address
            hoax(player, STARTING_USER_BALANCE); // hoax is a forge cheatcode that sets up a prank from an address
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Vm.log counts everything as bytes32
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimestamp();

        // Pretend to be Chainlink VRF to get random number and picker a winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0); // check that raffle state is open
        assert(raffle.getRecentWinner() != address(0)); // check that winner is not address 0
        assert(raffle.getLengthOfPlayersArray() == 0); // check that the players array is reinitialized
        assert(previousTimeStamp < raffle.getLastTimestamp());
        // check that Pickerwinner event is emitted
        // vm.expectEmit(true, false, false, false, address(raffle));
        // emit PickedWinner(raffle.getRecentWinner());
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
    }
}
