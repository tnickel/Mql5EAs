//+------------------------------------------------------------------+
//| CC FXSSI EA V1.21 Multi-Symbol.mq5 |
//| Copyright 2023, Jan Kotzorek |
//| https://consistencycapital.de |
//+------------------------------------------------------------------+
#property copyright "Consistency Capital, Jan Kotzorek"
#property link "https://www.consistencycapital.de"
#property version "1.21" // Multi-Symbol Support mit verbesserter Symbol-Validierung
#include <Trade\Trade.mqh>

//--- EA-Eingabeparameter
input group "Handelseinstellungen"
input double Lots = 0.01; // Handelsvolumen
input ulong BaseMagicNumber = 12345; // Basis-Magic-Number (per Symbol: Base + Index * Increment)
input int MagicIncrement = 100; // Inkrement für Magic-Numbers pro Symbol

input group "Spezielle Lot-Größen"
input double GoldLots = 0.01; // Lot-Größe für Gold
input double SilverLots = 0.01; // Lot-Größe für Silver

input group "CSV Signal-Steuerung"
input bool UseCSVSignals = true; // CSV-Signale verwenden
input int CSVCheckIntervalMinutes = 15; // Prüfintervall in Minuten
input string CSVFileName = "last_known_signals.csv"; // CSV-Dateiname
input bool DebugMode = false; // Debug-Prints aktivieren

input group "Stochastic Indikator"
enum ETimeframe
{
    TF_H4, // H4 (default)
    TF_H1  // H1
};
input ETimeframe Stoch_Timeframe = TF_H4; // Stochastic Timeframe für Entry-Signale
input int Stoch_K_Period = 14; // Stochastic %K Periode
input int Stoch_D_Period = 3; // Stochastic %D Periode
input int Stoch_Slowing = 3; // Stochastic Verlangsamung
input double Stoch_Upper_Level = 80.0; // Oberes Level für Short
input double Stoch_Lower_Level = 20.0; // Unteres Level für Long

input group "ADR-basiertes Management"
input int ATR_Period = 14; // Periode für Average Daily Range (ADR)
input double Grid_Distance_Multiplier = 1.0; // ADR-Multiplikator für Abstand zw. Trades
input double Basket_TP_Multiplier = 0.5; // ADR-Multiplikator für Basket-TP (BE + X ADR)
input double Individual_SL_Multiplier = 10.0; // ADR-Multiplikator für individuellen SL pro Trade

input group "Panel-Einstellungen"
input int PanelHeight = 800; // Höhe des schwarzen Panels (Pixel)
input color PanelBgColor = clrBlack; // Hintergrundfarbe des Panels
input color PanelTextColor = clrWhite; // Textfarbe im Panel
input string PanelTitle = "FXSSI All Positions"; // Title for the panel

//--- Enum für den Handelsmodus
enum ETradingMode
{
    MODE_NEUTRAL, // Kein Handel
    MODE_LONG, // Nur Long
    MODE_SHORT // Nur Short
};

//--- Struct für Symbol-Daten
struct SymbolInfo
{
    string symbol;
    string signal;
    ETradingMode mode;
    ulong magic;
    int stoch_handle;
    int atr_handle;
    datetime last_tf_time;
    int pos_count;
};

//--- Globale Variablen
CTrade trade;
SymbolInfo all_symbols[];
datetime lastCSVCheckTime = 0;
datetime lastManagementTime = 0;
int managementIntervalSeconds = 60; // Management-Check alle 60 Sekunden

//--- Panel Variablen
string panelBgName = "EA_PANEL_BG";
int labelStartY = 20; // Start-Y für Labels (no buttons)
int labelLineHeight = 16; // Abstand pro Zeile
int leftX = 10; // X für linke Spalte

// Column positions for split labels
int colSymbolX = 10;
int colBiasX = 140;
int colPosX = 220;
int colTPX = 290;
int colMagicX = 450;

//+------------------------------------------------------------------+
//| Expert initialization function |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Arrays leeren
    ArrayFree(all_symbols);
    
    //--- ALLE alten EA-Objekte löschen, um Artefakte zu vermeiden
    ObjectsDeleteAll(0, "EA_");
    
    //--- Schwarzes Panel-Hintergrund erstellen (Zuerst, damit es hinten ist)
    CreatePanelBackground();
    
    //--- Timer setzen (für CSV und Management)
    EventSetTimer(managementIntervalSeconds);
    
    if(UseCSVSignals)
    {
        // Initiale CSV-Prüfung (Init-Modus)
        CheckCSVSignals(true);
    }
    else
    {
        // Wenn kein CSV, initialisiere leere Liste oder warne
        Print("CSV-Steuerung deaktiviert - Verwende manuelle Buttons für globale Modi");
    }
    
    UpdateInfoPanel();
    ChartRedraw(0);
    Sleep(100); // Kurze Pause für Rendering
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    ObjectsDeleteAll(0, "EA_"); // Alle EA-Objekte löschen
    Comment(""); // Fallback
    
    // Handles freigeben
    for(int i = 0; i < ArraySize(all_symbols); i++)
    {
        IndicatorRelease(all_symbols[i].stoch_handle);
        IndicatorRelease(all_symbols[i].atr_handle);
    }
}

