#!/usr/bin/env python3
"""
GoPlus → AIPRegistry Sync Script
查詢 GoPlus API，將惡意地址自動同步到鏈上 AIPRegistry
"""

import os
import sys
import json
import time
import logging
import requests
from web3 import Web3
from web3.middleware import geth_poa_middleware

# ── 設定 ─────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger(__name__)

# 從環境變數讀取（不硬寫私鑰）
RPC_URL          = os.environ.get("ETH_RPC_URL", "")
PRIVATE_KEY      = os.environ.get("DEPLOYER_PRIVATE_KEY", "")
REGISTRY_ADDRESS = os.environ.get("AIP_REGISTRY_ADDRESS", "")
CHAIN_ID         = int(os.environ.get("CHAIN_ID", "1"))  # 1 = Ethereum mainnet

GOPLUS_API       = "https://api.gopluslabs.io/api/v1"
GOPLUS_CHAIN_ID  = "1"  # Ethereum

# AIPRegistry ABI（只需要用到的函數）
REGISTRY_ABI = [
    {
        "inputs": [
            {"internalType": "address", "name": "target", "type": "address"},
            {"internalType": "string",  "name": "reason", "type": "string"}
        ],
        "name": "blacklist",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "address[]", "name": "targets", "type": "address[]"},
            {"internalType": "string[]",  "name": "reasons", "type": "string[]"}
        ],
        "name": "blacklistBatch",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "address", "name": "target", "type": "address"}],
        "name": "isBlacklisted",
        "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function"
    }
]

# GoPlus 惡意 flag 判斷條件（任一為 "1" 則視為惡意）
MALICIOUS_FLAGS = [
    "is_honeypot",
    "is_blacklisted",
    "is_proxy",
    "can_take_back_ownership",
    "owner_change_balance",
    "hidden_owner",
    "selfdestruct",
    "external_call",
    "is_whitelisted",        # 白名單機制（可封鎖外部轉帳）
    "is_anti_whale",         # 反鯨魚機制（可操縱交易上限）
    "trading_cooldown",      # 交易冷卻（可凍結交易）
    "personal_slippage_modifiable",  # 可動態修改滑點
]


# ── GoPlus API 查詢 ───────────────────────────────────────────────────────────

def query_goplus_token(address: str) -> dict | None:
    """查詢單一 token 的 GoPlus 安全報告"""
    url = f"{GOPLUS_API}/token_security/{GOPLUS_CHAIN_ID}"
    try:
        resp = requests.get(
            url,
            params={"contract_addresses": address.lower()},
            timeout=10
        )
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") == 1 and data.get("result"):
            return data["result"].get(address.lower())
    except Exception as e:
        log.warning(f"GoPlus query failed for {address}: {e}")
    return None


def query_goplus_malicious_address(address: str) -> dict | None:
    """查詢地址是否在 GoPlus 惡意地址資料庫"""
    url = f"{GOPLUS_API}/address_security/{address}"
    try:
        resp = requests.get(url, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") == 1:
            return data.get("result")
    except Exception as e:
        log.warning(f"GoPlus address query failed for {address}: {e}")
    return None


def is_malicious_token(report: dict) -> tuple[bool, str]:
    """
    判斷 token 是否惡意
    Returns: (is_malicious, reason_string)
    """
    triggered = []
    for flag in MALICIOUS_FLAGS:
        if report.get(flag) == "1":
            triggered.append(flag)

    # 額外檢查：買/賣稅超過 10% 視為高風險
    buy_tax  = float(report.get("buy_tax",  "0") or "0")
    sell_tax = float(report.get("sell_tax", "0") or "0")
    if buy_tax > 0.10:
        triggered.append(f"high_buy_tax:{buy_tax:.0%}")
    if sell_tax > 0.10:
        triggered.append(f"high_sell_tax:{sell_tax:.0%}")

    if triggered:
        return True, f"GoPlus flagged: {', '.join(triggered)}"
    return False, ""


# ── 鏈上操作 ──────────────────────────────────────────────────────────────────

def get_web3_and_contract():
    """建立 Web3 連線和 Registry 合約實例"""
    if not RPC_URL:
        raise ValueError("ETH_RPC_URL not set")
    if not PRIVATE_KEY:
        raise ValueError("DEPLOYER_PRIVATE_KEY not set")
    if not REGISTRY_ADDRESS:
        raise ValueError("AIP_REGISTRY_ADDRESS not set")

    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    w3.middleware_onion.inject(geth_poa_middleware, layer=0)

    if not w3.is_connected():
        raise ConnectionError("Cannot connect to RPC")

    contract = w3.eth.contract(
        address=Web3.to_checksum_address(REGISTRY_ADDRESS),
        abi=REGISTRY_ABI
    )
    account = w3.eth.account.from_key(PRIVATE_KEY)
    return w3, contract, account


def blacklist_address(w3, contract, account, address: str, reason: str) -> str:
    """將地址加入 AIPRegistry 黑名單，回傳 tx hash"""
    checksum_addr = Web3.to_checksum_address(address)

    # 先確認是否已在黑名單
    if contract.functions.isBlacklisted(checksum_addr).call():
        log.info(f"Already blacklisted: {address}")
        return ""

    nonce = w3.eth.get_transaction_count(account.address)
    gas_price = w3.eth.gas_price

    tx = contract.functions.blacklist(checksum_addr, reason).build_transaction({
        "from":     account.address,
        "nonce":    nonce,
        "gas":      100_000,
        "gasPrice": gas_price,
        "chainId":  CHAIN_ID,
    })

    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

    if receipt.status == 1:
        log.info(f"Blacklisted {address} | reason: {reason} | tx: {tx_hash.hex()}")
        return tx_hash.hex()
    else:
        log.error(f"Blacklist tx failed for {address}")
        return ""


def blacklist_batch(w3, contract, account, entries: list[tuple[str, str]]) -> str:
    """批量加入黑名單"""
    addresses = [Web3.to_checksum_address(a) for a, _ in entries]
    reasons   = [r for _, r in entries]

    nonce = w3.eth.get_transaction_count(account.address)
    gas_price = w3.eth.gas_price

    tx = contract.functions.blacklistBatch(addresses, reasons).build_transaction({
        "from":     account.address,
        "nonce":    nonce,
        "gas":      50_000 * len(entries) + 50_000,
        "gasPrice": gas_price,
        "chainId":  CHAIN_ID,
    })

    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)

    if receipt.status == 1:
        log.info(f"Batch blacklisted {len(entries)} addresses | tx: {tx_hash.hex()}")
        return tx_hash.hex()
    else:
        log.error("Batch blacklist tx failed")
        return ""


