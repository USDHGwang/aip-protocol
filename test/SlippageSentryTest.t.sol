// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPHook.sol";
import "../src/AIPRegistry.sol";

contract SlippageSentryTest is Test {

    AIPSensoryLayer public hook;

    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE    = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    address constant SPENDER       = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        hook = new AIPSensoryLayer(address(this), address(0));

        // 給測試帳戶一些 USDC
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(this), 10_000e6);
    }

    function _buildMsgData(
        address[] memory pools,
        address[] memory tokens,
        address[] memory spenders,
        uint256[] memory minAmountsOut
    ) internal pure returns (bytes memory) {
        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        return abi.encodePacked(sel, abi.encode(pools, tokens, spenders, minAmountsOut));
    }

    /// @notice 測試1：產出高於最小值，正常通過
    function test_slippage_sufficient_output_passes() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        uint256[] memory minOut   = new uint256[](1);

        pools[0]    = POOL_ETH_USDC;
        tokens[0]   = USDC;
        spenders[0] = SPENDER;
        minOut[0]   = 100e6; // 最少要收到 100 USDC

        bytes memory hookData = hook.preCheck(
            address(this), 0,
            _buildMsgData(pools, tokens, spenders, minOut)
        );

        // 模擬交易讓餘額增加（收到 500 USDC）
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(this), 500e6);

        // postCheck 應通過（500 > 100）
        hook.postCheck(hookData);
        console.log("test_slippage_sufficient_output_passes: PASSED");
    }

    /// @notice 測試2：產出低於最小值，應被攔截
    function test_slippage_insufficient_output_reverts() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        uint256[] memory minOut   = new uint256[](1);

        pools[0]    = POOL_ETH_USDC;
        tokens[0]   = USDC;
        spenders[0] = SPENDER;
        minOut[0]   = 1_000e6; // 最少要收到 1000 USDC

        bytes memory hookData = hook.preCheck(
            address(this), 0,
            _buildMsgData(pools, tokens, spenders, minOut)
        );

        // 模擬夾子攻擊：只收到 50 USDC（遠低於預期）
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(this), 50e6);

        // postCheck 應 revert AIP__SlippageExceeded
        vm.expectRevert(abi.encodeWithSelector(
            AIP__SlippageExceeded.selector,
            USDC,
            50e6,
            1_000e6
        ));
        hook.postCheck(hookData);
        console.log("test_slippage_insufficient_output_reverts: PASSED");
    }

    /// @notice 測試3：未設定 minAmountsOut，不影響現有流程
    function test_slippage_no_minAmountsOut_passes() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);

        pools[0]    = POOL_ETH_USDC;
        tokens[0]   = USDC;
        spenders[0] = SPENDER;

        // 傳空的 minAmountsOut
        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        uint256[] memory minOut = new uint256[](0);
        bytes memory msgData = abi.encodePacked(sel, abi.encode(pools, tokens, spenders, minOut));

        bytes memory hookData = hook.preCheck(address(this), 0, msgData);
        hook.postCheck(hookData);
        console.log("test_slippage_no_minAmountsOut_passes: PASSED");
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
