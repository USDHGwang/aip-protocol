// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24  fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract FlashLoanAttacker is IFlashLoanSimpleReceiver {

    address constant AAVE_POOL     = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant SWAP_ROUTER   = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WETH          = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant POOL_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    uint24  constant FEE_TIER      = 500;

    address public immutable owner;
    address public aipHook;

    constructor(address _aipHook) {
        owner   = msg.sender;
        aipHook = _aipHook;
    }

    function attack(uint256 usdcAmount) external {
        IPool(AAVE_POOL).flashLoanSimple(
            address(this),
            USDC,
            usdcAmount,
            abi.encode(usdcAmount),
            0
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == AAVE_POOL, "Attacker: not Aave");

        uint256 usdcAmount = abi.decode(params, (uint256));

        // Step 1: 大量 swap 操縱 Spot Price
        IERC20(USDC).approve(SWAP_ROUTER, usdcAmount);
        ISwapRouter(SWAP_ROUTER).exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn:           USDC,
            tokenOut:          WETH,
            fee:               FEE_TIER,
            recipient:         address(this),
            deadline:          block.timestamp + 60,
            amountIn:          usdcAmount,
            amountOutMinimum:  0,
            sqrtPriceLimitX96: 0
        }));

        // Step 2: 呼叫 AIP preCheck，不用 try/catch
        // 若 revert → 整筆 tx revert → flash loan 失敗 = 攔截成功
        address[] memory pools    = new address[](1);
        address[] memory tokens   = new address[](1);
        address[] memory spenders = new address[](1);
        pools[0]    = POOL_ETH_USDC;
        tokens[0]   = USDC;
        spenders[0] = SWAP_ROUTER;

        bytes4 sel = bytes4(keccak256("execute(address[],address[],address[])"));
        bytes memory msgData = abi.encodePacked(sel, abi.encode(pools, tokens, spenders));

        IAIPHook(aipHook).preCheck(owner, 0, msgData);

        // Step 3: 只有 AIP 沒攔到才會執行還款
        uint256 repayAmount = amount + premium;
        IERC20(asset).approve(AAVE_POOL, repayAmount);
        return true;
    }
}

interface IAIPHook {
    function preCheck(
        address msgSender,
        uint256 msgValue,
        bytes calldata msgData
    ) external returns (bytes memory hookData);
}
