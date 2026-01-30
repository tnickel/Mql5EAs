//+------------------------------------------------------------------+
//|                                                       CC_KI.mq5  |
//|                               Copyright 2025, Algorithm Factory  |
//|       Feature: CSV Signals + MQL5 Economic Calendar News Filter  |
//+------------------------------------------------------------------+
#property copyright "Algorithm Factory"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

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

input group "--- Direction Filter ---"
input ENUM_DIR_FILTER InpStartDirection = FILTER_BOTH; 

input group "--- Positions Management ---"
input double   InpFirstLot          = 0.03;        // Start Lotgröße
input double   InpGridLot           = 0.03;        // Grid Lotgröße
input int      InpMaxPositions      = 20;          // Max Anzahl Positionen
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
input double   InpEntryADR_Pct      = 60.0;       // Entry: % von ADR
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
input int      InpMagicNumber       = 101;      // WICHTIG: Unique ID pro Chart!

//--- GLOBALS ---
CTrade trade;
int handleStoch;
int handleRSI = INVALID_HANDLE;
double adrValue = 0.0;
double dayRange = 0.0;
datetime lastProcessedH1Bar = 0;

// Stats & Monitoring
double stat_HighWaterMark = 0.0;
double stat_MaxDD_Equity_Money = 0.0;
double stat_MaxDD_Equity_Percent = 0.0;
string stat_EA_Action     = "Initializing...";

// Runtime State for Filter
ENUM_DIR_FILTER g_currentFilter;

// CSV Signal Integration
bool g_CSVMode = false;
ENUM_DIR_FILTER g_CSVDirection = FILTER_NEUTRAL;
datetime g_LastCSVCheck = 0;
string g_CSVStatus = "Not checked yet";
string g_CSVSignalText = "N/A";

// News Filter
bool g_NewsBlockActive = false;
string g_NextNewsInfo = "Keine News";
datetime g_NextNewsTime = 0;
string g_NextNewsName = "";

// Performance Optimization
datetime g_LastNewsCheckTime = 0;
int g_NewsCheckInterval = 300; // News nur alle 5 Minuten prüfen
datetime g_LastADRCalcDay = 0;

// GUI Object Names
string btnBothName    = "Btn_Dir_Both";
string btnLongName    = "Btn_Dir_Long";
string btnShortName   = "Btn_Dir_Short";
string btnNeutralName = "Btn_Dir_Neutral";
string btnPanicName   = "Btn_Dir_Panic";

