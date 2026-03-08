// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * AIP Gas Benchmark
 * 對比 SSTORE vs TSTORE 在 Intent 生命週期管理上的 gas 差異
 * 論文 Evaluation 章節核心數據
 */

// ── 傳統方案：SSTORE ──────────────────────────────────────
contract TraditionalSessionWallet {

    mapping(uint256 => bool)    public activeSessions;
    mapping(uint256 => address) public sessionOwner;
    mapping(uint256 => uint256) public sessionExpiry;
    uint256 public sessionCounter;

    function openSession() external returns (uint256 sessionId) {
        unchecked { sessionId = ++sessionCounter; }
        activeSessions[sessionId] = true;
        sessionOwner[sessionId]   = msg.sender;
        sessionExpiry[sessionId]  = block.timestamp + 3600;
    }

    function closeSession(uint256 sessionId) external {
        activeSessions[sessionId] = false;
        delete sessionOwner[sessionId];
        delete sessionExpiry[sessionId];
    }

    function validateSession(uint256 sessionId) external view returns (bool) {
        return activeSessions[sessionId] &&
               sessionOwner[sessionId] == msg.sender &&
               sessionExpiry[sessionId] > block.timestamp;
    }
}

// ── AIP 方案：TSTORE ──────────────────────────────────────
contract AIPIntentWallet {

    uint256 constant INTENT_SLOT = 0xB1000000000000000000000000000000000000000000000000000000000001;
    uint256 constant OWNER_SLOT  = 0xB1000000000000000000000000000000000000000000000000000000000002;
    uint256 constant EXPIRY_SLOT = 0xB1000000000000000000000000000000000000000000000000000000000003;

    uint256 private _intentCounter;

    function openIntent() external returns (uint256 intentId) {
        unchecked { intentId = ++_intentCounter; }
        assembly {
            tstore(0xB1000000000000000000000000000000000000000000000000000000000001, intentId)
            tstore(0xB1000000000000000000000000000000000000000000000000000000000002, caller())
            tstore(0xB1000000000000000000000000000000000000000000000000000000000003, add(timestamp(), 3600))
        }
    }

    function closeIntent() external {
        assembly {
            tstore(0xB1000000000000000000000000000000000000000000000000000000000001, 0)
            tstore(0xB1000000000000000000000000000000000000000000000000000000000002, 0)
            tstore(0xB1000000000000000000000000000000000000000000000000000000000003, 0)
        }
    }

    function validateIntent(uint256 intentId) external view returns (bool) {
        uint256 stored;
        uint256 owner;
        uint256 expiry;
        assembly {
            stored := tload(0xB1000000000000000000000000000000000000000000000000000000000001)
            owner  := tload(0xB1000000000000000000000000000000000000000000000000000000000002)
            expiry := tload(0xB1000000000000000000000000000000000000000000000000000000000003)
        }
        return stored == intentId &&
               address(uint160(owner)) == msg.sender &&
               expiry > block.timestamp;
    }
}
