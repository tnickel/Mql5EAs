//+------------------------------------------------------------------+
//|                                              CC_KI_Multi50.mq5  |
//|                               Copyright 2025, Algorithm Factory  |
//|       Feature: Multi-Symbol (50 Pairs) + CSV Signals + News      |
//+------------------------------------------------------------------+
#property copyright "Algorithm Factory"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- CONSTANTS ---
#define MAX_SYMBOLS 50
#define MAGIC_OFFSET 1000

//--- ENUMS ---
enum ENUM_ENTRY_MODE
{
   MODE_ADR = 0, // ADR Entry
   MODE_RSI = 1  // RSI Entry
};

enum ENUM_DIR_FILTER
{
   FILTER_BOTH    = 0, // Long & Short
   FILTER_LONG    = 1, // Only Long
   FILTER_SHORT   = 2, // Only Short
   FILTER_NEUTRAL = 3, // Neutral
   FILTER_PANIC   = 4  // PANIC - Alle Trades schließen
};

enum ENUM_NEWS_IMPORTANCE
{
   NEWS_HIGH_ONLY = 0,      // Nur High Impact
   NEWS_MEDIUM_HIGH = 1     // Medium + High Impact
};

//--- BASE SYMBOLS (ohne Broker-Suffix) ---
string g_BaseSymbols[MAX_SYMBOLS] = {
   "EURUSD", "USDJPY", "GBPUSD", "AUDUSD", "USDCAD",   // 1-5
   "USDCHF", "NZDUSD", "EURGBP", "EURJPY", "EURCHF",   // 6-10
   "EURCAD", "EURAUD", "EURNZD", "GBPJPY", "GBPCHF",   // 11-15
   "GBPCAD", "GBPAUD", "GBPNZD", "AUDJPY", "AUDCHF",   // 16-20
   "AUDCAD", "AUDNZD", "NZDJPY", "NZDCHF", "NZDCAD",   // 21-25
   "CADJPY", "CADCHF", "CHFJPY", "USDMXN", "USDZAR",   // 26-30
   "USDTRY", "USDSEK", "USDNOK", "USDDKK", "USDPLN",   // 31-35
   "USDHKD", "USDSGD", "USDTHB", "EURSEK", "EURNOK",   // 36-40
   "EURPLN", "GBPSEK", "GBPNOK", "AUDSEK", "AUDNOK",   // 41-45
   "NZDSEK", "NZDNOK", "USDCNY", "USDINR", "USDBRL"    // 46-50
};

//--- PER-SYMBOL STATE ---
struct SymbolState {
   string            brokerSymbol;     // Broker-Symbol (z.B. "EURUSDm")
   int               magic;            // Magic Number (1001-1050)
   bool              isValid;          // Symbol beim Broker verfügbar?
   ENUM_DIR_FILTER   filter;           // Aktuelle Richtung aus CSV
   datetime          lastProcessedBar; // Letzte verarbeitete H1-Bar
   double            adrValue;         // ADR für dieses Symbol
   datetime          lastADRCalcDay;   // Letzte ADR-Berechnung
   int               handleStoch;      // Stochastic-Handle
   int               handleRSI;        // RSI-Handle (wenn MODE_RSI)
};

SymbolState g_States[MAX_SYMBOLS];

//--- INPUT PARAMETERS ---
input group "=== CSV Signal Integration ==="
input bool     InpUseCSVSignals      = true;        // CSV-Signale nutzen?
input int      InpCSVCheckInterval   = 15;          // CSV Check Interval (Minuten)
input string   InpCSVFilename        = "last_known_signals.csv"; // CSV Dateiname
input bool     InpDebugMode          = false;       // Debug-Modus (ausführliche Logs)

input group "=== News Filter (MQL5 Calendar) ==="
input bool     InpUseNewsFilter           = true;           // News-Filter aktivieren?
input ENUM_NEWS_IMPORTANCE InpNewsImportance = NEWS_HIGH_ONLY; // Welche News filtern?
input int      InpMinutesBeforeNews       = 30;             // Minuten VOR News
input int      InpMinutesAfterNews        = 30;             // Minuten NACH News
input bool     InpNewsFilterBothCurrencies = true;          // Beide Währungen prüfen?

input group "--- Positions Management ---"
input double   InpFirstLot          = 0.03;        // Start Lotgröße
input double   InpGridLot           = 0.03;        // Grid Lotgröße
input int      InpMaxPositions      = 20;          // Max Anzahl Positionen pro Symbol
input double   InpIndividualSL_ADR  = 3.0;         // SL pro Trade in ADR

input group "--- Money Management ---"
input bool     InpUseMM             = false;       // MM Aktivieren?
input double   InpRefBalance        = 10000.0;     // Startkapital (Referenz)
input double   InpBalanceStep_Pct   = 10.0;        // Balance Step %
input double   InpLotIncrease_Pct   = 10.0;        // Lot Increase %