string lblMaxDDName   = "Lbl_Info_MaxDD";
string lblPosName     = "Lbl_Info_Pos";
string lblStatusName  = "Lbl_Info_Status";
string lblSetupName   = "Lbl_Info_Setup";
string lblCSVInfoName = "Lbl_CSV_Info";
string lblCSVTimeName = "Lbl_CSV_Time";
string lblNewsInfoName = "Lbl_News_Info";
string lblCSVDirectionName = "Lbl_CSV_Direction";

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Prüfe ob wir im Strategy Tester sind
   bool isInTester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   
   // Im Tester: FILTER_NEUTRAL macht keinen Sinn (würde alle Trades blockieren)
   // Setze auf FILTER_BOTH wenn NEUTRAL gewählt wurde
   if(isInTester && InpStartDirection == FILTER_NEUTRAL)
   {
      g_currentFilter = FILTER_BOTH;
      Print("WARNUNG: FILTER_NEUTRAL im Tester nicht sinnvoll - nutze FILTER_BOTH stattdessen!");
   }
   else
   {
      g_currentFilter = InpStartDirection;
   }
   
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

   // Indikatoren
   handleStoch = iStochastic(_Symbol, PERIOD_H1, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   if(handleStoch == INVALID_HANDLE) return(INIT_FAILED);

   if (InpEntryMode == MODE_RSI) 
   {
      handleRSI = iRSI(_Symbol, PERIOD_D1, InpRSI_Period, PRICE_CLOSE);
      if(handleRSI == INVALID_HANDLE) return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // GUI erstellen
   CreateButtons();
   CreateLabels();
   UpdateButtonsState();
   
   // CSV-Mode initialisieren
   // WICHTIG: Im Strategy Tester macht CSV-Steuerung keinen Sinn!
   if(InpUseCSVSignals && !isInTester)
   {
      if(InpDebugMode) Print("CSV-Signal Mode aktiviert. Prüfe Datei: ", InpCSVFilename);
      CheckCSVFile();
      
      // Timer für periodische CSV-Prüfung starten (in Sekunden)
      int timerSeconds = InpCSVCheckInterval * 60;
      if(!EventSetTimer(timerSeconds))
      {
         Print("FEHLER: Timer konnte nicht gestartet werden!");
         return(INIT_FAILED);
      }
      if(InpDebugMode) Print("Timer gestartet: Prüfe CSV alle ", InpCSVCheckInterval, " Minuten");
   }
   else
   {
      if(isInTester)
      {
         if(InpDebugMode) Print("CSV-Signal Mode DEAKTIVIERT im Strategy Tester (keine Datei-Zugriffe im Tester)");
         g_CSVMode = false;
      }
      else
      {
         if(InpDebugMode) Print("CSV-Signal Mode deaktiviert. Nutze manuelle Button-Steuerung.");
      }
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
      CheckUpcomingNews();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   
   EventKillTimer();
   
   ObjectDelete(0, btnBothName);
   ObjectDelete(0, btnLongName);
   ObjectDelete(0, btnShortName);
   ObjectDelete(0, btnNeutralName);
   ObjectDelete(0, btnPanicName);
   
   ObjectDelete(0, lblMaxDDName);
   ObjectDelete(0, lblPosName);
   ObjectDelete(0, lblStatusName);
   ObjectDelete(0, lblSetupName);
   ObjectDelete(0, lblCSVInfoName);
   ObjectDelete(0, lblCSVTimeName);
   ObjectDelete(0, lblNewsInfoName);
   ObjectDelete(0, lblCSVDirectionName);
   
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

   // --- PANIC-CHECK: Keine Trades im PANIC-Modus ---
   if(g_currentFilter == FILTER_PANIC)
   {
      stat_EA_Action = "PANIC-Modus: Alle Trades blockiert!";
      UpdateVisuals(0);
      return; // Stoppe alle weiteren Aktionen
   }

   // --- 2. PREPARATIONS ---
   ValidatePositionsAgainstFilter();
   CalculateADR_and_Range();
   CheckUpcomingNews();
   
   int openPositions = 0;
   ENUM_POSITION_TYPE openType = POSITION_TYPE_BUY;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            openPositions++;
            openType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         }
      }
   }

   // --- 3. STATUS LOGIC ---
   if(openPositions > 0) {
      double lastEntry = 0.0;
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
               lastEntry = PositionGetDouble(POSITION_PRICE_OPEN);
               break;
            }
         }
      }
      stat_EA_Action = StringFormat("Managing Basket (%s). Next Grid: %.5f", 
                                    (openType == POSITION_TYPE_BUY) ? "Long" : "Short", lastEntry);
   } else {
      if(InpEntryMode == MODE_ADR) {
         double neededRange = adrValue * (InpEntryADR_Pct / 100.0);
         if(dayRange < neededRange) {
            stat_EA_Action = StringFormat("Wait Range (%.5f < %.5f)", dayRange, neededRange);
         } else {
            stat_EA_Action = "ADR met. Scanning for Stoch Entry...";
         }
      } else if(InpEntryMode == MODE_RSI) {
         stat_EA_Action = "Scanning for RSI + Stoch Entry...";
      }
   }

   // --- 4. LOGIC EXECUTION ---
   if(openPositions > 0) {
      CheckBasketExit(openType, openPositions);
      
      datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
      if(currentH1Bar != lastProcessedH1Bar && openPositions < InpMaxPositions)
      {
         lastProcessedH1Bar = currentH1Bar;
         
         // News-Filter: Grid-Nachkauf blockieren wenn News anstehen
         if(g_NewsBlockActive)
         {
            stat_EA_Action = StringFormat("Grid blockiert: %s", g_NextNewsInfo);
         }
         else
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            double requiredDist = adrValue * (InpGridStep_ADR_Pct / 100.0);
            double slDistancePoints = adrValue * InpIndividualSL_ADR;
            
            double lastEntryPrice = 0.0;
            for(int i=PositionsTotal()-1; i>=0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
                     lastEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                     break;
                  }
               }
            }
            
            if(lastEntryPrice > 0) {
               bool gridOk = false;
               double dynGridLot = GetDynamicLot(InpGridLot);
               
               if(openType == POSITION_TYPE_SELL && ask >= (lastEntryPrice + requiredDist)) {
                  if(g_currentFilter == FILTER_SHORT || g_currentFilter == FILTER_BOTH) {
                     gridOk = true;
                     string comment = BuildTradeComment(false, openPositions + 1, "Short");
                     trade.Sell(dynGridLot, _Symbol, ask, ask + slDistancePoints, 0, comment);
                  }
               }
               if(openType == POSITION_TYPE_BUY && bid <= (lastEntryPrice - requiredDist)) {
                  if(g_currentFilter == FILTER_LONG || g_currentFilter == FILTER_BOTH) {
                     gridOk = true;
                     string comment = BuildTradeComment(false, openPositions + 1, "Long");
                     trade.Buy(dynGridLot, _Symbol, bid, bid - slDistancePoints, 0, comment);
                  }
               }
            }
         }
      }
   }

   // EOD Close
   if(InpUseEODClose) {
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(), tm);
      if(tm.hour == InpEODHour && tm.min >= InpEODMinute) {
         if(openPositions > 0) {
            CloseAllPositions();
            stat_EA_Action = "EOD Time. Closed all positions.";
         } else {
            stat_EA_Action = "EOD Time. Waiting for next day.";
         }
      }
   }

   // ENTRY LOGIC
   if(openPositions == 0)
   {
      datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
      if(currentH1Bar != lastProcessedH1Bar)
      {
         lastProcessedH1Bar = currentH1Bar;
         
         // News-Filter: Entry blockieren wenn News anstehen
         if(g_NewsBlockActive)
         {
            stat_EA_Action = StringFormat("Entry blockiert: %s", g_NextNewsInfo);
         }
         else
         {
            bool entryConditionMet = false;
            
            if(InpEntryMode == MODE_ADR) {
               double neededRange = adrValue * (InpEntryADR_Pct / 100.0);
               if(dayRange > neededRange) entryConditionMet = true;
            }
            else if(InpEntryMode == MODE_RSI) {
               double rsiValues[];
               if(CopyBuffer(handleRSI, 0, 0, 1, rsiValues) == 1) {
                  if(rsiValues[0] >= InpRSI_Upper || rsiValues[0] <= InpRSI_Lower) {
                     entryConditionMet = true;
                  }
               }
            }
            
            if(entryConditionMet) {
               double kBuffer[], dBuffer[];
               ArraySetAsSeries(kBuffer, true);
               ArraySetAsSeries(dBuffer, true);
               
               if(CopyBuffer(handleStoch, 0, 0, 3, kBuffer) < 3) return;
               if(CopyBuffer(handleStoch, 1, 0, 3, dBuffer) < 3) return;
               
               bool shortSignal = (kBuffer[2] >= InpStochUpper && kBuffer[1] < InpStochUpper);
               bool longSignal  = (kBuffer[2] <= InpStochLower && kBuffer[1] > InpStochLower);
               
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double slDistancePoints = adrValue * InpIndividualSL_ADR;
               double dynFirstLot = GetDynamicLot(InpFirstLot);
               
               if(shortSignal && (g_currentFilter == FILTER_SHORT || g_currentFilter == FILTER_BOTH)) {
                  string comment = BuildTradeComment(true, 1, "Short");
                  trade.Sell(dynFirstLot, _Symbol, ask, ask + slDistancePoints, 0, comment);
                  stat_EA_Action = "Entered Short";
               }
               if(longSignal && (g_currentFilter == FILTER_LONG || g_currentFilter == FILTER_BOTH)) {
                  string comment = BuildTradeComment(true, 1, "Long");
                  trade.Buy(dynFirstLot, _Symbol, bid, bid - slDistancePoints, 0, comment);
                  stat_EA_Action = "Entered Long";
               }
            }
         }
      }
   }

   // --- 5. VISUALS UPDATE ---
   UpdateVisuals(openPositions);
}

