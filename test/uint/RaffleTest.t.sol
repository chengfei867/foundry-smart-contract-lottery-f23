// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /**Events */
    event EnterRaffle(address indexed player);
    event WinnerPicked(address indexed winner);

    Raffle raffle;
    HelperConfig helperConfig;
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetWorkConfig();
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitStateIsOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * 测试enterRaffle
     */
    function testRafflerevertsWhewYouDontPayEnought() public {
        //Arrange
        vm.prank(PLAYER);
        //Act/Assert
        vm.expectRevert(Raffle.Raffle_NotEnoughtEthToSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordPlayerWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entranceFee}();
        //Assert
        assert(raffle.getPlayers().length == 1);
        assert(raffle.getPlayers()[0] == address(PLAYER));
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnterRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle_NotOPEN.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /**Test CheckUpKeep */
    function testCheckUpkeepReturnsTrueWhenUpkeepNeeded() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool isKeep, ) = raffle.checkUpkeep("");
        assertTrue(isKeep);
    }

    function testCheckUpkeepReturnsFalseIfNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool isKeep, ) = raffle.checkUpkeep("");
        assertFalse(isKeep);
    }

    function testCheckUpkeepReturnsFalseIfNoPlayer() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.deal(address(raffle), STARTING_BALANCE);
        (bool isKeep, ) = raffle.checkUpkeep("");
        assertFalse(isKeep);
    }

    function testCheckUpkeepReturnsFalseIfNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        (bool isKeep, ) = raffle.checkUpkeep("");
        assertFalse(isKeep);
    }

    function testCheckUpkeepReturnsFalseIfTimeNotPass() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);
        (bool isKeep, ) = raffle.checkUpkeep("");
        assertFalse(isKeep);
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(rState == Raffle.RaffleState.CALCULATING);
    }

    function testFulfillRandomWordsCan0nlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWrrdsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        //Arrange
        //再增加五个玩家
        uint256 additionalEntrances = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrances;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_BALANCE); // deal 1 eth to the player
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrances + 1);

        //获取requestId
        vm.recordLogs();
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 preTimestamp = raffle.getLastTimestamp();
        //模拟Chainlink VRF获取随机数
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        //Assert
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getPlayersNumber() == 0);
        assert(raffle.getLastTimestamp() > preTimestamp);
        assert(
            raffle.getRecentWinner().balance ==
                (STARTING_BALANCE - entranceFee) + prize
        );
    }
}
