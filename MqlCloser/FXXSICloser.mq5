//+------------------------------------------------------------------+
//|                                                       FXSSICloser.mq5 |
//|                                  Copyright 2024, SignalWatcher   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, SignalWatcher"
#property link      ""
#property version   "1.00"
#property description "Überwacht Signaldatei und schließt konfliktbehaftete Positionen"

//--- Input-Parameter
input string     SignalFileName   = "last_known_signals.csv"; // Dateiname in MQL5/Files
input int        CheckInterval    = 5;                         // Prüfintervall in Minuten

//--- Globale Variablen
datetime         g_lastCheckTime  = 0;
int              g_timerSeconds   = 0;
string           g_globalVarName  = "CloserConflictCount";

//--- Label-Namen für Chart-Anzeige
string           g_labelCountdown = "CloserCountdown";
string           g_labelCounter   = "CloserCounter";

//--- Struktur für Signale
struct SignalData
{
   string symbol;
   string direction;  // "BUY", "SELL", "NEUTRAL"
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Closer EA gestartet ===");
   Print("Signaldatei: ", SignalFileName);
   Print("Prüfintervall: ", CheckInterval, " Minuten");
   
   //--- Timer initialisieren (1 Sekunde für Countdown-Anzeige)
   if(!EventSetTimer(1))
   {
      Print("FEHLER: Timer konnte nicht initialisiert werden!");
      return(INIT_FAILED);
   }
   
   //--- Persistenten Zähler initialisieren (falls nicht vorhanden)
   if(!GlobalVariableCheck(g_globalVarName))
   {
      GlobalVariableSet(g_globalVarName, 0);
      Print("Konflikt-Zähler initialisiert auf 0");
   }
   else
   {
      Print("Konflikt-Zähler geladen: ", (int)GlobalVariableGet(g_globalVarName));
   }
   
   //--- Erste Prüfung sofort durchführen
   g_lastCheckTime = TimeCurrent();
   CheckSignalsAndCloseConflicts();
   
   //--- Chart-Labels erstellen
   CreateChartLabels();
   UpdateChartDisplay();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Timer stoppen
   EventKillTimer();
   
   //--- Chart-Labels entfernen
   ObjectDelete(0, g_labelCountdown);
   ObjectDelete(0, g_labelCounter);
   