//+------------------------------------------------------------------+
//| Chart Event Handler                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_CSVMode)
      {
         Print("WARNUNG: Manuelle Button-Steuerung deaktiviert. CSV-Datei steuert die Richtung!");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw();
         return;
      }
      
      if(sparam == btnBothName)
      {
         g_currentFilter = FILTER_BOTH;
         UpdateButtonsState();
         ValidatePositionsAgainstFilter();
      }
      else if(sparam == btnLongName)
      {
         g_currentFilter = FILTER_LONG;
         UpdateButtonsState();
         ValidatePositionsAgainstFilter();
      }
      else if(sparam == btnShortName)
      {
         g_currentFilter = FILTER_SHORT;
         UpdateButtonsState();
         ValidatePositionsAgainstFilter();
      }
      else if(sparam == btnNeutralName)
      {
         g_currentFilter = FILTER_NEUTRAL;
         UpdateButtonsState();
         ValidatePositionsAgainstFilter();
      }
      else if(sparam == btnPanicName)
      {
         g_currentFilter = FILTER_PANIC;
         CloseAllPositions();
         Print("PANIC-Modus manuell aktiviert - Alle Positionen geschlossen!");
         UpdateButtonsState();
         ValidatePositionsAgainstFilter();
      }
      
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| CSV Integration Functions                                       |
//+------------------------------------------------------------------+
void CheckCSVFile()
{
   g_LastCSVCheck = TimeCurrent();
   
   int fileHandle = FileOpen(InpCSVFilename, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(fileHandle == INVALID_HANDLE)
   {
      g_CSVMode = false;
      g_CSVStatus = "Datei nicht gefunden";
      g_CSVSignalText = "FILE NOT FOUND";
      Print("FEHLER: CSV-Datei nicht gefunden: ", InpCSVFilename);
      Print("Nutze manuelle Button-Steuerung als Fallback.");
      UpdateButtonsState();
      return;
   }
   
   bool foundSymbol = false;
   string newSignal = "NEUTRAL";
   string matchedCsvSymbol = "";
   int lineNumber = 0;
   
   // DEBUG: Nur bei aktiviertem Debug-Modus
   if(InpDebugMode)
   {
      Print("========================================");
      Print("CSV-Check: Suche Symbol '", _Symbol, "'");
      Print("========================================");
   }
   
   while(!FileIsEnding(fileHandle))
   {
      string line = FileReadString(fileHandle);
      lineNumber++;
      
      // Entferne Carriage Return und Whitespace
      StringReplace(line, "\r", "");
      StringReplace(line, "\n", "");
      StringTrimLeft(line);
      StringTrimRight(line);
      
      // Überspringe leere Zeilen
      if(line == "") 
      {
         if(InpDebugMode) Print("Zeile ", lineNumber, ": [LEER]");
         continue;
      }
      
      // Überspringe Header-Zeile
      if(lineNumber == 1 || StringFind(line, "Waehrungspaar") >= 0 || StringFind(line, "Letztes_Signal") >= 0)
      {
         if(InpDebugMode) Print("Zeile ", lineNumber, ": [HEADER] ", line);
         continue;
      }
      
      // Debug: Zeige die gelesene Zeile (nur im Debug-Modus)
      if(InpDebugMode) Print("Zeile ", lineNumber, ": '", line, "'");
      
      string parts[];
      int count = StringSplit(line, ';', parts);
      
      if(count >= 2)
      {
         string csvSymbol = parts[0];
         StringTrimLeft(csvSymbol);
         StringTrimRight(csvSymbol);
         
         string csvSignal = parts[1];
         StringTrimLeft(csvSignal);
         StringTrimRight(csvSignal);
         StringToUpper(csvSignal);
         
         // Debug: Zeige geparste Werte (nur im Debug-Modus)
         if(InpDebugMode) Print("  -> Parsed: Symbol='", csvSymbol, "' Signal='", csvSignal, "'");
         
         // VERBESSERTE VERGLEICHSLOGIK:
         bool isMatch = false;
         
         if(csvSymbol == _Symbol)
         {
            // Exakter Match
            isMatch = true;
            if(InpDebugMode) Print("  -> EXAKTER MATCH!");
         }
         else if(StringFind(_Symbol, csvSymbol) == 0)
         {
            // Symbol beginnt mit CSV-Symbol (z.B. NZDUSDm vs NZDUSD)
            isMatch = true;
            if(InpDebugMode) Print("  -> PREFIX MATCH!");
         }
         else if(StringFind(_Symbol, csvSymbol + ".") == 0 || 
                 StringFind(_Symbol, csvSymbol + "#") == 0 ||
                 StringFind(_Symbol, csvSymbol + "m") == 0)
         {
            // Symbol hat bekanntes Suffix
            isMatch = true;
            if(InpDebugMode) Print("  -> SUFFIX MATCH!");
         }
         else
         {
            if(InpDebugMode) Print("  -> Kein Match (suche '", _Symbol, "' vs gefunden '", csvSymbol, "')");
         }
         
         if(isMatch)
         {
            foundSymbol = true;
            newSignal = csvSignal;
            matchedCsvSymbol = csvSymbol;
            
            if(InpDebugMode)
            {
               Print("========================================");
               Print("ERFOLG! MT5-Symbol: '", _Symbol, "' = CSV-Symbol: '", csvSymbol, "' Signal: ", csvSignal);
               Print("========================================");
            }
            break;
         }
      }
      else
      {
         if(InpDebugMode) Print("  -> FEHLER: Konnte Zeile nicht in 2 Teile splitten (count=", count, ")");
      }
   }
   
   FileClose(fileHandle);
   
   if(!foundSymbol)
   {
      g_CSVMode = true;
      g_CSVStatus = "Symbol nicht in CSV gefunden";
      g_CSVSignalText = "NOT FOUND";
      g_CSVDirection = FILTER_NEUTRAL;
      
      // Fehler IMMER ausgeben (nicht nur im Debug-Modus)
      Print("WARNUNG: Symbol '", _Symbol, "' nicht in CSV gefunden! (", lineNumber, " Zeilen gelesen)");
      if(InpDebugMode)
      {
         Print("Prüfe das Expert-Log oben für Details.");
      }
      
      g_currentFilter = FILTER_NEUTRAL;
      UpdateButtonsState();
      return;
   }
   
   // Signal parsen
   ENUM_DIR_FILTER oldFilter = g_currentFilter;
   ENUM_DIR_FILTER newFilter = FILTER_NEUTRAL;
   
   if(newSignal == "BUY")
   {
      newFilter = FILTER_LONG;
      g_CSVSignalText = "BUY";
   }
   else if(newSignal == "SELL")
   {
      newFilter = FILTER_SHORT;
      g_CSVSignalText = "SELL";
   }
   else if(newSignal == "PANIC")
   {
      newFilter = FILTER_PANIC;
      g_CSVSignalText = "PANIC";
      Print("!!! PANIC-Signal empfangen für ", _Symbol, " - Schließe ALLE Positionen !!!");
   }
   else
   {
      newFilter = FILTER_NEUTRAL;
      g_CSVSignalText = "NEUTRAL";
   }
   
   g_CSVMode = true;
   g_CSVDirection = newFilter;
   g_CSVStatus = "CSV erfolgreich gelesen";
   
   // Erfolg IMMER ausgeben (kompakt, nicht nur im Debug-Modus)
   Print("CSV OK: '", _Symbol, "' → Signal: ", g_CSVSignalText);
   
   // Ausführliche Details nur im Debug-Modus
   if(InpDebugMode)
   {
      Print("========================================");
      Print("CSV ERFOLGREICH GELESEN!");
      Print("MT5-Symbol: '", _Symbol, "'");
      Print("CSV-Symbol: '", matchedCsvSymbol, "'");
      Print("Signal:     ", g_CSVSignalText);
      Print("Filter:     ", (newFilter == FILTER_LONG ? "LONG" : (newFilter == FILTER_SHORT ? "SHORT" : (newFilter == FILTER_PANIC ? "PANIC" : "NEUTRAL"))));
      Print("========================================");
   }
   
   // PANIC: Sofort alle Positionen schließen
   if(newFilter == FILTER_PANIC)
   {
      CloseAllPositions();
      Print("PANIC: Alle Positionen für ", _Symbol, " wurden geschlossen!");
   }
   // Wenn Signal geändert hat: Gegenpositionen schließen
   else if(oldFilter != newFilter)
   {
      CloseOppositePositions(oldFilter, newFilter);
   }
   
   g_currentFilter = newFilter;
   UpdateButtonsState();
}

//+------------------------------------------------------------------+
//| CloseOppositePositions                                          |
//+------------------------------------------------------------------+
void CloseOppositePositions(ENUM_DIR_FILTER oldDir, ENUM_DIR_FILTER newDir)
{
   // PANIC als Ziel: Alle Positionen schließen
   if(newDir == FILTER_PANIC)
   {
      Print("PANIC-Modus aktiviert - Schließe ALLE Positionen für ", _Symbol);
      CloseAllPositions();
      return;
   }
   
   // NEUTRAL als Ziel: Nichts schließen (einfach warten)
   if(newDir == FILTER_NEUTRAL)
   {
      Print("Neues Signal: NEUTRAL - halte bestehende Positionen, keine neuen Trades");
      return;
   }
   
   // Von NEUTRAL oder PANIC kommend: Nichts zu schließen (keine oder keine erlaubten Positionen)
   if(oldDir == FILTER_NEUTRAL || oldDir == FILTER_PANIC)
   {
      Print("Signal wechselt von ", (oldDir == FILTER_PANIC ? "PANIC" : "NEUTRAL"), " zu ", (newDir == FILTER_LONG) ? "BUY" : "SELL");
      return;
   }
   
   // BOTH sollte bei CSV-Steuerung nicht vorkommen
   if(oldDir == FILTER_BOTH || newDir == FILTER_BOTH)
   {
      Print("WARNUNG: FILTER_BOTH sollte bei CSV-Steuerung nicht vorkommen!");
      return;
   }
   
   // Gleiche Richtung: Nichts zu tun
   if(oldDir == newDir)
   {
      return;
   }
   
   // BUY -> SELL oder SELL -> BUY: Gegenpositionen schließen
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool closeIt = false;
            
            if(newDir == FILTER_LONG && type == POSITION_TYPE_SELL)
            {
               closeIt = true;
               Print("Schließe Short-Position #", ticket, " wegen neuem BUY-Signal");
            }
            else if(newDir == FILTER_SHORT && type == POSITION_TYPE_BUY)
            {
               closeIt = true;
               Print("Schließe Long-Position #", ticket, " wegen neuem SELL-Signal");
            }
            
            if(closeIt)
            {
               trade.PositionClose(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| News Filter Functions - OPTIMIERT!                              |
//+------------------------------------------------------------------+
void CheckUpcomingNews()
{
   if(!InpUseNewsFilter)
   {
      g_NewsBlockActive = false;
      g_NextNewsInfo = "Deaktiviert";
      return;
   }
   
   // OPTIMIERUNG: Nur alle X Sekunden prüfen statt bei jedem Tick!
   datetime currentTime = TimeCurrent();
   if(currentTime - g_LastNewsCheckTime < g_NewsCheckInterval && g_LastNewsCheckTime > 0)
   {
      return; // Nutze gecachte Werte
   }
   g_LastNewsCheckTime = currentTime;
   
   datetime serverTime = TimeTradeServer();
   
   datetime dateFrom = serverTime - (InpMinutesAfterNews * 60);
   datetime dateTo = serverTime + (InpMinutesBeforeNews * 60);
   
   string currencyBase = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string currencyQuote = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   ENUM_CALENDAR_EVENT_IMPORTANCE minImportance = (InpNewsImportance == NEWS_HIGH_ONLY) 
      ? CALENDAR_IMPORTANCE_HIGH 
      : CALENDAR_IMPORTANCE_MODERATE;
   
   MqlCalendarValue values[];
   datetime nearestNewsTime = 0;
   string nearestNewsName = "";
   ENUM_CALENDAR_EVENT_IMPORTANCE nearestImportance = CALENDAR_IMPORTANCE_NONE;
   
   // Base-Währung prüfen
   if(CalendarValueHistory(values, dateFrom, dateTo, NULL, currencyBase))
   {
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.time_mode != CALENDAR_TIMEMODE_DATETIME && event.time_mode != CALENDAR_TIMEMODE_DATE)
               continue;
            
            if(event.importance < minImportance)
               continue;
            
            if(nearestNewsTime == 0 || MathAbs((int)(values[i].time - serverTime)) < MathAbs((int)(nearestNewsTime - serverTime)))
            {
               nearestNewsTime = values[i].time;
               nearestNewsName = event.name;
               nearestImportance = event.importance;
            }
         }
      }
   }
   
   // Quote-Währung prüfen (wenn aktiviert)
   if(InpNewsFilterBothCurrencies && currencyBase != currencyQuote)
   {
      if(CalendarValueHistory(values, dateFrom, dateTo, NULL, currencyQuote))
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               if(event.time_mode != CALENDAR_TIMEMODE_DATETIME && event.time_mode != CALENDAR_TIMEMODE_DATE)
                  continue;
               
               if(event.importance < minImportance)
                  continue;
               
               if(nearestNewsTime == 0 || MathAbs((int)(values[i].time - serverTime)) < MathAbs((int)(nearestNewsTime - serverTime)))
               {
                  nearestNewsTime = values[i].time;
                  nearestNewsName = event.name;
                  nearestImportance = event.importance;
               }
            }
         }
      }
   }
   
   // Auswertung
   if(nearestNewsTime > 0)
   {
      int minutesDiff = (int)((nearestNewsTime - serverTime) / 60);
      
      string impText = "";
      switch(nearestImportance)
      {
         case CALENDAR_IMPORTANCE_HIGH: impText = "HIGH"; break;
         case CALENDAR_IMPORTANCE_MODERATE: impText = "MEDIUM"; break;
         case CALENDAR_IMPORTANCE_LOW: impText = "LOW"; break;
         default: impText = "NONE"; break;
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
//| Display Logic - IM TESTER DEAKTIVIERT!                          |
//+------------------------------------------------------------------+
void UpdateVisuals(int positions)
{
   // OPTIMIERUNG: Im Strategy Tester keine GUI-Updates (bringt nichts und kostet Zeit)
   static bool isInTester = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));
   if(isInTester) return;
   
   // Zeile 1: MaxDD
   string txtDD = StringFormat("MaxDD zu HWM-Balance in %%: %.2f%%", stat_MaxDD_Equity_Percent);
   ObjectSetString(0, lblMaxDDName, OBJPROP_TEXT, txtDD);

   // Zeile 2: Positionen
   string txtPos = StringFormat("Anzahl an Positionen: %d", positions);
   ObjectSetString(0, lblPosName, OBJPROP_TEXT, txtPos);
   
   // Zeile 3: Status
   string txtStatus = StringFormat("Status: %s", stat_EA_Action);
   ObjectSetString(0, lblStatusName, OBJPROP_TEXT, txtStatus);
   
   // Zeile 4: Config / Setup Info (Mit Magic Number!)
   string txtSetup = StringFormat("Config: Cap %.0f | Grid %.0f%% | Target %.0f%% | Lot %.2f | Magic %d", 
                                   InpEntryADR_Pct, InpGridStep_ADR_Pct, InpStartTarget_ADR, InpFirstLot, InpMagicNumber);
   ObjectSetString(0, lblSetupName, OBJPROP_TEXT, txtSetup);
   
   // Zeile 5: CSV Info
   if(InpUseCSVSignals)
   {
      string modeText = g_CSVMode ? "AKTIV" : "INAKTIV";
      color modeColor = g_CSVMode ? clrLimeGreen : clrOrange;
      
      string txtCSVInfo = StringFormat("CSV-Mode: %s | Signal: %s | Status: %s", 
                                       modeText, g_CSVSignalText, g_CSVStatus);
      ObjectSetString(0, lblCSVInfoName, OBJPROP_TEXT, txtCSVInfo);
      ObjectSetInteger(0, lblCSVInfoName, OBJPROP_COLOR, modeColor);
      
      // Zeile 6: Letzte CSV-Prüfung
      string timeText = "Noch nie";
      if(g_LastCSVCheck > 0)
      {
         timeText = TimeToString(g_LastCSVCheck, TIME_DATE|TIME_MINUTES);
      }
      string txtCSVTime = StringFormat("Letzte CSV-Prüfung: %s (Interval: %d Min)", timeText, InpCSVCheckInterval);
      ObjectSetString(0, lblCSVTimeName, OBJPROP_TEXT, txtCSVTime);
   }
   else
   {
      ObjectSetString(0, lblCSVInfoName, OBJPROP_TEXT, "CSV-Mode: DEAKTIVIERT (Nutze manuelle Buttons)");
      ObjectSetInteger(0, lblCSVInfoName, OBJPROP_COLOR, clrGray);
      ObjectSetString(0, lblCSVTimeName, OBJPROP_TEXT, "");
   }
   
   // Zeile 7: News-Filter Info
   if(InpUseNewsFilter)
   {
      string newsFilterText = "";
      color newsColor = clrLimeGreen;
      
      if(g_NewsBlockActive)
      {
         newsFilterText = StringFormat("News-Filter: BLOCKIERT | %s", g_NextNewsInfo);
         newsColor = clrRed;
      }
      else
      {
         newsFilterText = StringFormat("News-Filter: %s", g_NextNewsInfo);
         newsColor = clrLimeGreen;
      }
      
      ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, newsFilterText);
      ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, newsColor);
   }
   else
   {
      ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, "News-Filter: DEAKTIVIERT");
      ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, clrGray);
   }
   
   // Zeile 8: CSV Traderichtung
   if(InpUseCSVSignals && g_CSVMode)
   {
      string directionText = "";
      color directionColor = clrYellow;
      
      if(g_CSVSignalText == "NOT FOUND")
      {
         directionText = StringFormat("%s: NICHT GEFUNDEN IN CSV → KEINE TRADES", _Symbol);
         directionColor = clrOrange;
      }
      else
      {
         switch(g_currentFilter)
         {
            case FILTER_LONG:
               directionText = StringFormat("%s: BUY → NUR LONG TRADES ERLAUBT", _Symbol);
               directionColor = clrLimeGreen;
               break;
            case FILTER_SHORT:
               directionText = StringFormat("%s: SELL → NUR SHORT TRADES ERLAUBT", _Symbol);
               directionColor = clrRed;
               break;
            case FILTER_NEUTRAL:
               directionText = StringFormat("%s: NEUTRAL → KEINE NEUEN TRADES", _Symbol);
               directionColor = clrYellow;
               break;
            case FILTER_PANIC:
               directionText = StringFormat("%s: !!! PANIC !!! → ALLE TRADES GESCHLOSSEN, KEINE NEUEN TRADES", _Symbol);
               directionColor = clrRed;
               break;
         }
      }
      
      ObjectSetString(0, lblCSVDirectionName, OBJPROP_TEXT, directionText);
      ObjectSetInteger(0, lblCSVDirectionName, OBJPROP_COLOR, directionColor);
   }
   else if(InpUseCSVSignals && !g_CSVMode)
   {
      ObjectSetString(0, lblCSVDirectionName, OBJPROP_TEXT, StringFormat("%s: CSV-DATEI NICHT GEFUNDEN → WARNUNG", _Symbol));
      ObjectSetInteger(0, lblCSVDirectionName, OBJPROP_COLOR, clrOrange);
   }
   else
   {
      ObjectSetString(0, lblCSVDirectionName, OBJPROP_TEXT, "CSV-Steuerung: DEAKTIVIERT (Manuelle Buttons aktiv)");
      ObjectSetInteger(0, lblCSVDirectionName, OBJPROP_COLOR, clrGray);
   }
}

