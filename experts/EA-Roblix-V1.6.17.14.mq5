//+------------------------------------------------------------------+//+------------------------------------------------------------------+
//|                                                  EA_Roblix_Safe_Fixed.mq5 |
//|    Versão com correções aplicadas: renomeação de funções, casts,
//|    ajustes de PrintFormat e #property version.                   |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
CTrade m_trade;

#property copyright "Adaptado"
#property link      ""
#property version   "1.00"
#property description "EA Roblix - Safe fixed: buffer checks, sizing por risco, retry, scaling-in seguro, kill-switch"

// ENUMs e defines
enum ENUM_ENTRY_BLOCKING_MODE { NONE, BY_PRICE_RECOVERY, BY_CANDLE_END, ONE_TRADE_PER_CANDLE, BY_RSI_CROSS_RECOVERY, BY_MOMENTUM_CROSS_RECOVERY };
enum ENUM_EA_STATE { STATE_IDLE, STATE_INITIAL_TRADE_OPEN, STATE_PROFIT_MAXIMIZATION_ACTIVE, STATE_PROFIT_MAXIMIZATION_COMPLETE };

#define ROBLIX_MOMENTUM_SHORT_BUFFER_INDEX          4
#define ROBLIX_MOMENTUM_LONG_BUFFER_INDEX           5
#define ROBLIX_RSI_CROSS_UP_BUFFER_INDEX            6
#define ROBLIX_RSI_CROSS_DOWN_BUFFER_INDEX          7
#define ROBLIX_MOMENTUM_BULLISH_CROSS_BUFFER_INDEX  8
#define ROBLIX_MOMENTUM_BEARISH_CROSS_BUFFER_INDEX  9
#define ROBLIX_ATR_BUFFER_INDEX                     10
#define ROBLIX_DEMA_FAST_BUFFER_INDEX               11
#define ROBLIX_DEMA_SHORT_BUFFER_INDEX              12
#define ROBLIX_DEMA_MEDIUM_BUFFER_INDEX             13
#define ROBLIX_DEMA_LONG_BUFFER_INDEX               14
#define ROBLIX_RSI_FAST_VALUE_BUFFER_INDEX          15
#define ROBLIX_RSI_SLOW_VALUE_BUFFER_INDEX          16
#define ROBLIX_MACD_MAIN_BUFFER_INDEX               17
#define ROBLIX_MACD_SIGNAL_BUFFER_INDEX             18
#define TRADE_RETCODE_NOT_ENOUGH_MONEY 10019


#define ENGOLFO_LOOKBACK_BARS 30
#define ATR_ADJUSTMENT_FACTOR (3.0/32.0)

// Inputs
input double InpRiskPercent = 1.0;
input double InpMinLots = 0.01;
input double InpMaxLots = 100.0;

input double InpTakeProfitPriceUnits = 4000.0;
input double InpStopLossPriceUnits   = 1500.0;

input int    InpMagicNumber  = 12345;
input int    InpSlippage     = 250;

input double InpBreakevenProfitPriceUnits = 100.0;
input double InpBreakevenOffsetPriceUnits = 1300.0;
input double InpTrailingStopPriceUnits = 4000.0;

input bool InpUseATRForRiskManagement = true;
input double InpATR_TP_Multiplier = 2.0;
input double InpATR_SL_Multiplier = 1.5;
input double InpATR_BE_Profit_Multiplier = 1.0;
input double InpATR_BE_Offset_Multiplier = 0.5;
input double InpATR_TS_Distance_Multiplier = 1.0;
input double InpATR_TS_Step_Multiplier = 0.1;

input ENUM_MA_METHOD InpFastMAType = MODE_EMA;
input ENUM_APPLIED_PRICE InpFastMAPrice = PRICE_CLOSE;
input ENUM_MA_METHOD InpSlowMAType = MODE_EMA;
input ENUM_APPLIED_PRICE InpSlowMAPrice = PRICE_CLOSE;

input uint InpFastMAPeriod = 3;
input uint InpSlowMAPeriod = 10;
input uint InpShortMAPeriod = 9;
input uint InpMediumMAPeriod = 100;
input uint InpLongMAPeriod = 200;
input int InpADX_Period = 10;
input double InpADX_Threshold = 25.0;
input int InpATR_Period = 10;
input double InpATR_Threshold = 10;
input int InpRSI_Period = 10;
input double InpRSI_Buy_Threshold = 70.0;
input double InpRSI_Sell_Threshold = 30.0;

input bool InpUseDEmaLongCross = true;
input bool InpUseDEmaCross = true;
input bool InpUseEmaCross = true;
input bool InpUseSAR = true;
input bool InpUseMacdCross = true;
input bool InpUseStocasticCross = true;
input bool InpUseAdx = false;
input bool InpUsePlusDI = true;
input bool InpUseRsi = true;
input bool InpUseATR = true;
input bool InpUseMacdSignal = true;
input bool InpUseMacdMainBelowZero = true;
input bool InpUseMacdHistogramBelowZero = true;
input bool InpUseMacdMainAboveZero = true;
input bool InpUseMacdHistogramAboveZero = true;
input bool InpUseStocastic = false;
input bool InpUseStocasticInvert = false;
input bool InpGravaLog = false;

input int MomentumPeriodShort = 3;
input int MomentumPeriodLong = 16;
input bool InpUseRSICrossFilter = true;
input uint InpRSIFastPeriod = 3;
input uint InpRSISlowPeriod = 16;
input bool InpUseMomentumCross = false;

input int InpMaxInitialBars = 10000;
input bool InpDebugMode=true;
input int InpTradeWindowSeconds = 300;
input bool InpUseTrailingStop = true;
input double InpTrailingStepPriceUnits = 1.0;
input ENUM_ENTRY_BLOCKING_MODE InpEntryBlockingMode = BY_MOMENTUM_CROSS_RECOVERY;
input bool InpUseEngulfingFilter = false;
input bool InpBlockOpenTradesWithRoblixSignal = true;
input double InpGainFullTargetPoints = 6000.0;
input bool InpUseScalingIn = false;
input double InpScalingInMinProfitPoints = 100.0;
input int InpScalingInMaxTrades = 5;
input bool InpUseMomentumExit = true;
input int InpMaxEntriesPerPMS = 3; // Número máximo de entradas adicionais permitidas no PMS
input int InpMinSecondsBetweenEntriesInPMS = 60; // Tempo mínimo em segundos entre as entradas no PMS