input group "--- Entry Logic Selection ---"
input ENUM_ENTRY_MODE InpEntryMode  = MODE_ADR;    // Entry Mode

input group "--- ADR Settings ---"
input int      InpADRPeriod         = 14;          // ADR Periode
input double   InpEntryADR_Pct      = 60.0;        // Entry: % von ADR
input double   InpGridStep_ADR_Pct  = 10.0;        // Grid Step

input group "--- RSI Settings (D1) ---"
input int      InpRSI_Period        = 14;          // RSI Periode
input int      InpRSI_Upper         = 70;          // RSI Upper
input int      InpRSI_Lower         = 30;          // RSI Lower

input group "--- Dynamic Exit Targets ---"
input double   InpStartTarget_ADR   = 10.0;        // Ziel bei Start
input double   InpTargetDecay_ADR   = 0.0;         // Abzug pro Grid-Level

input group "--- Stochastic Settings (H1) ---"
input int      InpStochK            = 5;
input int      InpStochD            = 3;
input int      InpStochSlowing      = 3;
input int      InpStochUpper        = 85;
input int      InpStochLower        = 15;

input group "--- Time Filter ---"
input bool     InpUseEODClose       = false;
input int      InpEODHour           = 23;
input int      InpEODMinute         = 50;

//--- GLOBALS ---
CTrade trade;

// Stats & Monitoring
double stat_HighWaterMark = 0.0;
double stat_MaxDD_Equity_Money = 0.0;
double stat_MaxDD_Equity_Percent = 0.0;
string stat_EA_Action = "Initializing...";

// CSV Signal Integration
datetime g_LastCSVCheck = 0;
string g_CSVStatus = "Not checked yet";
int g_ValidSymbolCount = 0;

// News Filter
bool g_NewsBlockActive = false;
string g_NextNewsInfo = "Keine News";
datetime g_NextNewsTime = 0;
string g_NextNewsName = "";

// Performance Optimization
datetime g_LastNewsCheckTime = 0;
int g_NewsCheckInterval = 300;

// GUI Object Names
string lblMaxDDName   = "Lbl_Info_MaxDD";
string lblPosName     = "Lbl_Info_Pos";
string lblStatusName  = "Lbl_Info_Status";
string lblSetupName   = "Lbl_Info_Setup";
string lblCSVInfoName = "Lbl_CSV_Info";
string lblCSVTimeName = "Lbl_CSV_Time";
string lblNewsInfoName = "Lbl_News_Info";
string lblSymbolCountName = "Lbl_Symbol_Count";