//+------------------------------------------------------------------+
//| GUI Helper                                                       |
//+------------------------------------------------------------------+
void CreateLabels()
{
   int x = 20;
   int fontSize = 11;
   string font = "Arial Bold";
   color c = clrWhite;
   
   // Label 1: MaxDD (Y=50, da Buttons bei Y=5 ca 30px hoch sind)
   CreateSingleLabel(lblMaxDDName, x, 50, "MaxDD: 0.0%", fontSize, font, c);
   
   // Label 2: Positionen
   CreateSingleLabel(lblPosName, x, 75, "Anzahl: 0", fontSize, font, c);
   
   // Label 3: Status
   CreateSingleLabel(lblStatusName, x, 100, "Status: Init", fontSize, font, c);

   // Label 4: Setup Info
   CreateSingleLabel(lblSetupName, x, 125, "Setup: ...", fontSize, font, c);
   
   // Label 5: CSV Info
   CreateSingleLabel(lblCSVInfoName, x, 150, "CSV: Init...", fontSize, font, clrYellow);
   
   // Label 6: CSV Time
   CreateSingleLabel(lblCSVTimeName, x, 175, "CSV Check: ...", fontSize, font, clrWhite);
   
   // Label 7: News Info
   CreateSingleLabel(lblNewsInfoName, x, 200, "News: Init...", fontSize, font, clrYellow);
   
   // Label 8: CSV Traderichtung
   CreateSingleLabel(lblCSVDirectionName, x, 225, "CSV-Richtung: N/A", fontSize+2, font, clrYellow);
}