// --- Indicador SAR/Stochastic/Alert inputs (faltavam) ---
input bool InpDisplayAlert = false; // Mostra alertas do indicador
input double InpSARStep = 0.02;    // Parâmetro SAR step
input double InpSARMaximum = 0.2;  // Parâmetro SAR maximum
input int InpStoch_K = 5;          // Stochastic K period
input int InpStoch_D = 3;          // Stochastic D period
input int InpStoch_Slowing = 3;    // Stochastic slowing
input double InpStoch_K_Threshold = 30.0; // Stochastic K threshold
input double InpStoch_D_Threshold = 70.0; // Stochastic D threshold

// Safety inputs
input double InpMaxDailyLossPercent = 3.0;
input double InpDailyTakeProfitPercent = 3.0;
input int InpMaxConsecutiveLosses = 3;
input int MaxOrderAttempts = 3;

// Globals
int RoblixHandle = INVALID_HANDLE;

struct TradeInfo {
    ulong ticket;
    ENUM_ORDER_TYPE type;
    double entry_price;
    double volume;
    datetime entry_time;
    bool is_active;
    double exit_price;
    datetime exit_time;
    double profit;
    bool was_loss;
    bool was_gain;
    int scaling_trades_count;
};
TradeInfo g_current_trade;
TradeInfo g_last_closed_trade;
bool g_has_active_trade = false;
bool g_last_trade_was_loss = false;
double g_account_balance_before = 0;
double g_account_balance_after = 0;

bool g_block_new_entries_on_loss = false;
datetime g_loss_candle_time = 0;
double g_loss_entry_price = 0.0;
ENUM_ORDER_TYPE g_loss_trade_type = (ENUM_ORDER_TYPE)-1;
bool g_blocked_by_one_trade_per_candle = false;
datetime g_candle_time_of_last_closure = 0;

bool g_rsiCrossedUp = false;
bool g_rsiCrossedDown = false;
bool g_momentumBullishCross = false;
bool g_momentumBearishCross = false;
double g_momentumShortValue = 0.0;
double g_momentumLongValue = 0.0;

datetime g_market_closed_detected_time = 0;
ENUM_EA_STATE g_CurrentEAState = STATE_IDLE;
bool hasRoxaSignal = false;
bool hasVerdeSignal = false;
double g_current_atr_value = 0.0;
ENUM_EA_STATE g_lastPrintedEAState = STATE_IDLE;

bool g_isProfitMaximizationStageActive = false;
ENUM_ORDER_TYPE g_pms_trade_type = (ENUM_ORDER_TYPE)-1;
int g_entriesInCurrentPMS = 0;
datetime g_pms_macd_cross_time = 0;
datetime g_lastEntryTimeInPMS = 0;

// Persisted daily metrics

double g_daily_profit_money = 0.0;
int g_consecutive_losses = 0;

// Utilities
 // placeholder to avoid unused warnings

string OrderTypeToString(ENUM_ORDER_TYPE v)
{
    if(v == ORDER_TYPE_BUY)  return "BUY";
    if(v == ORDER_TYPE_SELL) return "SELL";
    return IntegerToString((int)v);
}

string EAStateToString(ENUM_EA_STATE st)
{
    switch(st)
    {
        case STATE_IDLE: return "STATE_IDLE";
        case STATE_INITIAL_TRADE_OPEN: return "STATE_INITIAL_TRADE_OPEN";
        case STATE_PROFIT_MAXIMIZATION_ACTIVE: return "STATE_PROFIT_MAXIMIZATION_ACTIVE";
        case STATE_PROFIT_MAXIMIZATION_COMPLETE: return "STATE_PROFIT_MAXIMIZATION_COMPLETE";
        default: return IntegerToString((int)st);
    }
}

string BoolToString(bool b) { return b ? "TRUE" : "FALSE"; }

void InitTradeInfo(TradeInfo &t) {
    t.ticket = 0; t.type = (ENUM_ORDER_TYPE)-1; t.entry_price = 0.0; t.volume = 0.0; t.entry_time = 0;
    t.is_active = false; t.exit_price = 0.0; t.exit_time = 0; t.profit = 0.0; t.was_loss = false; t.was_gain = false; t.scaling_trades_count = 0;
}

// GlobalVariable helpers
void GV_SetDouble(string name, double value) { GlobalVariableSet(name, value); }
double GV_GetDouble(string name, double def) { if(GlobalVariableCheck(name)) return GlobalVariableGet(name); GlobalVariableSet(name, def); return def; }
void GV_SetInt(string name, int value) { GlobalVariableSet(name, (double)value); }
int GV_GetInt(string name, int def) { if(GlobalVariableCheck(name)) return (int)GlobalVariableGet(name); GlobalVariableSet(name, def); return def; }

// Lot calculation

double CalculateLotFromRisk(double stop_loss_price_units) {
    if(stop_loss_price_units <= 0) stop_loss_price_units = InpStopLossPriceUnits;
    double risk_percent = InpRiskPercent;
    if(risk_percent <= 0) risk_percent = 1.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_money = balance * (risk_percent / 100.0);
    double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double dollar_per_point = point_value;
    double lots = 0.0;
    if(stop_loss_price_units * dollar_per_point > 0.0) lots = risk_money / (stop_loss_price_units * dollar_per_point);
    if(lots < InpMinLots) lots = InpMinLots;
    if(lots > InpMaxLots) lots = InpMaxLots;
    double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    if(step > 0) lots = MathFloor(lots / step) * step;
    if(lots < InpMinLots) lots = InpMinLots;
    return lots;
}

// TryPlaceOrder with retries
bool TryPlaceOrder(ENUM_ORDER_TYPE order_type, double lots, double price, double sl_price, double tp_price, string comment) {
    int attempts = 0;
    while(attempts < MaxOrderAttempts) {
        attempts++;
        bool ok = m_trade.PositionOpen(Symbol(), order_type, lots, price, sl_price, tp_price, comment);
        if(ok) return true;
        int rc = m_trade.ResultRetcode();
        string rcm = m_trade.ResultComment();
        if(InpDebugMode) PrintFormat("Order attempt %d failed. RetCode=%d, Comment=%s", attempts, rc, rcm);
        if(rc == TRADE_RETCODE_MARKET_CLOSED) {
            g_market_closed_detected_time = TimeCurrent();
            if(InpDebugMode) Print("Market closed detected - pausing new attempts.");
            return false;
        }
        if(rc == TRADE_RETCODE_INVALID_STOPS) {
            double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            int level = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
            if(level < 1) level = 1;
            if(sl_price != 0) {
                sl_price = (order_type==ORDER_TYPE_BUY) ? (price - point*level) : (price + point*level);
            } else sl_price = 0;
            Sleep(100);
            continue;
        }
        if(rc == TRADE_RETCODE_NOT_ENOUGH_MONEY || rc == TRADE_RETCODE_INVALID_VOLUME) {
            double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
            lots = MathMax(InpMinLots, lots - step);
            if(InpDebugMode) PrintFormat("Adjusting lots down to %.2f and retrying", lots);
            Sleep(100); continue;
        }
        Sleep(100);
    }
    return false;
}

