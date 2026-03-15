// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPHook.sol";
import "../src/AIPRegistry.sol";

/// @title GoPlusIntegrationTest
/// @notice 模擬 GoPlus 同步腳本寫入黑名單後，AIP 能正確攔截惡意地址
/// @dev 使用主網上已知的惡意/蜜罐合約地址作為測試輸入
contract GoPlusIntegrationTest is Test {

    AIPRegistry     public reg;
    AIPSensoryLayer public hook;

    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    // 主網上已知惡意合約（GoPlus 標記為 honeypot）
    // Squid Game Token — 2021年知名蜜罐，GoPlus is_honeypot = 1
    address constant HONEYPOT_TOKEN = 0xD99E25969F3E9A78FaCFaE4E6B4821fb1c7F8ff4;

    // 已知釣魚/詐騙合約（GoPlus is_blacklisted = 1）
    address constant SCAM_SPENDER   = 0x1522900B6dAfac587D499a862861C0869bE6428b;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        reg  = new AIPRegistry();
        hook = new AIPSensoryLayer(address(this), address(reg));
    }

    function _buildMsgData(
        address[] memory pools,
        address[] memory tokens,
        address[] memory spenders
    ) internal pure returns (bytes memory) {
        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        uint256[] memory minAmountsOut = new uint256[](0);
        return abi.encodePacked(sel, abi.encode(pools, tokens, spenders, minAmountsOut));
    }

    /// @notice 測試1：GoPlus 同步後，蜜罐 token 被攔截
    function test_goplus_honeypot_token_blocked() public {
        // 模擬 goplus_sync.py 執行後，將惡意 token 寫入 Registry
        reg.blacklist(HONEYPOT_TOKEN, "GoPlus flagged: is_honeypot=1, high_sell_tax");

        // 確認黑名單已寫入
        assertTrue(reg.isBlacklisted(HONEYPOT_TOKEN), "Token should be blacklisted");

        // AIP 應攔截含有該 token 的交易
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](0);
        pools[0]  = POOL_ETH_USDC;
        tokens[0] = HONEYPOT_TOKEN;

        vm.expectRevert(abi.encodeWithSelector(AIP__BlacklistedAddress.selector, HONEYPOT_TOKEN));
        hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));

        console.log("test_goplus_honeypot_token_blocked: PASSED");
        console.log("  Blocked token:", HONEYPOT_TOKEN);
    }

    /// @notice 測試2：GoPlus 同步後，惡意 spender（釣魚合約）被攔截
    function test_goplus_scam_spender_blocked() public {
        reg.blacklist(SCAM_SPENDER, "GoPlus flagged: phishing_activities=1");

        assertTrue(reg.isBlacklisted(SCAM_SPENDER));

        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](1);
        pools[0]    = POOL_ETH_USDC;
        spenders[0] = SCAM_SPENDER;

        vm.expectRevert(abi.encodeWithSelector(AIP__BlacklistedAddress.selector, SCAM_SPENDER));
        hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));

        console.log("test_goplus_scam_spender_blocked: PASSED");
        console.log("  Blocked spender:", SCAM_SPENDER);
    }

    /// @notice 測試3：批量同步後多個惡意地址全部被攔截
    function test_goplus_batch_sync_all_blocked() public {
        // 模擬 blacklistBatch
        address[] memory targets = new address[](2);
        string[]  memory reasons = new string[](2);
        targets[0] = HONEYPOT_TOKEN;
        targets[1] = SCAM_SPENDER;
        reasons[0] = "GoPlus: is_honeypot=1";
        reasons[1] = "GoPlus: phishing_activities=1";

        reg.blacklistBatch(targets, reasons);

        assertTrue(reg.isBlacklisted(HONEYPOT_TOKEN));
        assertTrue(reg.isBlacklisted(SCAM_SPENDER));

        // 任何包含這些地址的交易都應被攔截
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        pools[0]    = POOL_ETH_USDC;
        tokens[0]   = HONEYPOT_TOKEN;
        spenders[0] = SCAM_SPENDER;

        vm.expectRevert();
        hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));

        console.log("test_goplus_batch_sync_all_blocked: PASSED");
    }

    /// @notice 測試4：乾淨地址（USDC）不受影響
    function test_goplus_clean_address_passes() public {
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // USDC 不在黑名單
        assertFalse(reg.isBlacklisted(USDC));

        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](0);
        pools[0]  = POOL_ETH_USDC;
        tokens[0] = USDC;

        bytes memory hookData = hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
        assertTrue(hookData.length > 0, "Clean address should pass");

        console.log("test_goplus_clean_address_passes: PASSED");
    }
}
