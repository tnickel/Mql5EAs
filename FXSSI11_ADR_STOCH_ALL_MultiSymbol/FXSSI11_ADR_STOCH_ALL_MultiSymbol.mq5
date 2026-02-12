//+------------------------------------------------------------------+
//|                              FXSSI11_ADR_STOCH_ALL_MultiSymbol.mq5 |
//|                               Copyright 2025, Algorithm Factory  |
//|       Feature: Multi-Symbol CSV Trading + News Filter            |
//+------------------------------------------------------------------+
#property copyright "Algorithm Factory"
#property link      ""
#property version   "2.00"
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
   FILTER_NEUTRAL = 3  // Neutral
};

enum ENUM_NEWS_IMPORTANCE
{
   NEWS_HIGH_ONLY = 0,      // Nur High Impact
   NEWS_MEDIUM_HIGH = 1     // Medium + High Impact
};

//--- Multi-Symbol Struktur ---
struct SymbolTradeInfo
{
   string            symbol;           // CSV-Symbol z.B. "EURUSD"
   string            brokerSymbol;     // Broker-Symbol z.B. "EURUSDm"
   int               magic;            // 1000, 1001, 1002, ...
   ENUM_DIR_FILTER   direction;        // BUY/SELL/NEUTRAL aus CSV
   int               handleStoch;      // Stochastic Handle
   int               handleRSI;        // RSI Handle  
   double            adrValue;         // ADR-Wert
   double            dayRange;         // Tages-Range
   datetime          lastH1Bar;        // Letzter verarbeiteter H1 Bar
   datetime          lastADRCalcDay;   // Letzte ADR-Berechnung
   int               openPositions;    // Anzahl offener Positionen
   ENUM_POSITION_TYPE openType;        // Typ der offenen Positionen
   bool              newsBlocked;      // News-Filter aktiv?
   string            newsInfo;         // News-Info Text
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

input group "--- Direction Filter (nur wenn CSV deaktiviert) ---"
input ENUM_DIR_FILTER InpStartDirection = FILTER_BOTH; 

input group "--- Positions Management ---"
input double   InpFirstLot          = 4.0;         // Start Lotgröße (Double)
input double   InpGridLot           = 4.0;         // Grid Lotgröße (Double)
input int      InpMaxPositions      = 20;          // Max Anzahl Positionen PRO SYMBOL
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
input double   InpGridStep_ADR_Pct  = 20.0;        // Grid Step (Double)

input group "--- RSI Settings (D1) ---"
input int      InpRSI_Period        = 14;          // RSI Periode
input int      InpRSI_Upper         = 70;          // RSI Upper
input int      InpRSI_Lower         = 30;          // RSI Lower

input group "--- Dynamic Exit Targets ---"
input double   InpStartTarget_ADR   = 20.0;        // Ziel bei Start (Double)
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

input group "--- Multi-Symbol Settings ---"
input int      InpBaseMagicNumber   = 1000;        // Basis Magic Number (1000, 1001, ...)

//--- GLOBALS ---
CTrade trade;

// Multi-Symbol Array
SymbolTradeInfo g_Symbols[];
int g_SymbolCount = 0;

// Stats & Monitoring
double stat_HighWaterMark = 0.0;
double stat_MaxDD_Equity_Money = 0.0;
double stat_MaxDD_Equity_Percent = 0.0;
string stat_EA_Action = "Initializing...";

// CSV Signal Integration
bool g_CSVMode = false;
datetime g_LastCSVCheck = 0;
string g_CSVStatus = "Not checked yet";

// News Filter Cache
datetime g_LastNewsCheckTime = 0;
int g_NewsCheckInterval = 300; // News nur alle 5 Minuten prüfen

// GUI Object Names
string btnBothName    = "Btn_Dir_Both";
string btnLongName    = "Btn_Dir_Long";
string btnShortName   = "Btn_Dir_Short";
string btnNeutralName = "Btn_Dir_Neutral";

string lblMaxDDName   = "Lbl_Info_MaxDD";
string lblPosName     = "Lbl_Info_Pos";
string lblStatusName  = "Lbl_Info_Status";
string lblSetupName   = "Lbl_Info_Setup";
string lblCSVInfoName = "Lbl_CSV_Info";
string lblCSVTimeName = "Lbl_CSV_Time";
string lblNewsInfoName = "Lbl_News_Info";

// Symbol-Übersicht Labels (dynamisch)
string lblSymbolPrefix = "Lbl_Symbol_";

//+------------------------------------------------------------------+
//| Ausgeschlossene Symbole (Gold/Silber)                           |
//+------------------------------------------------------------------+
bool IsExcludedSymbol(string symbol)
{
   string upperSymbol = symbol;
   StringToUpper(upperSymbol);
   
   if(StringFind(upperSymbol, "XAU") >= 0) return true;  // XAUUSD
   if(StringFind(upperSymbol, "XAG") >= 0) return true;  // XAGUSD
   if(upperSymbol == "GOLD") return true;
   if(upperSymbol == "SILVER") return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Finde Broker-Symbol mit möglichen Suffixen                      |
//+------------------------------------------------------------------+
string FindBrokerSymbol(string csvSymbol)
{
   bool isCustom = false;  // Variable für SymbolExist Referenz-Parameter
   
   // Erst exakten Match versuchen
   if(SymbolExist(csvSymbol, isCustom))
   {
      SymbolSelect(csvSymbol, true);
      return csvSymbol;
   }
   
   // Bekannte Suffixe probieren
   string suffixes[] = {"m", ".", "#", ".a", ".b", "_", ".pro", ".raw"};
   
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      string testSymbol = csvSymbol + suffixes[i];
      if(SymbolExist(testSymbol, isCustom))
      {
         SymbolSelect(testSymbol, true);
         return testSymbol;
      }
   }
   
   // Auch mit Lowercase probieren
   string lowerSymbol = csvSymbol;
   StringToLower(lowerSymbol);
   if(SymbolExist(lowerSymbol, isCustom))
   {
      SymbolSelect(lowerSymbol, true);
      return lowerSymbol;
   }
   
   return "";  // Nicht gefunden
}

//+------------------------------------------------------------------+
//| Symbol aktivieren (MarketWatch)                                  |
//+------------------------------------------------------------------+
bool EnsureSymbolEnabled(string brokerSymbol)
{
   if(brokerSymbol == "") return false;
   
   bool isCustom = false;  // Variable für SymbolExist Referenz-Parameter
   
   // Prüfen ob Symbol existiert
   if(!SymbolExist(brokerSymbol, isCustom))
   {
      Print("FEHLER: Symbol ", brokerSymbol, " existiert nicht beim Broker!");
      return false;
   }
   
   // Symbol in MarketWatch aktivieren
   if(!SymbolSelect(brokerSymbol, true))
   {
      Print("FEHLER: Konnte Symbol ", brokerSymbol, " nicht aktivieren!");
      return false;
   }
   
   // Kurz warten bis Daten verfügbar sind
   int attempts = 0;
   while(SymbolInfoDouble(brokerSymbol, SYMBOL_BID) == 0 && attempts < 10)
   {
      Sleep(100);
      attempts++;
   }
   
   if(SymbolInfoDouble(brokerSymbol, SYMBOL_BID) == 0)
   {
      Print("WARNUNG: Keine Kursdaten für ", brokerSymbol, " - Symbol möglicherweise geschlossen");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Initialisiere Symbole aus CSV                                    |
//+------------------------------------------------------------------+
bool InitializeSymbolsFromCSV()
{
   int fileHandle = FileOpen(InpCSVFilename, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("FEHLER: CSV-Datei nicht gefunden: ", InpCSVFilename);
      g_CSVMode = false;
      g_CSVStatus = "Datei nicht gefunden";
      return false;
   }
   
   // Temporäres Array für Symbole
   SymbolTradeInfo tempSymbols[];
   int tempCount = 0;
   int lineNumber = 0;
   int magicCounter = InpBaseMagicNumber;
   
   Print("========================================");
   Print("Lade Symbole aus CSV: ", InpCSVFilename);
   Print("========================================");
   
   while(!FileIsEnding(fileHandle))
   {
      string line = FileReadString(fileHandle);
      lineNumber++;
      
      // Bereinigen
      StringReplace(line, "\r", "");
      StringReplace(line, "\n", "");
      StringTrimLeft(line);
      StringTrimRight(line);
      
      // Leere Zeilen überspringen
      if(line == "") continue;
      
      // Header überspringen
      if(lineNumber == 1 || StringFind(line, "Waehrungspaar") >= 0) continue;
      
      // Zeile parsen
      string parts[];
      int count = StringSplit(line, ';', parts);
      
      if(count >= 2)
      {
         string csvSymbol = parts[0];
         StringTrimLeft(csvSymbol);
         StringTrimRight(csvSymbol);
         StringToUpper(csvSymbol);
         
         string csvSignal = parts[1];
         StringTrimLeft(csvSignal);
         StringTrimRight(csvSignal);
         StringToUpper(csvSignal);
         
         // Gold/Silber ausschließen
         if(IsExcludedSymbol(csvSymbol))
         {
            Print("ÜBERSPRUNGEN (Edelmetall): ", csvSymbol);
            continue;
         }
         
         // Broker-Symbol finden
         string brokerSymbol = FindBrokerSymbol(csvSymbol);
         if(brokerSymbol == "")
         {
            Print("WARNUNG: Kein Broker-Symbol gefunden für: ", csvSymbol);
            continue;
         }
         
         // Symbol aktivieren
         if(!EnsureSymbolEnabled(brokerSymbol))
         {
            Print("WARNUNG: Konnte Symbol nicht aktivieren: ", brokerSymbol);
            continue;
         }
         
         // Richtung parsen
         ENUM_DIR_FILTER direction = FILTER_NEUTRAL;
         if(csvSignal == "BUY") direction = FILTER_LONG;
         else if(csvSignal == "SELL") direction = FILTER_SHORT;
         
         // Zum Array hinzufügen
         ArrayResize(tempSymbols, tempCount + 1);
         
         tempSymbols[tempCount].symbol = csvSymbol;
         tempSymbols[tempCount].brokerSymbol = brokerSymbol;
         tempSymbols[tempCount].magic = magicCounter;
         tempSymbols[tempCount].direction = direction;
         tempSymbols[tempCount].handleStoch = INVALID_HANDLE;
         tempSymbols[tempCount].handleRSI = INVALID_HANDLE;
         tempSymbols[tempCount].adrValue = 0;
         tempSymbols[tempCount].dayRange = 0;
         tempSymbols[tempCount].lastH1Bar = 0;
         tempSymbols[tempCount].lastADRCalcDay = 0;
         tempSymbols[tempCount].openPositions = 0;
         tempSymbols[tempCount].openType = POSITION_TYPE_BUY;
         tempSymbols[tempCount].newsBlocked = false;
         tempSymbols[tempCount].newsInfo = "";
         
         Print("HINZUGEFÜGT: ", csvSymbol, " (", brokerSymbol, ") → ", csvSignal, " | Magic: ", magicCounter);
         
         tempCount++;
         magicCounter++;
      }
   }
   
   FileClose(fileHandle);
   
   if(tempCount == 0)
   {
      Print("FEHLER: Keine gültigen Symbole in CSV gefunden!");
      g_CSVMode = false;
      g_CSVStatus = "Keine Symbole gefunden";
      return false;
   }
   
   // Globales Array übernehmen
   ArrayResize(g_Symbols, tempCount);
   for(int i = 0; i < tempCount; i++)
   {
      g_Symbols[i] = tempSymbols[i];
   }
   g_SymbolCount = tempCount;
   
   Print("========================================");
   Print("Erfolgreich ", g_SymbolCount, " Symbole geladen!");
   Print("========================================");
   
   g_CSVMode = true;
   g_CSVStatus = StringFormat("%d Symbole geladen", g_SymbolCount);
   g_LastCSVCheck = TimeCurrent();
   
   return true;
}

//+------------------------------------------------------------------+
//| Initialisiere Indikatoren für alle Symbole                       |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      string sym = g_Symbols[i].brokerSymbol;
      
      // Stochastic
      g_Symbols[i].handleStoch = iStochastic(sym, PERIOD_H1, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
      if(g_Symbols[i].handleStoch == INVALID_HANDLE)
      {
         Print("FEHLER: Stochastic Handle für ", sym, " konnte nicht erstellt werden!");
         return false;
      }
      
      // RSI (nur wenn RSI-Mode)
      if(InpEntryMode == MODE_RSI)
      {
         g_Symbols[i].handleRSI = iRSI(sym, PERIOD_D1, InpRSI_Period, PRICE_CLOSE);
         if(g_Symbols[i].handleRSI == INVALID_HANDLE)
         {
            Print("FEHLER: RSI Handle für ", sym, " konnte nicht erstellt werden!");
            return false;
         }
      }
      
      if(InpDebugMode) Print("Indikatoren initialisiert für: ", sym);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CSV Signale aktualisieren (nur Richtungen)                       |
//+------------------------------------------------------------------+
void UpdateSignalsFromCSV()
{
   g_LastCSVCheck = TimeCurrent();
   
   int fileHandle = FileOpen(InpCSVFilename, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("FEHLER: CSV-Datei nicht mehr verfügbar: ", InpCSVFilename);
      g_CSVStatus = "Datei nicht gefunden";
      return;
   }
   
   int lineNumber = 0;
   int updatedCount = 0;
   
   while(!FileIsEnding(fileHandle))
   {
      string line = FileReadString(fileHandle);
      lineNumber++;
      
      // Bereinigen
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
         StringToUpper(csvSymbol);
         
         string csvSignal = parts[1];
         StringTrimLeft(csvSignal);
         StringTrimRight(csvSignal);
         StringToUpper(csvSignal);
         
         // Gold/Silber überspringen
         if(IsExcludedSymbol(csvSymbol)) continue;
         
         // Im Array suchen und aktualisieren
         for(int i = 0; i < g_SymbolCount; i++)
         {
            if(g_Symbols[i].symbol == csvSymbol)
            {
               ENUM_DIR_FILTER oldDirection = g_Symbols[i].direction;
               ENUM_DIR_FILTER newDirection = FILTER_NEUTRAL;
               
               if(csvSignal == "BUY") newDirection = FILTER_LONG;
               else if(csvSignal == "SELL") newDirection = FILTER_SHORT;
               
               if(oldDirection != newDirection)
               {
                  Print("Signal-Änderung: ", csvSymbol, " → ", csvSignal, 
                        " (vorher: ", DirectionToString(oldDirection), ")");
                  
                  // Gegenpositionen schließen bei Richtungswechsel
                  CloseOppositePositionsForSymbol(i, oldDirection, newDirection);
               }
               
               g_Symbols[i].direction = newDirection;
               updatedCount++;
               break;
            }
         }
      }
   }
   
   FileClose(fileHandle);
   
   g_CSVStatus = StringFormat("Update OK (%d Symbole)", updatedCount);
   if(InpDebugMode) Print("CSV-Update: ", updatedCount, " Symbole aktualisiert");
}

//+------------------------------------------------------------------+
//| Richtung als String                                              |
//+------------------------------------------------------------------+
string DirectionToString(ENUM_DIR_FILTER dir)
{
   switch(dir)
   {
      case FILTER_LONG: return "BUY";
      case FILTER_SHORT: return "SELL";
      case FILTER_NEUTRAL: return "NEUTRAL";
      case FILTER_BOTH: return "BOTH";
   }
   return "?";
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Prüfe ob wir im Strategy Tester sind
   bool isInTester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   
   if(isInTester)
   {
      Print("WARNUNG: Multi-Symbol CSV-Trading funktioniert nicht im Strategy Tester!");
      Print("Im Tester wird nur das aktuelle Chart-Symbol getradet.");
      return(INIT_FAILED);
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
   
   // CSV-Mode initialisieren
   if(InpUseCSVSignals)
   {
      Print("CSV-Signal Multi-Symbol Mode aktiviert...");
      
      // Symbole aus CSV laden
      if(!InitializeSymbolsFromCSV())
      {
         Print("FEHLER: Konnte Symbole nicht aus CSV laden!");
         return(INIT_FAILED);
      }
      
      // Indikatoren für alle Symbole erstellen
      if(!InitializeIndicators())
      {
         Print("FEHLER: Konnte Indikatoren nicht initialisieren!");
         return(INIT_FAILED);
      }
      
      // Timer für periodische CSV-Prüfung starten
      int timerSeconds = InpCSVCheckInterval * 60;
      if(!EventSetTimer(timerSeconds))
      {
         Print("FEHLER: Timer konnte nicht gestartet werden!");
         return(INIT_FAILED);
      }
      Print("Timer gestartet: CSV-Check alle ", InpCSVCheckInterval, " Minuten");
   }
   else
   {
      Print("CSV-Mode deaktiviert - Multi-Symbol Trading nicht verfügbar!");
      return(INIT_FAILED);
   }
   
   // Trade-Objekt konfigurieren
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // GUI erstellen
   CreateButtons();
   CreateLabels();
   CreateSymbolLabels();
   UpdateButtonsState();
   
   Print("========================================");
   Print("EA erfolgreich gestartet!");
   Print("Anzahl Symbole: ", g_SymbolCount);
   Print("CSV-Interval: ", InpCSVCheckInterval, " Minuten");
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Indikatoren freigeben
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Symbols[i].handleStoch != INVALID_HANDLE) 
         IndicatorRelease(g_Symbols[i].handleStoch);
      if(g_Symbols[i].handleRSI != INVALID_HANDLE) 
         IndicatorRelease(g_Symbols[i].handleRSI);
   }
   
   EventKillTimer();
   
   // GUI Objekte löschen
   ObjectDelete(0, btnBothName);
   ObjectDelete(0, btnLongName);
   ObjectDelete(0, btnShortName);
   ObjectDelete(0, btnNeutralName);
   
   ObjectDelete(0, lblMaxDDName);
   ObjectDelete(0, lblPosName);
   ObjectDelete(0, lblStatusName);
   ObjectDelete(0, lblSetupName);
   ObjectDelete(0, lblCSVInfoName);
   ObjectDelete(0, lblCSVTimeName);
   ObjectDelete(0, lblNewsInfoName);
   
   // Symbol-Labels löschen
   for(int i = 0; i < g_SymbolCount; i++)
   {
      ObjectDelete(0, lblSymbolPrefix + IntegerToString(i));
   }
   
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer Event - CSV nur hier neu laden!                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpUseCSVSignals && g_CSVMode)
   {
      Print("Timer: CSV-Signale werden aktualisiert...");
      UpdateSignalsFromCSV();
   }
}

//+------------------------------------------------------------------+
//| OnTick - Hauptlogik für alle Symbole                             |
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
   