// ExecuteOrder updated
void ExecuteOrder(ENUM_ORDER_TYPE order_type) {
    if(InpDebugMode) PrintFormat("ExecuteOrder() called. State: %s", EAStateToString(g_CurrentEAState));
    double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double entry_price = (order_type==ORDER_TYPE_BUY)? current_ask : current_bid;

    double sl_distance_boleta = InpStopLossPriceUnits;
    double tp_distance_boleta = InpTakeProfitPriceUnits;

    if(InpUseATRForRiskManagement && g_current_atr_value > 0) {
        double atr_val = g_current_atr_value;
        double sl_from_atr = atr_val * InpATR_SL_Multiplier;
        double tp_from_atr = atr_val * InpATR_TP_Multiplier;
        if(sl_from_atr > sl_distance_boleta) sl_distance_boleta = sl_from_atr;
        if(tp_from_atr > tp_distance_boleta) tp_distance_boleta = tp_from_atr;
    }

    double sl_distance_price = sl_distance_boleta * point_value;
    double tp_distance_price = tp_distance_boleta * point_value;

    double sl_price = 0.0, tp_price = 0.0;
    if(order_type==ORDER_TYPE_BUY) {
        sl_price = entry_price - sl_distance_price;
        tp_price = entry_price + tp_distance_price;
    } else {
        sl_price = entry_price + sl_distance_price;
        tp_price = entry_price - tp_distance_price;
    }
    sl_price = NormalizeDouble(sl_price, digits);
    tp_price = NormalizeDouble(tp_price, digits);

    double lots = CalculateLotFromRisk(sl_distance_boleta);
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    if(min_lot>0 && lots<min_lot) lots = min_lot;
    if(step>0) lots = MathMax(step, MathFloor(lots/step)*step);

    string comment = (order_type==ORDER_TYPE_BUY) ? "Roblix Buy (safe)" : "Roblix Sell (safe)";

    if(InpDebugMode) PrintFormat("Attempting order: Type=%s, Lots=%.2f, Entry=%.5f, SL=%.5f, TP=%.5f", OrderTypeToString(order_type), lots, entry_price, sl_price, tp_price);

    if(TryPlaceOrder(order_type, lots, entry_price, sl_price, tp_price, comment)) {
        ulong ticket = m_trade.ResultOrder();
        RegisterTradeEntry(ticket, order_type, entry_price, lots);
        if(InpDebugMode) PrintFormat("Order opened ticket=%d", ticket);
    } else {
        if(InpDebugMode) Print("Failed to open order after retries.");
    }
}

// RegisterTradeEntry and ProcessTradeClosure
void RegisterTradeEntry(ulong ticket, ENUM_ORDER_TYPE type, double price, double volume) {
    InitTradeInfo(g_current_trade);
    g_current_trade.ticket = ticket;
    g_current_trade.type = type;
    g_current_trade.entry_price = price;
    g_current_trade.volume = volume;
    g_current_trade.entry_time = TimeCurrent();
    g_current_trade.is_active = true;
    g_current_trade.scaling_trades_count = 0;
    g_has_active_trade = true;
    g_account_balance_before = AccountInfoDouble(ACCOUNT_BALANCE);
    if(InpDebugMode) PrintFormat("TRADE REGISTER: ticket=%d type=%s price=%.5f vol=%.2f", ticket, OrderTypeToString(type), price, volume);
}

void ProcessTradeClosure() {
    g_account_balance_after = AccountInfoDouble(ACCOUNT_BALANCE);
    double real_profit_money = g_account_balance_after - g_account_balance_before;
    g_current_trade.exit_time = TimeCurrent();
    g_current_trade.profit = real_profit_money;
    g_current_trade.is_active = false;

    g_daily_profit_money += real_profit_money;
    GV_SetDouble("EA_Roblix_DailyProfit", g_daily_profit_money);

    if(real_profit_money > 0) {
        g_current_trade.was_gain = true; g_current_trade.was_loss = false; g_last_trade_was_loss = false;
        g_consecutive_losses = 0;
        GV_SetInt("EA_Roblix_ConsecLosses", g_consecutive_losses);
        g_CurrentEAState = STATE_PROFIT_MAXIMIZATION_ACTIVE;
    } else if(real_profit_money < 0) {
        g_current_trade.was_loss = true; g_current_trade.was_gain = false; g_last_trade_was_loss = true;
        g_consecutive_losses++;
        GV_SetInt("EA_Roblix_ConsecLosses", g_consecutive_losses);
        if(InpEntryBlockingMode == BY_PRICE_RECOVERY || InpEntryBlockingMode == BY_CANDLE_END || InpEntryBlockingMode == BY_RSI_CROSS_RECOVERY || InpEntryBlockingMode == BY_MOMENTUM_CROSS_RECOVERY) {
            g_block_new_entries_on_loss = true;
            g_loss_candle_time = iTime(Symbol(), Period(), 0);
            g_loss_entry_price = g_current_trade.entry_price;
            g_loss_trade_type = g_current_trade.type;
        }
        g_CurrentEAState = STATE_IDLE;
    } else {
        g_current_trade.was_gain = false; g_current_trade.was_loss = false; g_last_trade_was_loss = false;
        g_consecutive_losses = 0;
        GV_SetInt("EA_Roblix_ConsecLosses", g_consecutive_losses);
        g_CurrentEAState = STATE_IDLE;
    }

    g_last_closed_trade = g_current_trade;
    InitTradeInfo(g_current_trade);
    g_has_active_trade = false;

    if(InpEntryBlockingMode == ONE_TRADE_PER_CANDLE) {
        g_blocked_by_one_trade_per_candle = true;
        g_candle_time_of_last_closure = iTime(Symbol(), Period(), 0);
    }
    if(InpDebugMode) PrintFormat("Trade closed. Profit money: %.2f. DailyProfitMoney: %.2f, ConsecutiveLosses: %d", real_profit_money, g_daily_profit_money, g_consecutive_losses);
}

// MonitorActiveTrades
void MonitorActiveTrades() {
    if(!g_has_active_trade) return;
    if(!PositionSelectByTicket(g_current_trade.ticket)) {
        if(InpDebugMode) Print("Position not found - assuming closed externally.");
        ProcessTradeClosure();
        return;
    }
    g_current_trade.volume = PositionGetDouble(POSITION_VOLUME);
}

