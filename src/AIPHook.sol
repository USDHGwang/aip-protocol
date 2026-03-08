// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos)
        external view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
    function slot0()
        external view
        returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool);
}

interface IERC7579Hook {
    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData) external returns (bytes memory hookData);
    function postCheck(bytes calldata hookData) external;
}

/// @notice AIP Risk Registry 查詢介面
interface IAIPRegistry {
    function isBlacklisted(address target) external view returns (bool);
}

error AIP__PriceManipulated(address pool, uint256 deviationBps);
error AIP__InsufficientLiquidity(address pool);
error AIP__UnauthorisedCaller(address caller);
error AIP__NoActiveIntent();
error AIP__CommitmentMismatch();
error AIP__AllowanceResetFailed(address token, address spender);
error AIP__BlacklistedAddress(address target);  // 新增

event IntentOpened(uint256 indexed intentId, address indexed account);
event IntentClosed(uint256 indexed intentId, address indexed account);
event FingerprintPassed(address indexed pool, int24 twapTick, int24 spotTick);
event AllowanceReset(address indexed token, address indexed spender);
event RegistryUpdated(address indexed newRegistry);  // 新增

uint256 constant INTENT_TSLOT    = 0xA1B2C3D4E5F600000000000000000000000000000000000000000000000001;
uint256 constant COMMIT_TSLOT    = 0xA1B2C3D4E5F600000000000000000000000000000000000000000000000002;
uint32  constant TWAP_SECONDS    = 300;
uint256 constant MAX_DEV_BPS     = 100;
int24   constant MIN_TICK        = -92200;

