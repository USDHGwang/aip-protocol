# AIP Protocol — Autonomous Intent-integrity Protocol

**AI Agent 鏈上授權安全協議**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Tests](https://img.shields.io/badge/Tests-44%20passing-brightgreen.svg)]()

---

## Overview

AIP is an on-chain security protocol designed for AI Agents executing DeFi transactions. It enforces **Agent Intent Integrity (AII)**—ensuring that what an AI Agent *declares* it will do is exactly what gets *executed* on-chain, with no manipulation in between.

Built on **ERC-7579 Hook** + **EIP-1153 Transient Storage**, AIP intercepts every transaction at two checkpoints within the same atomic execution:
```
Agent Intent
    ↓
preCheck  → Blacklist check + TWAP Fingerprint + Lock intent hash (TSTORE)
    ↓
Execution → Untrusted DeFi calls
    ↓
postCheck → Hash verification + Slippage check + Zero-Allowance enforcement
    ↓
Intent Closed
```

---

## Why AIP?

Current AI Agent frameworks have no execution-layer security. `amountOutMinimum` only protects the *result*, not the *process*. AIP fills this gap:

| Attack Vector | AIP Defense |
|--------------|-------------|
| Flash loan price manipulation | TWAP Fingerprint (Adaptive δ) |
| hookData forgery | Hash Commitment (EIP-1153 TSTORE) |
| Authorization residue exploitation | Zero-Allowance Enforcement |
| Blacklisted address interaction | GoPlus Registry Check |
| Sandwich / slippage attacks | Slippage Sentry |

> **Key insight**: By leveraging EIP-1153 transient storage, AIP eliminates authorization persistence beyond transaction boundaries *by design*, structurally preventing cross-transaction allowance exploitation.

---

## Core Innovation — Adaptive δ (Dynamic TWAP Threshold)
```
δ(pool) = BASE_DELTA × (REFERENCE_LIQ / pool.liquidity())
```

- BASE_DELTA = 15 ticks: empirically derived from ETH/USDC 0.05% pool
- REFERENCE_LIQ = 2.486e18: measured active liquidity of the reference pool
- pool.liquidity(): **active LP liquidity at current tick** (not total TVL)
- Clamp: [5, 500] ticks

| Pool | Liquidity | Normal | 500k USDC Attack | Dynamic δ | Result |
|------|-----------|--------|-----------------|-----------|--------|
| ETH/USDC 0.05% (deep) | 2.46e18 | 3 ticks | 81 ticks | 15 | BLOCK ✅ |
| ETH/USDC 0.30% (medium) | 8.55e17 | 3 ticks | 242 ticks | ~44 | BLOCK ✅ |
| ETH/USDC 1.00% (shallow) | 1.15e17 | 2 ticks | 1720 ticks | ~214 | BLOCK ✅ |

---

## Test Results

**44 tests passing** on Ethereum mainnet fork:

| Test Category | Tests | Result |
|--------------|-------|--------|
| Core preCheck / postCheck | 12 | ✅ All pass |
| Stress tests (100 attacks each) | 4 | ✅ 100/100 intercepted |
| Real flash loan (500k USDC, Aave V3) | 1 | ✅ Blocked |
| Fuzz testing (256 runs each) | 2 | ✅ No bypass found |
| GoPlus blacklist integration | 4 | ✅ All pass |
| Slippage Sentry | 3 | ✅ All pass |
| Adaptive δ | 12 | ✅ All pass |
| Gas benchmark | 3 | ✅ All pass |

---

## Gas Overhead

| Scenario | Gas |
|---------|-----|
| Swap without AIP | 127,690 |
| Full AIP (preCheck + swap + postCheck) | 261,050 |
| **Overhead** | **+133,360 (+104%)** |

> ~$8/tx on Ethereum mainnet. Negligible on Layer 2 (< $0.01/tx).

---

## Quickstart
```bash
git clone https://github.com/USDHGwang/aip-protocol.git
cd aip-protocol && forge install
export ETH_RPC_URL=<your-rpc-url>
forge test --fork-url $ETH_RPC_URL -vv
```

---

## Academic Contributions

**C1** — First threat model treating AI Agent non-deterministic behavior as the on-chain threat principal.

**C2** — First application of EIP-1153 Transient Storage to AI Agent authorization lifecycle. Validated against 3,000+ paper survey (Alqithami 2026).

**C3** — Verifiable implementation: 44 tests, fork mainnet, 5 attack scenarios, 51% gas savings vs SSTORE.

---

## Limitations

- Stable-to-stable pools require separate BASE_DELTA (pool.liquidity() not cross-class comparable)
- Liquidity Manipulation: adversarial withdrawal can inflate δ (Liquidity-TWAP is future work)
- Reasoning layer attacks (prompt injection) are out of scope

---

## Roadmap

- [ ] Liquidity-TWAP
- [ ] Pool type classification for stable pools
- [ ] Intent signature via ERC-8004
- [ ] Modular Strategy Architecture

---

MIT © 2026 AIP Protocol
