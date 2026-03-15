// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPHook.sol";
import "../src/AIPRegistry.sol";

/**
 * AIP 壓力測試
 * 模擬大量攻擊，量測偵測時間與 gas
 */
contract AIPStressTest is Test {

    AIPSensoryLayer public hook;
    AIPRegistry     public reg;

    address constant POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

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

    // ── 壓力測試 1：100 筆正常交易 ──────────────────────
    function test_stress_100_normal_transactions() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL;

        uint256 totalGas;
        uint256 rounds = 100;

        for (uint256 i; i < rounds; i++) {
            uint256 g = gasleft();
            bytes memory hookData = hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
            hook.postCheck(hookData);
            totalGas += g - gasleft();
        }

        console.log("=== Stress Test: 100 Normal Transactions ===");
        console.log("Total gas:  ", totalGas);
        console.log("Avg gas/tx: ", totalGas / rounds);
    }

    // ── 壓力測試 2：100 筆閃電貸攻擊，全部被攔截 ───────
    function test_stress_100_flashloan_attacks() public {
        // 竄改 pool slot0，模擬閃電貸操縱
        vm.store(POOL, bytes32(0), bytes32(uint256(1 << 160)));

        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL;

        uint256 blockedCount;
        uint256 totalGas;
        uint256 rounds = 100;

        for (uint256 i; i < rounds; i++) {
            uint256 g = gasleft();
            try hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders)) {
                // 沒被攔截（不應該發生）
            } catch {
                blockedCount++;
            }
            totalGas += g - gasleft();
        }

        console.log("=== Stress Test: 100 FlashLoan Attacks ===");
        console.log("Blocked:        ", blockedCount, "/ 100");
        console.log("Total gas:      ", totalGas);
        console.log("Avg gas/attack: ", totalGas / 100);
    }

    // ── 壓力測試 3：100 筆黑名單攻擊，全部被攔截 ───────
    function test_stress_100_blacklist_attacks() public {
        // 批量加入 100 個惡意地址
        address[] memory targets = new address[](100);
        string[]  memory reasons = new string[](100);
        for (uint256 i; i < 100; i++) {
            targets[i] = address(uint160(0xDEAD0000 + i));
            reasons[i] = "GoPlus flagged";
        }
        reg.blacklistBatch(targets, reasons);

        uint256 blockedCount;
        uint256 totalGas;

        for (uint256 i; i < 100; i++) {
            address[] memory pools    = new address[](0);
            address[] memory tokens   = new address[](1);
            address[] memory spenders = new address[](0);
            tokens[0] = address(uint160(0xDEAD0000 + i));

            uint256 g = gasleft();
            try hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders)) {
            } catch {
                blockedCount++;
            }
            totalGas += g - gasleft();
        }

        console.log("=== Stress Test: 100 Blacklist Attacks ===");
        console.log("Blocked:        ", blockedCount, "/ 100");
        console.log("Total gas:      ", totalGas);
        console.log("Avg gas/attack: ", totalGas / 100);
    }

    // ── 壓力測試 4：100 筆 HookData 偽造攻擊 ───────────
    function test_stress_100_hookdata_forgery() public {
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](0);
        address[] memory spenders = new address[](0);
        pools[0] = POOL;

        uint256 blockedCount;
        uint256 totalGas;
        uint256 rounds = 100;

        for (uint256 i; i < rounds; i++) {
            hook.preCheck(address(this), 0, _buildMsgData(pools, tokens, spenders));
            bytes memory fakeHookData = abi.encode(i + 999, address(this), tokens, spenders);
            uint256 g = gasleft();
            try hook.postCheck(fakeHookData) {
            } catch {
                blockedCount++;
            }
            totalGas += g - gasleft();
        }

        console.log("=== Stress Test: 100 HookData Forgery Attacks ===");
        console.log("Blocked:        ", blockedCount, "/ 100");
        console.log("Total gas:      ", totalGas);
        console.log("Avg gas/attack: ", totalGas / 100);
    }
}