   Print("=== Closer EA beendet ===");
   Print("Grund: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Wir reagieren nicht auf jeden Tick, nur auf Timer
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Countdown aktualisieren
   UpdateChartDisplay();
   
   //--- Prüfen ob Intervall abgelaufen ist
   datetime now = TimeCurrent();
   int elapsedSeconds = (int)(now - g_lastCheckTime);
   
   if(elapsedSeconds >= CheckInterval * 60)
   {
      g_lastCheckTime = now;
      CheckSignalsAndCloseConflicts();
   }
}

//+------------------------------------------------------------------+
//| Erstellt die Chart-Labels                                        |
//+------------------------------------------------------------------+
void CreateChartLabels()
{
   //--- Countdown-Label
   ObjectCreate(0, g_labelCountdown, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_labelCountdown, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_labelCountdown, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_labelCountdown, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, g_labelCountdown, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, g_labelCountdown, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, g_labelCountdown, OBJPROP_FONT, "Arial Bold");
   
   //--- Counter-Label
   ObjectCreate(0, g_labelCounter, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_labelCounter, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_labelCounter, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_labelCounter, OBJPROP_YDISTANCE, 50);
   ObjectSetInteger(0, g_labelCounter, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, g_labelCounter, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, g_labelCounter, OBJPROP_FONT, "Arial Bold");
}

//+------------------------------------------------------------------+
//| Aktualisiert die Chart-Anzeige                                   |
//+------------------------------------------------------------------+
void UpdateChartDisplay()
{
   //--- Berechne verbleibende Zeit
   datetime now = TimeCurrent();
   int elapsedSeconds = (int)(now - g_lastCheckTime);
   int remainingSeconds = (CheckInterval * 60) - elapsedSeconds;
   
   if(remainingSeconds < 0) remainingSeconds = 0;
   
   int minutes = remainingSeconds / 60;
   int seconds = remainingSeconds % 60;
   
   //--- Countdown-Text
   string countdownText = StringFormat("Nächste Datei-Prüfung in: %d Min %d Sek", minutes, seconds);
   ObjectSetString(0, g_labelCountdown, OBJPROP_TEXT, countdownText);
   
   //--- Counter-Text
   int conflictCount = (int)GlobalVariableGet(g_globalVarName);
   string counterText = StringFormat("Bereits geschlossene Konflikt-Trades: %d", conflictCount);
   ObjectSetString(0, g_labelCounter, OBJPROP_TEXT, counterText);
}

//+------------------------------------------------------------------+
//| Liest die Signaldatei ein und gibt Array zurück                 |
//+------------------------------------------------------------------+
bool ReadSignalFile(SignalData &signals[])
{
   ArrayResize(signals, 0);
   
   string filepath = SignalFileName;
   int filehandle = FileOpen(filepath, FILE_READ|FILE_TXT|FILE_ANSI);
   
   if(filehandle == INVALID_HANDLE)
   {
      Print("FEHLER: Signaldatei konnte nicht geöffnet werden: ", filepath);
      Print("Fehlercode: ", GetLastError());
      return false;
   }
   
   Print("--- Lese Signaldatei: ", filepath, " ---");
   
   int lineCount = 0;
   bool isFirstLine = true; // Flag für Header-Zeile
   
   while(!FileIsEnding(filehandle))
   {
      string line = FileReadString(filehandle);
      StringTrimLeft(line);
      StringTrimRight(line);
      
      //--- Erste Zeile (Header) überspringen
      if(isFirstLine)
      {
         isFirstLine = false;
         Print("Header übersprungen: ", line);
         continue;
      }
      
      //--- Leere Zeilen überspringen
      if(StringLen(line) == 0)
         continue;
      
      //--- Zeile parsen (Format: Symbol;Richtung)
      string parts[];
      int partCount = StringSplit(line, ';', parts);
      
      if(partCount != 2)
      {
         Print("WARNUNG: Ungültige Zeile übersprungen: ", line);
         continue;
      }
      
      //--- Daten aufbereiten
      string symbol = parts[0];
      StringTrimLeft(symbol);
      StringTrimRight(symbol);
      
      string direction = parts[1];
      StringTrimLeft(direction);
      StringTrimRight(direction);
      StringToUpper(direction);
      
      //--- Validierung
      if(direction != "BUY" && direction != "SELL" && direction != "NEUTRAL")
      {
         Print("WARNUNG: Ungültige Richtung '", direction, "' für Symbol ", symbol);
         continue;
      }
      
      //--- Signal hinzufügen
      int idx = ArraySize(signals);
      ArrayResize(signals, idx + 1);
      signals[idx].symbol = symbol;
      signals[idx].direction = direction;
      
      Print("Signal gelesen: ", symbol, " -> ", direction);
      lineCount++;
   }
   
   FileClose(filehandle);
   Print("Signaldatei geschlossen. ", lineCount, " Signale geladen.");
   
   return true;
}

//+------------------------------------------------------------------+
//| Hauptfunktion: Prüft Signale und schließt Konflikte             |
//+------------------------------------------------------------------+
void CheckSignalsAndCloseConflicts()
{
   Print("========================================");
   Print("=== Starte Konfliktprüfung ===");
   Print("Zeit: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("========================================");
   
   //--- Signaldatei einlesen
   SignalData signals[];
   if(!ReadSignalFile(signals))
   {
      Print("FEHLER: Signaldatei konnte nicht gelesen werden!");
      return;
   }
   
   if(ArraySize(signals) == 0)
   {
      Print("WARNUNG: Keine Signale in Datei gefunden!");
      return;
   }
   
   //--- Für jedes Signal die Positionen prüfen
   int totalClosed = 0;
   
   for(int i = 0; i < ArraySize(signals); i++)
   {
      string symbol = signals[i].symbol;
      string direction = signals[i].direction;
      
      Print("--- Prüfe Symbol: ", symbol, " (Signal: ", direction, ") ---");
      
      //--- NEUTRAL-Signal = keine Aktion
      if(direction == "NEUTRAL")
      {
         Print("Signal ist NEUTRAL - keine Aktion");
         continue;
      }
      
      //--- Alle Positionen für dieses Symbol durchgehen
      int closed = CloseConflictingPositions(symbol, direction);
      totalClosed += closed;
   }
   
   Print("========================================");
   Print("=== Konfliktprüfung abgeschlossen ===");
   Print("Geschlossene Positionen: ", totalClosed);
   Print("========================================");
   
   //--- Chart aktualisieren
   UpdateChartDisplay();
}

//+------------------------------------------------------------------+
//| Schließt alle konfliktbehafteten Positionen für ein Symbol      |
//+------------------------------------------------------------------+
int CloseConflictingPositions(string symbol, string signalDirection)
{
   int closedCount = 0;
   
   //--- Alle Positionen durchgehen
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      
      //--- Position selektieren
      if(!PositionSelectByTicket(ticket))
         continue;
      
      //--- Nur Positionen des gesuchten Symbols
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      if(posSymbol != symbol)
         continue;
      
      //--- Positionstyp ermitteln
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string posDirection = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      
      //--- Konfliktprüfung
      bool isConflict = false;
      
      if(posDirection == "BUY" && signalDirection == "SELL")
         isConflict = true;
      
      if(posDirection == "SELL" && signalDirection == "BUY")
         isConflict = true;
      
      if(!isConflict)
      {
         Print("Position #", ticket, " (", posDirection, ") ist OK mit Signal (", signalDirection, ")");
         continue;
      }
      
      //--- Konflikt gefunden - Position schließen
      Print(">>> KONFLIKT gefunden! Position #", ticket, " (", posDirection, ") vs Signal (", signalDirection, ")");
      
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol = symbol;
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.deviation = 10;
      request.magic = 0;
      request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price = (posType == POSITION_TYPE_BUY) ? 
                      SymbolInfoDouble(symbol, SYMBOL_BID) : 
                      SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print(">>> Position #", ticket, " ERFOLGREICH geschlossen!");
            Print("    Symbol: ", symbol);
            Print("    Alte Richtung: ", posDirection);
            Print("    Neues Signal: ", signalDirection);
            Print("    Schließpreis: ", result.price);
            Print("    Zeit: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
            
            //--- Zähler erhöhen
            double currentCount = GlobalVariableGet(g_globalVarName);
            GlobalVariableSet(g_globalVarName, currentCount + 1);
            
            closedCount++;
         }
         else
         {
            Print("FEHLER beim Schließen - Retcode: ", result.retcode, " - ", result.comment);
         }
      }
      else
      {
         Print("FEHLER: OrderSend fehlgeschlagen - Error: ", GetLastError());
      }
   }
   
   return closedCount;
}

//+------------------------------------------------------------------+