//+------------------------------------------------------------------+
//| Timer function |
//+------------------------------------------------------------------+
void OnTimer()
{
    // CSV-Check falls aktiviert
    if(UseCSVSignals && (TimeCurrent() - lastCSVCheckTime > CSVCheckIntervalMinutes * 60))
    {
        CheckCSVSignals(false);
    }
    
    // Trade-Management für alle Symbole
    ManageAllSymbols();
    
    // Pos-Counts aktualisieren und Panel
    UpdatePosCounts();
    UpdateInfoPanel();
}

//+------------------------------------------------------------------+
//| ChartEvent function (inkl. Resize-Handling) |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_CHART_CHANGE)
    {
        // Panel-Hintergrund bei Chart-Resize anpassen
        CreatePanelBackground();
        UpdateInfoPanel(); // Labels neu positionieren
    }
}

//+------------------------------------------------------------------+
//| Alle Symbole managen |
//+------------------------------------------------------------------+
void ManageAllSymbols()
{
    ENUM_TIMEFRAMES tf = (Stoch_Timeframe == TF_H4 ? PERIOD_H4 : PERIOD_H1);
    
    for(int i = 0; i < ArraySize(all_symbols); i++)
    {
        if(all_symbols[i].mode == MODE_NEUTRAL) continue;
    
        datetime tf_time[1];
        if(CopyTime(all_symbols[i].symbol, tf, 0, 1, tf_time) <= 0) continue;
    
        if(tf_time[0] == all_symbols[i].last_tf_time) continue;
        all_symbols[i].last_tf_time = tf_time[0];
    
        if(all_symbols[i].mode == MODE_LONG)
        {
            ManageLongTradesForSymbol(i);
        }
        else if(all_symbols[i].mode == MODE_SHORT)
        {
            ManageShortTradesForSymbol(i);
        }
    }
}

//+------------------------------------------------------------------+
//| LONG TRADES MANAGEMENT pro Symbol |
//+------------------------------------------------------------------+
void ManageLongTradesForSymbol(int idx)
{
    SymbolInfo s = all_symbols[idx];
    string sym = s.symbol;
    ulong magic = s.magic;
    
    trade.SetExpertMagicNumber(magic);
    
    double adr = GetADRForSymbol(idx);
    if(adr == 0) return;
    
    // Positionen zählen und Preise sammeln
    int pos_count = 0;
    double sum_prices = 0.0;
    double prices[];
    ArrayResize(prices, 0);
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            pos_count++;
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            sum_prices += open_price;
            int sz = ArraySize(prices);
            ArrayResize(prices, sz + 1);
            prices[sz] = open_price;
        }
    }
    
    double current_price = SymbolInfoDouble(sym, SYMBOL_ASK);
    double grid_distance = Grid_Distance_Multiplier * adr;
    double sl_distance = Individual_SL_Multiplier * adr;
    
    double last_entry_price = 0.0;
    if(pos_count > 0)
    {
        ArraySort(prices); // ascending: lowest last
        last_entry_price = prices[0];
    }
    
    // Entry-Logik
    bool new_pos_opened = false;
    if(pos_count < 6)
    {
        bool should_open = false;
        if(pos_count == 0)
        {
            if(!CheckLongSignalForSymbol(idx)) return;
            should_open = true;
        }
        else
        {
            if(current_price <= last_entry_price - grid_distance)
            {
                should_open = true;
            }
        }
    
        if(should_open)
        {
            double trade_lots = Lots;
            if(StringFind(sym, "GOLD") >= 0) trade_lots = GoldLots;
            else if(StringFind(sym, "SILVER") >= 0) trade_lots = SilverLots;
            
            double sl = current_price - sl_distance;
            string comment = "Long " + IntegerToString(pos_count + 1);
            
            if(trade.Buy(trade_lots, sym, current_price, sl, 0, comment))
            {
                new_pos_opened = true;
                Print("Neue Long-Position für ", sym, " geöffnet: ", comment);
            }
        }
    }
    
    // Basket TP Management
    if(pos_count > 0 || new_pos_opened)
    {
        // Re-count nach potenzieller Öffnung
        pos_count = 0;
        sum_prices = 0.0;
        ArrayFree(prices);
        ArrayResize(prices, 0);
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                pos_count++;
                double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                sum_prices += open_price;
                int sz = ArraySize(prices);
                ArrayResize(prices, sz + 1);
                prices[sz] = open_price;
            }
        }
    
        double avg_entry = sum_prices / pos_count;
        double basket_tp = avg_entry + Basket_TP_Multiplier * adr;
    
        if(current_price >= basket_tp)
        {
            Print("Basket TP für Long-Positionen von ", sym, " erreicht (", basket_tp, "). Schließe alle.");
            CloseAllForSymbol(sym, magic, POSITION_TYPE_BUY);
        }
        else
        {
            SetUnifiedTPForSymbol(sym, magic, POSITION_TYPE_BUY, basket_tp);
            if(DebugMode) Print("Basket TP für Longs von ", sym, " aktualisiert auf: ", basket_tp);
        }
    }
}