//+------------------------------------------------------------------+
//| Find Broker Symbol (handles suffix like m, ., #)                |
//| WICHTIG: Fügt Symbole automatisch zur Marktübersicht hinzu!     |
//+------------------------------------------------------------------+
string FindBrokerSymbol(string baseSymbol)
{
   // Zuerst: Exakter Match - versuche Symbol zur Marktübersicht hinzuzufügen
   if(SymbolInfoInteger(baseSymbol, SYMBOL_EXIST))
   {
      if(SymbolSelect(baseSymbol, true)) // Füge zur Marktübersicht hinzu
         return baseSymbol;
   }
   
   // Bekannte Suffixe probieren
   string suffixes[] = {"m", ".", "#", ".pro", "_", ".e", ".i", ".r", ".s"};
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      string test = baseSymbol + suffixes[i];
      if(SymbolInfoInteger(test, SYMBOL_EXIST))
      {
         if(SymbolSelect(test, true)) // Füge zur Marktübersicht hinzu
            return test;
      }
   }
   
   // Suche in ALLEN Broker-Symbolen (auch nicht sichtbare)
   int total = SymbolsTotal(false); // false = alle Symbole, nicht nur sichtbare
   for(int i = 0; i < total; i++)
   {
      string sym = SymbolName(i, false);
      // Prüfe ob Symbol mit baseSymbol beginnt
      if(StringFind(sym, baseSymbol) == 0)
      {
         if(SymbolSelect(sym, true)) // Füge zur Marktübersicht hinzu
            return sym;
      }
   }
   
   return ""; // Nicht gefunden
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   bool isInTester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   
   // Init HWM
   stat_HighWaterMark = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // --- CHART STYLING ---
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   
   Comment("");
   ChartRedraw();

   // Initialize all 50 symbols
   g_ValidSymbolCount = 0;
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      g_States[i].brokerSymbol = FindBrokerSymbol(g_BaseSymbols[i]);
      g_States[i].magic = MAGIC_OFFSET + i + 1; // 1001-1050
      g_States[i].isValid = (g_States[i].brokerSymbol != "");
      g_States[i].filter = FILTER_NEUTRAL; // Start neutral until CSV loaded
      g_States[i].lastProcessedBar = 0;
      g_States[i].adrValue = 0.0;
      g_States[i].lastADRCalcDay = 0;
      g_States[i].handleStoch = INVALID_HANDLE;
      g_States[i].handleRSI = INVALID_HANDLE;
      
      if(g_States[i].isValid)
      {
         g_ValidSymbolCount++;
         
         // Create indicators for this symbol
         g_States[i].handleStoch = iStochastic(g_States[i].brokerSymbol, PERIOD_H1, 
                                                InpStochK, InpStochD, InpStochSlowing, 
                                                MODE_SMA, STO_LOWHIGH);
         
         if(InpEntryMode == MODE_RSI)
         {
            g_States[i].handleRSI = iRSI(g_States[i].brokerSymbol, PERIOD_D1, 
                                          InpRSI_Period, PRICE_CLOSE);
         }
         
         if(InpDebugMode)
            Print("Symbol ", i+1, ": ", g_BaseSymbols[i], " -> ", g_States[i].brokerSymbol, 
                  " | Magic: ", g_States[i].magic);
      }
      else
      {
         if(InpDebugMode)
            Print("Symbol ", i+1, ": ", g_BaseSymbols[i], " NOT FOUND at broker!");
      }
   }
   
   Print("Multi50 EA initialized: ", g_ValidSymbolCount, " / ", MAX_SYMBOLS, " symbols available");

   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // GUI erstellen (nur Info-Labels, keine Buttons)
   CreateLabels();
   
   // CSV-Mode initialisieren
   if(InpUseCSVSignals && !isInTester)
   {
      if(InpDebugMode) Print("CSV-Signal Mode aktiviert. Prüfe Datei: ", InpCSVFilename);
      CheckCSVFile();
      
      int timerSeconds = InpCSVCheckInterval * 60;
      if(!EventSetTimer(timerSeconds))
      {
         Print("FEHLER: Timer konnte nicht gestartet werden!");
         return(INIT_FAILED);
      }
      if(InpDebugMode) Print("Timer gestartet: Prüfe CSV alle ", InpCSVCheckInterval, " Minuten");
   }
   
   // News-Filter initialisieren
   if(InpUseNewsFilter)
   {
      if(InpDebugMode)
      {
         Print("News-Filter aktiviert. Wichtigkeit: ", 
               (InpNewsImportance == NEWS_HIGH_ONLY) ? "Nur HIGH" : "MEDIUM + HIGH",
               " | Zeitfenster: ", InpMinutesBeforeNews, " Min vorher / ", InpMinutesAfterNews, " Min nachher");
      }
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release all indicator handles
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(g_States[i].handleStoch != INVALID_HANDLE) 
         IndicatorRelease(g_States[i].handleStoch);
      if(g_States[i].handleRSI != INVALID_HANDLE) 
         IndicatorRelease(g_States[i].handleRSI);
   }
   
   EventKillTimer();
   
   ObjectDelete(0, lblMaxDDName);
   ObjectDelete(0, lblPosName);
   ObjectDelete(0, lblStatusName);
   ObjectDelete(0, lblSetupName);
   ObjectDelete(0, lblCSVInfoName);
   ObjectDelete(0, lblCSVTimeName);
   ObjectDelete(0, lblNewsInfoName);
   ObjectDelete(0, lblSymbolCountName);
   
   // Delete symbol grid labels
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      ObjectDelete(0, "Lbl_Sym_" + IntegerToString(i));
   }
   ObjectDelete(0, "Lbl_Legend");
   
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer Event                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpUseCSVSignals)
   {
      CheckCSVFile();
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- 1. MONITORING ---
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(currentBalance > stat_HighWaterMark) stat_HighWaterMark = currentBalance;
   
   double equityDD_Money = stat_HighWaterMark - currentEquity;
   if(equityDD_Money > stat_MaxDD_Equity_Money) stat_MaxDD_Equity_Money = equityDD_Money;
   
   double equityDD_Pct = 0.0;
   if(stat_HighWaterMark > 0) equityDD_Pct = (equityDD_Money / stat_HighWaterMark) * 100.0;
   if(equityDD_Pct > stat_MaxDD_Equity_Percent) stat_MaxDD_Equity_Percent = equityDD_Pct;

   // --- 2. NEWS FILTER (global für alle Symbole) ---
   CheckUpcomingNews();

   // --- 3. PROCESS ALL SYMBOLS ---
   int totalPositions = 0;
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(!g_States[i].isValid) continue;
      
      int posCount = ProcessSymbol(i);
      totalPositions += posCount;
   }

   // --- 4. VISUALS UPDATE ---
   UpdateVisuals(totalPositions);
}