# ── 主流程 ────────────────────────────────────────────────────────────────────

def sync_addresses(addresses: list[str], dry_run: bool = False):
    """
    主同步流程
    1. 逐一查詢 GoPlus
    2. 收集惡意地址
    3. 批量寫入 AIPRegistry
    """
    log.info(f"Starting GoPlus sync | {len(addresses)} addresses | dry_run={dry_run}")

    malicious_batch = []

    for i, addr in enumerate(addresses):
        log.info(f"[{i+1}/{len(addresses)}] Checking {addr}")

        # 查 token security
        report = query_goplus_token(addr)
        if report:
            flagged, reason = is_malicious_token(report)
            if flagged:
                log.warning(f"MALICIOUS TOKEN: {addr} | {reason}")
                malicious_batch.append((addr, reason))
            else:
                log.info(f"Clean: {addr}")
        else:
            # 查 address security（non-token 合約）
            addr_report = query_goplus_malicious_address(addr)
            if addr_report:
                flags = [k for k, v in addr_report.items() if v == "1"]
                if flags:
                    reason = f"GoPlus address_security: {', '.join(flags)}"
                    log.warning(f"MALICIOUS ADDRESS: {addr} | {reason}")
                    malicious_batch.append((addr, reason))
            else:
                log.info(f"No data for {addr}")

        # Rate limit: GoPlus 免費版 30 req/min
        time.sleep(2)

    log.info(f"Found {len(malicious_batch)} malicious addresses")

    if not malicious_batch:
        log.info("Nothing to blacklist.")
        return

    if dry_run:
        log.info("DRY RUN — would blacklist:")
        for addr, reason in malicious_batch:
            log.info(f"  {addr}: {reason}")
        return

    # 寫入鏈上
    w3, contract, account = get_web3_and_contract()
    log.info(f"Deployer: {account.address}")

    if len(malicious_batch) == 1:
        blacklist_address(w3, contract, account, *malicious_batch[0])
    else:
        blacklist_batch(w3, contract, account, malicious_batch)

    log.info("Sync complete.")


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="GoPlus → AIPRegistry Sync")
    parser.add_argument(
        "addresses",
        nargs="*",
        help="Contract addresses to check (or use --file)"
    )
    parser.add_argument(
        "--file", "-f",
        help="Text file with one address per line"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Query GoPlus but do not write to chain"
    )
    args = parser.parse_args()

    target_addresses = list(args.addresses)

    if args.file:
        with open(args.file) as f:
            target_addresses += [line.strip() for line in f if line.strip()]

    if not target_addresses:
        # 預設測試：幾個已知惡意合約
        target_addresses = [
            "0xd99E25969f3e9A78faCFAe4e6B4821fB1c7F8Ff4",  # 已知蜜罐
            "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",  # USDC（乾淨，對照用）
        ]
        log.info("No addresses provided, using default test set")

    sync_addresses(target_addresses, dry_run=args.dry_run)
