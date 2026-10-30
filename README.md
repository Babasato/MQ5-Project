# EURUSD Trend EA (MetaTrader 5)

A trend-following Expert Advisor for MetaTrader 5, written in MQL5. It is a learning project and is **not validated for live trading** (see Status).

## Strategy

The EA trades pullbacks within a trend. Logic runs once per newly closed bar, not on every tick, on whichever chart and timeframe the EA is attached to.

**Trend filter**
- Uptrend: the last close is above the 50 EMA, the 50 EMA is above the 200 EMA, and the 50 EMA is rising versus 10 bars ago.
- Downtrend: the mirror image.
- If neither condition holds, the EA does nothing.

**Entry**
- Long: a recent bar dipped to or below the 50 EMA, and the last closed bar is bullish and closes back above it. Shorts are the mirror image.
- Market orders. At most one open position per symbol.

**Exits**
- Stop loss: beyond the 20-bar swing low (longs) or swing high (shorts), plus a buffer of 0.5 x ATR(14).
- Take profit: 4 times the stop distance (1:4 reward to risk).
- No trailing stop or time-based exit.

**Position sizing**
- Risks a fixed percentage of account equity per trade (default 2%), using the symbol's tick value, rounded down to the broker's lot step.

## Inputs

| Parameter | Default | Purpose |
|---|---|---|
| EMA_Fast_Period | 50 | Fast trend EMA |
| EMA_Slow_Period | 200 | Slow trend EMA |
| ATR_Period | 14 | ATR length |
| ATR_Buffer_Mult | 0.5 | ATR multiple added to the stop |
| Swing_Lookback_Bars | 20 | Bars scanned for swing high/low |
| Risk_Percent | 2.0 | Equity risked per trade (%) |
| Reward_Risk_Ratio | 4.0 | Target as a multiple of the stop distance |
| Slope_Lookback_Bars | 10 | Bars back for the EMA slope check |
| Magic_Number | 20260815 | Trade identifier |

## Installation

1. In MetaTrader 5, choose File, then Open Data Folder.
2. Copy `EURUSD_TrendEA.mq5` into `MQL5/Experts/`.
3. Open MetaEditor, compile the file (F7), and attach it to a chart, or run it in the Strategy Tester.

## Status and honest limitations

- **Version 1.00. Not validated.** There are no published backtest or live results, and I do not recommend trading it with real money.
- **Research result:** I tested several trading ideas in Python on about nine years of hourly data across six currency pairs (mean reversion, moving-average crossover, volatility breakout, session timing, and others). After trading costs, nearly all of them failed to show a real edge, so I stopped before treating this EA as a product.
- **Known gaps:** this is a first version. It has no spread, session, or news filters and no daily loss limit, and it has not had a full code review or stress test.

This repository is kept as an example of my approach: write the logic down first, build it, test it honestly, and report what did and did not work.

## Disclaimer

For educational purposes only. Trading leveraged products carries a high risk of loss.

## Author

Robert Lenjirr, Nairobi, Kenya.
