// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPHook.sol";
import "../src/AIPRegistry.sol";

contract AIPHookTest is Test {

    AIPSensoryLayer public hook;
    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant USDC    = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant SPENDER = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        hook = new AIPSensoryLayer(address(this), address(0));
    }

    function _buildMsgData(
        address[] memory pools,
        address[] memory tokens,
        address[] memory spenders
    ) internal pure returns (bytes memory) {
        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        return abi.encodePacked(sel, abi.encode(pools, tokens, spenders));
    }

    function test_preCheck_normalPool_passes() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        pools[0] = POOL_ETH_USDC; tokens[0] = USDC; spenders[0] = SPENDER;

        bytes memory hookData = hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
        assertTrue(hookData.length > 0);
        console.log("test_preCheck_normalPool_passes: PASSED");
    }

    function test_fullFlow_preAndPostCheck() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        pools[0] = POOL_ETH_USDC; tokens[0] = USDC; spenders[0] = SPENDER;

        bytes memory hookData = hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
        // postCheck 成功 = TSTORE 驗證通過，這就是最好的證明
        hook.postCheck(hookData);
        console.log("test_fullFlow_preAndPostCheck: PASSED");
    }

    function test_postCheck_fakeHookData_reverts() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL_ETH_USDC;

        hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));

        bytes memory fake = abi.encode(uint256(999), address(this), tokens, spenders);
        vm.expectRevert(AIP__CommitmentMismatch.selector);
        hook.postCheck(fake);
        console.log("test_postCheck_fakeHookData_reverts: PASSED");
    }

    function test_preCheck_unauthorised_reverts() public {
        address[] memory empty = new address[](0);

        vm.prank(address(0xDEAD));
        vm.expectRevert(abi.encodeWithSelector(AIP__UnauthorisedCaller.selector, address(0xDEAD)));
        hook.preCheck(address(0xDEAD), 0, _buildMsgData(empty, empty, empty));
        console.log("test_preCheck_unauthorised_reverts: PASSED");
    }
}

contract AIPFlashLoanTest is Test {
    AIPSensoryLayer public hook;
    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        hook = new AIPSensoryLayer(address(this), address(0));
    }

    function test_flashLoan_manipulation_blocked() public {
        vm.store(
            POOL_ETH_USDC,
            bytes32(uint256(0)),
            bytes32(uint256(0x0000000000000000000000000000000000000001000000000000000000000000))
        );
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL_ETH_USDC;
        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        bytes memory msgData = abi.encodePacked(sel, abi.encode(pools, tokens, spenders));

        vm.expectRevert();
        hook.preCheck(address(this), 0, msgData);
        console.log("test_flashLoan_manipulation_blocked: PASSED");
    }
}

contract AIPRegistryTest is Test {
    AIPRegistry public reg;
    AIPSensoryLayer public hook;
    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    // 模擬一個惡意地址（蜜罐）
    address constant EVIL_TOKEN = address(0xDEAD);

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
        return abi.encodePacked(sel, abi.encode(pools, tokens, spenders));
    }

    // 測試 1：正常地址不在黑名單，通過
    function test_registry_clean_address_passes() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL_ETH_USDC;

        bytes memory hookData = hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
        assertTrue(hookData.length > 0);
        console.log("test_registry_clean_address_passes: PASSED");
    }

    // 測試 2：惡意 token 在黑名單，應該 revert
    function test_registry_blacklisted_token_blocked() public {
        // 把 EVIL_TOKEN 加入黑名單
        reg.blacklist(EVIL_TOKEN, "Honeypot token - GoPlus flagged");

        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](0);
        pools[0]  = POOL_ETH_USDC;
        tokens[0] = EVIL_TOKEN;

        vm.expectRevert(abi.encodeWithSelector(AIP__BlacklistedAddress.selector, EVIL_TOKEN));
        hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
        console.log("test_registry_blacklisted_token_blocked: PASSED");
    }

    // 測試 3：惡意 pool 在黑名單，應該 revert
    function test_registry_blacklisted_pool_blocked() public {
        address EVIL_POOL = address(0xBAD);
        reg.blacklist(EVIL_POOL, "Fake pool - GoPlus flagged");

        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = EVIL_POOL;

        vm.expectRevert(abi.encodeWithSelector(AIP__BlacklistedAddress.selector, EVIL_POOL));
        hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
        console.log("test_registry_blacklisted_pool_blocked: PASSED");
    }

    // 測試 4：批量加入黑名單
    function test_registry_batch_blacklist() public {
        address[] memory targets  = new address[](2);
        string[]  memory reasons  = new string[](2);
        targets[0] = address(0x111);
        targets[1] = address(0x222);
        reasons[0] = "Scam token A";
        reasons[1] = "Scam token B";

        reg.blacklistBatch(targets, reasons);

        assertTrue(reg.isBlacklisted(address(0x111)));
        assertTrue(reg.isBlacklisted(address(0x222)));
        assertFalse(reg.isBlacklisted(address(0x333)));
        console.log("test_registry_batch_blacklist: PASSED");
    }
}
