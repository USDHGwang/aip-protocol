// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/*
 * AIP Risk Registry
 * 黑名單查詢：O(1) mapping
 * 只有 owner 能新增/移除黑名單
 */

error Registry__NotOwner();
error Registry__ZeroAddress();

event Blacklisted(address indexed target, string reason);
event Whitelisted(address indexed target);

contract AIPRegistry {

    address public immutable OWNER;

    /// @dev 黑名單 mapping，true = 危險
    mapping(address => bool) private _blacklist;

    /// @dev 黑名單原因記錄
    mapping(address => string) private _reason;

    constructor() {
        OWNER = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert Registry__NotOwner();
        _;
    }

    // ── 查詢 ──────────────────────────────────────────────

    /// @notice 檢查地址是否在黑名單，O(1)
    function isBlacklisted(address target) external view returns (bool) {
        return _blacklist[target];
    }

    /// @notice 取得黑名單原因
    function getReason(address target) external view returns (string memory) {
        return _reason[target];
    }

    // ── 管理 ──────────────────────────────────────────────

    /// @notice 加入黑名單
    function blacklist(address target, string calldata reason) external onlyOwner {
        if (target == address(0)) revert Registry__ZeroAddress();
        _blacklist[target] = true;
        _reason[target] = reason;
        emit Blacklisted(target, reason);
    }

    /// @notice 批量加入黑名單
    function blacklistBatch(
        address[] calldata targets,
        string[] calldata reasons
    ) external onlyOwner {
        require(targets.length == reasons.length, "Registry: length mismatch");
        for (uint256 i; i < targets.length;) {
            if (targets[i] != address(0)) {
                _blacklist[targets[i]] = true;
                _reason[targets[i]] = reasons[i];
                emit Blacklisted(targets[i], reasons[i]);
            }
            unchecked { ++i; }
        }
    }

    /// @notice 移除黑名單
    function whitelist(address target) external onlyOwner {
        _blacklist[target] = false;
        delete _reason[target];
        emit Whitelisted(target);
    }
}
