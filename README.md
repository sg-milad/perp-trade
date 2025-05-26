# ⚖️ Decentralized Perpetuals Protocol

A minimal, modular, and secure decentralized perpetuals trading protocol. Inspired by the elegance of simplicity, this MVP is built to demonstrate the core mechanics behind perpetual derivatives—trustless margin trading, liquidity provisioning, and real-time liquidation.

## 🌟 Goal & Deliverables

This is **Mission 1**—implementing approximately **50%** of the essential features of a decentralized perpetual protocol. The smart contract codebase is intentionally compact (\~a few hundred lines), focusing on clarity and correctness.

## ✅ Must-Have Features

### 🧱 Protocol Components

* **Liquidity Providers**

  * Can deposit and withdraw liquidity into/from the vault.
  * Withdrawals are restricted if funds are reserved for active trader positions.

* **Oracle Integration**

  * Real-time asset pricing fetched via a mock oracle (expandable in the future).

* **Traders**

  * Can open and close BTC perpetual positions with specified size and collateral.
  * Can increase position size and collateral.
  * Cannot exceed a configured leverage cap (based on protocol's available liquidity).

* **Risk Management**

  * Ensures sufficient margin is maintained.
  * Prevents excessive liquidity use or withdrawal when positions are open.

### ♻️ Liquidation Bot

* [Liquidator Bot Repo](https://github.com/sg-milad/liquidator)
  A functional off-chain bot monitors positions and triggers liquidation when conditions are breached.

### 🌐 Frontend Interface *(WIP)*

* [Frontend Repo](https://github.com/sg-milad/perp-frontend)
  A simple UI for interacting with the protocol (positions, vault, oracle).
  Currently in development—community contributions welcome!

---

## 🧠 System Overview

### ↺ User Flow & Interactions

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

## ⚠️ Known Risks & Issues

* **Oracle Manipulation** – Current oracle is basic; secure oracles like Chainlink are recommended for production.
* **Insolvency Risk** – If margin enforcement fails, LPs may suffer losses.
* **Liquidator Dependency** – Requires active monitoring to enforce protocol health.

---

## 📊 Key Formulas

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

This protocol is built by a solo dev—but it doesn't have to stay that way!

### 💡 What You Can Help With

* Frontend development (React / ethers.js or viem)
* UI design & UX improvements
* Advanced oracle integration (e.g., Chainlink)
* Audit & security reviews
* Writing docs or tutorials
* Extending the liquidation bot
* Unit tests and edge-case simulations

### 📬 Contact Me

If you're into **DeFi**, **Solidity**, or **protocol design** and want to contribute, **I’d love to collaborate!**

* Message me on Telegram: [@Sg\_milad](https://t.me/Sg_milad)
* Or open an issue / pull request on GitHub

> Let’s build the simplest, most secure perpetuals protocol—together.

---

## 📦 Repositories

| Component          | Link                                                                           |
| ------------------ | ------------------------------------------------------------------------------ |
| 🔒 Smart Contracts | [github.com/sg-milad/perp-trade](https://github.com/sg-milad/perp-trade)                                                  |
| 🧠 Liquidator Bot  | [github.com/sg-milad/liquidator](https://github.com/sg-milad/liquidator)       |
| 🌐 Frontend        | [github.com/sg-milad/perp-frontend](https://github.com/sg-milad/perp-frontend) |