contract AIPSensoryLayer is IERC7579Hook {
    address public immutable ACCOUNT;
    uint256 private _intentCounter;

    /// @notice GoPlus 同步的黑名單 Registry
    IAIPRegistry public registry;

    constructor(address account, address _registry) {
        require(account != address(0), "AIP: zero account");
        ACCOUNT = account;
        registry = IAIPRegistry(_registry);
    }

    modifier onlyAccount() {
        if (msg.sender != ACCOUNT) revert AIP__UnauthorisedCaller(msg.sender);
        _;
    }

    /// @notice 更新 Registry 地址（只有 account 能呼叫）
    function updateRegistry(address newRegistry) external onlyAccount {
        registry = IAIPRegistry(newRegistry);
        emit RegistryUpdated(newRegistry);
    }

    function preCheck(address, uint256, bytes calldata msgData)
        external override onlyAccount returns (bytes memory hookData)
    {
        (address[] memory pools, address[] memory tokens, address[] memory spenders)
            = _decodeContext(msgData);

        // 1. Registry 黑名單檢查（GoPlus 同步）
        _registryCheck(pools, tokens);

        // 2. Liquidity Fingerprint
        for (uint256 i; i < pools.length;) {
            if (pools[i] != address(0)) _liquidityFingerprint(pools[i]);
            unchecked { ++i; }
        }

        // 3. 開啟 Intent
        uint256 intentId = _openIntent();

        // 4. 打包 hookData
        hookData = abi.encode(intentId, ACCOUNT, tokens, spenders);

        // 5. Hash Commitment
        _tstore(COMMIT_TSLOT, uint256(keccak256(hookData)));

        emit IntentOpened(intentId, ACCOUNT);
    }

    function postCheck(bytes calldata hookData) external override onlyAccount {
        bytes32 stored   = bytes32(_tload(COMMIT_TSLOT));
        bytes32 computed = keccak256(hookData);
        if (stored != computed) revert AIP__CommitmentMismatch();

        (uint256 intentId, address account, address[] memory tokens, address[] memory spenders)
            = abi.decode(hookData, (uint256, address, address[], address[]));

        if (_tload(INTENT_TSLOT) != intentId) revert AIP__NoActiveIntent();

        _enforceZeroAllowance(account, tokens, spenders);
        _closeIntent(intentId, account);
    }

    // ── Registry 黑名單檢查 ───────────────────────────────

    function _registryCheck(
        address[] memory pools,
        address[] memory tokens
    ) internal view {
        if (address(registry) == address(0)) return;

        for (uint256 i; i < pools.length;) {
            if (pools[i] != address(0) && registry.isBlacklisted(pools[i])) {
                revert AIP__BlacklistedAddress(pools[i]);
            }
            unchecked { ++i; }
        }

        for (uint256 i; i < tokens.length;) {
            if (tokens[i] != address(0) && registry.isBlacklisted(tokens[i])) {
                revert AIP__BlacklistedAddress(tokens[i]);
            }
            unchecked { ++i; }
        }
    }

    // ── Liquidity Fingerprint ─────────────────────────────

    function _liquidityFingerprint(address pool) internal {
        IUniswapV3Pool v3 = IUniswapV3Pool(pool);

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_SECONDS;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = v3.observe(secondsAgos);

        int24 twapTick = int24(
            (tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(TWAP_SECONDS))
        );
        (, int24 spotTick,,,,,) = v3.slot0();

        int24 diff    = spotTick > twapTick ? spotTick - twapTick : twapTick - spotTick;
        int24 absTwap = twapTick < 0 ? -twapTick : twapTick;

        uint256 deviationBps;
        if (absTwap > 0) {
            deviationBps = (uint256(uint24(diff)) * 10_000) / uint256(uint24(absTwap));
        }

        if (deviationBps > MAX_DEV_BPS) revert AIP__PriceManipulated(pool, deviationBps);
        if (spotTick < MIN_TICK)        revert AIP__InsufficientLiquidity(pool);

        emit FingerprintPassed(pool, twapTick, spotTick);
    }

    // ── Zero-Allowance Enforcement ────────────────────────

    function _enforceZeroAllowance(
        address account,
        address[] memory tokens,
        address[] memory spenders
    ) internal {
        require(tokens.length == spenders.length, "AIP: length mismatch");
        for (uint256 i; i < tokens.length;) {
            address token   = tokens[i];
            address spender = spenders[i];
            if (token != address(0) && spender != address(0)) {
                (bool ok1, bytes memory data) = token.staticcall(
                    abi.encodeWithSignature("allowance(address,address)", account, spender)
                );
                if (ok1 && data.length >= 32) {
                    uint256 current = abi.decode(data, (uint256));
                    if (current != 0) {
                        (bool ok2,) = token.call(
                            abi.encodeWithSignature("approve(address,uint256)", spender, 0)
                        );
                        if (!ok2) revert AIP__AllowanceResetFailed(token, spender);
                        emit AllowanceReset(token, spender);
                    }
                }
            }
            unchecked { ++i; }
        }
    }

    // ── Intent Lifecycle ──────────────────────────────────

    function _openIntent() internal returns (uint256 intentId) {
        unchecked { intentId = ++_intentCounter; }
        _tstore(INTENT_TSLOT, intentId);
    }

    function _closeIntent(uint256 intentId, address account) internal {
        _tstore(INTENT_TSLOT, 0);
        _tstore(COMMIT_TSLOT, 0);
        emit IntentClosed(intentId, account);
    }

    // ── Calldata Decoder ──────────────────────────────────

    function _decodeContext(bytes calldata msgData)
        internal pure
        returns (address[] memory pools, address[] memory tokens, address[] memory spenders)
    {
        if (msgData.length < 4) {
            return (new address[](0), new address[](0), new address[](0));
        }
        bytes calldata params = msgData[4:];
        if (params.length < 96) {
            return (new address[](0), new address[](0), new address[](0));
        }
        (pools, tokens, spenders) = abi.decode(params, (address[], address[], address[]));
    }

    // ── EIP-1153 ──────────────────────────────────────────

    function _tstore(uint256 slot, uint256 value) internal {
        assembly { tstore(slot, value) }
    }

    function _tload(uint256 slot) internal view returns (uint256 value) {
        assembly { value := tload(slot) }
    }
}
