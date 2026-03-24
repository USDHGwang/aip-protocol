// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/AIPRegistry.sol";
import "../src/AIPHook.sol";
import "../src/AIPBenchmark.sol";

contract DeployMonad is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Registry
        AIPRegistry registry = new AIPRegistry();
        console.log("AIPRegistry:", address(registry));

        // 2. Hook (正確合約名稱: AIPSensoryLayer)
        AIPSensoryLayer hook = new AIPSensoryLayer(deployer, address(registry));
        console.log("AIPSensoryLayer:", address(hook));

        // 3. Benchmark
        AIPIntentWallet wallet = new AIPIntentWallet();
        console.log("AIPIntentWallet:", address(wallet));

        vm.stopBroadcast();
    }
}