//+------------------------------------------------------------------+
//| Process Single Symbol - Returns position count                   |
//+------------------------------------------------------------------+
int ProcessSymbol(int idx)
{
   string symbol = g_States[idx].brokerSymbol;
   int magic = g_States[idx].magic;
   ENUM_DIR_FILTER filter = g_States[idx].filter;
   
   // Set magic for trade object
   trade.SetExpertMagicNumber(magic);
   
   // PANIC-CHECK
   if(filter == FILTER_PANIC)
   {
      CloseAllPositionsForSymbol(symbol, magic);
      return 0;
   }
   
   // Calculate ADR for this symbol
   CalculateADR_for_Symbol(idx);
   
   // Count open positions for this symbol
   int openPositions = 0;
   ENUM_POSITION_TYPE openType = POSITION_TYPE_BUY;
   double lastEntryPrice = 0.0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            openPositions++;
            openType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            lastEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
   }

   // --- MANAGE EXISTING POSITIONS ---
   if(openPositions > 0)
   {
      CheckBasketExitForSymbol(idx, openType, openPositions);
      
      // Grid-Nachkauf prüfen
      datetime currentH1Bar = iTime(symbol, PERIOD_H1, 0);
      if(currentH1Bar != g_States[idx].lastProcessedBar && openPositions < InpMaxPositions)
      {
         g_States[idx].lastProcessedBar = currentH1Bar;
         
         if(!g_NewsBlockActive)
         {
            double adr = g_States[idx].adrValue;
            double requiredDist = adr * (InpGridStep_ADR_Pct / 100.0);
            double slDistancePoints = adr * InpIndividualSL_ADR;
            
            double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            double dynGridLot = GetDynamicLot(InpGridLot);
            
            if(openType == POSITION_TYPE_SELL && ask >= (lastEntryPrice + requiredDist))
            {
               if(filter == FILTER_SHORT || filter == FILTER_BOTH)
               {
                  string comment = BuildTradeComment(false, openPositions + 1, "Short", symbol);
                  trade.Sell(dynGridLot, symbol, ask, ask + slDistancePoints, 0, comment);
               }
            }
            if(openType == POSITION_TYPE_BUY && bid <= (lastEntryPrice - requiredDist))
            {
               if(filter == FILTER_LONG || filter == FILTER_BOTH)
               {
                  string comment = BuildTradeComment(false, openPositions + 1, "Long", symbol);
                  trade.Buy(dynGridLot, symbol, bid, bid - slDistancePoints, 0, comment);
               }
            }
         }
      }
   }

   // EOD Close
   if(InpUseEODClose)
   {
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(), tm);
      if(tm.hour == InpEODHour && tm.min >= InpEODMinute)
      {
         if(openPositions > 0)
         {
            CloseAllPositionsForSymbol(symbol, magic);
         }
      }
   }

   // --- ENTRY LOGIC (nur wenn keine Positionen) ---
   if(openPositions == 0 && filter != FILTER_NEUTRAL)
   {
      datetime currentH1Bar = iTime(symbol, PERIOD_H1, 0);
      if(currentH1Bar != g_States[idx].lastProcessedBar)
      {
         g_States[idx].lastProcessedBar = currentH1Bar;
         
         if(!g_NewsBlockActive)
         {
            bool entryConditionMet = false;
            double adr = g_States[idx].adrValue;
            
            if(InpEntryMode == MODE_ADR)
            {
               double dayRange = iHigh(symbol, PERIOD_D1, 0) - iLow(symbol, PERIOD_D1, 0);
               double neededRange = adr * (InpEntryADR_Pct / 100.0);
               if(dayRange > neededRange) entryConditionMet = true;
            }
            else if(InpEntryMode == MODE_RSI && g_States[idx].handleRSI != INVALID_HANDLE)
            {
               double rsiValues[];
               if(CopyBuffer(g_States[idx].handleRSI, 0, 0, 1, rsiValues) == 1)
               {
                  if(rsiValues[0] >= InpRSI_Upper || rsiValues[0] <= InpRSI_Lower)
                  {
                     entryConditionMet = true;
                  }
               }
            }
            
            if(entryConditionMet && g_States[idx].handleStoch != INVALID_HANDLE)
            {
               double kBuffer[], dBuffer[];
               ArraySetAsSeries(kBuffer, true);
               ArraySetAsSeries(dBuffer, true);
               
               if(CopyBuffer(g_States[idx].handleStoch, 0, 0, 3, kBuffer) >= 3 &&
                  CopyBuffer(g_States[idx].handleStoch, 1, 0, 3, dBuffer) >= 3)
               {
                  bool shortSignal = (kBuffer[2] >= InpStochUpper && kBuffer[1] < InpStochUpper);
                  bool longSignal  = (kBuffer[2] <= InpStochLower && kBuffer[1] > InpStochLower);
                  
                  double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
                  double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
                  double slDistancePoints = adr * InpIndividualSL_ADR;
                  double dynFirstLot = GetDynamicLot(InpFirstLot);
                  
                  if(shortSignal && (filter == FILTER_SHORT || filter == FILTER_BOTH))
                  {
                     string comment = BuildTradeComment(true, 1, "Short", symbol);
                     trade.Sell(dynFirstLot, symbol, ask, ask + slDistancePoints, 0, comment);
                  }
                  if(longSignal && (filter == FILTER_LONG || filter == FILTER_BOTH))
                  {
                     string comment = BuildTradeComment(true, 1, "Long", symbol);
                     trade.Buy(dynFirstLot, symbol, bid, bid - slDistancePoints, 0, comment);
                  }
               }
            }
         }
      }
   }

   return openPositions;
}

