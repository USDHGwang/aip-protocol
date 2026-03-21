// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPHook.sol";
import "../src/AIPRegistry.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn; address tokenOut; uint24 fee; address recipient;
        uint256 deadline; uint256 amountIn; uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256);
}

interface IERC20 {
    function approve(address, uint256) external returns (bool);
}

contract GasOverheadStudy is Test {

    AIPSensoryLayer public hook;
    AIPRegistry     public registry;

    address constant ROUTER      = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant POOL        = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant USDC        = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH        = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant SPENDER     = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint256 constant SWAP_AMOUNT = 10_000e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        registry = new AIPRegistry();
        hook = new AIPSensoryLayer(address(this), address(registry));
        deal(USDC, address(this), 100_000_000e6);
    }

    function _buildMsgData() internal pure returns (bytes memory) {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        uint256[] memory minAmountsOut = new uint256[](1);
        pools[0] = POOL; tokens[0] = USDC; spenders[0] = SPENDER;
        minAmountsOut[0] = 0;
        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[],uint256[])"));
        return abi.encodePacked(sel, abi.encode(pools, tokens, spenders, minAmountsOut));
    }

    function _doSwap() internal returns (uint256) {
        IERC20(USDC).approve(ROUTER, SWAP_AMOUNT);
        return ISwapRouter(ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC, tokenOut: WETH, fee: 500,
                recipient: address(this), deadline: block.timestamp + 60,
                amountIn: SWAP_AMOUNT, amountOutMinimum: 0, sqrtPriceLimitX96: 0
            })
        );
    }

    function test_01_baseline_swap_noAIP() public {
        uint256 gasBefore = gasleft();
        _doSwap();
        uint256 gasUsed = gasBefore - gasleft();
        console.log("=== BASELINE: Swap without AIP ===");
        console.log("  gas used     :", gasUsed);
    }

    function test_02_preCheck_only() public {
        bytes memory msgData = _buildMsgData();
        uint256 gasBefore = gasleft();
        hook.preCheck(address(this), 0, msgData);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("=== AIP preCheck only ===");
        console.log("  gas used     :", gasUsed);
    }

    function test_03_full_AIP_flow() public {
        bytes memory msgData = _buildMsgData();
        uint256 gasBefore = gasleft();
        bytes memory hookData = hook.preCheck(address(this), 0, msgData);
        _doSwap();
        hook.postCheck(hookData);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("=== FULL AIP FLOW: preCheck + swap + postCheck ===");
        console.log("  gas used     :", gasUsed);
    }

    function test_04_overhead_summary() public {
        bytes memory msgData = _buildMsgData();

        uint256 gasA_before = gasleft();
        _doSwap();
        uint256 gasA = gasA_before - gasleft();

        deal(USDC, address(this), 100_000_000e6);

        uint256 gasB_before = gasleft();
        bytes memory hookData = hook.preCheck(address(this), 0, msgData);
        _doSwap();
        hook.postCheck(hookData);
        uint256 gasB = gasB_before - gasleft();

        uint256 overhead    = gasB > gasA ? gasB - gasA : 0;
        uint256 overheadBps = gasA > 0 ? (overhead * 10_000) / gasA : 0;

        console.log("=== GAS OVERHEAD SUMMARY ===");
        console.log("  Without AIP  :", gasA, "gas");
        console.log("  With AIP     :", gasB, "gas");
        console.log("  Overhead     :", overhead, "gas");
        console.log("  Overhead pct :", overheadBps, "bps (divide by 100 = %)");
    }
}
