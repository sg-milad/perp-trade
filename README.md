# ⚖️ Decentralized Perpetuals Protocol

A minimal, modular, and secure decentralized perpetuals trading protocol. Inspired by the elegance of simplicity, this MVP is built to demonstrate the core mechanics behind perpetual derivatives—trustless margin trading, liquidity provisioning, and real-time liquidation.

## 🎯 Goal & Deliverables

This protocol has **2 Missions**. This repository delivers **Mission 1**, which implements roughly **50%** of the basic functionality of a decentralized perpetuals protocol. The smart contract codebase is intentionally compact (\~a few hundred lines), focusing on clarity and correctness.

## 🧠 System Overview

The protocol uses a **virtual AMM (vAMM)** model to simulate trading without requiring real counterparties. The vAMM is responsible for pricing trades based on supply and demand dynamics, enabling decentralized and trustless perpetual swaps.

### 🔄 User Flow & Interactions

1. **Liquidity Provider** deposits collateral into the vault.
2. **Trader** opens a long/short position by depositing margin and selecting leverage.
3. **Smart Contract** calculates risk, reserves required liquidity, and updates the state.
4. **Liquidator Bot** monitors open positions and liquidates them if margin requirements are not met.
5. **LPs** can withdraw unreserved liquidity at any time.

### 👥 Actors & Roles

* **Trader** – Opens & manages leveraged positions.
* **Liquidity Provider (LP)** – Supplies protocol liquidity for margin trading.
* **Liquidator Bot** – Monitors the chain and enforces liquidation.
* **Admin (you)** – Currently managing upgrades, configurations, and risk parameters.

---

## 📐 Key Formulas

* **PnL**:
  `PnL = Position Size * (Current Price - Entry Price)`
* **Margin Ratio**:
  `Margin Ratio = Collateral / Position Value`
* **Liquidation Condition**:
  `Margin Ratio < Maintenance Margin`
* **Max Leverage Check**:
  `Used Liquidity ≤ X% of Total Available Liquidity`

---

## 🚀 Contributing

Frontend help wanted! If you're into **DeFi**, **Solidity**, or **protocol design**, I’d love to collaborate.

📩 DM me on Telegram: [@Sg\_milad](https://t.me/Sg_milad)

> Let’s build the simplest, most secure perpetuals protocol—together.

---

## 📦 Repositories

| Component          | Link                                                                           |
| ------------------ | ------------------------------------------------------------------------------ |
| 🔒 Smart Contracts | [github.com/sg-milad/perp-trade](https://github.com/sg-milad/perp-trade)       |
| 🧠 Liquidator Bot  | [github.com/sg-milad/liquidator](https://github.com/sg-milad/liquidator)       |
| 🌐 Frontend        | [github.com/sg-milad/perp-frontend](https://github.com/sg-milad/perp-frontend) |
