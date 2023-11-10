// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {VRFCoordinatorV2} from "@chainlink/contracts/src/v0.8/dev/VRFCoordinatorV2.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Raffle} from "../src/Raffle.sol";

contract CreateSubscription is Script {
    function creatSubscription(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint64) {
        uint64  subscriptionId;
        console.log("Creating subscription on ChianId:", block.chainid);
        if (block.chainid == 11155111){
            vm.startBroadcast(deployerKey);
            subscriptionId = VRFCoordinatorV2(vrfCoordinator).createSubscription();
            vm.stopBroadcast();
        }else{
            vm.startBroadcast(deployerKey);
            subscriptionId = VRFCoordinatorV2Mock(vrfCoordinator)
                .createSubscription();
            vm.stopBroadcast();
        }
        console.log("Your subId is:", subscriptionId);
        return subscriptionId;
    }

    function createSubscriptionUsingConfig() internal returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig
            .activeNetWorkConfig();
        return creatSubscription(vrfCoordinator, deployerKey);
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscription(
        address vrfCoordinator,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding subscription:", subId);
        console.log("Using vrfCoordinator:", vrfCoordinator);
        console.log("On ChainID:", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function fundSubscriptionUsingConfig() internal {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetWorkConfig();
        fundSubscription(vrfCoordinator, subId, link, deployerKey);
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address raffle,
        address vrfCoordinator,
        uint64 subId,
        uint256 deployerKey
    ) public {
        console.log("Adding consumer:", address(raffle));
        console.log("Using crfCoordinator:", vrfCoordinator);
        console.log("Adding consumer on chainId:", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, raffle);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2(vrfCoordinator).addConsumer(subId, raffle);
            vm.stopBroadcast();
        }
    }

    function addConsumerUsingConfig(address raffle) internal {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetWorkConfig();
        addConsumer(raffle, vrfCoordinator, subId, deployerKey);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(raffle);
    }
}
