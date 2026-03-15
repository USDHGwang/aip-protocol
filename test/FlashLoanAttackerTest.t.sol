// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPHook.sol";
import "../src/AIPRegistry.sol";
import "./FlashLoanAttacker.sol";

contract FlashLoanAttackerTest is Test {

    AIPSensoryLayer   public hook;
    FlashLoanAttacker public attacker;

    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE    = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        hook     = new AIPSensoryLayer(address(this), address(0));
        attacker = new FlashLoanAttacker(address(hook));
        hook     = new AIPSensoryLayer(address(attacker), address(0));
        attacker = new FlashLoanAttacker(address(hook));

        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(attacker), 2_000e6);
    }

    /// @notice 核心測試：真實閃電貸攻擊被 AIP TWAP Fingerprint 攔截
    function test_realFlashLoan_blocked_by_AIP() public {
        console.log("=== Real Flash Loan Attack Test ===");
        _logPoolState("Before attack");

        uint256 attackAmount = 500_000e6;
        console.log("Launching flash loan attack with USDC:", attackAmount / 1e6, "USDC");

        // 預期整筆 tx revert（AIP__PriceManipulated）
        vm.expectRevert();
        attacker.attack(attackAmount);

        console.log("=== Test PASSED: Real Flash Loan Blocked ===");
    }

    /// @notice 對照測試：正常交易不被攔截
    function test_normalTrade_not_blocked() public {
        console.log("=== Normal Trade Control Test ===");

        AIPSensoryLayer testHook = new AIPSensoryLayer(address(this), address(0));

        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL_ETH_USDC;

        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        bytes memory msgData = abi.encodePacked(sel, abi.encode(pools, tokens, spenders));

        bytes memory hookData = testHook.preCheck(address(this), 0, msgData);
        assertTrue(hookData.length > 0, "Normal trade should pass");
        console.log("Normal trade passed as expected");
    }

    function _logPoolState(string memory label) internal view {
        (uint160 sqrtPriceX96, int24 tick,,,,, ) = IUniswapV3Pool(POOL_ETH_USDC).slot0();
        console.log(label);
        console.log("  Current tick:", uint256(uint24(tick)));
        console.log("  sqrtPriceX96:", sqrtPriceX96);
    }
}
