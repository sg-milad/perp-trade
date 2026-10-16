# Math & Fundamentals — Perp-Trade Protocol

All arithmetic is integer (Solidity, truncates toward zero). Prices are 18-decimal
(`feed answer * 1e10`); USDT amounts use the token's own units consistently, so
formulas are unit-agnostic.

## Protocol parameters

| Name | Value | Meaning |
|---|---|---|
| `TRADING_FEE` | 10 / 10000 = 0.1% | charged on `size` at open AND at close (0.2% round-trip); also on size increases |
| `MIN_COLLATERAL_RATIO` | 150 / 10000 = 1.5% | `collateral / size >= 1.5%`, i.e. max leverage ~66.6x |
| `MAX_UTILIZATION_RATE` | 8000 / 10000 = 80% | `(reserved + newSize) / totalLiquidity <= 80%` |
| `LIQUIDATION_THRESHOLD` | 8000 / 10000 = 80% | liquidatable once `remaining <= 80%` of collateral |
| `LIQUIDATION_REWARD` | 500 / 10000 = 5% | keeper cut, taken from position collateral |

## 1. Oracle price

```
price = feed.latestRoundData().answer * 1e10        (8-decimal feed -> 18 decimals)
```

No TWAP, no staleness check, no slippage model — execution price always equals
the oracle quote at the block of the call.

## 2. PnL (the core formula)

```
long:   PnL = size * (P_exit - P_entry) / P_entry
short:  PnL = size * (P_entry - P_exit) / P_entry
```

Linear in relative price move times notional. Equivalent: `PnL = size * return`
signed by direction. Worked example from the test suite (collateral 1000,
size 5000 = 5x long, entry 50k, exit 55k):

```
PnL = 5000 * (55000 - 50000) / 50000 = +500 USDT
```

## 3. Opening gate (collateral ratio)

```
collateral * 10000 >= size * 150
<=>  collateral / size >= 1.5%  <=>  leverage <= ~66.6x
```

1000 collateral / 5000 size = 20% — passes. Note the repo's
`test_RevertInsufficientCollateral` (100 collateral, 1000 size = 10%) also
passes the ratio gate; it reverts only because the test approves exactly 100
but open pulls `collateral + fee = 101`, so `transferFrom` fails on allowance.
A true ratio rejection needs leverage above ~66x (e.g. 100 collateral for
10_000 size).

## 4. Utilization cap (solvency gate)

```
(reservedLiquidity + newSize) * 10000 / totalLiquidity <= 8000
```

At most 80% of LP funds can back open notional, leaving a 20% buffer so
winners can always be paid and LPs can withdraw free liquidity.

## 5. Fees

```
fee_open    = size * 0.1%            (paid into Vault on top of collateral)
fee_increase= additionalSize * 0.1%
fee_close   = size * 0.1%            (deducted from payout)
```

Round-trip cost is 0.2% of notional. Fees accrue to `totalFeesCollected` and
stay in the Vault (LP revenue).

## 6. Close payout

```
netPayout = collateral + PnL - fee_close        (via settlePnL)
```

Profit example: `1000 + 500 - 5 = 1495` paid out. The Vault took in 1005
(collateral + open fee) and pays 1495, for a net token loss of 490 = 500
trader profit minus the 10 USDT of round-trip fees kept. Loss example (exit
45k, PnL −500): payout `1000 − 500 − 5 = 495`; the Vault keeps the 1005 taken
in, pays 495, net token gain 510 = 500 trader loss plus 10 fees.

## 7. Liquidation

```
remaining = collateral + PnL
liquidatable  <=>  remaining <= 80% * collateral
              <=>  loss >= 20% of collateral
reward = 5% * collateral
```

Loss needed to liquidate scales with collateral, not notional: a 5x position
(20% margin) liquidates after a ~4% adverse move. Worked: entry 50k, price 42k
(−16%), 5x long: `PnL = 5000 * (−8000)/50000 = −800`, remaining `1000 − 800 =
200 <= 800` → liquidatable. Keeper gets 50, trader gets 150. If
`0 < remaining <= reward`, the keeper takes all of it; if `remaining <= 0`
(e.g. −30% move on minimum 750 collateral → PnL −1500), nobody is paid and the
collateral stays in the Vault.

## 8. Vault settlement and LP shares

```
profit path:  totalLiquidity -= min(payout, totalLiquidity); transfer USDT
loss path:    totalLiquidity += loss   (accounting only; tokens already held)
```

Two quirks to know: (a) trader collateral/fees sit in the Vault's token balance
but are never added to `totalLiquidity`, so `totalLiquidity` tracks LP funds,
not the token balance; (b) vUSD is minted/burned 1:1 with deposits, so there is
no share-price math — profits, losses, and any insolvency haircut (`profit`
capped at `totalLiquidity`) are socialized across all LPs equally.

## 9. Read helpers

`getUnrealizedPnL` = PnL formula at the current price (0 if closed).
`isLiquidatable` / `getLiquidatablePositions` re-evaluate formula 7 on-chain —
this is what the off-chain keeper bot polls. `getUtilizationRate` returns the
absolute `reservedLiquidity` (mislabeled: not a percentage); the true
percentage is `reserved / total`. `getProtocolStats` bundles volume,
liquidation count, fees, active positions, liquidity, and utilization.