// ScaleInTrade
void ScaleInTrade(ENUM_ORDER_TYPE order_type, double base_lots) {
    if(!g_has_active_trade || g_current_trade.type != order_type) { if(InpDebugMode) Print("Scaling-in: no active trade or mismatch type."); return; }
    if(g_current_trade.scaling_trades_count >= InpScalingInMaxTrades) { if(InpDebugMode) Print("Scaling-in: reached max scaling trades."); return; }

    double factor = MathPow(0.5, g_current_trade.scaling_trades_count + 1);
    double lots = MathMax(InpMinLots, base_lots * factor);
    CPositionInfo pos;
    if(!pos.Select(g_current_trade.ticket)) { if(InpDebugMode) Print("Scaling-in: failed select position."); return; }
    double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double profit_in_price_units = 0.0;
    if(pos.PositionType() == POSITION_TYPE_BUY) profit_in_price_units = SymbolInfoDouble(Symbol(), SYMBOL_BID) - pos.PriceOpen();
    else profit_in_price_units = pos.PriceOpen() - SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double profit_points = profit_in_price_units / point_value;
    if(profit_points < InpScalingInMinProfitPoints) { if(InpDebugMode) PrintFormat("SCALING-IN: profit %.2f < min %.2f", profit_points, InpScalingInMinProfitPoints); return; }

    double price = (order_type==ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    string comment = "Roblix Scaling-in";
    if(TryPlaceOrder(order_type, lots, price, 0.0, 0.0, comment)) {
        g_current_trade.scaling_trades_count++;
        if(InpDebugMode) PrintFormat("Scaling-in executed. Added lots=%.2f. Total scaling trades=%d", lots, g_current_trade.scaling_trades_count);
    } else {
        if(InpDebugMode) Print("Scaling-in failed after retries.");
    }
}

// ShouldBlockNewEntries
bool ShouldBlockNewEntries() {
    int consec = GV_GetInt("EA_Roblix_ConsecLosses", 0);
    if(consec >= InpMaxConsecutiveLosses) {
        if(InpDebugMode) PrintFormat("BLOCK: Consecutive losses (%d) >= Max (%d).", consec, InpMaxConsecutiveLosses);
        return true;
    }
    double dailyProfit = GV_GetDouble("EA_Roblix_DailyProfit", 0.0);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance > 0) {
        if(dailyProfit <= 0 && MathAbs(dailyProfit) >= (balance * (InpMaxDailyLossPercent/100.0))) {
            if(InpDebugMode) PrintFormat("BLOCK: Daily loss reached (%.2f money / %.2f%%) - stopping entries.", dailyProfit, (MathAbs(dailyProfit)/balance)*100.0);
            return true;
        }
        if(dailyProfit > 0 && (dailyProfit >= (balance * (InpDailyTakeProfitPercent/100.0)))) {
            if(InpDebugMode) PrintFormat("BLOCK: Daily take profit target reached (%.2f money).", dailyProfit);
            return true;
        }
    }

    datetime current_candle_open_time = iTime(Symbol(), Period(), 0);
    switch(InpEntryBlockingMode) {
        case NONE: return false;
        case BY_PRICE_RECOVERY: {
            if(!g_block_new_entries_on_loss) return false;
            double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            bool recovered=false;
            if(g_loss_trade_type == ORDER_TYPE_BUY) { if(current_ask > g_loss_entry_price) recovered=true; }
            else if(g_loss_trade_type == ORDER_TYPE_SELL) { if(current_bid < g_loss_entry_price) recovered=true; }
            if(recovered) { g_block_new_entries_on_loss = false; return false; }
            return true;
        }
        case BY_CANDLE_END: {
            if(!g_block_new_entries_on_loss) return false;
            if(current_candle_open_time > g_loss_candle_time) { g_block_new_entries_on_loss = false; return false; }
            return true;
        }
        case ONE_TRADE_PER_CANDLE: {
            if(!g_blocked_by_one_trade_per_candle) return false;
            if(current_candle_open_time != g_candle_time_of_last_closure) { g_blocked_by_one_trade_per_candle = false; g_candle_time_of_last_closure=0; return false; }
            return true;
        }
        case BY_RSI_CROSS_RECOVERY: {
            if(!g_block_new_entries_on_loss) return false;
            bool ok=false;
            if(g_loss_trade_type==ORDER_TYPE_BUY && g_rsiCrossedUp) ok=true;
            if(g_loss_trade_type==ORDER_TYPE_SELL && g_rsiCrossedDown) ok=true;
            if(ok) { g_block_new_entries_on_loss=false; return false; }
            return true;
        }
        case BY_MOMENTUM_CROSS_RECOVERY: {
            if(!g_block_new_entries_on_loss) return false;
            bool ok=false;
            if(g_loss_trade_type==ORDER_TYPE_BUY && g_momentumBullishCross) ok=true;
            if(g_loss_trade_type==ORDER_TYPE_SELL && g_momentumBearishCross) ok=true;
            if(ok) { g_block_new_entries_on_loss=false; return false; }
            return true;
        }
    }
    return false;
}