//+------------------------------------------------------------------+
//| SHORT TRADES MANAGEMENT pro Symbol |
//+------------------------------------------------------------------+
void ManageShortTradesForSymbol(int idx)
{
    SymbolInfo s = all_symbols[idx];
    string sym = s.symbol;
    ulong magic = s.magic;
    
    trade.SetExpertMagicNumber(magic);
    
    double adr = GetADRForSymbol(idx);
    if(adr == 0) return;
    
    // Positionen zählen und Preise sammeln
    int pos_count = 0;
    double sum_prices = 0.0;
    double prices[];
    ArrayResize(prices, 0);
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            pos_count++;
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            sum_prices += open_price;
            int sz = ArraySize(prices);
            ArrayResize(prices, sz + 1);
            prices[sz] = open_price;
        }
    }
    
    double current_price = SymbolInfoDouble(sym, SYMBOL_BID);
    double grid_distance = Grid_Distance_Multiplier * adr;
    double sl_distance = Individual_SL_Multiplier * adr;
    
    double last_entry_price = 0.0;
    if(pos_count > 0)
    {
        ArraySort(prices); // ascending: highest last
        last_entry_price = prices[pos_count - 1];
    }
    
    // Entry-Logik
    bool new_pos_opened = false;
    if(pos_count < 6)
    {
        bool should_open = false;
        if(pos_count == 0)
        {
            if(!CheckShortSignalForSymbol(idx)) return;
            should_open = true;
        }
        else
        {
            if(current_price >= last_entry_price + grid_distance)
            {
                should_open = true;
            }
        }
    
        if(should_open)
        {
            double trade_lots = Lots;
            if(StringFind(sym, "GOLD") >= 0) trade_lots = GoldLots;
            else if(StringFind(sym, "SILVER") >= 0) trade_lots = SilverLots;
            
            double sl = current_price + sl_distance;
            string comment = "Short " + IntegerToString(pos_count + 1);
            
            if(trade.Sell(trade_lots, sym, current_price, sl, 0, comment))
            {
                new_pos_opened = true;
                Print("Neue Short-Position für ", sym, " geöffnet: ", comment);
            }
        }
    }
    
    // Basket TP Management
    if(pos_count > 0 || new_pos_opened)
    {
        // Re-count nach potenzieller Öffnung
        pos_count = 0;
        sum_prices = 0.0;
        ArrayFree(prices);
        ArrayResize(prices, 0);
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                pos_count++;
                double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                sum_prices += open_price;
                int sz = ArraySize(prices);
                ArrayResize(prices, sz + 1);
                prices[sz] = open_price;
            }
        }
    
        double avg_entry = sum_prices / pos_count;
        double basket_tp = avg_entry - Basket_TP_Multiplier * adr;
    
        if(current_price <= basket_tp)
        {
            Print("Basket TP für Short-Positionen von ", sym, " erreicht (", basket_tp, "). Schließe alle.");
            CloseAllForSymbol(sym, magic, POSITION_TYPE_SELL);
        }
        else
        {
            SetUnifiedTPForSymbol(sym, magic, POSITION_TYPE_SELL, basket_tp);
            if(DebugMode) Print("Basket TP für Shorts von ", sym, " aktualisiert auf: ", basket_tp);
        }
    }
}

//+------------------------------------------------------------------+
//| Basket TP Profit berechnen |
//+------------------------------------------------------------------+
double CalculateBasketTPProfit(int idx)
{
    if(all_symbols[idx].pos_count == 0) return 0.0;
    
    SymbolInfo s = all_symbols[idx];
    string sym = s.symbol;
    ulong magic = s.magic;
    ENUM_POSITION_TYPE type = (s.mode == MODE_LONG ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
    ENUM_ORDER_TYPE action = (s.mode == MODE_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
    
    // Ersten Loop: Avg Entry und ADR berechnen
    int actual_count = 0;
    double sum_open = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == sym && 
           PositionGetInteger(POSITION_MAGIC) == magic && 
           PositionGetInteger(POSITION_TYPE) == type)
        {
            double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
            sum_open += open_p;
            actual_count++;
        }
    }
    if(actual_count == 0) return 0.0;
    
    double avg_entry = sum_open / actual_count;
    double adr = GetADRForSymbol(idx);
    if(adr == 0) return 0.0;
    
    double basket_tp = (s.mode == MODE_LONG) ? avg_entry + Basket_TP_Multiplier * adr : avg_entry - Basket_TP_Multiplier * adr;
    
    // Zweiten Loop: Profit pro Position berechnen
    double total_profit = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == sym && 
           PositionGetInteger(POSITION_MAGIC) == magic && 
           PositionGetInteger(POSITION_TYPE) == type)
        {
            double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
            double vol = PositionGetDouble(POSITION_VOLUME);
            double this_profit = 0.0;
            if(!OrderCalcProfit(action, sym, vol, open_p, basket_tp, this_profit))
            {
                if(DebugMode) Print("OrderCalcProfit fehlgeschlagen für ", sym, " Ticket: ", ticket);
                continue;
            }
            total_profit += this_profit;
        }
    }
    
    return total_profit;
}