//+------------------------------------------------------------------+
//| CSV Integration - Load all signals                               |
//+------------------------------------------------------------------+
void CheckCSVFile()
{
   g_LastCSVCheck = TimeCurrent();
   
   int fileHandle = FileOpen(InpCSVFilename, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(fileHandle == INVALID_HANDLE)
   {
      g_CSVStatus = "Datei nicht gefunden";
      Print("FEHLER: CSV-Datei nicht gefunden: ", InpCSVFilename);
      return;
   }
   
   // Reset all filters to NEUTRAL before loading
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(g_States[i].isValid)
      {
         ENUM_DIR_FILTER oldFilter = g_States[i].filter;
         g_States[i].filter = FILTER_NEUTRAL; // Default if not found in CSV
      }
   }
   
   int lineNumber = 0;
   int matchedCount = 0;
   
   while(!FileIsEnding(fileHandle))
   {
      string line = FileReadString(fileHandle);
      lineNumber++;
      
      StringReplace(line, "\r", "");
      StringReplace(line, "\n", "");
      StringTrimLeft(line);
      StringTrimRight(line);
      
      if(line == "") continue;
      if(lineNumber == 1 || StringFind(line, "Waehrungspaar") >= 0) continue;
      
      string parts[];
      int count = StringSplit(line, ';', parts);
      
      if(count >= 2)
      {
         string csvSymbol = parts[0];
         StringTrimLeft(csvSymbol);
         StringTrimRight(csvSymbol);
         
         // Entferne / aus CSV-Symbol (EUR/USD -> EURUSD)
         StringReplace(csvSymbol, "/", "");
         StringToUpper(csvSymbol);
         
         string csvSignal = parts[1];
         StringTrimLeft(csvSignal);
         StringTrimRight(csvSignal);
         StringToUpper(csvSignal);
         
         // Find matching symbol in our array
         for(int i = 0; i < MAX_SYMBOLS; i++)
         {
            if(!g_States[i].isValid) continue;
            
            // Compare with base symbol (without broker suffix)
            if(csvSymbol == g_BaseSymbols[i])
            {
               ENUM_DIR_FILTER oldFilter = g_States[i].filter;
               ENUM_DIR_FILTER newFilter = FILTER_NEUTRAL;
               
               if(csvSignal == "BUY")
                  newFilter = FILTER_LONG;
               else if(csvSignal == "SELL")
                  newFilter = FILTER_SHORT;
               else if(csvSignal == "PANIC")
                  newFilter = FILTER_PANIC;
               else
                  newFilter = FILTER_NEUTRAL;
               
               g_States[i].filter = newFilter;
               matchedCount++;
               
               // Handle filter change
               if(oldFilter != newFilter)
               {
                  if(InpDebugMode)
                     Print(g_BaseSymbols[i], ": ", csvSignal, " (Magic ", g_States[i].magic, ")");
                  
                  // PANIC: Close all positions
                  if(newFilter == FILTER_PANIC)
                  {
                     CloseAllPositionsForSymbol(g_States[i].brokerSymbol, g_States[i].magic);
                     Print("PANIC: Alle Positionen für ", g_States[i].brokerSymbol, " geschlossen!");
                  }
                  // Direction change: Close opposite positions
                  else if(oldFilter != FILTER_NEUTRAL && oldFilter != FILTER_PANIC && newFilter != FILTER_NEUTRAL)
                  {
                     CloseOppositePositionsForSymbol(g_States[i].brokerSymbol, g_States[i].magic, newFilter);
                  }
               }
               
               break;
            }
         }
      }
   }
   
   FileClose(fileHandle);
   
   g_CSVStatus = StringFormat("OK: %d/%d Signale geladen", matchedCount, g_ValidSymbolCount);
   Print("CSV geladen: ", matchedCount, " Signale für ", g_ValidSymbolCount, " aktive Symbole");
}

