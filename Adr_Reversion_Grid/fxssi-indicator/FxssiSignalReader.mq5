//+------------------------------------------------------------------+
//|                                          FxssiSignalReader.mq5   |
//|                              FXSSI Sentiment Signal Reader       |
//|                                                                  |
//| Liest CSV-Dateien mit FXSSI-Sentiment-Daten und stellt die       |
//| Werte über 4 Indikator-Buffers bereit.                           |
//|                                                                  |
//| Buffer 0 = Anzahl geladener Symbole                              |
//| Buffer 1 = Buy-Prozent für aktuelles Chart-Symbol                |
//| Buffer 2 = Sell-Prozent für aktuelles Chart-Symbol               |
//| Buffer 3 = Signal (+1=BUY, -1=SELL, 0=NEUTRAL)                  |
//|                                                                  |
//| Verwendung durch EAs: iCustom() mit FxssiSignalData.mqh         |
//+------------------------------------------------------------------+
#property copyright "FXSSI Signal Reader"
#property link      ""
#property version   "2.03"
#property indicator_chart_window

#define INDICATOR_VERSION "v2.03"
#property indicator_buffers 4
#property indicator_plots   4    // 4 Plots (alle DRAW_NONE) damit CopyBuffer funktioniert

//--- Input-Parameter
input string InputDataPath = "currency_pairs"; // Pfad zum CSV-Verzeichnis (relativ zu MQL5/Files/)

input bool   DebugMode = true; // Debug-Modus (ausführliche Logs)

//--- Indikator-Buffers (nur 4!)
double BufSymbolCount[];   // Buffer 0: Anzahl geladener Symbole
double BufBuyPercent[];    // Buffer 1: Buy% für aktuelles Symbol
double BufSellPercent[];   // Buffer 2: Sell% für aktuelles Symbol
double BufSignal[];        // Buffer 3: Signal für aktuelles Symbol

//--- Interne Daten-Arrays (alle geladenen Paare)
string g_symbolNames[];
int    g_symbolCount = 0;
double g_buyPercent[];
double g_sellPercent[];
double g_signal[];

//--- Aktuelles Symbol-Daten (für schnellen Buffer-Zugriff)
double g_currentBuy = 0.0;
double g_currentSell = 0.0;
double g_currentSignal = 0.0;
bool   g_dataLoaded = false;

//+------------------------------------------------------------------+
//| Normalisiert Symbol: EURUSD -> EUR_USD                           |
//+------------------------------------------------------------------+
string NormalizeSymbol(string brokerSymbol)
  {
   // Entferne Suffixe wie ".m" oder ".raw"
   int dotPos = StringFind(brokerSymbol, ".");
   if(dotPos > 0)
      brokerSymbol = StringSubstr(brokerSymbol, 0, dotPos);
   
   // Schon im FXSSI-Format?
   if(StringFind(brokerSymbol, "_") >= 0)
      return brokerSymbol;
   
   // 6+ Zeichen -> 3+3 mit Unterstrich
   int len = StringLen(brokerSymbol);
   if(len >= 6)
     {
      return StringSubstr(brokerSymbol, 0, 3) + "_" + StringSubstr(brokerSymbol, 3, 3);
     }
   
   return brokerSymbol;
  }

//+------------------------------------------------------------------+
//| Konvertiert deutsches Zahlenformat (Komma) in double              |
//+------------------------------------------------------------------+
double ParseGermanDouble(string text)
  {
   StringReplace(text, ",", ".");
   StringReplace(text, "%", "");
   StringReplace(text, " ", "");
   return StringToDouble(text);
  }

//+------------------------------------------------------------------+
//| Konvertiert Signal-Text in numerischen Wert                       |
//+------------------------------------------------------------------+
double ParseSignal(string text)
  {
   StringReplace(text, " ", "");
   StringReplace(text, "\r", "");
   StringReplace(text, "\n", "");
   
   if(StringFind(text, "BUY") >= 0 || StringFind(text, "buy") >= 0 || StringFind(text, "Buy") >= 0)
      return 1.0;
   if(StringFind(text, "SELL") >= 0 || StringFind(text, "sell") >= 0 || StringFind(text, "Sell") >= 0)
      return -1.0;
   
   double val = StringToDouble(text);
   if(val > 0.5) return 1.0;
   if(val < -0.5) return -1.0;
   
   return 0.0;  // NEUTRAL
  }

