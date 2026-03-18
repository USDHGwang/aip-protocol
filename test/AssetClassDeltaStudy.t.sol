// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory, uint160[] memory);
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function liquidity() external view returns (uint128);
    function fee() external view returns (uint24);
}

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

contract AssetClassDeltaStudy is Test {

    address constant ROUTER         = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant USDC           = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT           = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC           = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH           = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // CLASS A — USDC/USDT 0.01%
    address constant POOL_A = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    // CLASS B — ETH/USDC 0.05% (現有基準)
    address constant POOL_B = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    // CLASS C — WBTC/ETH 0.05%
    address constant POOL_C = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0;

    uint32  constant TWAP_SEC      = 300;
    uint256 constant BASE_DELTA    = 15;
    uint256 constant REFERENCE_LIQ = 2_486_648_450_510_458_845;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        deal(USDC, address(this), 20_000_000e6);
        deal(WBTC, address(this), 100e8);
    }

    function _measure(address pool, string memory label) internal view {
        (, int24 spot,,,,,) = IUniswapV3Pool(pool).slot0();
        uint128 liq = IUniswapV3Pool(pool).liquidity();
        uint32[] memory ago = new uint32[](2);
        ago[0] = TWAP_SEC; ago[1] = 0;
        (int56[] memory cum,) = IUniswapV3Pool(pool).observe(ago);
        int24 twap = int24((cum[1] - cum[0]) / int56(uint56(TWAP_SEC)));
        int24 diff = spot > twap ? spot - twap : twap - spot;
        uint256 dynDelta = liq > 0 ? BASE_DELTA * REFERENCE_LIQ / uint256(liq) : 500;
        if (dynDelta < 5)   dynDelta = 5;
        if (dynDelta > 500) dynDelta = 500;
        console.log(label);
        console.log("  liquidity    :", uint256(liq));
        console.log("  deviation    :", uint256(uint24(diff)), "ticks");
        console.log("  dynamic delta:", dynDelta, "ticks");
        console.log("  AIP result   :", uint256(uint24(diff)) <= dynDelta ? "PASS" : "BLOCK");
    }

    function _swapUSDC(address pool, address tokenOut, uint256 amt, string memory label) internal {
        IERC20(USDC).approve(ROUTER, amt);
        try ISwapRouter(ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC, tokenOut: tokenOut, fee: IUniswapV3Pool(pool).fee(),
            recipient: address(this), deadline: block.timestamp + 60,
            amountIn: amt, amountOutMinimum: 0, sqrtPriceLimitX96: 0
        })) {} catch {}
        _measure(pool, label);
    }

    function _swapWBTC(uint256 amt, string memory label) internal {
        IERC20(WBTC).approve(ROUTER, amt);
        try ISwapRouter(ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: WBTC, tokenOut: WETH, fee: IUniswapV3Pool(POOL_C).fee(),
            recipient: address(this), deadline: block.timestamp + 60,
            amountIn: amt, amountOutMinimum: 0, sqrtPriceLimitX96: 0
        })) {} catch {}
        _measure(POOL_C, label);
    }

    function test_01_baseline() public view {
        console.log("=== BASELINE (no swap) ===");
        _measure(POOL_A, "[CLASS A] USDC/USDT 0.01%");
        _measure(POOL_B, "[CLASS B] ETH/USDC  0.05%");
        _measure(POOL_C, "[CLASS C] WBTC/ETH  0.05%");
    }

    function test_02_small_swap() public {
        console.log("=== SMALL SWAP ===");
        _swapUSDC(POOL_A, USDT, 100_000e6, "[CLASS A] 100k USDC");
        _swapUSDC(POOL_B, WETH, 100_000e6, "[CLASS B] 100k USDC");
        _swapWBTC(1e8,               "[CLASS C] 1 WBTC  ");
    }

    function test_03_medium_swap() public {
        console.log("=== MEDIUM SWAP ===");
        _swapUSDC(POOL_A, USDT, 1_000_000e6, "[CLASS A] 1M USDC  ");
        _swapUSDC(POOL_B, WETH,   500_000e6, "[CLASS B] 500k USDC");
        _swapWBTC(5e8,                "[CLASS C] 5 WBTC  ");
    }

    function test_04_large_swap() public {
        console.log("=== LARGE SWAP ===");
        _swapUSDC(POOL_A, USDT, 5_000_000e6, "[CLASS A] 5M USDC  ");
        _swapUSDC(POOL_B, WETH, 2_000_000e6, "[CLASS B] 2M USDC  ");
        _swapWBTC(20e8,               "[CLASS C] 20 WBTC ");
    }
}