// CheckQualificationSignal (defensivo)
bool CheckQualificationSignal(ENUM_ORDER_TYPE type) {
    double buffer_values[1];
    if(CopyBuffer(RoblixHandle, ROBLIX_DEMA_SHORT_BUFFER_INDEX, 0, 1, buffer_values) <= 0) { if(InpDebugMode) Print("QUALIFICATION: Falha DEMA Short"); return false; }
    double demaShort = buffer_values[0]; if(demaShort==EMPTY_VALUE) return false;
    if(CopyBuffer(RoblixHandle, ROBLIX_DEMA_MEDIUM_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("QUALIFICATION: Falha DEMA Medium"); return false; }
    double demaMedium = buffer_values[0]; if(demaMedium==EMPTY_VALUE) return false;
    if(CopyBuffer(RoblixHandle, ROBLIX_DEMA_LONG_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("QUALIFICATION: Falha DEMA Long"); return false; }
    double demaLong = buffer_values[0]; if(demaLong==EMPTY_VALUE) return false;
    if(CopyBuffer(RoblixHandle, ROBLIX_ATR_BUFFER_INDEX, 0, 1, buffer_values) <= 0) { g_current_atr_value = 0.0; } else g_current_atr_value = buffer_values[0];
    if(CopyBuffer(RoblixHandle, ROBLIX_RSI_FAST_VALUE_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("QUALIFICATION: Falha RSI Fast"); return false; }
    double rsiFast = buffer_values[0];
    if(CopyBuffer(RoblixHandle, ROBLIX_RSI_SLOW_VALUE_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("QUALIFICATION: Falha RSI Slow"); return false; }
    double rsiSlow = buffer_values[0];

    double SellBuffer_0[8]; ArrayInitialize(SellBuffer_0, EMPTY_VALUE);
    double BuyBuffer_1[8]; ArrayInitialize(BuyBuffer_1, EMPTY_VALUE);
    int copiedSell = CopyBuffer(RoblixHandle, 0, 0, 8, SellBuffer_0);
    int copiedBuy  = CopyBuffer(RoblixHandle, 1, 0, 8, BuyBuffer_1);
    if(copiedSell <= 0 || copiedBuy <= 0) { if(InpDebugMode) Print("QUALIFICATION: erro copy arrow buffers"); return false; }
    bool hasSellSignal=false, hasBuySignal=false;
    for(int i=0;i<copiedSell;i++) if(SellBuffer_0[i] != EMPTY_VALUE) { hasSellSignal=true; break; }
    for(int i=0;i<copiedBuy;i++)  if(BuyBuffer_1[i]  != EMPTY_VALUE) { hasBuySignal=true; break; }

    double SellBufferEngolfo_2_History[ENGOLFO_LOOKBACK_BARS]; ArrayInitialize(SellBufferEngolfo_2_History, EMPTY_VALUE);
    double BuyBufferEngolfo_3_History[ENGOLFO_LOOKBACK_BARS]; ArrayInitialize(BuyBufferEngolfo_3_History, EMPTY_VALUE);
    if(InpUseEngulfingFilter) {
        int cs = CopyBuffer(RoblixHandle, 2, 0, ENGOLFO_LOOKBACK_BARS, SellBufferEngolfo_2_History);
        int cb = CopyBuffer(RoblixHandle, 3, 0, ENGOLFO_LOOKBACK_BARS, BuyBufferEngolfo_3_History);
        if(cs <=0 || cb <=0) { if(InpDebugMode) Print("QUALIFICATION: erro copy engulf"); return false; }
    }
    bool hasRoxa=false, hasVerde=false;
    for(int i=0;i<ENGOLFO_LOOKBACK_BARS;i++) { if(SellBufferEngolfo_2_History[i]!=EMPTY_VALUE) { hasRoxa=true; break; } }
    for(int i=0;i<ENGOLFO_LOOKBACK_BARS;i++) { if(BuyBufferEngolfo_3_History[i]!=EMPTY_VALUE) { hasVerde=true; break; } }

    double current_close = iClose(Symbol(), Period(), 0);
    if(type==ORDER_TYPE_BUY) {
        current_close = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        if(!(current_close > demaShort && current_close > demaMedium && current_close > demaLong)) { if(InpDebugMode) Print("QUALIFICATION BUY: price not above DEMAs"); return false; }
        if(!(demaShort > demaMedium && demaMedium > demaLong)) { if(InpDebugMode) Print("QUALIFICATION BUY: DEMAs not aligned"); return false; }
        if(!(rsiFast > rsiSlow)) { if(InpDebugMode) Print("QUALIFICATION BUY: RSI not ok"); return false; }
        if(!hasBuySignal) { if(InpDebugMode) Print("QUALIFICATION BUY: Roblix buy absent"); return false; }
        if(InpUseEngulfingFilter && !hasVerde) { if(InpDebugMode) Print("QUALIFICATION BUY: engulf filter blocked"); return false; }
        return true;
    } else {
        if(!(current_close < demaShort && current_close < demaMedium && current_close < demaLong)) { if(InpDebugMode) Print("QUALIFICATION SELL: price not below DEMAs"); return false; }
        if(!(demaShort < demaMedium && demaMedium < demaLong)) { if(InpDebugMode) Print("QUALIFICATION SELL: DEMAs not aligned"); return false; }
        if(!(rsiFast < rsiSlow)) { if(InpDebugMode) Print("QUALIFICATION SELL: RSI not ok"); return false; }
        if(!hasSellSignal) { if(InpDebugMode) Print("QUALIFICATION SELL: Roblix sell absent"); return false; }
        if(InpUseEngulfingFilter && !hasRoxa) { if(InpDebugMode) Print("QUALIFICATION SELL: engulf filter blocked"); return false; }
        return true;
    }
}

// CheckReEntryCondition
bool CheckReEntryCondition(ENUM_ORDER_TYPE type) {
    double buffer_values[1];
    if(CopyBuffer(RoblixHandle, ROBLIX_RSI_FAST_VALUE_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("REENTRY: failed RSI Fast"); return false; }
    double rsiFast = buffer_values[0];
    if(CopyBuffer(RoblixHandle, ROBLIX_RSI_SLOW_VALUE_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("REENTRY: failed RSI Slow"); return false; }
    double rsiSlow = buffer_values[0];
    if(CopyBuffer(RoblixHandle, ROBLIX_MOMENTUM_SHORT_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("REENTRY: failed MomShort"); return false; }
    double momentumShort = buffer_values[0];
    if(CopyBuffer(RoblixHandle, ROBLIX_MOMENTUM_LONG_BUFFER_INDEX, 0, 1, buffer_values) <=0) { if(InpDebugMode) Print("REENTRY: failed MomLong"); return false; }
    double momentumLong = buffer_values[0];

    if(type==ORDER_TYPE_BUY) {
        if(!(rsiFast > rsiSlow)) { if(InpDebugMode) Print("REENTRY BUY: RSI not ok"); return false; }
        return true;
    } else {
        if(!(rsiFast < rsiSlow)) { if(InpDebugMode) Print("REENTRY SELL: RSI not ok"); return false; }
        return true;
    }
}

// OnInit / OnDeinit
int OnInit() {
    RoblixHandle = iCustom(Symbol(), Period(), "EMA_SAR_MACD_RSI_V2.7.7.11",
                           InpFastMAType, InpFastMAPrice,InpFastMAPeriod,
                           InpSlowMAPeriod,InpSlowMAType, InpSlowMAPrice,
                           InpShortMAPeriod, InpMediumMAPeriod,InpLongMAPeriod,
                           InpADX_Period, InpADX_Threshold, InpATR_Period, InpATR_Threshold,
                           InpRSI_Period, InpRSI_Buy_Threshold, InpRSI_Sell_Threshold,
                           InpDisplayAlert,
                           InpSARStep, InpSARMaximum,
                           InpStoch_K, InpStoch_D, InpStoch_Slowing, InpStoch_K_Threshold, InpStoch_D_Threshold,
                           InpUseDEmaLongCross,InpUseDEmaCross, InpUseEmaCross, InpUseSAR, InpUseMacdCross, InpUseStocasticCross,
                           InpUseAdx, InpUsePlusDI, InpUseRsi, InpUseATR, InpUseMacdSignal,
                           InpUseMacdMainBelowZero, InpUseMacdHistogramBelowZero, InpUseMacdMainAboveZero,
                           InpUseMacdHistogramAboveZero, InpUseStocastic,InpUseStocasticInvert,
                           InpGravaLog,
                           MomentumPeriodShort, MomentumPeriodLong,
                           InpUseRSICrossFilter, InpRSIFastPeriod, InpRSISlowPeriod, InpUseMomentumCross, InpMaxInitialBars);
    if(RoblixHandle==INVALID_HANDLE) { Print("Erro ao criar handle Roblix."); return INIT_FAILED; }

    m_trade.SetExpertMagicNumber(InpMagicNumber);
    m_trade.SetTypeFilling(ORDER_FILLING_FOK);
    m_trade.SetDeviationInPoints(InpSlippage);

    InitTradeInfo(g_current_trade); InitTradeInfo(g_last_closed_trade);

    g_daily_profit_money = GV_GetDouble("EA_Roblix_DailyProfit", 0.0);
    g_consecutive_losses = GV_GetInt("EA_Roblix_ConsecLosses", 0);

    for(int i=PositionsTotal()-1;i>=0;i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            string sym = PositionGetString(POSITION_SYMBOL);
            if(sym==Symbol()) {
                long magic = PositionGetInteger(POSITION_MAGIC);
                if((int)magic == InpMagicNumber) {
                    g_current_trade.ticket = ticket;
                    g_current_trade.type = (ENUM_ORDER_TYPE)(int)PositionGetInteger(POSITION_TYPE);
                    g_current_trade.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
                    g_current_trade.volume = PositionGetDouble(POSITION_VOLUME);
                    g_current_trade.entry_time = (datetime)PositionGetInteger(POSITION_TIME);
                    g_current_trade.is_active = true;
                    g_has_active_trade = true;
                    g_CurrentEAState = STATE_INITIAL_TRADE_OPEN;
                    if(InpDebugMode) PrintFormat("Recovered open position ticket=%d", ticket);
                    break;
                }
            }
        }
    }

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    if(RoblixHandle!=INVALID_HANDLE) IndicatorRelease(RoblixHandle);
}

// ManageTrailingStop (simplificado)
void ManageTrailingStop(bool hasBuySignalFromRoblix, bool hasSellSignalFromRoblix) {
    if(!g_has_active_trade) return;
    if(!PositionSelectByTicket(g_current_trade.ticket)) { if(InpDebugMode) Print("ManageTS: position not found"); ProcessTradeClosure(); return; }
    ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_price_for_profit_calc = (pos_type==POSITION_TYPE_BUY)? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double profit_in_points = (pos_type==POSITION_TYPE_BUY) ? (current_price_for_profit_calc - entry_price)/point_value : (entry_price - current_price_for_profit_calc)/point_value;

    double effective_be_points = InpBreakevenProfitPriceUnits;
    double effective_be_offset_points = InpBreakevenOffsetPriceUnits;
    double effective_trailing_stop_points = InpTrailingStopPriceUnits;
    double effective_trailing_step_points = InpTrailingStepPriceUnits;
    if(InpUseATRForRiskManagement && g_current_atr_value>0) {
        double atr = g_current_atr_value;
        effective_be_points = MathMax(effective_be_points, atr * InpATR_BE_Profit_Multiplier);
        effective_be_offset_points = MathMax(effective_be_offset_points, atr * InpATR_BE_Offset_Multiplier);
        effective_trailing_stop_points = MathMax(effective_trailing_stop_points, atr * InpATR_TS_Distance_Multiplier);
        effective_trailing_step_points = MathMax(effective_trailing_step_points, atr * InpATR_TS_Step_Multiplier);
    }

    bool skip_be_logic = false;
    if(InpBlockOpenTradesWithRoblixSignal) {
        bool roblixActive=false;
        if(pos_type==POSITION_TYPE_BUY && hasBuySignalFromRoblix) roblixActive=true;
        if(pos_type==POSITION_TYPE_SELL && hasSellSignalFromRoblix) roblixActive=true;
        if(InpUseRSICrossFilter) {
            if(pos_type==POSITION_TYPE_BUY && g_rsiCrossedDown) roblixActive=false;
            if(pos_type==POSITION_TYPE_SELL && g_rsiCrossedUp) roblixActive=false;
        }
        if(roblixActive) skip_be_logic = true;
    }

    if(!skip_be_logic && effective_be_points>0 && profit_in_points>=effective_be_points) {
        double breakeven_price = 0.0;
        if(pos_type==POSITION_TYPE_BUY) breakeven_price = entry_price + effective_be_offset_points*point_value;
        else breakeven_price = entry_price - effective_be_offset_points*point_value;
        int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
        breakeven_price = NormalizeDouble(breakeven_price, digits);
        double cur_sl = PositionGetDouble(POSITION_SL);
        bool should_move = false;
        if(cur_sl==0.0) should_move = true;
        else {
            if(pos_type==POSITION_TYPE_BUY && breakeven_price > cur_sl && (breakeven_price - cur_sl) >= effective_trailing_step_points*point_value) should_move = true;
            if(pos_type==POSITION_TYPE_SELL && breakeven_price < cur_sl && (cur_sl - breakeven_price) >= effective_trailing_step_points*point_value) should_move = true;
        }
        if(should_move) {
            if(m_trade.PositionModify((ulong)PositionGetInteger(POSITION_TICKET), breakeven_price, PositionGetDouble(POSITION_TP))) {
                if(InpDebugMode) PrintFormat("Moved SL to breakeven: %.5f", breakeven_price);
            }
        }
    }

    if(InpUseTrailingStop && effective_trailing_stop_points>0 && profit_in_points>=effective_trailing_stop_points) {
        double new_sl = 0.0;
        if(pos_type==POSITION_TYPE_BUY) new_sl = SymbolInfoDouble(Symbol(), SYMBOL_BID) - effective_trailing_stop_points*point_value;
        else new_sl = SymbolInfoDouble(Symbol(), SYMBOL_ASK) + effective_trailing_stop_points*point_value;
        int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
        new_sl = NormalizeDouble(new_sl, digits);
        double cur_sl = PositionGetDouble(POSITION_SL);
        bool modify=false;
        if(cur_sl==0.0) modify=true;
        else {
            if(pos_type==POSITION_TYPE_BUY && new_sl > cur_sl && (new_sl - cur_sl) >= effective_trailing_step_points*point_value) modify=true;
            if(pos_type==POSITION_TYPE_SELL && new_sl < cur_sl && (cur_sl - new_sl) >= effective_trailing_step_points*point_value) modify=true;
        }
        if(modify) {
            if(m_trade.PositionModify((ulong)PositionGetInteger(POSITION_TICKET), new_sl, PositionGetDouble(POSITION_TP))) {
                if(InpDebugMode) PrintFormat("Trailing moved SL to %.5f", new_sl);
            }
        }
    }

    if(InpUseMomentumExit) {
        if(pos_type==POSITION_TYPE_BUY && g_momentumBearishCross) {
            if(m_trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET))) {
                if(InpDebugMode) Print("Momentum exit closed buy position.");
            }
            return;
        } else if(pos_type==POSITION_TYPE_SELL && g_momentumBullishCross) {
            if(m_trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET))) {
                if(InpDebugMode) Print("Momentum exit closed sell position.");
            }
            return;
        }
    }
}

// OnTick
void OnTick() {
    MonitorActiveTrades();

    double SellBuffer_0[5]; ArrayInitialize(SellBuffer_0, EMPTY_VALUE);
    double BuyBuffer_1[5]; ArrayInitialize(BuyBuffer_1, EMPTY_VALUE);
    if(CopyBuffer(RoblixHandle, 0, 0, 5, SellBuffer_0) <= 0) { if(InpDebugMode) Print("OnTick: failed copy SellBuffer_0"); return; }
    if(CopyBuffer(RoblixHandle, 1, 0, 5, BuyBuffer_1) <= 0) { if(InpDebugMode) Print("OnTick: failed copy BuyBuffer_1"); return; }

    double SellBufferEngolfo_2_History[ENGOLFO_LOOKBACK_BARS]; ArrayInitialize(SellBufferEngolfo_2_History, EMPTY_VALUE);
    double BuyBufferEngolfo_3_History[ENGOLFO_LOOKBACK_BARS]; ArrayInitialize(BuyBufferEngolfo_3_History, EMPTY_VALUE);
    if(CopyBuffer(RoblixHandle, 2, 0, ENGOLFO_LOOKBACK_BARS, SellBufferEngolfo_2_History) <= 0) { }
    if(CopyBuffer(RoblixHandle, 3, 0, ENGOLFO_LOOKBACK_BARS, BuyBufferEngolfo_3_History) <= 0) { }

    double RSICrossUpBuffer_EA[1]; ArrayInitialize(RSICrossUpBuffer_EA, EMPTY_VALUE);
    double RSICrossDownBuffer_EA[1]; ArrayInitialize(RSICrossDownBuffer_EA, EMPTY_VALUE);
    if(CopyBuffer(RoblixHandle, ROBLIX_RSI_CROSS_UP_BUFFER_INDEX, 0, 1, RSICrossUpBuffer_EA) <= 0) RSICrossUpBuffer_EA[0]=EMPTY_VALUE;
    if(CopyBuffer(RoblixHandle, ROBLIX_RSI_CROSS_DOWN_BUFFER_INDEX, 0, 1, RSICrossDownBuffer_EA) <= 0) RSICrossDownBuffer_EA[0]=EMPTY_VALUE;

    double MomentumShortBuffer_EA[1]; ArrayInitialize(MomentumShortBuffer_EA, EMPTY_VALUE);
    double MomentumLongBuffer_EA[1]; ArrayInitialize(MomentumLongBuffer_EA, EMPTY_VALUE);
    double MomentumBullishCrossBuffer_EA[1]; ArrayInitialize(MomentumBullishCrossBuffer_EA, EMPTY_VALUE);
    double MomentumBearishCrossBuffer_EA[1]; ArrayInitialize(MomentumBearishCrossBuffer_EA, EMPTY_VALUE);
    if(CopyBuffer(RoblixHandle, ROBLIX_MOMENTUM_SHORT_BUFFER_INDEX, 0, 1, MomentumShortBuffer_EA) <= 0) MomentumShortBuffer_EA[0]=EMPTY_VALUE;
    if(CopyBuffer(RoblixHandle, ROBLIX_MOMENTUM_LONG_BUFFER_INDEX, 0, 1, MomentumLongBuffer_EA) <= 0) MomentumLongBuffer_EA[0]=EMPTY_VALUE;
    if(CopyBuffer(RoblixHandle, ROBLIX_MOMENTUM_BULLISH_CROSS_BUFFER_INDEX, 0, 1, MomentumBullishCrossBuffer_EA) <=0) MomentumBullishCrossBuffer_EA[0]=EMPTY_VALUE;
    if(CopyBuffer(RoblixHandle, ROBLIX_MOMENTUM_BEARISH_CROSS_BUFFER_INDEX, 0, 1, MomentumBearishCrossBuffer_EA) <=0) MomentumBearishCrossBuffer_EA[0]=EMPTY_VALUE;

    double ATRBuffer_EA[1]; ArrayInitialize(ATRBuffer_EA, EMPTY_VALUE);
    if(CopyBuffer(RoblixHandle, ROBLIX_ATR_BUFFER_INDEX, 0, 1, ATRBuffer_EA) <= 0) { g_current_atr_value = 0.0; }
    else { g_current_atr_value = ATRBuffer_EA[0]; if(g_current_atr_value == EMPTY_VALUE) g_current_atr_value = 0.0; }

    double MacdMainBuffer_EA[1]; ArrayInitialize(MacdMainBuffer_EA, EMPTY_VALUE);
    double MacdSignalBuffer_EA[1]; ArrayInitialize(MacdSignalBuffer_EA, EMPTY_VALUE);
    if(CopyBuffer(RoblixHandle, ROBLIX_MACD_MAIN_BUFFER_INDEX, 0, 1, MacdMainBuffer_EA) <= 0) MacdMainBuffer_EA[0]=EMPTY_VALUE;
    if(CopyBuffer(RoblixHandle, ROBLIX_MACD_SIGNAL_BUFFER_INDEX, 0, 1, MacdSignalBuffer_EA) <= 0) MacdSignalBuffer_EA[0]=EMPTY_VALUE;
    double currentMacdMain = MacdMainBuffer_EA[0], currentMacdSignal = MacdSignalBuffer_EA[0];

    bool hasSellSignal = false, hasBuySignal = false;
    for(int i=0;i<5;i++){ if(SellBuffer_0[i] != EMPTY_VALUE) { hasSellSignal=true; break; } }
    for(int i=0;i<5;i++){ if(BuyBuffer_1[i] != EMPTY_VALUE) { hasBuySignal=true; break; } }

    double roxaSignalValue = EMPTY_VALUE, verdeSignalValue = EMPTY_VALUE;
    for(int i=0;i<ENGOLFO_LOOKBACK_BARS;i++){ if(SellBufferEngolfo_2_History[i]!=EMPTY_VALUE) { roxaSignalValue = SellBufferEngolfo_2_History[i]; break; } }
    for(int i=0;i<ENGOLFO_LOOKBACK_BARS;i++){ if(BuyBufferEngolfo_3_History[i]!=EMPTY_VALUE) { verdeSignalValue = BuyBufferEngolfo_3_History[i]; break; } }
    hasRoxaSignal = (roxaSignalValue != EMPTY_VALUE);
    hasVerdeSignal = (verdeSignalValue != EMPTY_VALUE);

    g_rsiCrossedUp = (RSICrossUpBuffer_EA[0] != EMPTY_VALUE);
    g_rsiCrossedDown = (RSICrossDownBuffer_EA[0] != EMPTY_VALUE);
    g_momentumShortValue = MomentumShortBuffer_EA[0];
    g_momentumLongValue  = MomentumLongBuffer_EA[0];
    g_momentumBullishCross = (MomentumBullishCrossBuffer_EA[0] != EMPTY_VALUE);
    g_momentumBearishCross = (MomentumBearishCrossBuffer_EA[0] != EMPTY_VALUE);

    ManageTrailingStop(hasBuySignal, hasSellSignal);

    if(g_market_closed_detected_time != 0) {
        datetime current_time = TimeCurrent();
        if((current_time - g_market_closed_detected_time) < 3600*6) {
            if(InpDebugMode) Print("Market closed recently - skipping OnTick.");
            return;
        } else {
            g_market_closed_detected_time = 0;
        }
    }

    datetime now = TimeCurrent();
    datetime bar_open = iTime(Symbol(), Period(), 0);
    long timeframe_seconds = PeriodSeconds(Period());
    datetime bar_close = bar_open + timeframe_seconds;
    long seconds_remaining = (long)(bar_close - now);

    if(seconds_remaining <= InpTradeWindowSeconds && seconds_remaining >= 0) {
        if(InpDebugMode) PrintFormat("Within trade window. seconds_remaining=%d", seconds_remaining);
        if(InpDebugMode && g_CurrentEAState != g_lastPrintedEAState) { PrintFormat("EA State changed: %s", EAStateToString(g_CurrentEAState)); g_lastPrintedEAState = g_CurrentEAState; }

        switch(g_CurrentEAState) {
            case STATE_IDLE:
                if(!g_has_active_trade) {
                    if(ShouldBlockNewEntries()) { if(InpDebugMode) Print("New entry blocked by rules."); return; }
                    bool execBuy=false, execSell=false;
                    if(CheckQualificationSignal(ORDER_TYPE_BUY)) { execBuy=true; }
                    else if(CheckQualificationSignal(ORDER_TYPE_SELL)) { execSell=true; }

                    if(execBuy) ExecuteOrder(ORDER_TYPE_BUY);
                    else if(execSell) ExecuteOrder(ORDER_TYPE_SELL);
                }
                break;

            case STATE_INITIAL_TRADE_OPEN:
                break;

            case STATE_PROFIT_MAXIMIZATION_ACTIVE:
                {
                    bool macd_condition_met = false;
                    double prevMacdMain=EMPTY_VALUE, prevMacdSignal=EMPTY_VALUE;
                    double tmp[1];
                    if(CopyBuffer(RoblixHandle, ROBLIX_MACD_MAIN_BUFFER_INDEX, 1, 1, tmp) > 0) prevMacdMain = tmp[0];
                    if(CopyBuffer(RoblixHandle, ROBLIX_MACD_SIGNAL_BUFFER_INDEX, 1, 1, tmp) > 0) prevMacdSignal = tmp[0];

                    if(g_pms_trade_type == ORDER_TYPE_BUY) {
                        if(currentMacdMain < currentMacdSignal && prevMacdMain>=prevMacdSignal) { g_isProfitMaximizationStageActive = false; }
                        else if(currentMacdMain >= currentMacdSignal) macd_condition_met = true;
                    } else if(g_pms_trade_type == ORDER_TYPE_SELL) {
                        if(currentMacdMain > currentMacdSignal && prevMacdMain<=prevMacdSignal) { g_isProfitMaximizationStageActive = false; }
                        else if(currentMacdMain <= currentMacdSignal) macd_condition_met = true;
                    }

                    g_isProfitMaximizationStageActive = macd_condition_met;
                    if(!g_isProfitMaximizationStageActive) { g_CurrentEAState = STATE_PROFIT_MAXIMIZATION_COMPLETE; break; }

                    if(g_has_active_trade && InpUseScalingIn) {
                        CPositionInfo pos;
                        if(!pos.Select(g_current_trade.ticket)) break;
                        double current_profit_points = (pos.PositionType()==POSITION_TYPE_BUY) ? (SymbolInfoDouble(Symbol(), SYMBOL_BID)-pos.PriceOpen())/SymbolInfoDouble(Symbol(), SYMBOL_POINT) : (pos.PriceOpen()-SymbolInfoDouble(Symbol(), SYMBOL_ASK))/SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                        if(current_profit_points >= InpScalingInMinProfitPoints && g_current_trade.scaling_trades_count < InpScalingInMaxTrades) {
                            if(CheckReEntryCondition(g_current_trade.type)) {
                                double base_lots = CalculateLotFromRisk(InpStopLossPriceUnits);
                                ScaleInTrade(g_current_trade.type, base_lots);
                                g_entriesInCurrentPMS++;
                                g_lastEntryTimeInPMS = TimeCurrent();
                            }
                        }
                    } else if(!g_has_active_trade) {
                        if(ShouldBlockNewEntries()) break;
                        if(CheckReEntryCondition(ORDER_TYPE_BUY)) { ExecuteOrder(ORDER_TYPE_BUY); g_entriesInCurrentPMS++; g_lastEntryTimeInPMS = TimeCurrent(); }
                        else if(CheckReEntryCondition(ORDER_TYPE_SELL)) { ExecuteOrder(ORDER_TYPE_SELL); g_entriesInCurrentPMS++; g_lastEntryTimeInPMS = TimeCurrent(); }
                    }
                }
                break;

            case STATE_PROFIT_MAXIMIZATION_COMPLETE:
                g_CurrentEAState = STATE_IDLE;
                break;
        }
    } else {
        if(InpDebugMode) PrintFormat("Outside trade window (seconds_remaining=%d) - skipping trade logic", seconds_remaining);
    }
}

//+------------------------------------------------------------------+
