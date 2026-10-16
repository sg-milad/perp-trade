# PerpEngine — How It Works

`src/PerpEngine.sol` is the only contract that understands positions. It holds
no tokens: every USDT movement is a `transferFrom` into the Vault or a
`settlePnL` instruction that makes the Vault pay out. Its three jobs are
(1) enforce margin gates at open/increase time, (2) compute PnL from the oracle
at close/liquidation time, (3) expose keeper views so the off-chain bot can
find underwater positions.

## Storage

```solidity
struct Position {
    uint256 collateral;   // USDT posted (own token units)
    uint256 size;         // notional in USDT — reserved against Vault liquidity
    uint256 entryPrice;   // oracle price snapshot at open (18 decimals)
    uint256 timestamp;    // stored but never read by any logic
    address trader;       // position owner; only they can manage/close
    bool isLong;          // true = profit when price rises
    bool isActive;        // false after close or liquidation; never re-opened
}
```

- `positions[id]` — all positions ever opened. IDs start at 1 (`nextPositionId`),
  never reused.
- `traderPositions[trader]` — append-only ID list, including closed positions.
- Stats: `totalTradingVolume` (sum of opened + increased size),
  `totalLiquidations`, `totalFeesCollected` (open + increase + close fees).

Immutable links set at construction: `vault`, `collateralToken` (USDT),
`priceFeed` (Chainlink BTC/USD).

## Constants (basis points, 10000 = 100%)

| Name | Value | Effect |
|---|---|---|
| `TRADING_FEE` | 10 (0.1%) | On `size` at open, on added size at increase, on `size` at close |
| `MIN_COLLATERAL_RATIO` | 150 (1.5%) | `collateral / size >= 1.5%`, max leverage ~66.6x |
| `MAX_UTILIZATION_RATE` | 8000 (80%) | `(reserved + newSize) / totalLiquidity <= 80%` |
| `LIQUIDATION_THRESHOLD` | 8000 (80%) | Liquidatable when `collateral + PnL <= 80%` of collateral |
| `LIQUIDATION_REWARD` | 500 (5%) | Keeper cut from position collateral |

## Opening a position (`openPosition`)

Runs in this order:

1. Reject zero collateral or size (`InvalidPositionSize`).
2. `fee = size * 0.1%`; `totalRequired = collateral + fee`. Revert if the
   trader's balance is below it (`InsufficientBalance`).
3. Collateral-ratio gate: `collateral * 10000 >= size * 150`
   (`InsufficientCollateral`). Note the direction: more collateral per unit of
   size passes; high leverage fails.
4. Utilization gate: `(reserved + size) * 10000 / total <= 8000`
   (`ExceedsUtilizationLimit`). Reverts when the Vault is empty too.
5. Read the oracle once — this becomes the immutable `entryPrice`.
6. Store the position, append to `traderPositions`, `reserveLiquidity(size)` in
   the Vault, bump `totalTradingVolume` / `totalFeesCollected`.
7. Pull `collateral + fee` from the trader into the Vault. Emits
   `PositionOpened`.

The fee is paid on top of collateral and stays in the Vault as LP revenue.

## Managing a position

- `increasePositionSize(id, additionalSize)`: owner only, position must be
  active. Pulls only the 0.1% fee on the added size. Re-checks gates 3–4
  against the **new total size** with the **old collateral** — leverage always
  rises. Entry price is not re-averaged; the original entry stands.
- `addCollateral(id, amount)`: owner only. Adds to `collateral`, pulls the
  tokens, emits `CollateralAdded`. No fee, no price read, no utilization check.
  This is the rescue action: it raises `remaining = collateral + PnL` and moves
  liquidation further away without changing size or entry.

## Closing (`closePosition`)

Owner only, must be active. Reads the oracle, computes signed PnL (see
`docs/MATH.md` §2), then:

```
fee   = size * 0.1%
payout = collateral + PnL - fee        (signed)
releaseLiquidity(size)
settlePnL(trader, payout)
```

Marks inactive **before** the Vault calls. A second 0.1% fee is charged here,
so a round trip costs 0.2% of notional. If `payout <= 0` the trader receives
nothing and the Vault books the loss as liquidity (see accounting quirk below).
Emits `PositionClosed`.

## Liquidation (`liquidate`)

Callable by **anyone** — this is the keeper bot's entry point. No close fee.

1. Must be active. Read oracle, compute `remaining = collateral + PnL`.
2. Gate: `remaining <= 80% * collateral`, else `PositionNotLiquidatable`.
   Equivalently, the position has lost ≥ 20% of posted collateral. Because the
   loss is measured against collateral, not size, liquidation distance depends
   on leverage: a 5x position (20% margin) dies after roughly a 4% adverse move.
3. `reward = collateral * 5%`. Release the size reservation, mark inactive.
4. Split: if `remaining > reward`, keeper gets `reward` and the trader gets
   `remaining - reward`; if `0 < remaining <= reward`, the keeper takes all of
   it; if `remaining <= 0`, nobody is paid and the collateral stays in the
   Vault (LPs absorb the shortfall, capped by `settlePnL`'s solvency logic).

Emits `PositionLiquidated`. `totalLiquidations` increments.

## Keeper and frontend views

- `isLiquidatable(id)`: re-evaluates the liquidation gate at the current price.
- `getLiquidatablePositions()`: scans every position from 1 to
  `nextPositionId` and returns the liquidatable IDs. Simple but O(n) with a
  price read per position — fine for this MVP, a subgraph/events feed would
  replace it in production.
- `getUnrealizedPnL(id)`: current PnL, 0 for closed positions.
- `getPositionWithPnL(id)`: position + PnL + price + liquidatable flag in one
  call — the bot/frontend polling endpoint.
- `getProtocolStats()`: volume, liquidation count, fees, active-position count,
  Vault liquidity, utilization.

## Settlement accounting quirk (read before integrating)

Trader collateral and open fees land in the Vault's **token balance** but are
never added to `totalLiquidity`, which tracks LP funds. Payouts, however,
subtract the full amount (including the trader's own collateral return) from
`totalLiquidity`, and losing closes only adjust it by the loss. Net effect:
after profit closes `totalLiquidity` understates, and the token balance and
`totalLiquidity` permanently diverge (verified against the test suite: a
1000-collateral / 500-profit / 5-fee close moves 1495 tokens but books
`totalLiquidity -= 1495`). Utilization checks and LP withdrawals both consume
`totalLiquidity`, so this drift matters for solvency math at scale. vUSD
stays 1:1 regardless — there is no share-price mechanism, so all PnL and any
insolvency haircut (`settlePnL` caps profit payouts at `totalLiquidity`) is
socialized across LPs.

## Known MVP limitations

Oracle price only: no TWAP, staleness check, slippage, or funding rate.
`timestamp` is stored, never used. `getUtilizationRate` returns absolute
reserved liquidity despite its name (the engine uses it correctly as an
absolute). No reentrancy guard — safety relies on checks-effects ordering plus
`SafeERC20` (non-standard fee-on-transfer tokens would break accounting).