//+------------------------------------------------------------------+
//| CreateSingleLabel                                               |
//+------------------------------------------------------------------+
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
//| CreateButtons                                                    |
//+------------------------------------------------------------------+
void CreateButtons()
{
   int xBase = 20;
   int yBase = 5; // Ganz oben
   
   int width = 90;
   int height = 30;
   int gap = 5;

   CreateSingleButton(btnBothName, xBase, yBase, width, height, "BOTH");
   CreateSingleButton(btnLongName, xBase + width + gap, yBase, width, height, "LONG");
   CreateSingleButton(btnShortName, xBase + (width + gap)*2, yBase, width, height, "SHORT");
   CreateSingleButton(btnNeutralName, xBase + (width + gap)*3, yBase, width, height, "NEUTRAL");
   CreateSingleButton(btnPanicName, xBase + (width + gap)*4, yBase, width, height, "PANIC");
}

//+------------------------------------------------------------------+
//| CreateSingleButton                                              |
//+------------------------------------------------------------------+
void CreateSingleButton(string name, int x, int y, int w, int h, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrSilver);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   }
}

//+------------------------------------------------------------------+
//| UpdateButtonsState                                              |
//+------------------------------------------------------------------+
void UpdateButtonsState()
{
   color activeColor = clrSilver;
   color inactiveColor = clrWhiteSmoke;
   color disabledColor = clrDarkGray;
   
   // Wenn CSV-Mode aktiv: Alle Buttons ausgrauen
   if(g_CSVMode)
   {
      ObjectSetInteger(0, btnBothName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnLongName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnShortName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnNeutralName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnPanicName, OBJPROP_BGCOLOR, disabledColor);
      
      ObjectSetString(0, btnBothName, OBJPROP_TEXT, "BOTH (CSV)");
      ObjectSetString(0, btnLongName, OBJPROP_TEXT, "LONG (CSV)");
      ObjectSetString(0, btnShortName, OBJPROP_TEXT, "SHORT (CSV)");
      ObjectSetString(0, btnNeutralName, OBJPROP_TEXT, "NEUTRAL (CSV)");
      ObjectSetString(0, btnPanicName, OBJPROP_TEXT, "PANIC (CSV)");
      
      switch(g_currentFilter)
      {
         case FILTER_BOTH:
            ObjectSetInteger(0, btnBothName, OBJPROP_BGCOLOR, clrGray);
            break;
         case FILTER_LONG:
            ObjectSetInteger(0, btnLongName, OBJPROP_BGCOLOR, clrGray);
            break;
         case FILTER_SHORT:
            ObjectSetInteger(0, btnShortName, OBJPROP_BGCOLOR, clrGray);
            break;
         case FILTER_NEUTRAL:
            ObjectSetInteger(0, btnNeutralName, OBJPROP_BGCOLOR, clrGray);
            break;
         case FILTER_PANIC:
            ObjectSetInteger(0, btnPanicName, OBJPROP_BGCOLOR, clrRed);
            break;
      }
   }
   else
   {
      ObjectSetString(0, btnBothName, OBJPROP_TEXT, "BOTH");
      ObjectSetString(0, btnLongName, OBJPROP_TEXT, "LONG");
      ObjectSetString(0, btnShortName, OBJPROP_TEXT, "SHORT");
      ObjectSetString(0, btnNeutralName, OBJPROP_TEXT, "NEUTRAL");
      ObjectSetString(0, btnPanicName, OBJPROP_TEXT, "PANIC");
      
      color cBoth    = (g_currentFilter == FILTER_BOTH)    ? clrSkyBlue : inactiveColor;
      color cLong    = (g_currentFilter == FILTER_LONG)    ? clrLimeGreen : inactiveColor;
      color cShort   = (g_currentFilter == FILTER_SHORT)   ? clrTomato : inactiveColor;
      color cNeutral = (g_currentFilter == FILTER_NEUTRAL) ? clrKhaki : inactiveColor;
      color cPanic   = (g_currentFilter == FILTER_PANIC)   ? clrRed : inactiveColor;
      
      ObjectSetInteger(0, btnBothName, OBJPROP_BGCOLOR, cBoth);
      ObjectSetInteger(0, btnLongName, OBJPROP_BGCOLOR, cLong);
      ObjectSetInteger(0, btnShortName, OBJPROP_BGCOLOR, cShort);
      ObjectSetInteger(0, btnNeutralName, OBJPROP_BGCOLOR, cNeutral);
      ObjectSetInteger(0, btnPanicName, OBJPROP_BGCOLOR, cPanic);
   }
   
   ObjectSetInteger(0, btnBothName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnLongName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnShortName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnNeutralName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnPanicName, OBJPROP_STATE, false);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string BuildTradeComment(bool isFirstEntry, int positionNumber, string direction)
{
   // CSV-Status
   string csvPart = g_CSVMode ? StringFormat("CSV:%s", g_CSVSignalText) : "Manual";
   
   // Entry-Typ
   string entryType = "";
   if(isFirstEntry)
   {
      entryType = (InpEntryMode == MODE_ADR) ? "ADR" : "RSI";
   }
   else
   {
      entryType = "Grid";
   }
   
   // Vollständiger Comment
   string comment = StringFormat("%s | %s-%s #%d", csvPart, entryType, direction, positionNumber);
   
   return comment;
}

//+------------------------------------------------------------------+
//| ADR Berechnung - OPTIMIERT! NUR 1x PRO TAG                      |
//+------------------------------------------------------------------+
void CalculateADR_and_Range()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   
   // OPTIMIERUNG: ADR nur einmal pro Tag berechnen!
   if(currentDay != g_LastADRCalcDay || adrValue == 0)
   {
      g_LastADRCalcDay = currentDay;
      
      double sum = 0;
      for(int i=1; i<=InpADRPeriod; i++) 
         sum += (iHigh(_Symbol, PERIOD_D1, i) - iLow(_Symbol, PERIOD_D1, i));
      
      adrValue = sum / InpADRPeriod;
      if(adrValue == 0) adrValue = 100 * _Point;
   }
   
   // DayRange muss aktuell bleiben (aber viel schneller als ADR-Calc)
   dayRange = iHigh(_Symbol, PERIOD_D1, 0) - iLow(_Symbol, PERIOD_D1, 0);
}