//+------------------------------------------------------------------+
//| Close Opposite Positions for Symbol                              |
//+------------------------------------------------------------------+
void CloseOppositePositionsForSymbol(string symbol, int magic, ENUM_DIR_FILTER newFilter)
{
   if(newFilter == FILTER_NEUTRAL || newFilter == FILTER_BOTH) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool closeIt = false;
            
            if(newFilter == FILTER_LONG && type == POSITION_TYPE_SELL)
               closeIt = true;
            else if(newFilter == FILTER_SHORT && type == POSITION_TYPE_BUY)
               closeIt = true;
            
            if(closeIt)
            {
               trade.SetExpertMagicNumber(magic);
               trade.PositionClose(ticket);
               Print("Closed opposite position #", ticket, " for ", symbol);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| News Filter - Check for any symbol's currencies                  |
//+------------------------------------------------------------------+
void CheckUpcomingNews()
{
   if(!InpUseNewsFilter)
   {
      g_NewsBlockActive = false;
      g_NextNewsInfo = "Deaktiviert";
      return;
   }
   
   datetime currentTime = TimeCurrent();
   if(currentTime - g_LastNewsCheckTime < g_NewsCheckInterval && g_LastNewsCheckTime > 0)
   {
      return;
   }
   g_LastNewsCheckTime = currentTime;
   
   datetime serverTime = TimeTradeServer();
   datetime dateFrom = serverTime - (InpMinutesAfterNews * 60);
   datetime dateTo = serverTime + (InpMinutesBeforeNews * 60);
   
   ENUM_CALENDAR_EVENT_IMPORTANCE minImportance = (InpNewsImportance == NEWS_HIGH_ONLY) 
      ? CALENDAR_IMPORTANCE_HIGH 
      : CALENDAR_IMPORTANCE_MODERATE;
   
   // Check major currencies
   string currencies[] = {"USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF"};
   
   MqlCalendarValue values[];
   datetime nearestNewsTime = 0;
   string nearestNewsName = "";
   ENUM_CALENDAR_EVENT_IMPORTANCE nearestImportance = CALENDAR_IMPORTANCE_NONE;
   
   for(int c = 0; c < ArraySize(currencies); c++)
   {
      if(CalendarValueHistory(values, dateFrom, dateTo, NULL, currencies[c]))
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               if(event.time_mode != CALENDAR_TIMEMODE_DATETIME && 
                  event.time_mode != CALENDAR_TIMEMODE_DATE)
                  continue;
               
               if(event.importance < minImportance)
                  continue;
               
               if(nearestNewsTime == 0 || 
                  MathAbs((int)(values[i].time - serverTime)) < MathAbs((int)(nearestNewsTime - serverTime)))
               {
                  nearestNewsTime = values[i].time;
                  nearestNewsName = event.name;
                  nearestImportance = event.importance;
               }
            }
         }
      }
   }
   
   if(nearestNewsTime > 0)
   {
      int minutesDiff = (int)((nearestNewsTime - serverTime) / 60);
      
      string impText = "";
      switch(nearestImportance)
      {
         case CALENDAR_IMPORTANCE_HIGH: impText = "HIGH"; break;
         case CALENDAR_IMPORTANCE_MODERATE: impText = "MEDIUM"; break;
         default: impText = "LOW"; break;
      }
      
      if(minutesDiff > 0)
      {
         g_NewsBlockActive = true;
         g_NextNewsInfo = StringFormat("%s [%s] in %d Min", nearestNewsName, impText, minutesDiff);
      }
      else
      {
         g_NewsBlockActive = true;
         g_NextNewsInfo = StringFormat("%s [%s] vor %d Min", nearestNewsName, impText, -minutesDiff);
      }
      
      g_NextNewsTime = nearestNewsTime;
      g_NextNewsName = nearestNewsName;
   }
   else
   {
      g_NewsBlockActive = false;
      g_NextNewsInfo = "Klar - Keine News";
      g_NextNewsTime = 0;
      g_NextNewsName = "";
   }
}

//+------------------------------------------------------------------+
//| Display Logic                                                    |
//+------------------------------------------------------------------+
void UpdateVisuals(int totalPositions)
{
   static bool isInTester = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));
   if(isInTester) return;
   
   // Count positions per direction
   int longCount = 0, shortCount = 0;
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(!g_States[i].isValid) continue;
      if(g_States[i].filter == FILTER_LONG) longCount++;
      else if(g_States[i].filter == FILTER_SHORT) shortCount++;
   }
   
   string txtDD = StringFormat("MaxDD: %.2f%%", stat_MaxDD_Equity_Percent);
   ObjectSetString(0, lblMaxDDName, OBJPROP_TEXT, txtDD);

   string txtPos = StringFormat("Positionen: %d | Long: %d | Short: %d", totalPositions, longCount, shortCount);
   ObjectSetString(0, lblPosName, OBJPROP_TEXT, txtPos);
   
   string txtSetup = StringFormat("Grid %.0f%% | Target %.0f%% | Lot %.2f", 
                                   InpGridStep_ADR_Pct, InpStartTarget_ADR, InpFirstLot);
   ObjectSetString(0, lblSetupName, OBJPROP_TEXT, txtSetup);
   
   string txtCSVInfo = StringFormat("CSV: %s", g_CSVStatus);
   ObjectSetString(0, lblCSVInfoName, OBJPROP_TEXT, txtCSVInfo);
   ObjectSetInteger(0, lblCSVInfoName, OBJPROP_COLOR, clrLimeGreen);
   
   string timeText = (g_LastCSVCheck > 0) ? TimeToString(g_LastCSVCheck, TIME_DATE|TIME_MINUTES) : "Noch nie";
   string txtCSVTime = StringFormat("Letzte Prüfung: %s", timeText);
   ObjectSetString(0, lblCSVTimeName, OBJPROP_TEXT, txtCSVTime);
   
   if(InpUseNewsFilter)
   {
      color newsColor = g_NewsBlockActive ? clrRed : clrLimeGreen;
      string newsText = g_NewsBlockActive ? 
         StringFormat("News: BLOCKIERT | %s", g_NextNewsInfo) :
         StringFormat("News: %s", g_NextNewsInfo);
      ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, newsText);
      ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, newsColor);
   }
   else
   {
      ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, "News-Filter: DEAKTIVIERT");
      ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, clrGray);
   }
   
   string txtSymbols = StringFormat("Symbole: %d / %d aktiv", g_ValidSymbolCount, MAX_SYMBOLS);
   ObjectSetString(0, lblSymbolCountName, OBJPROP_TEXT, txtSymbols);
   
   // Update symbol direction grid
   UpdateSymbolGrid();
}