//+------------------------------------------------------------------+
//| Liest die letzte Zeile einer CSV-Datei                           |
//+------------------------------------------------------------------+
bool ReadCSVFile(string filePath, double &buyPct, double &sellPct, double &signalVal)
  {
   // Versuch 1: FILE_COMMON
   int fileHandle = FileOpen(filePath, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   
   // Versuch 2: Ohne FILE_COMMON  
   if(fileHandle == INVALID_HANDLE)
      fileHandle = FileOpen(filePath, FILE_READ | FILE_TXT | FILE_ANSI);
   
   // Versuch 3: Nur Dateiname
   if(fileHandle == INVALID_HANDLE)
     {
      // Dateiname extrahieren
      string justFileName = filePath;
      for(int p = StringLen(filePath) - 1; p >= 0; p--)
        {
         string ch = StringSubstr(filePath, p, 1);
         if(ch == "\\" || ch == "/")
           {
            justFileName = StringSubstr(filePath, p + 1);
            break;
           }
        }
      if(justFileName != filePath)
        {
         fileHandle = FileOpen(justFileName, FILE_READ | FILE_TXT | FILE_ANSI);
         if(fileHandle == INVALID_HANDLE)
            fileHandle = FileOpen(justFileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
        }
     }
   
   if(fileHandle == INVALID_HANDLE)
      return false;
   
   // Letzte Zeile lesen
   string lastLine = "";
   while(!FileIsEnding(fileHandle))
     {
      string line = FileReadString(fileHandle);
      if(StringLen(line) > 5) // Mindestens etwas Inhalt
         lastLine = line;
     }
   FileClose(fileHandle);
   
   if(StringLen(lastLine) < 5)
      return false;
   
   // Parsen: Format "Datum;Buy%;Sell%;Signal"
   string parts[];
   int count = StringSplit(lastLine, ';', parts);
   if(count < 4)
      return false;
   
   buyPct    = ParseGermanDouble(parts[1]);
   sellPct   = ParseGermanDouble(parts[2]);
   signalVal = ParseSignal(parts[3]);
   
   return true;
  }

//+------------------------------------------------------------------+
//| Lädt alle CSV-Dateien und findet Daten für aktuelles Symbol      |
//+------------------------------------------------------------------+
bool LoadAllData()
  {
   string normalizedSymbol = NormalizeSymbol(_Symbol);
   
   if(DebugMode)
     {
      Print("========================================================");
      Print("  LoadAllData() gestartet");
      Print("  InputDataPath: ", InputDataPath);
      Print("  Chart-Symbol: ", _Symbol, " -> ", normalizedSymbol);
      Print("========================================================");
     }
   
   // Pfad normalisieren
   string path = InputDataPath;
   if(StringLen(path) > 0)
     {
      string lastChar = StringSubstr(path, StringLen(path) - 1, 1);
      if(lastChar != "\\" && lastChar != "/")
         path += "\\";
     }
   
   // Bekannte Paare laden
   string knownPairs[] = {
      "AUD_JPY", "AUD_USD", "BTC_USD", "EUR_AUD", "EUR_CHF",
      "EUR_GBP", "EUR_JPY", "EUR_USD", "GBP_CHF", "GBP_JPY",
      "GBP_USD", "NZD_USD", "USD_CAD", "USD_CHF", "USD_JPY",
      "XAG_USD", "XAU_USD"
   };
   
   int totalPairs = ArraySize(knownPairs);
   int loadedCount = 0;
   bool foundCurrentSymbol = false;
   
   // Temporäre Arrays
   ArrayResize(g_symbolNames, 0);
   ArrayResize(g_buyPercent, 0);
   ArrayResize(g_sellPercent, 0);
   ArrayResize(g_signal, 0);
   g_symbolCount = 0;
   
   for(int i = 0; i < totalPairs; i++)
     {
      string fullPath = path + knownPairs[i] + ".csv";
      double buyPct, sellPct, signalVal;
      
      if(ReadCSVFile(fullPath, buyPct, sellPct, signalVal))
        {
         ArrayResize(g_symbolNames, loadedCount + 1);
         ArrayResize(g_buyPercent, loadedCount + 1);
         ArrayResize(g_sellPercent, loadedCount + 1);
         ArrayResize(g_signal, loadedCount + 1);
         
         g_symbolNames[loadedCount] = knownPairs[i];
         g_buyPercent[loadedCount] = buyPct;
         g_sellPercent[loadedCount] = sellPct;
         g_signal[loadedCount] = signalVal;
         loadedCount++;
         
         // Ist das unser Chart-Symbol?
         if(knownPairs[i] == normalizedSymbol)
           {
            g_currentBuy = buyPct;
            g_currentSell = sellPct;
            g_currentSignal = signalVal;
            foundCurrentSymbol = true;
            
            if(DebugMode) 
               Print("  >>> ", knownPairs[i], " = AKTUELLES SYMBOL! Buy:", 
                     DoubleToString(buyPct, 1), "% Sell:", DoubleToString(sellPct, 1), 
                     "% Signal:", (signalVal > 0.5 ? "BUY" : signalVal < -0.5 ? "SELL" : "NEUTRAL"));
           }
         else if(DebugMode)
           {
            Print("  ", knownPairs[i], " Buy:", DoubleToString(buyPct, 1), 
                  "% Sell:", DoubleToString(sellPct, 1), "%");
           }
        }
      else
        {
         if(DebugMode) Print("  ", knownPairs[i], " -> NICHT GELADEN");
        }
     }
   
   g_symbolCount = loadedCount;
   g_dataLoaded = (loadedCount > 0 && foundCurrentSymbol);
   
   Print("=== FXSSI: ", loadedCount, " Symbole geladen, ", 
         normalizedSymbol, (foundCurrentSymbol ? " GEFUNDEN" : " NICHT GEFUNDEN"), " ===");
   
   if(!foundCurrentSymbol && loadedCount > 0)
     {
      Print("WARNUNG: Chart-Symbol ", _Symbol, " (", normalizedSymbol, ") nicht in den Daten!");
      Print("Verfuegbare Symbole:");
      for(int i = 0; i < g_symbolCount; i++)
         Print("  [", i, "] ", g_symbolNames[i]);
     }
   
   if(loadedCount == 0)
     {
      bool isInTester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
      string agentFiles = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";
      string commonFiles = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\";
      
      Print("!!! FEHLER: Keine CSV-Dateien geladen!");
      Print("  Gesucht in: ", agentFiles, path);
      Print("  Und in:     ", commonFiles, path);
      
      if(isInTester)
        {
         Alert("FXSSI: KEINE CSV-Dateien gefunden!\n\n",
               "Gesucht in:\n",
               "1) ", agentFiles, path, "\n",
               "2) ", commonFiles, path, "\n\n",
               "LOESUNG: Kopieren Sie '", InputDataPath, "'\n",
               "nach: ", commonFiles);
        }
      return false;
     }
   
   return true;
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   bool isInTester = MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION);
   
   // Pfade berechnen fuer Anzeige
   string agentFiles = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";
   string commonFiles = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\";
   string normalizedPath = InputDataPath;
   if(StringLen(normalizedPath) > 0)
     {
      string lastChar = StringSubstr(normalizedPath, StringLen(normalizedPath) - 1, 1);
      if(lastChar != "\\" && lastChar != "/")
         normalizedPath += "\\";
     }
   
   Print("========================================================");
   Print("  FXSSI Signal Reader ", INDICATOR_VERSION, " - INIT");
   Print("========================================================");
   Print("  Umgebung: ", isInTester ? "STRATEGY TESTER" : "LIVE");
   Print("  Symbol: ", _Symbol, " -> ", NormalizeSymbol(_Symbol));
   Print("  Debug-Modus: ", DebugMode ? "AN" : "AUS");
   Print("  ");
   Print("  --- Erwartete Datei-Pfade ---");
   Print("  Pfad 1 (Agent/Local): ", agentFiles, normalizedPath);
   Print("  Pfad 2 (Common):      ", commonFiles, normalizedPath);
   Print("  Beispiel-Datei:        ", normalizedPath, "EUR_USD.csv");
   Print("  ---");
   
   // 4 Buffers registrieren (als Plot-Buffers damit CopyBuffer funktioniert)
   SetIndexBuffer(0, BufSymbolCount, INDICATOR_DATA);
   SetIndexBuffer(1, BufBuyPercent,  INDICATOR_DATA);
   SetIndexBuffer(2, BufSellPercent, INDICATOR_DATA);
   SetIndexBuffer(3, BufSignal,      INDICATOR_DATA);
   
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
   
   // Daten laden
   if(!LoadAllData())
     {
      Print("!!! FEHLER: Initialer Datenlade FEHLGESCHLAGEN!");
      Print("!!! Keine CSV-Dateien gefunden.");
      Print("!!! Gesucht in: ", agentFiles, normalizedPath);
      Print("!!! Und in:     ", commonFiles, normalizedPath);
      
      Alert("FXSSI Signal Reader - FEHLER!\n\n",
            "Keine CSV-Dateien gefunden!\n\n",
            "Gesucht in:\n",
            "1) ", agentFiles, normalizedPath, "\n",
            "2) ", commonFiles, normalizedPath, "\n\n",
            "LOESUNG: CSV-Dateien in eines der\n",
            "obigen Verzeichnisse kopieren.\n\n",
            "Indikator wird gestoppt.");
      
      return(INIT_FAILED);
     }
   
   // Daten geladen - pruefen ob aktuelles Chart-Symbol dabei ist
   if(!g_dataLoaded)
     {
      Print("!!! WARNUNG: ", g_symbolCount, " Symbole geladen, aber ", 
            NormalizeSymbol(_Symbol), " ist NICHT dabei!");
      
      string verfuegbar = "";
      for(int i = 0; i < g_symbolCount; i++)
        {
         if(i > 0) verfuegbar += ", ";
         verfuegbar += g_symbolNames[i];
        }
      
      Alert("FXSSI Signal Reader - WARNUNG!\n\n",
            "Chart-Symbol ", _Symbol, " (", NormalizeSymbol(_Symbol), 
            ") wurde NICHT in den FXSSI-Daten gefunden!\n\n",
            "Verfuegbare Symbole:\n", verfuegbar, "\n\n",
            "Indikator wird gestoppt.");
      
      return(INIT_FAILED);
     }
   
   // Alles OK - Zusammenfassung ausgeben
   Print("  ");
   Print("  >>> DATEN ERFOLGREICH GELADEN <<<");
   Print("  Symbole geladen: ", g_symbolCount);
   Print("  Aktuelles Symbol: ", NormalizeSymbol(_Symbol));
   Print("  Buy:  ", DoubleToString(g_currentBuy, 1), "%");
   Print("  Sell: ", DoubleToString(g_currentSell, 1), "%");
   Print("  Signal: ", (g_currentSignal > 0.5 ? "BUY" : g_currentSignal < -0.5 ? "SELL" : "NEUTRAL"));
   
   // Indikator-Name
   string status = StringFormat("Buy:%.0f%% Sell:%.0f%% %s", 
      g_currentBuy, g_currentSell,
      (g_currentSignal > 0.5 ? "BUY" : g_currentSignal < -0.5 ? "SELL" : "NEUTRAL"));
   IndicatorSetString(INDICATOR_SHORTNAME, 
      StringFormat("FXSSI %s (%s) [%s]", INDICATOR_VERSION, NormalizeSymbol(_Symbol), status));
   
   Print("========================================================");
   Print("  FXSSI Signal Reader INIT OK");
   Print("========================================================");
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("FXSSI Signal Reader beendet. Grund: ", reason);
  }



//+------------------------------------------------------------------+
//| OnCalculate - Buffers befüllen                                    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total > 0)
     {
      // Alle Bars mit den gleichen Werten füllen
      // (unsere Daten sind zeitunabhängig)
      ArrayInitialize(BufSymbolCount, (double)g_symbolCount);
      ArrayInitialize(BufBuyPercent,  g_currentBuy);
      ArrayInitialize(BufSellPercent, g_currentSell);
      ArrayInitialize(BufSignal,      g_currentSignal);
     }
   
   return(rates_total);
  }
//+------------------------------------------------------------------+
