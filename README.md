# Decentralized Perpetuals Protocol

---

## Goal & Deliverables

The first mission focuses on implementing roughly 50% of the basic functionality of a decentralized perpetuals protocol. Don’t fret—this initial MVP should remain compact (a few hundred lines of Solidity), not as large as GMX V2’s 10,000+ SLOC.

### Must-Have

- **Protocol Name**: Decide on a unique, memorable name for our protocol.
- **Smart Contracts** with corresponding tests for:

  - Liquidity Providers can deposit and withdraw liquidity.
  - A way to fetch the real-time price of the asset being traded.
  - Traders can open a perpetual position for BTC with a given size and collateral.
  - Traders can increase the size of an existing perpetual position.
  - Traders can increase the collateral of a perpetual position.
  - Enforce that traders cannot utilize more than a configured percentage of the deposited liquidity.
  - Prevent liquidity providers from withdrawing liquidity that is reserved for open positions.

### Documentation (README)

- **How does the system work?** Outline user flows and contract interactions.
- **Actors & Roles**: Who are the users? Is there a keeper? What’s the admin responsible for?
- **Known Risks & Issues**: Highlight potential pitfalls (e.g., oracle manipulation, insolvency scenarios).
- **Key Formulas**: Any formulas used for funding, margin, P\&L, liquidation, etc.

<!-- ---

## Roadmap

| Phase       | Duration | Focus                                        |
| ----------- | -------- | -------------------------------------------- |
| **Phase 0** | 1 day    | Repo setup, Foundry/Hardhat configuration    |
| **Phase 1** | 2 days   | Core market engine (open/close positions)    |
| **Phase 2** | 2 days   | Oracle integration & price feed abstraction  |
| **Phase 3** | 2 days   | Funding rate computation & accounting        |
| **Phase 4** | 2 days   | Liquidation engine & insurance fund          |
| **Phase 5** | 1 day    | Fees, insurance logic, and reentrancy checks |
| **Phase 6** | 2 days   | Unit tests, fuzzing, fork tests              |
| **Phase 7** | 1–2 days | Testnet deploy, keeper bot, monitoring setup |
 -->

---

## 🚀 Contributing

I’m currently building this protocol solo and looking for collaborators! If you’re interested in DeFi, Solidity, and protocol design, let’s work together.

📩 **Message me on Telegram**: \[@Sg_milad]

Let’s build the simplest, most secure perpetuals protocol—together!

---

_Questions? Feedback? Reach out via Telegram or open an issue!_

<!-- ## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
``` -->