//+------------------------------------------------------------------+
//| Update Symbol Direction Grid                                     |
//+------------------------------------------------------------------+
void UpdateSymbolGrid()
{
   int startX = 20;
   int startY = 195;
   int colWidth = 140;  // Breite pro Symbol (viel mehr Abstand)
   int rowHeight = 26;  // Höhe pro Zeile (viel mehr Abstand)
   int cols = 5;        // Nur 5 Spalten für beste Lesbarkeit
   int fontSize = 12;   // Größere Schrift
   
   int validIdx = 0;
   for(int i = 0; i < MAX_SYMBOLS; i++)
   {
      if(!g_States[i].isValid) continue;
      
      string lblName = "Lbl_Sym_" + IntegerToString(i);
      int col = validIdx % cols;
      int row = validIdx / cols;
      int x = startX + (col * colWidth);
      int y = startY + (row * rowHeight);
      
      // Kürzel erstellen
      string shortName = g_BaseSymbols[i];
      
      // Farbe basierend auf Richtung
      color symColor = clrGray;
      string dirChar = " ";
      if(g_States[i].filter == FILTER_LONG)
      {
         symColor = clrLimeGreen;
         dirChar = "▲ ";
      }
      else if(g_States[i].filter == FILTER_SHORT)
      {
         symColor = clrTomato;
         dirChar = "▼ ";
      }
      else if(g_States[i].filter == FILTER_PANIC)
      {
         symColor = clrRed;
         dirChar = "X ";
      }
      else
      {
         symColor = clrGray;
         dirChar = "- ";
      }
      
      string displayText = dirChar + shortName;
      
      if(ObjectFind(0, lblName) < 0)
      {
         ObjectCreate(0, lblName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, lblName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetString(0, lblName, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, fontSize);
         ObjectSetInteger(0, lblName, OBJPROP_BACK, false);
         ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, true);
      }
      
      ObjectSetInteger(0, lblName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, lblName, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, lblName, OBJPROP_TEXT, displayText);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, symColor);
      
      validIdx++;
   }
   
   // Legende am Ende des Grids
   int legendY = startY + ((validIdx / cols) + 2) * rowHeight;
   
   // Legende Labels erstellen
   string legendName = "Lbl_Legend";
   string legendText = "▲ BUY (Long)     ▼ SELL (Short)     - NEUTRAL     X PANIC";
   
   if(ObjectFind(0, legendName) < 0)
   {
      ObjectCreate(0, legendName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, legendName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, legendName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, legendName, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, legendName, OBJPROP_BACK, false);
      ObjectSetInteger(0, legendName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, legendName, OBJPROP_HIDDEN, true);
   }
   
   ObjectSetInteger(0, legendName, OBJPROP_XDISTANCE, startX);
   ObjectSetInteger(0, legendName, OBJPROP_YDISTANCE, legendY);
   ObjectSetString(0, legendName, OBJPROP_TEXT, legendText);
   ObjectSetInteger(0, legendName, OBJPROP_COLOR, clrWhite);
}

//+------------------------------------------------------------------+
//| GUI Helper - Labels only (no buttons)                            |
//+------------------------------------------------------------------+
void CreateLabels()
{
   int x = 20;
   int fontSize = 11;
   string font = "Arial Bold";
   color c = clrWhite;
   
   CreateSingleLabel(lblMaxDDName, x, 20, "MaxDD: 0.0%", fontSize, font, c);
   CreateSingleLabel(lblPosName, x, 45, "Positionen: 0", fontSize, font, c);
   CreateSingleLabel(lblSetupName, x, 70, "Setup: ...", fontSize, font, c);
   CreateSingleLabel(lblCSVInfoName, x, 95, "CSV: Init...", fontSize, font, clrYellow);
   CreateSingleLabel(lblCSVTimeName, x, 120, "CSV Check: ...", fontSize, font, clrWhite);
   CreateSingleLabel(lblNewsInfoName, x, 145, "News: Init...", fontSize, font, clrYellow);
   CreateSingleLabel(lblSymbolCountName, x, 170, "Symbole: 0/50", fontSize, font, clrCyan);
   
   // Create initial symbol grid
   UpdateSymbolGrid();
}

