// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external view returns (int56[] memory, uint160[] memory);
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn; address tokenOut; uint24 fee; address recipient;
        uint256 deadline; uint256 amountIn; uint256 amountOutMinimum; uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256);
}

interface IERC20 {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract TWAPThresholdStudy is Test {

    address constant POOL       = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant ROUTER     = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant USDC       = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH       = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WHALE      = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    uint32  constant TWAP_SEC   = 300;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    }

    function _getDeviation() internal view returns (int24 spotTick, int24 twapTick, int24 deviationBps) {
        (, spotTick,,,,,) = IUniswapV3Pool(POOL).slot0();
        uint32[] memory ago = new uint32[](2);
        ago[0] = TWAP_SEC; ago[1] = 0;
        (int56[] memory cum,) = IUniswapV3Pool(POOL).observe(ago);
        twapTick = int24((cum[1] - cum[0]) / int56(uint56(TWAP_SEC)));
        int24 diff = spotTick > twapTick ? spotTick - twapTick : twapTick - spotTick;
        // 1 tick ≈ 1 bps for Uniswap V3 (tickSpacing = 10, fee = 0.05%)
        deviationBps = diff;
    }

    function _swap(uint256 usdcAmount) internal {
        vm.prank(WHALE);
        IERC20(USDC).approve(ROUTER, usdcAmount);
        vm.prank(WHALE);
        ISwapRouter(ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC, tokenOut: WETH, fee: 500,
            recipient: WHALE, deadline: block.timestamp + 60,
            amountIn: usdcAmount, amountOutMinimum: 0, sqrtPriceLimitX96: 0
        }));
    }

    /// @notice 基準線：正常狀態的 spot/TWAP 偏差
    function test_baseline_deviation() public view {
        (int24 spot, int24 twap, int24 dev) = _getDeviation();
        console.log("=== Baseline (No Attack) ===");
        console.log("Spot tick:     ", uint256(uint24(spot)));
        console.log("TWAP tick:     ", uint256(uint24(twap)));
        console.log("Deviation(bps):", uint256(uint24(dev)));
    }

    /// @notice 小規模 swap：10,000 USDC
    function test_deviation_10k_usdc() public {
        _swap(10_000e6);
        (int24 spot, int24 twap, int24 dev) = _getDeviation();
        console.log("=== After 10,000 USDC Swap ===");
        console.log("Spot tick:     ", uint256(uint24(spot)));
        console.log("TWAP tick:     ", uint256(uint24(twap)));
        console.log("Deviation(bps):", uint256(uint24(dev)));
    }

    /// @notice 中規模 swap：100,000 USDC
    function test_deviation_100k_usdc() public {
        _swap(100_000e6);
        (int24 spot, int24 twap, int24 dev) = _getDeviation();
        console.log("=== After 100,000 USDC Swap ===");
        console.log("Spot tick:     ", uint256(uint24(spot)));
        console.log("TWAP tick:     ", uint256(uint24(twap)));
        console.log("Deviation(bps):", uint256(uint24(dev)));
    }

    /// @notice 大規模 swap：500,000 USDC（接近閃電貸攻擊規模）
    function test_deviation_500k_usdc() public {
        vm.prank(WHALE);
        IERC20(USDC).approve(ROUTER, 500_000e6);
        vm.prank(WHALE);
        ISwapRouter(ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC, tokenOut: WETH, fee: 500,
            recipient: WHALE, deadline: block.timestamp + 60,
            amountIn: 500_000e6, amountOutMinimum: 0, sqrtPriceLimitX96: 0
        }));
        (int24 spot, int24 twap, int24 dev) = _getDeviation();
        console.log("=== After 500,000 USDC Swap (Attack Scale) ===");
        console.log("Spot tick:     ", uint256(uint24(spot)));
        console.log("TWAP tick:     ", uint256(uint24(twap)));
        console.log("Deviation(bps):", uint256(uint24(dev)));
    }

    /// @notice 超大規模 swap：2,000,000 USDC
    function test_deviation_2m_usdc() public {
        vm.prank(WHALE);
        IERC20(USDC).approve(ROUTER, 2_000_000e6);
        vm.prank(WHALE);
        ISwapRouter(ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC, tokenOut: WETH, fee: 500,
            recipient: WHALE, deadline: block.timestamp + 60,
            amountIn: 2_000_000e6, amountOutMinimum: 0, sqrtPriceLimitX96: 0
        }));
        (int24 spot, int24 twap, int24 dev) = _getDeviation();
        console.log("=== After 2,000,000 USDC Swap ===");
        console.log("Spot tick:     ", uint256(uint24(spot)));
        console.log("TWAP tick:     ", uint256(uint24(twap)));
        console.log("Deviation(bps):", uint256(uint24(dev)));
    }
}