//+------------------------------------------------------------------+
//| Current Total P/L berechnen (unrealized) |
//+------------------------------------------------------------------+
double CalculateCurrentTotalPL()
{
    double total_pl = 0.0;
    for(int i = 0; i < ArraySize(all_symbols); i++)
    {
        if(all_symbols[i].mode == MODE_NEUTRAL) continue;
        
        ulong magic = all_symbols[i].magic;
        ENUM_POSITION_TYPE type = (all_symbols[i].mode == MODE_LONG ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
        
        for(int j = PositionsTotal() - 1; j >= 0; j--)
        {
            ulong ticket = PositionGetTicket(j);
            if(PositionGetInteger(POSITION_MAGIC) == magic &&
               PositionGetInteger(POSITION_TYPE) == type)
            {
                total_pl += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    return total_pl;
}

//+------------------------------------------------------------------+
//| Schwarzes Panel-Hintergrund erstellen/anpassen |
//+------------------------------------------------------------------+
void CreatePanelBackground()
{
    long chart_width = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    long chart_height = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    
    // Höhe begrenzen auf Chart-Höhe, aber mindestens PanelHeight
    int panel_h = MathMin(PanelHeight, (int)chart_height);
    
    ObjectDelete(0, panelBgName);
    
    if(!ObjectCreate(0, panelBgName, OBJ_RECTANGLE_LABEL, 0, 0, 0))
    {
        Print("Fehler beim Erstellen des Panel-Hintergrunds: ", GetLastError());
        return;
    }
    
    ObjectSetInteger(0, panelBgName, OBJPROP_XDISTANCE, 0);
    ObjectSetInteger(0, panelBgName, OBJPROP_YDISTANCE, 0);
    ObjectSetInteger(0, panelBgName, OBJPROP_XSIZE, chart_width);
    ObjectSetInteger(0, panelBgName, OBJPROP_YSIZE, panel_h);
    ObjectSetInteger(0, panelBgName, OBJPROP_BGCOLOR, PanelBgColor);
    ObjectSetInteger(0, panelBgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, panelBgName, OBJPROP_BORDER_COLOR, PanelBgColor);
    ObjectSetInteger(0, panelBgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, panelBgName, OBJPROP_BACK, true); // Hinten zeichnen
    ObjectSetInteger(0, panelBgName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, panelBgName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, panelBgName, OBJPROP_ZORDER, -10); // Sehr niedrig für absoluten Hintergrund
}

//+------------------------------------------------------------------+
//| Info-Panel mit integrierter Tabelle aktualisieren (Multi-Symbol) |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    // ALLE alten Labels löschen, um Overlaps/Artefakte zu vermeiden
    ObjectsDeleteAll(0, "EA_LABEL_");
    
    int currentY = labelStartY;
    
    // Big Title
    CreateLabel("EA_LABEL_TITLE", PanelTitle, currentY, leftX, PanelTextColor, 18);
    currentY += labelLineHeight * 2;
    
    // POSITIONS TABLE FIRST (above trading logic)
    string modeText = "─────────────────────────────────────────────────────────────────────────";
    CreateLabel("EA_LABEL_TABLE_LINE1", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    // Header - split for alignment
    CreateLabel("EA_LABEL_TABLE_HEADER_SYM", "SYMBOL", currentY, colSymbolX, PanelTextColor);
    CreateLabel("EA_LABEL_TABLE_HEADER_BIAS", "BIAS", currentY, colBiasX, PanelTextColor);
    CreateLabel("EA_LABEL_TABLE_HEADER_POS", "POS", currentY, colPosX, PanelTextColor);
    CreateLabel("EA_LABEL_TABLE_HEADER_TP", "TP-PROFIT", currentY, colTPX, PanelTextColor);
    CreateLabel("EA_LABEL_TABLE_HEADER_MAGIC", "MAGIC", currentY, colMagicX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "─────────────────────────────────────────────────────────────────────────";
    CreateLabel("EA_LABEL_TABLE_SEP", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    int total_pos = 0;
    
    if(ArraySize(all_symbols) > 0)
    {
        for(int i = 0; i < ArraySize(all_symbols); i++)
        {
            string dir = "";
            color biasColor = PanelTextColor;
            switch(all_symbols[i].mode)
            {
                case MODE_LONG: dir = "LONG"; biasColor = clrLime; break;
                case MODE_SHORT: dir = "SHORT"; biasColor = clrRed; break;
                case MODE_NEUTRAL: dir = "NEUT"; biasColor = PanelTextColor; break;
            }
            
            // Split row into columns for selective coloring
            string symText = StringFormat("%-12s", all_symbols[i].symbol);
            string biasText = StringFormat("%-7s", dir);
            string posText = StringFormat("%-7d", all_symbols[i].pos_count);
            
            double tp_profit = CalculateBasketTPProfit(i);
            string tpText = StringFormat("%10.2f", tp_profit);
            color tpColor = (tp_profit > 0 ? clrLime : (tp_profit < 0 ? clrRed : PanelTextColor));
            
            string magicText = StringFormat("%-10lu", all_symbols[i].magic);
            
            CreateLabel("EA_LABEL_TABLE_ROW_SYM_" + IntegerToString(i), symText, currentY, colSymbolX, PanelTextColor);
            CreateLabel("EA_LABEL_TABLE_ROW_BIAS_" + IntegerToString(i), biasText, currentY, colBiasX, biasColor);
            CreateLabel("EA_LABEL_TABLE_ROW_POS_" + IntegerToString(i), posText, currentY, colPosX, PanelTextColor);
            CreateLabel("EA_LABEL_TABLE_ROW_TP_" + IntegerToString(i), tpText, currentY, colTPX, tpColor);
            CreateLabel("EA_LABEL_TABLE_ROW_MAGIC_" + IntegerToString(i), magicText, currentY, colMagicX, PanelTextColor);
            
            currentY += labelLineHeight;
            total_pos += all_symbols[i].pos_count;
        }
    }
    else
    {
        modeText = "Keine Symbole geladen";
        CreateLabel("EA_LABEL_TABLE_NONE", modeText, currentY, leftX, PanelTextColor);
        currentY += labelLineHeight;
    }
    
    currentY += labelLineHeight;
    
    modeText = "─────────────────────────────────────────────────────────────────────────";
    CreateLabel("EA_LABEL_TABLE_FOOTER", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    double current_pl = CalculateCurrentTotalPL();
    color plColor = (current_pl > 0 ? clrLime : (current_pl < 0 ? clrRed : PanelTextColor));
    
    string posText = StringFormat(" TOTAL POSITIONS: %d", total_pos);
    CreateLabel("EA_LABEL_TOTAL_POS", posText, currentY, leftX, PanelTextColor);
    
    string plText = StringFormat(" | CURRENT P/L: %8.2f", current_pl);
    CreateLabel("EA_LABEL_TOTAL_PL", plText, currentY, leftX + 180, plColor);
    currentY += labelLineHeight * 2;
    
    // TRADING LOGIC SECTION (below positions table)
    modeText = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    CreateLabel("EA_LABEL_LOGIC_LINE1", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = " TRADING LOGIC (pro Symbol)";
    CreateLabel("EA_LABEL_LOGIC_TITLE", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    CreateLabel("EA_LABEL_LOGIC_LINE2", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "• 1. Entry: Stoch " + EnumToString(Stoch_Timeframe) + " Crossover (<20 up)";
    CreateLabel("EA_LABEL_LOGIC1", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "• Grid Adds (2-6): Every 1x ADR against last";
    CreateLabel("EA_LABEL_LOGIC2", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "• SL each: 10x ADR from entry";
    CreateLabel("EA_LABEL_LOGIC3", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "• Basket TP: Avg Entry + 0.5x ADR";
    CreateLabel("EA_LABEL_LOGIC4", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight * 2;
    
    // CSV-Information (links, unter Tabelle)
    if(UseCSVSignals)
    {
        modeText = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
        CreateLabel("EA_LABEL_CSV_LINE1", modeText, currentY, leftX, PanelTextColor);
        currentY += labelLineHeight;
        
        modeText = " CSV-STEUERUNG AKTIV";
        CreateLabel("EA_LABEL_CSV_TITLE", modeText, currentY, leftX, PanelTextColor);
        currentY += labelLineHeight;
        
        modeText = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
        CreateLabel("EA_LABEL_CSV_LINE2", modeText, currentY, leftX, PanelTextColor);
        currentY += labelLineHeight;
    
        if(lastCSVCheckTime > 0)
        {
            modeText = "Letzte Prüfung: " + TimeToString(lastCSVCheckTime, TIME_DATE|TIME_MINUTES);
            CreateLabel("EA_LABEL_CHECK_TIME", modeText, currentY, leftX, PanelTextColor);
            currentY += labelLineHeight;
        }
    
        int nextCheckIn = (CSVCheckIntervalMinutes * 60) - (int)(TimeCurrent() - lastCSVCheckTime);
        if(nextCheckIn > 0)
        {
            modeText = "Nächste in: " + IntegerToString(nextCheckIn / 60) + "min";
            CreateLabel("EA_LABEL_NEXT_CHECK", modeText, currentY, leftX, PanelTextColor);
        }
        else
        {
            modeText = "Nächste: ÜBERFÄLLIG";
            CreateLabel("EA_LABEL_NEXT_CHECK", modeText, currentY, leftX, PanelTextColor);
        }
        currentY += labelLineHeight * 2;
    }
    else
    {
        currentY += labelLineHeight * 2;
        modeText = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
        CreateLabel("EA_LABEL_MAN_LINE1", modeText, currentY, leftX, PanelTextColor);
        currentY += labelLineHeight;
        
        modeText = " MANUELLE STEUERUNG";
        CreateLabel("EA_LABEL_MAN_TITLE", modeText, currentY, leftX, PanelTextColor);
        currentY += labelLineHeight * 3;
    }
    
    // Zeitstempel (unten)
    modeText = "───────────────────────────────────────────────";
    CreateLabel("EA_LABEL_TIME_LINE", modeText, currentY, leftX, PanelTextColor);
    currentY += labelLineHeight;
    
    modeText = "Aktualisiert: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
    CreateLabel("EA_LABEL_TIME_NOW", modeText, currentY, leftX, PanelTextColor);
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Pos-Counts für alle Symbole aktualisieren |
//+------------------------------------------------------------------+
void UpdatePosCounts()
{
    for(int i = 0; i < ArraySize(all_symbols); i++)
    {
        all_symbols[i].pos_count = 0;
        if(all_symbols[i].mode == MODE_NEUTRAL) continue;
        
        ENUM_POSITION_TYPE type = (all_symbols[i].mode == MODE_LONG ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
        
        for(int j = PositionsTotal() - 1; j >= 0; j--)
        {
            ulong ticket = PositionGetTicket(j);
            if(PositionGetString(POSITION_SYMBOL) == all_symbols[i].symbol &&
               PositionGetInteger(POSITION_MAGIC) == all_symbols[i].magic &&
               PositionGetInteger(POSITION_TYPE) == type)
            {
                all_symbols[i].pos_count++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Label erstellen (mit X-Position und Farbe, optional fontsize) |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int y, int x = 10, color textColor = clrWhite, int fontsize = 9)
{
    ObjectDelete(0, name); // Immer löschen, bevor neu erstellen
    
    if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
    {
        if(DebugMode) Print("Fehler beim Erstellen des Labels '", name, "': ", GetLastError());
        return;
    }
    
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); // Anpassbarer X-Rand
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_FONT, "Courier New"); // Fixed width for table alignment
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontsize);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK, false); // Vorne über Hintergrund
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, name, OBJPROP_ZORDER, 5); // Mittel Z-Order
}

//+------------------------------------------------------------------+
//| Symbol prüfen und für Trading vorbereiten - VOLLSTÄNDIG KORRIGIERT |
//+------------------------------------------------------------------+
bool ValidateAndPrepareSymbol(string symbol)
{
    // 1. Versuchen Symbol zum MarketWatch hinzuzufügen (prüft gleichzeitig Existenz)
    if(!SymbolSelect(symbol, true))
    {
        Print("FEHLER: Symbol '", symbol, "' existiert nicht beim Broker oder konnte nicht hinzugefügt werden");
        return false;
    }
    
    Sleep(500); // Kurz warten nach dem Hinzufügen
    
    // 2. Prüfen ob Symbol handelbar ist
    long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
    {
        Print("WARNUNG: Symbol '", symbol, "' ist für Trading deaktiviert");
        // Nicht return false - wir laden es trotzdem für Anzeigezwecke
    }
    
    // 3. Synchronisieren und Chart-Daten anfordern
    if(!SymbolIsSynchronized(symbol))
    {
        Print("Synchronisiere Symbol '", symbol, "'...");
        int timeout = 5000; // 5 Sekunden Timeout
        int start = GetTickCount();
        while(!SymbolIsSynchronized(symbol) && (GetTickCount() - start < timeout))
        {
            Sleep(100);
        }
        if(!SymbolIsSynchronized(symbol))
        {
            Print("WARNUNG: Symbol '", symbol, "' konnte nicht synchronisiert werden");
            return false;
        }
    }
    
    // 4. Chart-Daten für die benötigten Timeframes laden
    ENUM_TIMEFRAMES tf = (Stoch_Timeframe == TF_H4 ? PERIOD_H4 : PERIOD_H1);
    
    // Test-Abfrage für Stochastic-Timeframe
    datetime time_array[];
    int copied = CopyTime(symbol, tf, 0, 10, time_array);
    if(copied <= 0)
    {
        Print("FEHLER: Keine Daten für ", symbol, " ", EnumToString(tf), " verfügbar (Fehlercode: ", GetLastError(), ")");
        return false;
    }
    
    // Test-Abfrage für D1 (für ATR)
    copied = CopyTime(symbol, PERIOD_D1, 0, 10, time_array);
    if(copied <= 0)
    {
        Print("FEHLER: Keine D1-Daten für ", symbol, " verfügbar (Fehlercode: ", GetLastError(), ")");
        return false;
    }
    
    if(DebugMode) Print("✓ Symbol '", symbol, "' erfolgreich validiert und vorbereitet");
    return true;
}
//+------------------------------------------------------------------+
//| CSV Signal Check Function (Init oder Update) - VERBESSERT       |
//+------------------------------------------------------------------+
void CheckCSVSignals(bool init_mode)
{
    string filename = CSVFileName;
    // Datei öffnen
    int file_handle = FileOpen(filename, FILE_READ | FILE_ANSI);
    if(file_handle == INVALID_HANDLE)
    {
        Print("Fehler beim Öffnen der CSV-Datei: ", filename);
        return;
    }
    
    if(DebugMode)
    {
        Print("=== CSV DEBUG START (Init: ", (init_mode ? "JA" : "NEIN"), ") ===");
    }
    
    bool isFirstLine = true;
    int lineNumber = 0;
    
    // Durch alle Zeilen iterieren
    while(!FileIsEnding(file_handle))
    {
        string line = FileReadString(file_handle);
        lineNumber++;
    
        if(DebugMode) Print("Zeile ", lineNumber, ": '", line, "'");
    
        // Leer Zeilen überspringen
        if(StringLen(line) == 0) continue;
    
        // Header überspringen
        if(isFirstLine)
        {
            string lineLower = line;
            StringToLower(lineLower);
            if(StringFind(lineLower, "waehrungspaar") >= 0 ||
               StringFind(lineLower, "symbol") >= 0 ||
               StringFind(lineLower, "währungspaar") >= 0)
            {
                if(DebugMode) Print("Header erkannt und übersprungen: ", line);
                isFirstLine = false;
                continue;
            }
        }
        isFirstLine = false;
    
        // Parsen
        string parts[];
        int num = StringSplit(line, ';', parts);
        if(num < 2)
        {
            num = StringSplit(line, ',', parts);
        }
        if(num < 2)
        {
            num = StringSplit(line, '\t', parts);
        }
    
        if(num >= 2)
        {
            string csvSymbol = parts[0];
            string csvSignal = parts[1];
        
            // Bereinigen
            StringTrimLeft(csvSymbol);
            StringTrimRight(csvSymbol);
            StringReplace(csvSymbol, "/", "");
            StringTrimLeft(csvSignal);
            StringTrimRight(csvSignal);
        
            if(DebugMode)
            {
                Print("Symbol: '", csvSymbol, "', Signal: '", csvSignal, "'");
            }
        
            if(init_mode)
            {
                // *** Symbol-Verfügbarkeit prüfen (nur beim Start nötig - kostet Sleep/Sync-Wartezeit) ***
                if(!ValidateAndPrepareSymbol(csvSymbol))
                {
                    Print("WARNUNG: Symbol '", csvSymbol, "' konnte nicht vorbereitet werden - wird übersprungen");
                    continue; // Dieses Symbol überspringen
                }

                // Neu hinzufügen
                int sz = ArraySize(all_symbols);
                ArrayResize(all_symbols, sz + 1);
                all_symbols[sz].symbol = csvSymbol;
                all_symbols[sz].signal = csvSignal;
            
                // Mode bestimmen
                string signalLower = csvSignal;
                StringToLower(signalLower);
                if(StringFind(signalLower, "buy") >= 0 || StringFind(signalLower, "long") >= 0)
                    all_symbols[sz].mode = MODE_LONG;
                else if(StringFind(signalLower, "sell") >= 0 || StringFind(signalLower, "short") >= 0)
                    all_symbols[sz].mode = MODE_SHORT;
                else
                    all_symbols[sz].mode = MODE_NEUTRAL;
            
                // Magic zuweisen
                all_symbols[sz].magic = BaseMagicNumber + (ulong)(sz * MagicIncrement);
            
                // Handles erstellen mit Fehlerprüfung
                ENUM_TIMEFRAMES tf = (Stoch_Timeframe == TF_H4 ? PERIOD_H4 : PERIOD_H1);
                
                // *** NEU: Mehrere Versuche mit Wartezeit ***
                all_symbols[sz].stoch_handle = INVALID_HANDLE;
                for(int attempt = 0; attempt < 3; attempt++)
                {
                    all_symbols[sz].stoch_handle = iStochastic(csvSymbol, tf, Stoch_K_Period, Stoch_D_Period, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
                    if(all_symbols[sz].stoch_handle != INVALID_HANDLE)
                    {
                        if(DebugMode) Print("Stochastic Handle erfolgreich erstellt für ", csvSymbol, " (Versuch ", attempt + 1, ")");
                        break;
                    }
                    Sleep(500); // 500ms warten vor erneutem Versuch
                }
                
                if(all_symbols[sz].stoch_handle == INVALID_HANDLE)
                {
                    Print("FEHLER: Konnte Stochastic-Handle für ", csvSymbol, " nicht erstellen (Fehlercode: ", GetLastError(), ") - Symbol wird übersprungen");
                    ArrayResize(all_symbols, sz);
                    continue;
                }
                
                // *** NEU: Mehrere Versuche für ATR ***
                all_symbols[sz].atr_handle = INVALID_HANDLE;
                for(int attempt = 0; attempt < 3; attempt++)
                {
                    all_symbols[sz].atr_handle = iATR(csvSymbol, PERIOD_D1, ATR_Period);
                    if(all_symbols[sz].atr_handle != INVALID_HANDLE)
                    {
                        if(DebugMode) Print("ATR Handle erfolgreich erstellt für ", csvSymbol, " (Versuch ", attempt + 1, ")");
                        break;
                    }
                    Sleep(500);
                }
                
                if(all_symbols[sz].atr_handle == INVALID_HANDLE)
                {
                    Print("FEHLER: Konnte ATR-Handle für ", csvSymbol, " nicht erstellen (Fehlercode: ", GetLastError(), ") - Symbol wird übersprungen");
                    IndicatorRelease(all_symbols[sz].stoch_handle);
                    ArrayResize(all_symbols, sz);
                    continue;
                }
            
                all_symbols[sz].last_tf_time = 0;
                all_symbols[sz].pos_count = 0;
            
                Print("✓ Symbol erfolgreich initialisiert: ", csvSymbol, " | Mode: ", EnumToString(all_symbols[sz].mode), " | Magic: ", all_symbols[sz].magic);
            }
            else
            {
                // Update bestehend
                bool found = false;
                for(int k = 0; k < ArraySize(all_symbols); k++)
                {
                    if(all_symbols[k].symbol == csvSymbol)
                    {
                        ETradingMode old_mode = all_symbols[k].mode;
                        all_symbols[k].signal = csvSignal;
                    
                        // Neuen Mode bestimmen
                        string signalLower = csvSignal;
                        StringToLower(signalLower);
                        ETradingMode new_mode = MODE_NEUTRAL;
                        if(StringFind(signalLower, "buy") >= 0 || StringFind(signalLower, "long") >= 0)
                            new_mode = MODE_LONG;
                        else if(StringFind(signalLower, "sell") >= 0 || StringFind(signalLower, "short") >= 0)
                            new_mode = MODE_SHORT;
                        else
                            new_mode = MODE_NEUTRAL;
                    
                        all_symbols[k].mode = new_mode;
                    
                        // Bei Wechsel: Alte Positionen schließen
                        if(old_mode != new_mode && old_mode != MODE_NEUTRAL)
                        {
                            ENUM_POSITION_TYPE old_type = (old_mode == MODE_LONG ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
                            CloseAllForSymbol(all_symbols[k].symbol, all_symbols[k].magic, old_type);
                            Print("Modus-Wechsel für ", csvSymbol, " von ", EnumToString(old_mode), " zu ", EnumToString(new_mode), " - Positionen geschlossen.");
                        }
                    
                        found = true;
                        if(DebugMode) Print("Update für ", csvSymbol, ": Neuer Mode ", EnumToString(new_mode));
                        break;
                    }
                }
                if(!found && DebugMode) Print("Symbol ", csvSymbol, " nicht in Liste gefunden - Ignoriert.");
            }
        }
    }
    
    FileClose(file_handle);
    
    if(DebugMode)
    {
        Print("=== CSV DEBUG ENDE ===");
        Print("Gesamt erfolgreich geladene Symbole: ", ArraySize(all_symbols));
    }
    
    lastCSVCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Hilfsfunktionen |
//+------------------------------------------------------------------+
bool CheckLongSignalForSymbol(int idx)
{
    double main_line[2];
    if(CopyBuffer(all_symbols[idx].stoch_handle, 0, 1, 2, main_line) < 2) return false;
    return(main_line[1] < Stoch_Lower_Level && main_line[0] > Stoch_Lower_Level);
}

bool CheckShortSignalForSymbol(int idx)
{
    double main_line[2];
    if(CopyBuffer(all_symbols[idx].stoch_handle, 0, 1, 2, main_line) < 2) return false;
    return(main_line[1] > Stoch_Upper_Level && main_line[0] < Stoch_Upper_Level);
}

double GetADRForSymbol(int idx)
{
    double atr_values[1];
    if(CopyBuffer(all_symbols[idx].atr_handle, 0, 1, 1, atr_values) < 1)
    {
        if(DebugMode) Print("Fehler beim Abrufen des ADR-Wertes für ", all_symbols[idx].symbol);
        return 0.0;
    }
    return atr_values[0];
}

void CloseAllForSymbol(string sym, ulong magic, ENUM_POSITION_TYPE type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic && PositionGetInteger(POSITION_TYPE) == type)
        {
            trade.PositionClose(ticket);
        }
    }
}

void SetUnifiedTPForSymbol(string sym, ulong magic, ENUM_POSITION_TYPE type, double tp)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic && PositionGetInteger(POSITION_TYPE) == type)
        {
            double current_sl = PositionGetDouble(POSITION_SL);
            trade.PositionModify(ticket, current_sl, tp);
        }
    }
}
//+------------------------------------------------------------------+