   // --- 2. OPTIMIERT: Positionen einmal zählen für ALLE Symbole ---
   CountAllPositionsOptimized();
   
   // --- 3. LOOP ÜBER ALLE SYMBOLE ---
   int totalPositions = 0;
   
   for(int i = 0; i < g_SymbolCount; i++)
   {
      ProcessSymbol(i);
      totalPositions += g_Symbols[i].openPositions;
   }
   
   // --- 4. VISUALS UPDATE (nur alle 500ms) ---
   static uint lastVisualUpdate = 0;
   uint currentTick = GetTickCount();
   if(currentTick - lastVisualUpdate >= 500)
   {
      lastVisualUpdate = currentTick;
      stat_EA_Action = StringFormat("Trading %d Symbole | %d Positionen", g_SymbolCount, totalPositions);
      UpdateVisuals(totalPositions);
   }
}

//+------------------------------------------------------------------+
//| Verarbeite ein einzelnes Symbol                                  |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx)
{
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   ENUM_DIR_FILTER direction = g_Symbols[idx].direction;
   
   // Magic Number für dieses Symbol setzen
   trade.SetExpertMagicNumber(magic);
   
   // Positionen validieren (gegen Filter) - NUR wenn nötig
   if(direction != FILTER_BOTH && direction != FILTER_NEUTRAL)
   {
      ValidatePositionsForSymbol(idx);
   }
   
   // ADR berechnen
   CalculateADRForSymbol(idx);
   
   // News prüfen
   CheckNewsForSymbol(idx);
   
   // Positionen wurden bereits in CountAllPositionsOptimized() gezählt!
   int openPos = g_Symbols[idx].openPositions;
   ENUM_POSITION_TYPE openType = g_Symbols[idx].openType;
   
   // --- BASKET MANAGEMENT ---
   if(openPos > 0)
   {
      // Exit prüfen
      CheckBasketExitForSymbol(idx);
      
      // Grid-Nachkauf
      datetime currentH1Bar = iTime(sym, PERIOD_H1, 0);
      if(currentH1Bar != g_Symbols[idx].lastH1Bar && openPos < InpMaxPositions)
      {
         g_Symbols[idx].lastH1Bar = currentH1Bar;
         
         if(!g_Symbols[idx].newsBlocked)
         {
            ProcessGridEntryForSymbol(idx);
         }
      }
   }
   
   // --- EOD CLOSE ---
   if(InpUseEODClose && openPos > 0)
   {
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(), tm);
      if(tm.hour == InpEODHour && tm.min >= InpEODMinute)
      {
         CloseAllPositionsForSymbol(idx);
      }
   }
   
   // --- ENTRY LOGIC ---
   if(openPos == 0 && direction != FILTER_NEUTRAL)
   {
      datetime currentH1Bar = iTime(sym, PERIOD_H1, 0);
      if(currentH1Bar != g_Symbols[idx].lastH1Bar)
      {
         g_Symbols[idx].lastH1Bar = currentH1Bar;
         
         if(!g_Symbols[idx].newsBlocked)
         {
            ProcessEntryForSymbol(idx);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ADR berechnen für Symbol                                         |
//+------------------------------------------------------------------+
void CalculateADRForSymbol(int idx)
{
   string sym = g_Symbols[idx].brokerSymbol;
   datetime currentDay = iTime(sym, PERIOD_D1, 0);
   
   if(currentDay != g_Symbols[idx].lastADRCalcDay || g_Symbols[idx].adrValue == 0)
   {
      g_Symbols[idx].lastADRCalcDay = currentDay;
      
      double sum = 0;
      for(int i = 1; i <= InpADRPeriod; i++)
      {
         sum += (iHigh(sym, PERIOD_D1, i) - iLow(sym, PERIOD_D1, i));
      }
      
      g_Symbols[idx].adrValue = sum / InpADRPeriod;
      if(g_Symbols[idx].adrValue == 0) 
         g_Symbols[idx].adrValue = 100 * SymbolInfoDouble(sym, SYMBOL_POINT);
   }
   
   g_Symbols[idx].dayRange = iHigh(sym, PERIOD_D1, 0) - iLow(sym, PERIOD_D1, 0);
}

//+------------------------------------------------------------------+
//| OPTIMIERT: Alle Positionen einmal zählen für alle Symbole        |
//+------------------------------------------------------------------+
void CountAllPositionsOptimized()
{
   // Zuerst alle Zähler auf 0 setzen
   for(int i = 0; i < g_SymbolCount; i++)
   {
      g_Symbols[i].openPositions = 0;
      g_Symbols[i].openType = POSITION_TYPE_BUY;
   }
   
   // Einmal über alle Positionen loopen
   int totalPos = PositionsTotal();
   for(int i = 0; i < totalPos; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      
      // Zu welchem Symbol gehört diese Position?
      for(int j = 0; j < g_SymbolCount; j++)
      {
         if(g_Symbols[j].brokerSymbol == posSymbol && g_Symbols[j].magic == posMagic)
         {
            g_Symbols[j].openPositions++;
            g_Symbols[j].openType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            break;  // Gefunden, nächste Position
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Positionen validieren gegen Filter                               |
//+------------------------------------------------------------------+
void ValidatePositionsForSymbol(int idx)
{
   ENUM_DIR_FILTER direction = g_Symbols[idx].direction;
   if(direction == FILTER_BOTH || direction == FILTER_NEUTRAL) return;
   
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == sym && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool closeIt = false;
            
            if(direction == FILTER_LONG && type == POSITION_TYPE_SELL) closeIt = true;
            if(direction == FILTER_SHORT && type == POSITION_TYPE_BUY) closeIt = true;
            
            if(closeIt)
            {
               trade.SetExpertMagicNumber(magic);
               trade.PositionClose(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Gegenpositionen schließen bei Signalwechsel                      |
//+------------------------------------------------------------------+
void CloseOppositePositionsForSymbol(int idx, ENUM_DIR_FILTER oldDir, ENUM_DIR_FILTER newDir)
{
   if(newDir == FILTER_NEUTRAL) return;
   if(oldDir == FILTER_NEUTRAL) return;
   if(oldDir == newDir) return;
   
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   
   trade.SetExpertMagicNumber(magic);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == sym && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            if(newDir == FILTER_LONG && type == POSITION_TYPE_SELL)
            {
               Print("Schließe Short für ", sym, " wegen BUY-Signal");
               trade.PositionClose(ticket);
            }
            else if(newDir == FILTER_SHORT && type == POSITION_TYPE_BUY)
            {
               Print("Schließe Long für ", sym, " wegen SELL-Signal");
               trade.PositionClose(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Entry-Logik für Symbol                                           |
//+------------------------------------------------------------------+
void ProcessEntryForSymbol(int idx)
{
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   ENUM_DIR_FILTER direction = g_Symbols[idx].direction;
   double adrValue = g_Symbols[idx].adrValue;
   double dayRange = g_Symbols[idx].dayRange;
   
   bool entryConditionMet = false;
   
   // Entry-Bedingung prüfen
   if(InpEntryMode == MODE_ADR)
   {
      double neededRange = adrValue * (InpEntryADR_Pct / 100.0);
      if(dayRange > neededRange) entryConditionMet = true;
   }
   else if(InpEntryMode == MODE_RSI)
   {
      double rsiValues[];
      if(CopyBuffer(g_Symbols[idx].handleRSI, 0, 0, 1, rsiValues) == 1)
      {
         if(rsiValues[0] >= InpRSI_Upper || rsiValues[0] <= InpRSI_Lower)
         {
            entryConditionMet = true;
         }
      }
   }
   
   if(!entryConditionMet) return;
   
   // Stochastic prüfen
   double kBuffer[], dBuffer[];
   ArraySetAsSeries(kBuffer, true);
   ArraySetAsSeries(dBuffer, true);
   
   if(CopyBuffer(g_Symbols[idx].handleStoch, 0, 0, 3, kBuffer) < 3) return;
   if(CopyBuffer(g_Symbols[idx].handleStoch, 1, 0, 3, dBuffer) < 3) return;
   
   bool shortSignal = (kBuffer[2] >= InpStochUpper && kBuffer[1] < InpStochUpper);
   bool longSignal  = (kBuffer[2] <= InpStochLower && kBuffer[1] > InpStochLower);
   
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double slDistancePoints = adrValue * InpIndividualSL_ADR;
   double dynFirstLot = GetDynamicLot(InpFirstLot, sym);
   
   trade.SetExpertMagicNumber(magic);
   
   if(shortSignal && (direction == FILTER_SHORT || direction == FILTER_BOTH))
   {
      string comment = BuildTradeComment(g_Symbols[idx].symbol, true, 1, "Short");
      if(trade.Sell(dynFirstLot, sym, bid, bid + slDistancePoints, 0, comment))
      {
         Print("ENTRY SHORT: ", sym, " @ ", bid, " | Lot: ", dynFirstLot);
      }
   }
   
   if(longSignal && (direction == FILTER_LONG || direction == FILTER_BOTH))
   {
      string comment = BuildTradeComment(g_Symbols[idx].symbol, true, 1, "Long");
      if(trade.Buy(dynFirstLot, sym, bid, bid - slDistancePoints, 0, comment))
      {
         Print("ENTRY LONG: ", sym, " @ ", bid, " | Lot: ", dynFirstLot);
      }
   }
}

//+------------------------------------------------------------------+
//| Grid-Entry für Symbol                                            |
//+------------------------------------------------------------------+
void ProcessGridEntryForSymbol(int idx)
{
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   ENUM_DIR_FILTER direction = g_Symbols[idx].direction;
   ENUM_POSITION_TYPE openType = g_Symbols[idx].openType;
   int openPos = g_Symbols[idx].openPositions;
   double adrValue = g_Symbols[idx].adrValue;
   
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   
   double requiredDist = adrValue * (InpGridStep_ADR_Pct / 100.0);
   double slDistancePoints = adrValue * InpIndividualSL_ADR;
   
   // Letzte Entry-Price finden (neueste Position nach Zeit)
   double lastEntryPrice = 0.0;
   datetime lastEntryTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == sym && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(posTime > lastEntryTime)
            {
               lastEntryTime = posTime;
               lastEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   
   if(lastEntryPrice <= 0) return;
   
   double dynGridLot = GetDynamicLot(InpGridLot, sym);
   trade.SetExpertMagicNumber(magic);
   
   if(openType == POSITION_TYPE_SELL && ask >= (lastEntryPrice + requiredDist))
   {
      if(direction == FILTER_SHORT || direction == FILTER_BOTH)
      {
         string comment = BuildTradeComment(g_Symbols[idx].symbol, false, openPos + 1, "Short");
         if(trade.Sell(dynGridLot, sym, bid, bid + slDistancePoints, 0, comment))
         {
            Print("GRID SHORT: ", sym, " #", openPos + 1, " @ ", bid);
         }
      }
   }
   
   if(openType == POSITION_TYPE_BUY && bid <= (lastEntryPrice - requiredDist))
   {
      if(direction == FILTER_LONG || direction == FILTER_BOTH)
      {
         string comment = BuildTradeComment(g_Symbols[idx].symbol, false, openPos + 1, "Long");
         if(trade.Buy(dynGridLot, sym, bid, bid - slDistancePoints, 0, comment))
         {
            Print("GRID LONG: ", sym, " #", openPos + 1, " @ ", bid);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Basket Exit prüfen für Symbol                                    |
//+------------------------------------------------------------------+
void CheckBasketExitForSymbol(int idx)
{
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   ENUM_POSITION_TYPE openType = g_Symbols[idx].openType;
   int count = g_Symbols[idx].openPositions;
   double adrValue = g_Symbols[idx].adrValue;
   
   double totalLots = 0.0;
   double weightedPrice = 0.0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == sym && 
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
   if(targetPct < 1.0) targetPct = 1.0;  // Minimum-Schutz: Target nie unter 1% ADR
   
   double targetDistPoints = adrValue * (targetPct / 100.0);
   bool triggerClose = false;
   
   if(openType == POSITION_TYPE_BUY)
   {
      double currentPrice = SymbolInfoDouble(sym, SYMBOL_BID);
      if(currentPrice >= (avgPrice + targetDistPoints)) triggerClose = true;
   }
   else if(openType == POSITION_TYPE_SELL)
   {
      double currentPrice = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(currentPrice <= (avgPrice - targetDistPoints)) triggerClose = true;
   }
   
   if(triggerClose)
   {
      Print("TARGET ERREICHT: ", sym, " - Schließe alle Positionen");
      CloseAllPositionsForSymbol(idx);
   }
}

//+------------------------------------------------------------------+
//| Alle Positionen für Symbol schließen                             |
//+------------------------------------------------------------------+
void CloseAllPositionsForSymbol(int idx)
{
   string sym = g_Symbols[idx].brokerSymbol;
   int magic = g_Symbols[idx].magic;
   
   trade.SetExpertMagicNumber(magic);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == sym && 
            PositionGetInteger(POSITION_MAGIC) == magic)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| News Filter für Symbol                                           |
//+------------------------------------------------------------------+
void CheckNewsForSymbol(int idx)
{
   if(!InpUseNewsFilter)
   {
      g_Symbols[idx].newsBlocked = false;
      g_Symbols[idx].newsInfo = "Deaktiviert";
      return;
   }
   
   // Caching: News-Check nur alle X Sekunden
   datetime currentTime = TimeCurrent();
   bool cacheValid = (currentTime - g_LastNewsCheckTime < g_NewsCheckInterval && g_LastNewsCheckTime > 0);
   
   // Cache nur zurücksetzen wenn wir beim ersten Symbol sind UND Cache abgelaufen ist
   if(idx == 0 && !cacheValid)
   {
      g_LastNewsCheckTime = currentTime;
   }
   
   // Wenn Cache noch gültig, gecachte Werte behalten
   if(cacheValid)
   {
      return;
   }
   
   string sym = g_Symbols[idx].brokerSymbol;
   datetime serverTime = TimeTradeServer();
   
   datetime dateFrom = serverTime - (InpMinutesAfterNews * 60);
   datetime dateTo = serverTime + (InpMinutesBeforeNews * 60);
   
   string currencyBase = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
   string currencyQuote = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
   
   ENUM_CALENDAR_EVENT_IMPORTANCE minImportance = (InpNewsImportance == NEWS_HIGH_ONLY) 
      ? CALENDAR_IMPORTANCE_HIGH 
      : CALENDAR_IMPORTANCE_MODERATE;
   
   MqlCalendarValue values[];
   datetime nearestNewsTime = 0;
   string nearestNewsName = "";
   
   // Base-Währung prüfen
   if(CalendarValueHistory(values, dateFrom, dateTo, NULL, currencyBase))
   {
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance < minImportance) continue;
            
            if(nearestNewsTime == 0 || 
               MathAbs((int)(values[i].time - serverTime)) < MathAbs((int)(nearestNewsTime - serverTime)))
            {
               nearestNewsTime = values[i].time;
               nearestNewsName = event.name;
            }
         }
      }
   }
   
   // Quote-Währung prüfen
   if(InpNewsFilterBothCurrencies && currencyBase != currencyQuote)
   {
      if(CalendarValueHistory(values, dateFrom, dateTo, NULL, currencyQuote))
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               if(event.importance < minImportance) continue;
               
               if(nearestNewsTime == 0 || 
                  MathAbs((int)(values[i].time - serverTime)) < MathAbs((int)(nearestNewsTime - serverTime)))
               {
                  nearestNewsTime = values[i].time;
                  nearestNewsName = event.name;
               }
            }
         }
      }
   }
   
   if(nearestNewsTime > 0)
   {
      int minutesDiff = (int)((nearestNewsTime - serverTime) / 60);
      g_Symbols[idx].newsBlocked = true;
      g_Symbols[idx].newsInfo = StringFormat("%s in %d Min", nearestNewsName, minutesDiff);
   }
   else
   {
      g_Symbols[idx].newsBlocked = false;
      g_Symbols[idx].newsInfo = "Klar";
   }
}

//+------------------------------------------------------------------+
//| Trade Comment bauen                                              |
//+------------------------------------------------------------------+
string BuildTradeComment(string symbol, bool isFirstEntry, int posNum, string dir)
{
   string entryType = isFirstEntry ? ((InpEntryMode == MODE_ADR) ? "ADR" : "RSI") : "Grid";
   return StringFormat("CSV:%s | %s-%s #%d", symbol, entryType, dir, posNum);
}

//+------------------------------------------------------------------+
//| Dynamische Lot-Berechnung                                        |
//+------------------------------------------------------------------+
double GetDynamicLot(double baseLot, string sym)
{
   if(!InpUseMM || InpRefBalance <= 0 || InpBalanceStep_Pct <= 0) return baseLot;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(currentBalance < InpRefBalance) return baseLot;
   
   double profitAbs = currentBalance - InpRefBalance;
   double profitPct = (profitAbs / InpRefBalance) * 100.0;
   
   int steps = (int)(profitPct / InpBalanceStep_Pct);
   double multiplier = 1.0 + (steps * (InpLotIncrease_Pct / 100.0));
   
   double calculatedLot = baseLot * multiplier;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   
   calculatedLot = MathFloor(calculatedLot / step) * step;
   
   if(calculatedLot < min) calculatedLot = min;
   if(calculatedLot > max) calculatedLot = max;
   
   return calculatedLot;
}

//+------------------------------------------------------------------+
//| Chart Event Handler                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Buttons sind im CSV-Mode deaktiviert
      if(g_CSVMode)
      {
         Print("HINWEIS: Manuelle Steuerung deaktiviert - CSV steuert alle Symbole!");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw();
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| GUI: Labels erstellen                                            |
//+------------------------------------------------------------------+
void CreateLabels()
{
   int x = 20;
   int fontSize = 11;
   string font = "Arial Bold";
   color c = clrWhite;
   
   CreateSingleLabel(lblMaxDDName, x, 50, "MaxDD: 0.0%", fontSize, font, c);
   CreateSingleLabel(lblPosName, x, 75, "Positionen: 0", fontSize, font, c);
   CreateSingleLabel(lblStatusName, x, 100, "Status: Init", fontSize, font, c);
   CreateSingleLabel(lblSetupName, x, 125, "Setup: ...", fontSize, font, c);
   CreateSingleLabel(lblCSVInfoName, x, 150, "CSV: Init...", fontSize, font, clrYellow);
   CreateSingleLabel(lblCSVTimeName, x, 175, "CSV Check: ...", fontSize, font, clrWhite);
   CreateSingleLabel(lblNewsInfoName, x, 200, "News: Init...", fontSize, font, clrYellow);
}

//+------------------------------------------------------------------+
//| GUI: Symbol-Labels erstellen                                     |
//+------------------------------------------------------------------+
void CreateSymbolLabels()
{
   int x = 20;
   int startY = 240;
   int fontSize = 10;
   string font = "Consolas";
   
   // Überschrift
   CreateSingleLabel("Lbl_Symbol_Header", x, startY - 20, 
                     "=== SYMBOL-ÜBERSICHT ===", fontSize, font, clrCyan);
   
   for(int i = 0; i < g_SymbolCount; i++)
   {
      string labelName = lblSymbolPrefix + IntegerToString(i);
      int y = startY + (i * 18);
      CreateSingleLabel(labelName, x, y, "", fontSize, font, clrWhite);
   }
}

//+------------------------------------------------------------------+
//| GUI: Einzelnes Label erstellen                                   |
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
//| GUI: Buttons erstellen                                           |
//+------------------------------------------------------------------+
void CreateButtons()
{
   int xBase = 20;
   int yBase = 5;
   int width = 90;
   int height = 30;
   int gap = 5;

   CreateSingleButton(btnBothName, xBase, yBase, width, height, "BOTH");
   CreateSingleButton(btnLongName, xBase + width + gap, yBase, width, height, "LONG");
   CreateSingleButton(btnShortName, xBase + (width + gap)*2, yBase, width, height, "SHORT");
   CreateSingleButton(btnNeutralName, xBase + (width + gap)*3, yBase, width, height, "NEUTRAL");
}

//+------------------------------------------------------------------+
//| GUI: Einzelnen Button erstellen                                  |
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
//| GUI: Button-Status aktualisieren                                 |
//+------------------------------------------------------------------+
void UpdateButtonsState()
{
   color disabledColor = clrDarkGray;
   
   // Im CSV-Mode sind alle Buttons deaktiviert
   if(g_CSVMode)
   {
      ObjectSetInteger(0, btnBothName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnLongName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnShortName, OBJPROP_BGCOLOR, disabledColor);
      ObjectSetInteger(0, btnNeutralName, OBJPROP_BGCOLOR, disabledColor);
      
      ObjectSetString(0, btnBothName, OBJPROP_TEXT, "CSV-MODE");
      ObjectSetString(0, btnLongName, OBJPROP_TEXT, "CSV-MODE");
      ObjectSetString(0, btnShortName, OBJPROP_TEXT, "CSV-MODE");
      ObjectSetString(0, btnNeutralName, OBJPROP_TEXT, "CSV-MODE");
   }
   
   ObjectSetInteger(0, btnBothName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnLongName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnShortName, OBJPROP_STATE, false);
   ObjectSetInteger(0, btnNeutralName, OBJPROP_STATE, false);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| GUI: Visuals aktualisieren                                       |
//+------------------------------------------------------------------+
void UpdateVisuals(int totalPositions)
{
   // MaxDD
   string txtDD = StringFormat("MaxDD zu HWM: %.2f%%", stat_MaxDD_Equity_Percent);
   ObjectSetString(0, lblMaxDDName, OBJPROP_TEXT, txtDD);

   // Positionen gesamt
   string txtPos = StringFormat("Positionen gesamt: %d (über %d Symbole)", totalPositions, g_SymbolCount);
   ObjectSetString(0, lblPosName, OBJPROP_TEXT, txtPos);
   
   // Status
   ObjectSetString(0, lblStatusName, OBJPROP_TEXT, "Status: " + stat_EA_Action);
   
   // Config
   string txtSetup = StringFormat("Config: Entry %.0f%% | Grid %.0f%% | Target %.0f%% | Lot %.2f", 
                                   InpEntryADR_Pct, InpGridStep_ADR_Pct, InpStartTarget_ADR, InpFirstLot);
   ObjectSetString(0, lblSetupName, OBJPROP_TEXT, txtSetup);
   
   // CSV Info
   string txtCSVInfo = StringFormat("CSV-Mode: AKTIV | %d Symbole | Status: %s", g_SymbolCount, g_CSVStatus);
   ObjectSetString(0, lblCSVInfoName, OBJPROP_TEXT, txtCSVInfo);
   ObjectSetInteger(0, lblCSVInfoName, OBJPROP_COLOR, clrLimeGreen);
   
   // CSV Time
   string timeText = (g_LastCSVCheck > 0) ? TimeToString(g_LastCSVCheck, TIME_DATE|TIME_MINUTES) : "Noch nie";
   string txtCSVTime = StringFormat("Letzter CSV-Check: %s (Interval: %d Min)", timeText, InpCSVCheckInterval);
   ObjectSetString(0, lblCSVTimeName, OBJPROP_TEXT, txtCSVTime);
   
   // News Info (global)
   int newsBlockedCount = 0;
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Symbols[i].newsBlocked) newsBlockedCount++;
   }
   
   if(InpUseNewsFilter)
   {
      string newsText = (newsBlockedCount > 0) 
         ? StringFormat("News-Filter: %d Symbole blockiert", newsBlockedCount)
         : "News-Filter: Alle Symbole klar";
      ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, newsText);
      ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, (newsBlockedCount > 0) ? clrOrange : clrLimeGreen);
   }
   else
   {
      ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, "News-Filter: DEAKTIVIERT");
      ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, clrGray);
   }
   
   // Symbol-Übersicht aktualisieren
   for(int i = 0; i < g_SymbolCount; i++)
   {
      string labelName = lblSymbolPrefix + IntegerToString(i);
      
      string dirText = "";
      color dirColor = clrWhite;
      
      switch(g_Symbols[i].direction)
      {
         case FILTER_LONG:
            dirText = "BUY ";
            dirColor = clrLimeGreen;
            break;
         case FILTER_SHORT:
            dirText = "SELL";
            dirColor = clrTomato;
            break;
         case FILTER_NEUTRAL:
            dirText = "WAIT";
            dirColor = clrYellow;
            break;
         default:
            dirText = "BOTH";
            dirColor = clrSkyBlue;
            break;
      }
      
      string newsIcon = g_Symbols[i].newsBlocked ? " [NEWS]" : "";
      
      string symbolText = StringFormat("%-8s | %s | Pos: %2d | Magic: %d%s", 
                                       g_Symbols[i].symbol,
                                       dirText,
                                       g_Symbols[i].openPositions,
                                       g_Symbols[i].magic,
                                       newsIcon);
      
      ObjectSetString(0, labelName, OBJPROP_TEXT, symbolText);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, dirColor);
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+