// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIPBenchmark.sol";

/**
 * SSTORE vs TSTORE Gas Benchmark
 * 論文 Evaluation 章節數據來源
 */
contract GasBenchmarkTest is Test {

    TraditionalSessionWallet public traditional;
    AIPIntentWallet          public aip;

    function setUp() public {
        traditional = new TraditionalSessionWallet();
        aip         = new AIPIntentWallet();
    }

    // ── SSTORE 測試 ───────────────────────────────────────

    function test_SSTORE_openSession() public {
        uint256 gasBefore = gasleft();
        traditional.openSession();
        uint256 gasUsed = gasBefore - gasleft();
        console.log("[SSTORE] openSession gas:", gasUsed);
    }

    function test_SSTORE_closeSession() public {
        uint256 sessionId = traditional.openSession();
        uint256 gasBefore = gasleft();
        traditional.closeSession(sessionId);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("[SSTORE] closeSession gas:", gasUsed);
    }

    function test_SSTORE_fullLifecycle() public {
        uint256 gasBefore = gasleft();
        uint256 sessionId = traditional.openSession();
        traditional.validateSession(sessionId);
        traditional.closeSession(sessionId);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("[SSTORE] full lifecycle gas:", gasUsed);
    }

    // ── TSTORE 測試 ───────────────────────────────────────

    function test_TSTORE_openIntent() public {
        uint256 gasBefore = gasleft();
        aip.openIntent();
        uint256 gasUsed = gasBefore - gasleft();
        console.log("[TSTORE] openIntent gas:", gasUsed);
    }

    function test_TSTORE_closeIntent() public {
        aip.openIntent();
        uint256 gasBefore = gasleft();
        aip.closeIntent();
        uint256 gasUsed = gasBefore - gasleft();
        console.log("[TSTORE] closeIntent gas:", gasUsed);
    }

    function test_TSTORE_fullLifecycle() public {
        uint256 gasBefore = gasleft();
        uint256 intentId = aip.openIntent();
        aip.validateIntent(intentId);
        aip.closeIntent();
        uint256 gasUsed = gasBefore - gasleft();
        console.log("[TSTORE] full lifecycle gas:", gasUsed);
    }

    // ── 對比總結 ──────────────────────────────────────────

    function test_comparison_summary() public {
        // SSTORE full lifecycle
        uint256 s1 = gasleft();
        uint256 sessionId = traditional.openSession();
        traditional.validateSession(sessionId);
        traditional.closeSession(sessionId);
        uint256 sstoreGas = s1 - gasleft();

        // TSTORE full lifecycle
        uint256 t1 = gasleft();
        uint256 intentId = aip.openIntent();
        aip.validateIntent(intentId);
        aip.closeIntent();
        uint256 tstoreGas = t1 - gasleft();

        console.log("=== AIP Gas Benchmark ===");
        console.log("[SSTORE] Traditional wallet lifecycle:", sstoreGas);
        console.log("[TSTORE] AIP Intent lifecycle:        ", tstoreGas);

        uint256 savings = sstoreGas > tstoreGas ? sstoreGas - tstoreGas : 0;
        uint256 pct     = sstoreGas > 0 ? (savings * 100) / sstoreGas : 0;
        console.log("Gas savings:                          ", savings);
        console.log("Reduction %:                          ", pct);

        assertLt(tstoreGas, sstoreGas, "TSTORE should be cheaper than SSTORE");
    }
}
