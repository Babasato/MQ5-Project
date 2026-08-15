//+------------------------------------------------------------------+
//| EURUSD_TrendEA.mq5                                                |
//| Trend-following EA — v1                                           |
//|                                                                    |
//| Logic reference: logic-spec.md in this repo. Any rule change here |
//| must be logged there FIRST with date + rationale before editing   |
//| this file. That log is part of the ownership/decision trail.      |
//|                                                                    |
//| Strategy summary (see logic-spec.md for full detail):             |
//|  - Trend: 50 EMA vs 200 EMA, with slope check, on chart timeframe |
//|  - Entry: pullback to 50 EMA, then a confirmation candle closing  |
//|    back in the trend direction                                    |
//|  - Stop: beyond recent swing point, buffered by ATR               |
//|  - Target: fixed 4x the stop distance (reward:risk = 1:4)         |
//|  - Size: risk a fixed % of account equity per trade               |
//+------------------------------------------------------------------+
#property copyright "Robert"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs (all adjustable from MT5's EA settings panel, no code editing needed)
input int    EMA_Fast_Period     = 50;      // Fast EMA period (trend)
input int    EMA_Slow_Period     = 200;     // Slow EMA period (trend)
input int    ATR_Period          = 14;      // ATR period for stop buffer
input double ATR_Buffer_Mult     = 0.5;     // Stop buffer = ATR * this
input int    Swing_Lookback_Bars = 20;      // Bars to look back for swing high/low
input double Risk_Percent        = 2.0;     // % of equity risked per trade
input double Reward_Risk_Ratio   = 4.0;     // Target = stop_distance * this
input int    Slope_Lookback_Bars = 10;      // Bars back to confirm EMA slope direction
input ulong  Magic_Number        = 20260815; // Unique ID so this EA only manages its own trades

//--- Indicator handles (set once in OnInit, reused every tick — this is the correct
//    MQL5 pattern; creating handles inside OnTick would leak resources over time)
int emaFastHandle;
int emaSlowHandle;
int atrHandle;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle     = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handle(s). EA will not run.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(Magic_Number);
   Print("EURUSD_TrendEA initialized. Risk per trade: ", Risk_Percent, "%  RR target: 1:", Reward_Risk_Ratio);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Helper: has a new bar formed since last check?                    |
//| (We only evaluate trade logic once per closed bar, not every tick,|
//|  matching how we read charts by hand — on completed candles.)     |
//+------------------------------------------------------------------+
datetime lastBarTime = 0;
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get the swing low over the lookback window, EXCLUDING the still- |
//| forming current bar (index 0)                                    |
//+------------------------------------------------------------------+
double GetSwingLow(int lookback)
{
   int idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1);
   return iLow(_Symbol, PERIOD_CURRENT, idx);
}

double GetSwingHigh(int lookback)
{
   int idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1);
   return iHigh(_Symbol, PERIOD_CURRENT, idx);
}

//+------------------------------------------------------------------+
//| Determine trend: +1 uptrend, -1 downtrend, 0 no trend             |
//+------------------------------------------------------------------+
int GetTrend()
{
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   // Copy enough bars to check current value AND slope
   if(CopyBuffer(emaFastHandle, 0, 0, Slope_Lookback_Bars + 1, emaFast) <= 0) return 0;
   if(CopyBuffer(emaSlowHandle, 0, 0, 2, emaSlow) <= 0) return 0;

   double price = iClose(_Symbol, PERIOD_CURRENT, 1); // last CLOSED bar, not the forming one
   double fastNow  = emaFast[1];                       // last closed bar's EMA value
   double fastPast = emaFast[Slope_Lookback_Bars];      // EMA value N bars back, for slope
   double slowNow  = emaSlow[1];

   bool fastAboveSlow = fastNow > slowNow;
   bool fastBelowSlow = fastNow < slowNow;
   bool slopeUp   = fastNow > fastPast;
   bool slopeDown = fastNow < fastPast;

   if(price > fastNow && fastAboveSlow && slopeUp)   return 1;   // uptrend
   if(price < fastNow && fastBelowSlow && slopeDown) return -1;  // downtrend
   return 0; // no clear trend — this is a valid, deliberate "no trade" outcome
}