//+------------------------------------------------------------------+
//| ValidatePositionsAgainstFilter                                  |
//+------------------------------------------------------------------+
void ValidatePositionsAgainstFilter()
{
   if(g_currentFilter == FILTER_BOTH || g_currentFilter == FILTER_NEUTRAL) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool closeIt = false;
            if(g_currentFilter == FILTER_LONG && type == POSITION_TYPE_SELL) closeIt = true;
            if(g_currentFilter == FILTER_SHORT && type == POSITION_TYPE_BUY) closeIt = true;
            if(closeIt) trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| GetDynamicLot                                                   |
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
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   calculatedLot = MathFloor(calculatedLot / step) * step;
   
   if(calculatedLot < min) calculatedLot = min;
   if(calculatedLot > max) calculatedLot = max;
   
   return(calculatedLot);
}

//+------------------------------------------------------------------+
//| CheckBasketExit                                                 |
//+------------------------------------------------------------------+
void CheckBasketExit(ENUM_POSITION_TYPE type, int count)
{
   double totalLots = 0.0;
   double weightedPrice = 0.0;
   
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
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
   if (count > 1) {
      targetPct = targetPct - ((count - 1) * InpTargetDecay_ADR);
   }
   
   double targetDistPoints = adrValue * (targetPct / 100.0);
   bool triggerClose = false;
   double currentPrice = 0.0;

   if(type == POSITION_TYPE_BUY)
   {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(currentPrice >= (avgPrice + targetDistPoints)) triggerClose = true;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(currentPrice <= (avgPrice - targetDistPoints)) triggerClose = true;
   }
   
   if(triggerClose) CloseAllPositions();
}

//+------------------------------------------------------------------+
//| CloseAllPositions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            trade.PositionClose(ticket);
         }
      }
   }
}