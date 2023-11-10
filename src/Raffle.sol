// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

/**
 * @title 一个简单的抽奖合约
 * @author GanYu
 * @notice 实现了一个可验证的公平随机彩票合约
 * @dev 使用了Chainlink VRF
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    /**Error */
    error Raffle_NotEnoughtEthToSent();
    error Raffle_NotEnoughtTimestamp();
    error Raffle_TransferFailed();
    error Raffle_NotOPEN();

    /**类型声明 */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /**常量 */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    //入场费
    uint256 private immutable i_entranceFee;
    //抽奖间隔时间
    uint256 private immutable i_interval;
    //vrf请求地址
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    //keyHash
    bytes32 private immutable i_gasLane;
    //订阅地址
    uint64 private immutable i_subscriptionId;
    //回调请求gas限制
    uint32 private immutable i_callbackGasLimit;

    //上次抽奖结束时间
    uint256 private s_lastTimeStamp;
    //参与者数组
    address payable[] private s_players;
    //最近的获胜者
    address private s_recentWinner;
    //抽奖状态
    RaffleState private s_raffleState;

    /**Event */
    event EnterRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
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
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    //参与抽奖
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughtEthToSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_NotOPEN();
        }
        s_players.push(payable(msg.sender));
        emit EnterRaffle(msg.sender);
    }

    /**
     * @dev 合约自动化触发条件，需要满足以下几点要求
     * 1、达到指定的时间间隔
     * 2、处于OPEN状态
     * 3、合约余额不为0
     * 4、订阅地址已经被资助
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed&&isOpen&&hasBalance&&hasPlayers);
        return (upkeepNeeded,"0x0");
    }

    //自动化触发逻辑
    //选出胜者
    //1、获取一个随机数来选出一个玩家
    //2、该过程自动调用
    function performUpkeep(bytes calldata /*performData*/) external {
        s_raffleState = RaffleState.CALCULATING;
        //获取随机数
        //1、请求随机数
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    //chainlink vrf节点调用的函数
    function fulfillRandomWords(
        uint256 /*_requestId*/,
        uint256[] memory _randomWords
    ) internal override {
        uint256 winnerIndex = _randomWords[0] % s_players.length;
        address payable winner = s_players[winnerIndex];
        s_recentWinner = winner;
        //重新初始化
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(winner);
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState){
        return s_raffleState;
    }

    function getPlayers() external view returns(address payable[] memory){
        return s_players;
    }

    function getRecentWinner() external view returns(address){
        return s_recentWinner;
    }

    function getPlayersNumber() external view returns(uint256){
        return s_players.length;
    }

    function getLastTimestamp() external view returns(uint256){
        return s_lastTimeStamp;
    }
}
