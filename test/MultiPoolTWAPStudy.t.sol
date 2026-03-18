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
        uint256 deadline; uint256 amountIn; uint256 amountOutMinimum; uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256);
}

interface IERC20 {
    function approve(address, uint256) external returns (bool);
}

contract MultiPoolTWAPStudy is Test {

    address constant ROUTER         = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant USDC           = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH           = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WHALE          = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    address constant POOL_005_ETHUSDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // deep
    address constant POOL_030_ETHUSDC = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8; // medium
    address constant POOL_100_ETHUSDC = 0xE0554a476A092703abdB3Ef35c80e0D76d32939F; // shallow

    uint32 constant TWAP_SEC = 300;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    }

    function _measure(address pool, string memory label) internal view {
        (, int24 spot,,,,,) = IUniswapV3Pool(pool).slot0();
        uint128 liq = IUniswapV3Pool(pool).liquidity();
        uint32[] memory ago = new uint32[](2);
        ago[0] = TWAP_SEC; ago[1] = 0;
        (int56[] memory cum,) = IUniswapV3Pool(pool).observe(ago);
        int24 twap = int24((cum[1] - cum[0]) / int56(uint56(TWAP_SEC)));
        int24 diff = spot > twap ? spot - twap : twap - spot;
        console.log(label);
        console.log("  liquidity :", uint256(liq));
        console.log("  deviation :", uint256(uint24(diff)), "ticks");
    }

    function _swap(address pool, uint256 amount, string memory label) internal {
        vm.prank(WHALE);
        IERC20(USDC).approve(ROUTER, amount);
        uint24 fee = IUniswapV3Pool(pool).fee();
        vm.prank(WHALE);
        try ISwapRouter(ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC, tokenOut: WETH, fee: fee, recipient: WHALE,
            deadline: block.timestamp + 60, amountIn: amount,
            amountOutMinimum: 0, sqrtPriceLimitX96: 0
        })) {} catch {}
        _measure(pool, label);
    }

    function test_01_baseline() public view {
        console.log("=== BASELINE ===");
        _measure(POOL_005_ETHUSDC, "[0.05% Deep  ]");
        _measure(POOL_030_ETHUSDC, "[0.30% Medium]");
        _measure(POOL_100_ETHUSDC, "[1.00% Shallow]");
    }

    function test_02_swap_100k() public {
        console.log("=== 100,000 USDC Swap ===");
        _swap(POOL_005_ETHUSDC, 100_000e6, "[0.05% Deep  ]");
        _swap(POOL_030_ETHUSDC, 100_000e6, "[0.30% Medium]");
        _swap(POOL_100_ETHUSDC, 100_000e6, "[1.00% Shallow]");
    }

    function test_03_swap_500k() public {
        console.log("=== 500,000 USDC Swap (Attack Scale) ===");
        _swap(POOL_005_ETHUSDC, 500_000e6, "[0.05% Deep  ]");
        _swap(POOL_030_ETHUSDC, 500_000e6, "[0.30% Medium]");
        _swap(POOL_100_ETHUSDC, 500_000e6, "[1.00% Shallow]");
    }

    function test_04_swap_1m() public {
        console.log("=== 1,000,000 USDC Swap ===");
        _swap(POOL_005_ETHUSDC, 1_000_000e6, "[0.05% Deep  ]");
        _swap(POOL_030_ETHUSDC, 1_000_000e6, "[0.30% Medium]");
        _swap(POOL_100_ETHUSDC, 1_000_000e6, "[1.00% Shallow]");
    }
}