void CreateSingleLabel(string name, int x, int y, string text, int fSize, string font, color c)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, font);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string BuildTradeComment(bool isFirstEntry, int positionNumber, string direction, string symbol)
{
   string entryType = isFirstEntry ? ((InpEntryMode == MODE_ADR) ? "ADR" : "RSI") : "Grid";
   return StringFormat("CSV | %s-%s #%d | %s", entryType, direction, positionNumber, symbol);
}

//+------------------------------------------------------------------+
//| ADR Calculation for specific symbol                              |
//+------------------------------------------------------------------+
void CalculateADR_for_Symbol(int idx)
{
   string symbol = g_States[idx].brokerSymbol;
   datetime currentDay = iTime(symbol, PERIOD_D1, 0);
   
   if(currentDay != g_States[idx].lastADRCalcDay || g_States[idx].adrValue == 0)
   {
      g_States[idx].lastADRCalcDay = currentDay;
      
      double sum = 0;
      for(int i = 1; i <= InpADRPeriod; i++)
         sum += (iHigh(symbol, PERIOD_D1, i) - iLow(symbol, PERIOD_D1, i));
      
      g_States[idx].adrValue = sum / InpADRPeriod;
      
      if(g_States[idx].adrValue == 0)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         g_States[idx].adrValue = 100 * point;
      }
   }
}

//+------------------------------------------------------------------+
//| GetDynamicLot                                                    |
//+------------------------------------------------------------------+
double GetDynamicLot(double baseLot)
{
   if(!InpUseMM || InpRefBalance <= 0 || InpBalanceStep_Pct <= 0) return(baseLot);
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(currentBalance < InpRefBalance) return(baseLot);
   
   double profitAbs = currentBalance - InpRefBalance;
   double profitPct = (profitAbs / InpRefBalance) * 100.0;
   
   int steps = (int)(profitPct / InpBalanceStep_Pct);
   double multiplier = 1.0 + (steps * (InpLotIncrease_Pct / 100.0));
   
   double calculatedLot = baseLot * multiplier;
   
   // Use a common symbol for lot normalization
   string refSymbol = (g_ValidSymbolCount > 0 && g_States[0].isValid) ? g_States[0].brokerSymbol : _Symbol;
   double step = SymbolInfoDouble(refSymbol, SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(refSymbol, SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(refSymbol, SYMBOL_VOLUME_MAX);
   
   calculatedLot = MathFloor(calculatedLot / step) * step;
   
   if(calculatedLot < min) calculatedLot = min;
   if(calculatedLot > max) calculatedLot = max;
   
   return(calculatedLot);
}

//+------------------------------------------------------------------+
//| CheckBasketExit for specific symbol                              |
//+------------------------------------------------------------------+
void CheckBasketExitForSymbol(int idx, ENUM_POSITION_TYPE type, int count)
{
   string symbol = g_States[idx].brokerSymbol;
   int magic = g_States[idx].magic;
   double adr = g_States[idx].adrValue;
   
   double totalLots = 0.0;
   double weightedPrice = 0.0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            weightedPrice += (price * vol);
            totalLots += vol;
         }
      }
   }
   
   if(totalLots <= 0) return;
   double avgPrice = weightedPrice / totalLots;
   
   double targetPct = InpStartTarget_ADR;
   if(count > 1)
   {
      targetPct = targetPct - ((count - 1) * InpTargetDecay_ADR);
   }
   
   double targetDistPoints = adr * (targetPct / 100.0);
   bool triggerClose = false;
   double currentPrice = 0.0;

   if(type == POSITION_TYPE_BUY)
   {
      currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(currentPrice >= (avgPrice + targetDistPoints)) triggerClose = true;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      currentPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(currentPrice <= (avgPrice - targetDistPoints)) triggerClose = true;
   }
   
   if(triggerClose) 
   {
      CloseAllPositionsForSymbol(symbol, magic);
      if(InpDebugMode)
         Print("Basket Exit: ", symbol, " @ ", currentPrice, " (Avg: ", avgPrice, ")");
   }
}

//+------------------------------------------------------------------+
//| CloseAllPositions for specific symbol                            |
//+------------------------------------------------------------------+
void CloseAllPositionsForSymbol(string symbol, int magic)
{
   trade.SetExpertMagicNumber(magic);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}
//+------------------------------------------------------------------+