//+------------------------------------------------------------------+
//| Check pullback + confirmation entry condition                     |
//| trend: 1 = uptrend (look for long entry), -1 = downtrend (short)  |
//+------------------------------------------------------------------+
bool CheckEntrySignal(int trend, double &emaFastValue)
{
   double emaFast[];
   ArraySetAsSeries(emaFast, true);
   if(CopyBuffer(emaFastHandle, 0, 0, 3, emaFast) <= 0) return false;
   emaFastValue = emaFast[1]; // EMA at last closed bar

   double closePrev  = iClose(_Symbol, PERIOD_CURRENT, 1); // last closed bar
   double openPrev   = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double lowPrev2    = iLow(_Symbol, PERIOD_CURRENT, 2);   // bar before that
   double highPrev2   = iHigh(_Symbol, PERIOD_CURRENT, 2);

   if(trend == 1)
   {
      bool touchedEma   = lowPrev2 <= emaFastValue;         // pullback touched/pierced the EMA
      bool bullishClose = closePrev > openPrev;              // confirmation candle is bullish
      bool closedAboveEma = closePrev > emaFastValue;
      return (touchedEma && bullishClose && closedAboveEma);
   }
   if(trend == -1)
   {
      bool touchedEma   = highPrev2 >= emaFastValue;
      bool bearishClose = closePrev < openPrev;
      bool closedBelowEma = closePrev < emaFastValue;
      return (touchedEma && bearishClose && closedBelowEma);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Position sizing: risk a fixed % of equity given the stop distance |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopDistancePrice)
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (Risk_Percent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return 0;

   double moneyPerLotAtStopDistance = (stopDistancePrice / tickSize) * tickValue;
   if(moneyPerLotAtStopDistance <= 0) return 0;

   double lots = riskMoney / moneyPerLotAtStopDistance;

   // Respect the broker's allowed lot step, minimum, and maximum
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < lotMin) lots = lotMin;
   if(lots > lotMax) lots = lotMax;

   return lots;
}

//+------------------------------------------------------------------+
//| Main tick handler                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return; // only act once per closed bar, not every price tick

   // Don't stack trades — one position at a time for this EA/symbol
   if(PositionSelect(_Symbol)) return;

   int trend = GetTrend();
   if(trend == 0) return; // no qualifying trend — deliberately do nothing

   double emaFastValue = 0;
   if(!CheckEntrySignal(trend, emaFastValue)) return; // no valid pullback+confirmation yet

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return;
   double atrValue = atr[0];

   double entryPrice, stopPrice, targetPrice, stopDistance;

   if(trend == 1) // long
   {
      double swingLow = GetSwingLow(Swing_Lookback_Bars);
      stopPrice   = swingLow - (atrValue * ATR_Buffer_Mult);
      entryPrice  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      stopDistance = entryPrice - stopPrice;
      if(stopDistance <= 0) return; // sanity check — invalid setup, skip
      targetPrice = entryPrice + (stopDistance * Reward_Risk_Ratio);

      double lots = CalculateLotSize(stopDistance);
      if(lots <= 0) return;

      trade.Buy(lots, _Symbol, entryPrice, stopPrice, targetPrice, "TrendEA long");
   }
   else if(trend == -1) // short
   {
      double swingHigh = GetSwingHigh(Swing_Lookback_Bars);
      stopPrice   = swingHigh + (atrValue * ATR_Buffer_Mult);
      entryPrice  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      stopDistance = stopPrice - entryPrice;
      if(stopDistance <= 0) return;
      targetPrice = entryPrice - (stopDistance * Reward_Risk_Ratio);

      double lots = CalculateLotSize(stopDistance);
      if(lots <= 0) return;

      trade.Sell(lots, _Symbol, entryPrice, stopPrice, targetPrice, "TrendEA short");
   }
}
//+------------------------------------------------------------------+