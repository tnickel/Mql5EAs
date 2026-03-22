//+------------------------------------------------------------------+
//|                                                   MQL5Notify.mq5 |
//|                                          Trade Monitor & Notifier |
//|                              Überwacht Trades und sendet E-Mails  |
//+------------------------------------------------------------------+
#property copyright "Thomas"
#property link      ""
#property version   "1.25"
#property description "Überwacht Trade-Aktivitäten und sendet E-Mail-Benachrichtigungen"
#property description "bei neuen oder geschlossenen Trades in konfigurierbaren Intervallen."

//+------------------------------------------------------------------+
//| Input-Parameter                                                   |
//+------------------------------------------------------------------+
input int    InpCheckIntervalMinutes = 5;       // Prüf-Intervall in Minuten (1-n)
input string InpEmailSubjectPrefix  = "[MT5] "; // E-Mail Betreff-Prefix
input bool   InpLogToExperts        = true;     // Log-Ausgabe im Experts-Tab
input bool   InpTradeReportEnabled  = true;     // Trade-Report bei Eröffnung/Schluss
input bool   InpDailyReportEnabled  = true;     // Tagesreport aktivieren
input int    InpDailyReportHour     = 22;       // Tagesreport Stunde (0-23)
input int    InpDailyReportMinute   = 00;       // Tagesreport Minute (0-59)
input bool   InpOpenEquityReport    = false;    // Open Equity Reporting aktivieren
input bool   InpWeeklyReportEnabled = true;     // Wochenreport aktivieren (Freitag 20:00)
input int    InpWeeklyReportHour    = 20;       // Wochenreport Stunde (0-23)
input bool   InpMonthlyReportEnabled= true;     // Monatsreport aktivieren (Monatsende 20:00)
input int    InpMonthlyReportHour   = 20;       // Monatsreport Stunde (0-23)

//+------------------------------------------------------------------+
//| Konstanten                                                        |
//+------------------------------------------------------------------+
#define EA_VERSION "1.25"
#define LABEL_PREFIX "MQL5Notify_"

// Logdatei für Report-Persistenz über Neustarts
#define REPORT_LOG_FILE "MQL5Notify_ReportLog.txt"

//+------------------------------------------------------------------+
//| Struktur für Trade-Equity-Tracking                                |
//+------------------------------------------------------------------+
struct TradeEquityInfo
{
   ulong  positionId;     // Position-ID
   double maxEquity;      // Maximale Equity für diesen Trade
};

//+------------------------------------------------------------------+
//| Globale Variablen                                                 |
//+------------------------------------------------------------------+
datetime g_lastCheckTime         = 0;       // Zeitpunkt der letzten Prüfung
datetime g_lastNotificationTime  = 0;       // Zeitpunkt der letzten E-Mail
int      g_lastDealsTotal        = 0;       // Anzahl Deals bei letzter Prüfung
ulong    g_knownDealTickets[];              // Array mit bereits bekannten Deal-Tickets
int      g_notificationCount     = 0;       // Anzahl gesendeter E-Mails


// Equity-Tracking
TradeEquityInfo g_tradeEquity[];            // Array für per-Trade max Equity
double   g_maxDailyEquity        = 0;       // Max Account-Equity des Tages
double   g_minDailyEquity        = 0;       // Min Account-Equity des Tages
int      g_equityTrackingDay     = 0;       // Tag für Equity-Reset

// Cache für geschlossene Trades (Optimierung)
long     g_closedMagicNumbers[];            // Magic Numbers mit geschlossenen Trades heute
double   g_closedMagicProfit[];             // Profit pro Magic (geschlossen)
int      g_closedCacheDay        = 0;       // Tag für den der Cache gilt
int      g_closedCacheDealsCount = 0;       // Anzahl Deals beim letzten Cache-Update

// Startup-Schutz
int      g_startupTickCount      = 0;       // Zählt Timer-Ticks seit Startup (Warmup)

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Parameter-Validierung
   if(InpCheckIntervalMinutes < 1)
   {
      Print("FEHLER: Intervall muss mindestens 1 Minute sein!");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // E-Mail-Konfiguration prüfen
   if(!TerminalInfoInteger(TERMINAL_EMAIL_ENABLED))
   {
      Print("WARNUNG: E-Mail ist im Terminal nicht aktiviert!");
      Print("Bitte unter Extras -> Optionen -> E-Mail konfigurieren.");
   }
   
   // History laden - komplette History seit Account-Eröffnung
   if(!HistorySelect(0, TimeCurrent()))
   {
      Print("FEHLER: Konnte Trade-History nicht laden!");
      return(INIT_FAILED);
   }
   
   // Initiale Deal-Liste aufbauen (damit wir beim Start keine Altdaten mailen)
   InitializeKnownDeals();
   
   // Report-Logdatei initialisieren (Persistenz über Neustarts)
   InitReportLog();
   
   // Startup-Warmup zurücksetzen
   g_startupTickCount = 0;
   
   // Timer starten (jede Minute prüfen, ob Intervall erreicht)
   EventSetTimer(60);
   g_lastCheckTime = TimeCurrent();
   
   Print("MQL5Notify gestartet - Prüf-Intervall: ", InpCheckIntervalMinutes, " Minute(n)");
   Print("Bekannte Deals beim Start: ", ArraySize(g_knownDealTickets));
   
   // Chart-Info anzeigen
   UpdateChartInfo();
   
   // Chart-Balkenfarben transparent machen für bessere Lesbarkeit
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrNONE);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrNONE);
   // Tick-Anzeige und Last-Price-Linie ausblenden
   ChartSetInteger(0, CHART_SHOW_LAST_LINE, false);
   ChartSetInteger(0, CHART_COLOR_LAST, clrNONE);
   ChartSetInteger(0, CHART_COLOR_BID, clrNONE);
   ChartSetInteger(0, CHART_COLOR_ASK, clrNONE);
   // Trade History Pfeile ausblenden
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);
   ChartRedraw(0);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Chart-Labels entfernen
   ObjectDelete(0, LABEL_PREFIX + "Version");
   ObjectDelete(0, LABEL_PREFIX + "Intervall");
   ObjectDelete(0, LABEL_PREFIX + "LastNotify");
   ObjectDelete(0, LABEL_PREFIX + "Status");
   ObjectDelete(0, LABEL_PREFIX + "EmailCount");
   ObjectDelete(0, LABEL_PREFIX + "DailyEquity");
   for(int j = 0; j < 20; j++)
   {
      ObjectDelete(0, LABEL_PREFIX + "PosEquity" + IntegerToString(j));
   }
   ChartRedraw(0);
   
   Print("MQL5Notify gestoppt. Grund: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function - wird jede Minute aufgerufen                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime currentTime = TimeCurrent();
   
   // Startup-Warmup: Erste 2 Minuten nach Start keine Reports prüfen
   // (TimeCurrent() kann nach Neustart veraltete Daten der letzten Sitzung liefern)
   g_startupTickCount++;
   
   if(g_startupTickCount > 2)
   {
      // Tagesreport prüfen (wenn aktiviert und neuer Tag)
      if(InpDailyReportEnabled)
      {
         CheckAndSendDailyReport();
      }
      
      // Wochenreport prüfen (wenn aktiviert)
      if(InpWeeklyReportEnabled)
      {
         CheckAndSendWeeklyReport();
      }
      
      // Monatsreport prüfen (wenn aktiviert)
      if(InpMonthlyReportEnabled)
      {
         CheckAndSendMonthlyReport();
      }
   }
   else if(InpLogToExperts)
   {
      Print("Startup-Warmup: Report-Prüfung übersprungen (", g_startupTickCount, "/2)");
   }
   
   // Prüfen ob das konfigurierte Intervall erreicht ist
   if(currentTime - g_lastCheckTime < InpCheckIntervalMinutes * 60)
      return;
   
   g_lastCheckTime = currentTime;
   
   // Equity-Tracking zuerst aktualisieren (damit Chart aktuelle Werte zeigt)
   UpdateEquityTracking();
   
   // Chart-Info aktualisieren (nur im Prüf-Intervall)
   UpdateChartInfo();
   
   // History aktualisieren
   if(!HistorySelect(0, TimeCurrent()))
   {
      Print("WARNUNG: Konnte Trade-History nicht aktualisieren!");
      return;
   }
   
   // Neue Deals suchen (nur wenn Trade-Report aktiviert)
   if(InpTradeReportEnabled)
   {
      CheckForNewDeals();
   }
   else
   {
      // Trotzdem Deals als bekannt markieren, damit später kein Rückstau entsteht
      UpdateKnownDealsWithoutNotification();
   }
}

//+------------------------------------------------------------------+
//| Initiale Deal-Liste aufbauen                                      |
//+------------------------------------------------------------------+
void InitializeKnownDeals()
{
   int totalDeals = HistoryDealsTotal();
   ArrayResize(g_knownDealTickets, totalDeals);
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      g_knownDealTickets[i] = ticket;
   }
   
   g_lastDealsTotal = totalDeals;
}

//+------------------------------------------------------------------+
//| Report-Logdatei initialisieren                                    |
//+------------------------------------------------------------------+
void InitReportLog()
{
   // Prüfen ob die Logdatei existiert, wenn nicht erstellen
   int handle = FileOpen(REPORT_LOG_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      // Datei existiert noch nicht - erstellen mit Header
      handle = FileOpen(REPORT_LOG_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         FileWriteString(handle, "# MQL5Notify Report-Log\n");
         
         // Beim allerersten Start: Bereits vergangene Report-Zeiten als gesendet markieren
         // Verhindert dass beim ersten Start sofort Reports auf Vorrat gesendet werden
         MqlDateTime dtInit;
         TimeCurrent(dtInit);
         int currentMinutes = dtInit.hour * 60 + dtInit.min;
         string todayStr = TimeToString(TimeCurrent(), TIME_DATE);
         
         // Tagesreport: Wenn aktuelle Zeit >= Report-Zeit, als gesendet markieren
         int dailyTarget = InpDailyReportHour * 60 + InpDailyReportMinute;
         if(currentMinutes >= dailyTarget)
         {
            FileWriteString(handle, todayStr + "|DAILY|OK|INIT\n");
            if(InpLogToExperts) Print("Report-Log Init: Daily als gesendet markiert (Zeit bereits vorbei)");
         }
         
         // Wochenreport: Wenn Freitag und aktuelle Zeit >= Report-Zeit
         if(dtInit.day_of_week == 5)
         {
            int weeklyTarget = InpWeeklyReportHour * 60;
            if(currentMinutes >= weeklyTarget)
            {
               FileWriteString(handle, todayStr + "|WEEKLY|OK|INIT\n");
               if(InpLogToExperts) Print("Report-Log Init: Weekly als gesendet markiert (Zeit bereits vorbei)");
            }
         }
         
         // Monatsreport: Wenn letzter Monatstag und aktuelle Zeit >= Report-Zeit
         if(IsLastDayOfMonth())
         {
            int monthlyTarget = InpMonthlyReportHour * 60;
            if(currentMinutes >= monthlyTarget)
            {
               FileWriteString(handle, todayStr + "|MONTHLY|OK|INIT\n");
               if(InpLogToExperts) Print("Report-Log Init: Monthly als gesendet markiert (Zeit bereits vorbei)");
            }
         }
         
         FileClose(handle);
         if(InpLogToExperts) Print("Report-Logdatei erstellt: ", REPORT_LOG_FILE);
      }
      else
      {
         Print("FEHLER: Konnte Report-Logdatei nicht erstellen!");
      }
   }
   else
   {
      FileClose(handle);
      if(InpLogToExperts) Print("Report-Logdatei gefunden: ", REPORT_LOG_FILE);
   }
}

//+------------------------------------------------------------------+
//| Prüfen ob ein Report bereits gesendet wurde (aus Logdatei)        |
//+------------------------------------------------------------------+
bool IsReportAlreadySent(string reportType, string dateKey)
{
   int handle = FileOpen(REPORT_LOG_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   
   string searchPattern = dateKey + "|" + reportType + "|OK";
   
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(StringFind(line, searchPattern) >= 0)
      {
         FileClose(handle);
         return true;
      }
   }
   
   FileClose(handle);
   return false;
}

//+------------------------------------------------------------------+
//| Report-Sendung in Logdatei protokollieren                         |
//+------------------------------------------------------------------+
void LogReportSent(string reportType, string dateKey)
{
   int handle = FileOpen(REPORT_LOG_FILE, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("FEHLER: Konnte Report-Logdatei nicht öffnen zum Schreiben!");
      return;
   }
   
   // Ans Ende der Datei springen
   FileSeek(handle, 0, SEEK_END);
   
   string logEntry = dateKey + "|" + reportType + "|OK\n";
   FileWriteString(handle, logEntry);
   FileClose(handle);
   
   if(InpLogToExperts)
      Print("Report-Log: ", reportType, " für ", dateKey, " als gesendet protokolliert");
}

//+------------------------------------------------------------------+
//| Auf neue Deals prüfen und E-Mail senden                           |
//+------------------------------------------------------------------+
void CheckForNewDeals()
{
   int totalDeals = HistoryDealsTotal();
   
   // Schnell-Check: Hat sich die Anzahl geändert?
   if(totalDeals == g_lastDealsTotal)
      return;
   
   // Neue Deals sammeln
   string openedTrades     = "";
   string closedTrades     = "";
   string openedSymbols    = "";  // Unique Symbole für eröffnete Trades
   string closedSymbols    = "";  // Unique Symbole für geschlossene Trades
   string openedDirSymbols = "";  // "BUY EURGBP" / "SELL USDJPY" für Betreff
   double closedProfit     = 0.0; // Summe Profit+Comm+Swap aller geschlossenen Trades
   int    openCount        = 0;
   int    closeCount       = 0;
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      
      // Ist dieser Deal bereits bekannt?
      if(IsDealKnown(ticket))
         continue;
      
      // Neuen Deal zur bekannten Liste hinzufügen
      AddKnownDeal(ticket);
      
      // Deal-Informationen abrufen
      string dealInfo = FormatDealInfo(ticket);
      
      if(dealInfo == "")
         continue;
      
      // Deal-Typ bestimmen
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE  type  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      
      if(entry == DEAL_ENTRY_IN)
      {
         // Trade eröffnet
         openedTrades += dealInfo + "\n";
         openCount++;
         
         if(dealSymbol != "")
         {
            openedSymbols = AddUniqueSymbol(openedSymbols, dealSymbol);
            
            // "BUY EURUSD" oder "SELL EURUSD" für Betreff aufbauen
            string direction = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            string dirSym    = direction + " " + dealSymbol;
            if(StringFind(openedDirSymbols, dirSym) < 0)
            {
               if(openedDirSymbols != "") openedDirSymbols += " ";
               openedDirSymbols += dirSym;
            }
         }
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         // Trade geschlossen
         closedTrades += dealInfo + "\n";
         closeCount++;
         
         if(dealSymbol != "")
            closedSymbols = AddUniqueSymbol(closedSymbols, dealSymbol);
         
         // Profit für Betreff summieren
         closedProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP);
      }
      else if(type == DEAL_TYPE_BALANCE || type == DEAL_TYPE_CREDIT)
      {
         // Balance/Credit-Operationen ignorieren wir
         continue;
      }
      else
      {
         // Sonstige Deals (z.B. Korrekturen)
         closedTrades += dealInfo + "\n";
         closeCount++;
         
         if(dealSymbol != "")
            closedSymbols = AddUniqueSymbol(closedSymbols, dealSymbol);
      }
   }
   
   g_lastDealsTotal = totalDeals;
   
   // E-Mail zusammenstellen und senden
   if(openCount > 0 || closeCount > 0)
   {
      SendNotificationEmail(openedTrades, closedTrades, openCount, closeCount,
                            openedSymbols, openedDirSymbols, closedSymbols, closedProfit);
   }
}

//+------------------------------------------------------------------+
//| Prüfen ob ein Deal bereits bekannt ist                            |
//+------------------------------------------------------------------+
bool IsDealKnown(ulong ticket)
{
   int size = ArraySize(g_knownDealTickets);
   for(int i = 0; i < size; i++)
   {
      if(g_knownDealTickets[i] == ticket)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Deal zur bekannten Liste hinzufügen                               |
//+------------------------------------------------------------------+
void AddKnownDeal(ulong ticket)
{
   int size = ArraySize(g_knownDealTickets);
   ArrayResize(g_knownDealTickets, size + 1);
   g_knownDealTickets[size] = ticket;
}

//+------------------------------------------------------------------+
//| Deal-Informationen formatieren                                    |
//+------------------------------------------------------------------+
string FormatDealInfo(ulong ticket)
{
   // Deal-Daten abrufen
   string symbol     = HistoryDealGetString(ticket, DEAL_SYMBOL);
   double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   double price      = HistoryDealGetDouble(ticket, DEAL_PRICE);
   double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
   datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
   long     posId    = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   string   comment  = HistoryDealGetString(ticket, DEAL_COMMENT);
   
   ENUM_DEAL_TYPE  type  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
   
   // Leere Symbole überspringen (z.B. Balance-Operationen)
   if(symbol == "")
      return "";
   
   // Richtung bestimmen
   // Bei CLOSE-Deals ist der Deal-Typ invertiert (Schließen eines SELL = BUY-Deal),
   // daher invertieren wir die Richtung für die Anzeige der ursprünglichen Position.
   string direction = "";
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
   {
      // Close: invertieren -> SELL-Position schließen = BUY-Deal -> zeige "SELL"
      if(type == DEAL_TYPE_BUY)       direction = "SELL";
      else if(type == DEAL_TYPE_SELL) direction = "BUY";
      else                            direction = "OTHER";
   }
   else
   {
      // Open: Deal-Typ entspricht der Positionsrichtung
      if(type == DEAL_TYPE_BUY)       direction = "BUY";
      else if(type == DEAL_TYPE_SELL) direction = "SELL";
      else                            direction = "OTHER";
   }
   
   // Entry-Typ bestimmen
   string entryStr = "";
   if(entry == DEAL_ENTRY_IN)          entryStr = "OPEN";
   else if(entry == DEAL_ENTRY_OUT)    entryStr = "CLOSE";
   else if(entry == DEAL_ENTRY_INOUT)  entryStr = "REVERSE";
   else if(entry == DEAL_ENTRY_OUT_BY) entryStr = "CLOSE BY";
   
   // Digits für Preisformatierung
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 0) digits = 2; // Fallback
   
   // Formatierung
   string info = StringFormat("  %s | %s %s %.2f Lots @ %s | Pos#%d",
                              TimeToString(dealTime, TIME_DATE | TIME_MINUTES),
                              entryStr,
                              direction,
                              volume,
                              DoubleToString(price, digits),
                              posId);
   
   // Bei eröffneten Trades: SL/TP anzeigen (aus der Position holen)
   if(entry == DEAL_ENTRY_IN)
   {
      // Versuche die zugehörige Position zu finden
      double sl = 0;
      double tp = 0;
      
      // Suche nach der Position mit dieser Position-ID
      for(int p = 0; p < PositionsTotal(); p++)
      {
         ulong posTicket = PositionGetTicket(p);
         if(posTicket > 0)
         {
            long positionId = PositionGetInteger(POSITION_IDENTIFIER);
            if(positionId == posId)
            {
               sl = PositionGetDouble(POSITION_SL);
               tp = PositionGetDouble(POSITION_TP);
               break;
            }
         }
      }
      
      // SL/TP anzeigen falls gesetzt
      if(sl > 0 || tp > 0)
      {
         info += StringFormat(" | SL: %s | TP: %s",
                              sl > 0 ? DoubleToString(sl, digits) : "-",
                              tp > 0 ? DoubleToString(tp, digits) : "-");
      }
   }
   
   // Bei geschlossenen Trades: Profit und Max Equity anzeigen
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
   {
      double totalResult = profit + commission + swap;
      info += StringFormat(" | P/L: %.2f (Profit: %.2f, Comm: %.2f)",
                           totalResult, profit, commission);
      
      // Max Open Equity für diesen Trade anzeigen (falls aktiviert)
      if(InpOpenEquityReport)
      {
         double maxEquity = GetMaxEquityForPosition((ulong)posId);
         if(maxEquity != 0)
         {
            info += StringFormat(" | Max Open Equity: %+.2f", maxEquity);
         }
      }
      
      // Trade aus Equity-Tracking entfernen
      RemoveTradeFromEquityTracking((ulong)posId);
   }
   
   // Kommentar hinzufügen falls vorhanden
   if(comment != "")
      info += " | Kommentar: " + comment;
   
   // Symbol hervorheben
   info = "  [" + symbol + "] " + info;
   
   return info;
}

//+------------------------------------------------------------------+
//| E-Mail-Benachrichtigung senden                                    |
//+------------------------------------------------------------------+
void SendNotificationEmail(string openedTrades, string closedTrades,
                           int openCount,       int closeCount,
                           string openedSymbols,    string openedDirSymbols,
                           string closedSymbols,    double closedProfit)
{
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   
   // --- Betreff zusammenbauen ---
   string subject = InpEmailSubjectPrefix;
   
   if(closeCount > 0 && openCount == 0)
   {
      // Nur geschlossene Trades
      if(closedSymbols != "")
         subject += closedSymbols + " ";
      
      if(closeCount == 1)
         subject += StringFormat("1 Trade(s) geschlossen: Profit %+.2f %s", closedProfit, currency);
      else
         subject += StringFormat("%d Trade(s) geschlossen: Summe Profits %+.2f %s",
                                 closeCount, closedProfit, currency);
   }
   else if(openCount > 0 && closeCount == 0)
   {
      // Nur eröffnete Trades
      if(openedSymbols != "")
         subject += openedSymbols + " ";
      
      subject += StringFormat("%d Trade(s) %s eröffnet",
                              openCount,
                              openedDirSymbols != "" ? openedDirSymbols : "");
   }
   else
   {
      // Gemischte Benachrichtigung (eröffnet + geschlossen)
      string parts = "";
      
      if(openCount > 0)
      {
         if(openedSymbols != "") parts += openedSymbols + " ";
         parts += StringFormat("%d eröffnet", openCount);
      }
      if(closeCount > 0)
      {
         if(parts != "") parts += " | ";
         if(closedSymbols != "") parts += closedSymbols + " ";
         parts += StringFormat("%d geschlossen %+.2f %s", closeCount, closedProfit, currency);
      }
      subject += parts;
   }
   
   // --- Account-Info ---
   string accountInfo = StringFormat(
      "Account: %d (%s)\n"
      "Server: %s\n"
      "Balance: %.2f %s\n"
      "Equity: %.2f %s\n"
      "Zeitpunkt: %s\n",
      AccountInfoInteger(ACCOUNT_LOGIN),
      AccountInfoString(ACCOUNT_NAME),
      AccountInfoString(ACCOUNT_SERVER),
      AccountInfoDouble(ACCOUNT_BALANCE), currency,
      AccountInfoDouble(ACCOUNT_EQUITY),  currency,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)
   );
   
   // --- E-Mail-Body ---
   string body = "=== MQL5 Trade Notification ===\n\n";
   body += accountInfo;
   body += "\n";
   
   if(openCount > 0)
   {
      body += StringFormat("--- %d TRADE(S) ERÖFFNET ---\n", openCount);
      body += openedTrades;
      body += "\n";
   }
   
   if(closeCount > 0)
   {
      body += StringFormat("--- %d TRADE(S) GESCHLOSSEN ---\n", closeCount);
      body += closedTrades;
      body += StringFormat("Gesamt geschlossener P/L: %+.2f %s\n\n", closedProfit, currency);
   }
   
   // Offene Positionen anhängen
   body += GetOpenPositionsInfo();
   
   // Tagesbilanz
   double todayPL    = GetTodayClosedPL();
   string todayPLStr = StringFormat("%+.2f %s", todayPL, currency);
   body += StringFormat("--- TAGESBILANZ (heute geschlossen): %s ---\n", todayPLStr);
   
   body += "\n=== Ende der Benachrichtigung ===";
   
   // E-Mail senden
   if(!SendMail(subject, body))
   {
      Print("FEHLER: E-Mail konnte nicht gesendet werden!");
      Print("Betreff: ", subject);
   }
   else
   {
      g_lastNotificationTime = TimeCurrent();
      g_notificationCount++;
      UpdateChartInfo();
      
      if(InpLogToExperts)
         Print("E-Mail gesendet: ", subject);
   }
   
   // Optional: Auch in Experts-Tab loggen
   if(InpLogToExperts)
   {
      Print("---");
      Print(body);
      Print("---");
   }
}

//+------------------------------------------------------------------+
//| Aktuelle offene Positionen als Info-Text                          |
//+------------------------------------------------------------------+
string GetOpenPositionsInfo()
{
   int total = PositionsTotal();
   
   if(total == 0)
      return "--- OFFENE POSITIONEN: keine ---\n";
   
   string info = StringFormat("--- %d OFFENE POSITION(EN) ---\n", total);
   
   double totalProfit = 0;
   
   for(int i = 0; i < total; i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0) continue;
      
      string symbol     = PositionGetString(POSITION_SYMBOL);
      double volume     = PositionGetDouble(POSITION_VOLUME);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPrice   = PositionGetDouble(POSITION_PRICE_CURRENT);
      double profit     = PositionGetDouble(POSITION_PROFIT);
      double swap       = PositionGetDouble(POSITION_SWAP);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string direction = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      
      // Position-ID für Max-Equity
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double maxEquity = GetMaxEquityForPosition(posId);
      
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits == 0) digits = 2;
      
      info += StringFormat("  [%s] %s %.2f Lots @ %s (aktuell: %s) | P/L: %.2f | Swap: %.2f",
                           symbol,
                           direction,
                           volume,
                           DoubleToString(openPrice, digits),
                           DoubleToString(curPrice, digits),
                           profit,
                           swap);
      
      // Max Equity anzeigen (falls aktiviert)
      if(InpOpenEquityReport && maxEquity != 0)
         info += StringFormat(" | Max: %+.2f", maxEquity);
      
      if(sl > 0 || tp > 0)
         info += StringFormat(" | SL: %s | TP: %s",
                              sl > 0 ? DoubleToString(sl, digits) : "-",
                              tp > 0 ? DoubleToString(tp, digits) : "-");
      
      info += StringFormat(" | Offen seit: %s", TimeToString(openTime, TIME_DATE | TIME_MINUTES));
      info += "\n";
      totalProfit += profit + swap;
   }
   
   info += StringFormat("  Gesamt offener P/L: %.2f %s\n",
                        totalProfit,
                        AccountInfoString(ACCOUNT_CURRENCY));
   
   return info;
}

//+------------------------------------------------------------------+
//| Chart-Label erstellen oder aktualisieren                          |
//+------------------------------------------------------------------+
void CreateChartLabel(string name, int xDist, int yDist, string text, color clr)
{
   string fullName = LABEL_PREFIX + name;
   
   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, fullName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, fullName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, 11);
      ObjectSetInteger(0, fullName, OBJPROP_BACK, false);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, xDist);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, yDist);
   ObjectSetString(0, fullName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Chart-Informationen aktualisieren                                 |
//+------------------------------------------------------------------+
void UpdateChartInfo()
{
   int x = 15;
   int y = 30;
   int lineHeight = 22;
   
   // Zeile 1: Version
   CreateChartLabel("Version", x, y,
      "MQL5Notify v" + EA_VERSION, clrDodgerBlue);
   
   // Zeile 2: Intervall
   y += lineHeight;
   CreateChartLabel("Intervall", x, y,
      StringFormat("Intervall: %d Min", InpCheckIntervalMinutes), clrWhite);
   
   // Zeile 3: Letzte Notification
   y += lineHeight;
   string lastNotifyStr = "Letzte Mail: -";
   if(g_lastNotificationTime > 0)
      lastNotifyStr = "Letzte Mail: " + TimeToString(g_lastNotificationTime, TIME_DATE | TIME_MINUTES);
   CreateChartLabel("LastNotify", x, y, lastNotifyStr, clrGold);
   
   // Zeile 4: Anzahl gesendeter E-Mails
   y += lineHeight;
   CreateChartLabel("EmailCount", x, y,
      StringFormat("Gesendete Mails: %d", g_notificationCount), clrWhite);
   
   // Zeile 5: Status (nächste Prüfung mit lokaler Uhrzeit)
   y += lineHeight;
   string statusStr = "Status: Aktiv";
   if(g_lastCheckTime > 0)
   {
      // Berechne Zeitdifferenz zwischen Broker und lokal
      datetime brokerTime = TimeCurrent();
      datetime localTime = TimeLocal();
      int timeDiff = (int)(localTime - brokerTime);
      
      datetime nextCheck = g_lastCheckTime + InpCheckIntervalMinutes * 60;
      datetime nextCheckLocal = nextCheck + timeDiff;
      statusStr = StringFormat("Nächste Prüfung: %s", TimeToString(nextCheckLocal, TIME_MINUTES));
   }
   CreateChartLabel("Status", x, y, statusStr, clrLimeGreen);
   
   // Open Equity Informationen anzeigen (falls aktiviert)
   if(InpOpenEquityReport)
   {
      // Tages-Equity
      y += lineHeight;
      string dailyEquityStr = StringFormat("Tages-Equity: Min %+.2f / Max %+.2f", 
                                           g_minDailyEquity, g_maxDailyEquity);
      CreateChartLabel("DailyEquity", x, y, dailyEquityStr, clrCyan);
      
      // Arrays zum Sammeln der Magic-Daten (offen + geschlossen heute)
      long magicNumbers[];
      double magicEquity[];      // Aktueller Equity (offen) + Profit (geschlossen)
      double magicMaxEquity[];   // Max Equity (nur für offene)
      double magicClosedProfit[]; // Nur geschlossene Profits heute
      int magicCount = 0;
      
      // 1. Offene Positionen durchgehen
      int posTotal = PositionsTotal();
      for(int i = 0; i < posTotal; i++)
      {
         ulong posTicket = PositionGetTicket(i);
         if(posTicket == 0) continue;
         
         long magic = PositionGetInteger(POSITION_MAGIC);
         ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double swap = PositionGetDouble(POSITION_SWAP);
         double currentEquity = profit + swap;
         double maxEquity = GetMaxEquityForPosition(posId);
         
         // Suche ob Magic bereits existiert
         int foundIdx = -1;
         for(int m = 0; m < magicCount; m++)
         {
            if(magicNumbers[m] == magic)
            {
               foundIdx = m;
               break;
            }
         }
         
         if(foundIdx >= 0)
         {
            magicEquity[foundIdx] += currentEquity;
            magicMaxEquity[foundIdx] += maxEquity;
         }
         else
         {
            ArrayResize(magicNumbers, magicCount + 1);
            ArrayResize(magicEquity, magicCount + 1);
            ArrayResize(magicMaxEquity, magicCount + 1);
            ArrayResize(magicClosedProfit, magicCount + 1);
            magicNumbers[magicCount] = magic;
            magicEquity[magicCount] = currentEquity;
            magicMaxEquity[magicCount] = maxEquity;
            magicClosedProfit[magicCount] = 0;
            magicCount++;
         }
      }
      
      // 2. Geschlossene Deals von heute aus Cache holen (optimiert)
      MqlDateTime dtNow;
      TimeCurrent(dtNow);
      datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      
      // Cache aktualisieren nur wenn nötig (neuer Tag oder neue Deals)
      if(HistorySelect(todayStart, TimeCurrent()))
      {
         int totalDeals = HistoryDealsTotal();
         
         // Prüfen ob Cache neu aufgebaut werden muss
         if(g_closedCacheDay != dtNow.day_of_year || g_closedCacheDealsCount != totalDeals)
         {
            // Cache neu aufbauen
            ArrayResize(g_closedMagicNumbers, 0);
            ArrayResize(g_closedMagicProfit, 0);
            int closedCount = 0;
            
            for(int i = 0; i < totalDeals; i++)
            {
               ulong ticket = HistoryDealGetTicket(i);
               ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
               
               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
               {
                  string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
                  if(symbol == "") continue;
                  
                  long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                  double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                  double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
                  double closedResult = profit + commission + swap;
                  
                  // Im Cache suchen/hinzufügen
                  int foundIdx = -1;
                  for(int c = 0; c < closedCount; c++)
                  {
                     if(g_closedMagicNumbers[c] == magic)
                     {
                        foundIdx = c;
                        break;
                     }
                  }
                  
                  if(foundIdx >= 0)
                  {
                     g_closedMagicProfit[foundIdx] += closedResult;
                  }
                  else
                  {
                     ArrayResize(g_closedMagicNumbers, closedCount + 1);
                     ArrayResize(g_closedMagicProfit, closedCount + 1);
                     g_closedMagicNumbers[closedCount] = magic;
                     g_closedMagicProfit[closedCount] = closedResult;
                     closedCount++;
                  }
               }
            }
            
            g_closedCacheDay = dtNow.day_of_year;
            g_closedCacheDealsCount = totalDeals;
            
            if(InpLogToExperts)
               Print("Closed-Trades Cache: ", closedCount, " Magic(s) aktualisiert");
         }
      }
      
      // Gecachte geschlossene Trades zu den lokalen Arrays hinzufügen
      int closedCacheSize = ArraySize(g_closedMagicNumbers);
      for(int c = 0; c < closedCacheSize; c++)
      {
         long magic = g_closedMagicNumbers[c];
         double closedResult = g_closedMagicProfit[c];
         
         // Suche ob Magic bereits in lokalen Arrays existiert
         int foundIdx = -1;
         for(int m = 0; m < magicCount; m++)
         {
            if(magicNumbers[m] == magic)
            {
               foundIdx = m;
               break;
            }
         }
         
         if(foundIdx >= 0)
         {
            magicEquity[foundIdx] += closedResult;
            magicClosedProfit[foundIdx] += closedResult;
         }
         else
         {
            ArrayResize(magicNumbers, magicCount + 1);
            ArrayResize(magicEquity, magicCount + 1);
            ArrayResize(magicMaxEquity, magicCount + 1);
            ArrayResize(magicClosedProfit, magicCount + 1);
            magicNumbers[magicCount] = magic;
            magicEquity[magicCount] = closedResult;
            magicMaxEquity[magicCount] = 0;
            magicClosedProfit[magicCount] = closedResult;
            magicCount++;
         }
      }
      
      // Gruppierte Magic-Equity anzeigen (max 20)
      int equityLabelCount = 0;
      for(int m = 0; m < magicCount && equityLabelCount < 20; m++)
      {
         y += lineHeight;
         string magicEquityStr;
         
         // Unterscheide zwischen rein geschlossen (kein Max) und mit offenen Positionen
         if(magicMaxEquity[m] != 0 || magicClosedProfit[m] == 0)
         {
            // Hat offene Positionen - Tabellenformat mit fester Breite
            magicEquityStr = StringFormat("  M%-12d %+10.2f  Max:%+9.2f", 
                                          magicNumbers[m], magicEquity[m], magicMaxEquity[m]);
         }
         else
         {
            // Nur geschlossene Trades heute
            magicEquityStr = StringFormat("  M%-12d %+10.2f  (closed)", 
                                          magicNumbers[m], magicEquity[m]);
         }
         
         // Farbe basierend auf Equity
         color eqColor = magicEquity[m] >= 0 ? clrLime : clrOrangeRed;
         CreateChartLabel("PosEquity" + IntegerToString(equityLabelCount), x, y, magicEquityStr, eqColor);
         equityLabelCount++;
      }
      
      // Nicht mehr verwendete Labels entfernen
      for(int j = equityLabelCount; j < 20; j++)
      {
         ObjectDelete(0, LABEL_PREFIX + "PosEquity" + IntegerToString(j));
      }
   }
   else
   {
      // Labels entfernen wenn deaktiviert
      ObjectDelete(0, LABEL_PREFIX + "DailyEquity");
      for(int j = 0; j < 20; j++)
      {
         ObjectDelete(0, LABEL_PREFIX + "PosEquity" + IntegerToString(j));
      }
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Deals ohne Benachrichtigung aktualisieren                         |
//+------------------------------------------------------------------+
void UpdateKnownDealsWithoutNotification()
{
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      
      if(!IsDealKnown(ticket))
      {
         AddKnownDeal(ticket);
      }
   }
   
   g_lastDealsTotal = totalDeals;
}

//+------------------------------------------------------------------+
//| Prüfen ob Tagesreport gesendet werden soll                        |
//+------------------------------------------------------------------+
void CheckAndSendDailyReport()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Prüfen ob die konfigurierte Tageszeit erreicht oder überschritten wurde
   // (innerhalb des Prüf-Intervalls)
   int currentMinutes = dt.hour * 60 + dt.min;
   int targetMinutes = InpDailyReportHour * 60 + InpDailyReportMinute;
   
   // Freitags-Sicherheit: Spätestens um 20:00 senden (Markt schließt um ~22:00)
   if(dt.day_of_week == 5 && targetMinutes > 20 * 60)
   {
      if(InpLogToExperts)
         Print("HINWEIS: Tagesreport von ", InpDailyReportHour, ":00 auf 20:00 vorgezogen (Freitag Marktschluss)");
      targetMinutes = 20 * 60;
   }
   
   // Ist die Zielzeit erreicht? (aktuell >= Zielzeit UND aktuell < Zielzeit + Intervall)
   if(currentMinutes >= targetMinutes && currentMinutes < targetMinutes + InpCheckIntervalMinutes)
   {
      // Wurde heute schon ein Report gesendet? (Logdatei prüfen)
      string todayStr = TimeToString(TimeCurrent(), TIME_DATE);
      if(!IsReportAlreadySent("DAILY", todayStr))
      {
         if(SendDailyReport())
            LogReportSent("DAILY", todayStr);
      }
   }
}

//+------------------------------------------------------------------+
//| Tagesreport senden                                                 |
//+------------------------------------------------------------------+
bool SendDailyReport()
{
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   // History für heute laden
   if(!HistorySelect(todayStart, TimeCurrent()))
   {
      Print("WARNUNG: Konnte Tages-History nicht laden!");
      return false;
   }
   
   // Geschlossene Trades heute sammeln
   string closedTrades = "";
   int closedCount = 0;
   double totalProfit = 0;
   double totalCommission = 0;
   double totalSwap = 0;
   

   
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE  type  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      
      // Nur geschlossene Trades zählen
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(symbol == "") continue; // Balance-Operationen überspringen
         
         double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price      = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         
         totalProfit += profit;
         totalCommission += commission;
         totalSwap += swap;
         
         // Close-Deal: Richtung invertieren (SELL schließen = BUY-Deal -> zeige "SELL")
         string direction = (type == DEAL_TYPE_BUY) ? "SELL" : (type == DEAL_TYPE_SELL) ? "BUY" : "OTHER";
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         if(digits == 0) digits = 2;
         
         double dealResult = profit + commission + swap;
         
         // Position-ID für Max-Equity und Einstiegspreis
         long posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         double maxEquity = GetMaxEquityForPosition((ulong)posId);
         
         // Einstiegspreis suchen (Opening-Deal dieser Position)
         double openPrice = 0;
         for(int j = 0; j < totalDeals; j++)
         {
            ulong openTicket = HistoryDealGetTicket(j);
            if(HistoryDealGetInteger(openTicket, DEAL_POSITION_ID) == posId &&
               HistoryDealGetInteger(openTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            {
               openPrice = HistoryDealGetDouble(openTicket, DEAL_PRICE);
               break;
            }
         }
         
         string maxEquityStr = "";
         if(InpOpenEquityReport && maxEquity != 0)
            maxEquityStr = StringFormat(" | Max: %+.2f", maxEquity);
         
         // Format: Open -> Close Preis
         string priceStr = "";
         if(openPrice > 0)
            priceStr = StringFormat("%s -> %s", DoubleToString(openPrice, digits), DoubleToString(price, digits));
         else
            priceStr = DoubleToString(price, digits);
         
         closedTrades += StringFormat("  [%s] %s | %s %.2f @ %s | P/L: %.2f%s\n",
                                      symbol,
                                      TimeToString(dealTime, TIME_MINUTES),
                                      direction,
                                      volume,
                                      priceStr,
                                      dealResult,
                                      maxEquityStr);
         closedCount++;
      }
   }
   
   // Gesamtgewinn/Verlust berechnen
   double dayResult = totalProfit + totalCommission + totalSwap;
   
   // Betreff erstellen
   string subject = InpEmailSubjectPrefix + "Tagesreport " + TimeToString(TimeCurrent(), TIME_DATE);
   if(dayResult >= 0)
      subject += StringFormat(" +%.2f %s", dayResult, AccountInfoString(ACCOUNT_CURRENCY));
   else
      subject += StringFormat(" %.2f %s", dayResult, AccountInfoString(ACCOUNT_CURRENCY));
   
   // Account-Info
   string accountInfo = StringFormat(
      "Account: %d (%s)\n"
      "Server: %s\n"
      "Balance: %.2f %s\n"
      "Equity: %.2f %s\n"
      "Datum: %s\n",
      AccountInfoInteger(ACCOUNT_LOGIN),
      AccountInfoString(ACCOUNT_NAME),
      AccountInfoString(ACCOUNT_SERVER),
      AccountInfoDouble(ACCOUNT_BALANCE),
      AccountInfoString(ACCOUNT_CURRENCY),
      AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoString(ACCOUNT_CURRENCY),
      TimeToString(TimeCurrent(), TIME_DATE)
   );
   
   // E-Mail-Body zusammenstellen
   string body = "=== MQL5 TAGESREPORT ===\n\n";
   body += accountInfo;
   body += "\n";
   
   // Tagesergebnis
   body += "=== TAGESERGEBNIS ===\n";
   body += StringFormat("Profit: %.2f %s\n", totalProfit, AccountInfoString(ACCOUNT_CURRENCY));
   body += StringFormat("Commission: %.2f %s\n", totalCommission, AccountInfoString(ACCOUNT_CURRENCY));
   body += StringFormat("Swap: %.2f %s\n", totalSwap, AccountInfoString(ACCOUNT_CURRENCY));
   body += StringFormat("GESAMT: %.2f %s\n", dayResult, AccountInfoString(ACCOUNT_CURRENCY));
   if(InpOpenEquityReport)
   {
      body += StringFormat("Max Account Equity heute: %+.2f %s\n", g_maxDailyEquity, AccountInfoString(ACCOUNT_CURRENCY));
      body += StringFormat("Min Account Equity heute: %+.2f %s\n\n", g_minDailyEquity, AccountInfoString(ACCOUNT_CURRENCY));
   }
   else
   {
      body += "\n";
   }
   
   // Geschlossene Trades
   if(closedCount > 0)
   {
      body += StringFormat("--- %d TRADE(S) HEUTE GESCHLOSSEN ---\n", closedCount);
      body += closedTrades;
      body += "\n";
   }
   else
   {
      body += "--- KEINE TRADES HEUTE GESCHLOSSEN ---\n\n";
   }
   
   // Offene Positionen anhängen
   body += GetOpenPositionsInfo();
   
   body += "\n=== Ende Tagesreport ===";
   
   // E-Mail senden
   bool mailSent = SendMail(subject, body);
   
   if(!mailSent)
   {
      Print("FEHLER: Tagesreport E-Mail konnte nicht gesendet werden!");
   }
   else
   {
      g_lastNotificationTime = TimeCurrent();
      g_notificationCount++;
      UpdateChartInfo();
      
      if(InpLogToExperts)
         Print("Tagesreport gesendet: ", subject);
   }
   
   if(InpLogToExperts)
   {
      Print("---");
      Print(body);
      Print("---");
   }
   
   // History wieder vollständig laden
   HistorySelect(0, TimeCurrent());
   return mailSent;
}

//+------------------------------------------------------------------+
//| Equity-Tracking aktualisieren                                     |
//+------------------------------------------------------------------+
void UpdateEquityTracking()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Neuer Tag? Dann Tages-Equity zurücksetzen
   if(g_equityTrackingDay != dt.day_of_year)
   {
      g_equityTrackingDay = dt.day_of_year;
      g_maxDailyEquity = -DBL_MAX;  // Wird beim ersten Update überschrieben
      g_minDailyEquity = DBL_MAX;   // Wird beim ersten Update überschrieben
      
      if(InpLogToExperts)
         Print("Equity-Tracking: Neuer Tag, Reset durchgeführt");
   }
   
   // Account-Equity berechnen (nur offene Positionen)
   double totalOpenEquity = 0;
   int posTotal = PositionsTotal();
   
   for(int i = 0; i < posTotal; i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0) continue;
      
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      double currentEquity = profit + swap;
      
      totalOpenEquity += currentEquity;
      
      // Per-Trade Tracking aktualisieren
      UpdateTradeMaxEquity(posId, currentEquity);
   }
   
   // Account-weites Maximum/Minimum aktualisieren
   if(totalOpenEquity > g_maxDailyEquity)
   {
      g_maxDailyEquity = totalOpenEquity;
   }
   if(totalOpenEquity < g_minDailyEquity)
   {
      g_minDailyEquity = totalOpenEquity;
   }
}

//+------------------------------------------------------------------+
//| Max Equity für einzelnen Trade aktualisieren                      |
//+------------------------------------------------------------------+
void UpdateTradeMaxEquity(ulong positionId, double currentEquity)
{
   int size = ArraySize(g_tradeEquity);
   
   // Suche nach bestehendem Eintrag
   for(int i = 0; i < size; i++)
   {
      if(g_tradeEquity[i].positionId == positionId)
      {
         // Aktualisiere Maximum wenn größer
         if(currentEquity > g_tradeEquity[i].maxEquity)
         {
            g_tradeEquity[i].maxEquity = currentEquity;
         }
         return;
      }
   }
   
   // Neuer Trade - zum Array hinzufügen
   ArrayResize(g_tradeEquity, size + 1);
   g_tradeEquity[size].positionId = positionId;
   g_tradeEquity[size].maxEquity = currentEquity;
}

//+------------------------------------------------------------------+
//| Max Equity für Position abrufen                                   |
//+------------------------------------------------------------------+
double GetMaxEquityForPosition(ulong positionId)
{
   int size = ArraySize(g_tradeEquity);
   
   for(int i = 0; i < size; i++)
   {
      if(g_tradeEquity[i].positionId == positionId)
      {
         return g_tradeEquity[i].maxEquity;
      }
   }
   
   return 0; // Nicht gefunden
}

//+------------------------------------------------------------------+
//| Trade aus Equity-Tracking entfernen                               |
//+------------------------------------------------------------------+
void RemoveTradeFromEquityTracking(ulong positionId)
{
   int size = ArraySize(g_tradeEquity);
   
   for(int i = 0; i < size; i++)
   {
      if(g_tradeEquity[i].positionId == positionId)
      {
         // Entferne durch Überschreiben mit letztem Element
         if(i < size - 1)
         {
            g_tradeEquity[i] = g_tradeEquity[size - 1];
         }
         ArrayResize(g_tradeEquity, size - 1);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Unique Symbol zur Liste hinzufügen (Hilfsfunktion)               |
//+------------------------------------------------------------------+
string AddUniqueSymbol(string symbolList, string symbol)
{
   if(StringFind(symbolList, symbol) >= 0)
      return symbolList;
   if(symbolList == "")
      return symbol;
   return symbolList + ", " + symbol;
}

//+------------------------------------------------------------------+
//| Heutigen geschlossenen P/L berechnen                             |
//+------------------------------------------------------------------+
double GetTodayClosedPL()
{
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   if(!HistorySelect(todayStart, TimeCurrent()))
      return 0;
   
   double total = 0;
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(sym == "") continue;
         
         total += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         total += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         total += HistoryDealGetDouble(ticket, DEAL_SWAP);
      }
   }
   
   // History wieder vollständig laden
   HistorySelect(0, TimeCurrent());
   return total;
}

//+------------------------------------------------------------------+
//| Prüfen ob letzter Tag des Monats                                  |
//+------------------------------------------------------------------+
bool IsLastDayOfMonth()
{
   datetime tomorrow = TimeCurrent() + 86400;
   MqlDateTime dtToday, dtTomorrow;
   TimeCurrent(dtToday);
   TimeToStruct(tomorrow, dtTomorrow);
   return dtTomorrow.mon != dtToday.mon;
}

//+------------------------------------------------------------------+
//| Prüfen ob Wochenreport gesendet werden soll (Freitag 20:00)      |
//+------------------------------------------------------------------+
void CheckAndSendWeeklyReport()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Nur freitags (day_of_week == 5)
   if(dt.day_of_week != 5)
      return;
   
   int currentMinutes = dt.hour * 60 + dt.min;
   int targetMinutes  = InpWeeklyReportHour * 60;
   
   // Freitags-Sicherheit: Spätestens um 20:00 senden (Markt schließt um ~22:00)
   if(targetMinutes > 20 * 60)
   {
      if(InpLogToExperts)
         Print("HINWEIS: Wochenreport von ", InpWeeklyReportHour, ":00 auf 20:00 vorgezogen (Freitag Marktschluss)");
      targetMinutes = 20 * 60;
   }
   
   if(currentMinutes >= targetMinutes && currentMinutes < targetMinutes + InpCheckIntervalMinutes)
   {
      // Heute schon gesendet? (Logdatei prüfen)
      string todayStr = TimeToString(TimeCurrent(), TIME_DATE);
      if(!IsReportAlreadySent("WEEKLY", todayStr))
      {
         if(SendWeeklyReport())
            LogReportSent("WEEKLY", todayStr);
      }
   }
}

//+------------------------------------------------------------------+
//| Wochenreport senden                                               |
//+------------------------------------------------------------------+
bool SendWeeklyReport()
{
   // Montag dieser Woche berechnen
   MqlDateTime dtNow;
   TimeCurrent(dtNow);
   // day_of_week: 0=So, 1=Mo, 2=Di, 3=Mi, 4=Do, 5=Fr, 6=Sa
   int daysFromMonday = dtNow.day_of_week - 1;
   if(daysFromMonday < 0) daysFromMonday = 6; // Sonntag
   datetime weekStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE)) - daysFromMonday * 86400;
   
   if(!HistorySelect(weekStart, TimeCurrent()))
   {
      Print("WARNUNG: Konnte Wochen-History nicht laden!");
      return false;
   }
   
   // Trades der Woche sammeln
   string closedTrades  = "";
   int    closedCount   = 0;
   double totalProfit   = 0;
   double totalComm     = 0;
   double totalSwap     = 0;
   
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE  type  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(symbol == "") continue;
         
         double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price      = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         
         totalProfit += profit;
         totalComm   += commission;
         totalSwap   += swap;
         
         // Close-Deal: Richtung invertieren (SELL schließen = BUY-Deal -> zeige "SELL")
         string direction = (type == DEAL_TYPE_BUY) ? "SELL" : (type == DEAL_TYPE_SELL) ? "BUY" : "OTHER";
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         if(digits == 0) digits = 2;
         double dealResult = profit + commission + swap;
         
         closedTrades += StringFormat("  [%s] %s | %s %.2f @ %s | P/L: %.2f\n",
                                      symbol,
                                      TimeToString(dealTime, TIME_DATE | TIME_MINUTES),
                                      direction,
                                      volume,
                                      DoubleToString(price, digits),
                                      dealResult);
         closedCount++;
      }
   }
   
   double weekResult = totalProfit + totalComm + totalSwap;
   string currency   = AccountInfoString(ACCOUNT_CURRENCY);
   
   string subject = InpEmailSubjectPrefix + "Wochenreport KW" +
                    IntegerToString(dtNow.day_of_year / 7 + 1) +
                    StringFormat(" %+.2f %s", weekResult, currency);
   
   string body = "=== MQL5 WOCHENREPORT ===\n\n";
   body += StringFormat("Account: %d (%s)\nServer: %s\nBalance: %.2f %s\nEquity: %.2f %s\n"
                        "Zeitraum: %s - %s\n\n",
                        AccountInfoInteger(ACCOUNT_LOGIN),
                        AccountInfoString(ACCOUNT_NAME),
                        AccountInfoString(ACCOUNT_SERVER),
                        AccountInfoDouble(ACCOUNT_BALANCE), currency,
                        AccountInfoDouble(ACCOUNT_EQUITY),  currency,
                        TimeToString(weekStart, TIME_DATE),
                        TimeToString(TimeCurrent(), TIME_DATE));
   
   body += "=== WOCHENERGEBNIS ===\n";
   body += StringFormat("Profit: %.2f %s\n",     totalProfit, currency);
   body += StringFormat("Commission: %.2f %s\n", totalComm,   currency);
   body += StringFormat("Swap: %.2f %s\n",       totalSwap,   currency);
   body += StringFormat("GESAMT: %+.2f %s\n\n",  weekResult,  currency);
   
   if(closedCount > 0)
      body += StringFormat("--- %d TRADE(S) DIESE WOCHE ---\n%s\n", closedCount, closedTrades);
   else
      body += "--- KEINE TRADES DIESE WOCHE ---\n\n";
   
   body += GetOpenPositionsInfo();
   body += "\n=== Ende Wochenreport ===";
   
   bool mailSent = SendMail(subject, body);
   
   if(!mailSent)
   {
      Print("FEHLER: Wochenreport E-Mail konnte nicht gesendet werden!");
   }
   else
   {
      g_lastNotificationTime = TimeCurrent();
      g_notificationCount++;
      UpdateChartInfo();
      if(InpLogToExperts)
         Print("Wochenreport gesendet: ", subject);
   }
   
   HistorySelect(0, TimeCurrent());
   return mailSent;
}

//+------------------------------------------------------------------+
//| Prüfen ob Monatsreport gesendet werden soll (letzter Monatstag)  |
//+------------------------------------------------------------------+
void CheckAndSendMonthlyReport()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(!IsLastDayOfMonth())
      return;
   
   int currentMinutes = dt.hour * 60 + dt.min;
   int targetMinutes  = InpMonthlyReportHour * 60;
   
   // Freitags-Sicherheit: Wenn Monatsende auf Freitag fällt,
   // spätestens um 20:00 senden (Markt schließt um ~22:00)
   if(dt.day_of_week == 5 && targetMinutes > 20 * 60)
   {
      if(InpLogToExperts)
         Print("HINWEIS: Monatsreport von ", InpMonthlyReportHour, ":00 auf 20:00 vorgezogen (Freitag Marktschluss)");
      targetMinutes = 20 * 60;
   }
   
   if(currentMinutes >= targetMinutes && currentMinutes < targetMinutes + InpCheckIntervalMinutes)
   {
      // Diesen Monat schon gesendet? (Logdatei prüfen)
      string todayStr = TimeToString(TimeCurrent(), TIME_DATE);
      if(!IsReportAlreadySent("MONTHLY", todayStr))
      {
         if(SendMonthlyReport())
            LogReportSent("MONTHLY", todayStr);
      }
   }
}

//+------------------------------------------------------------------+
//| Monatsreport senden                                               |
//+------------------------------------------------------------------+
bool SendMonthlyReport()
{
   MqlDateTime dtNow;
   TimeCurrent(dtNow);
   
   // Erster Tag dieses Monats
   string monthStartStr = StringFormat("%04d.%02d.01", dtNow.year, dtNow.mon);
   datetime monthStart  = StringToTime(monthStartStr);
   
   if(!HistorySelect(monthStart, TimeCurrent()))
   {
      Print("WARNUNG: Konnte Monats-History nicht laden!");
      return false;
   }
   
   string closedTrades = "";
   int    closedCount  = 0;
   double totalProfit  = 0;
   double totalComm    = 0;
   double totalSwap    = 0;
   
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE  type  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(symbol == "") continue;
         
         double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price      = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         
         totalProfit += profit;
         totalComm   += commission;
         totalSwap   += swap;
         
         // Close-Deal: Richtung invertieren (SELL schließen = BUY-Deal -> zeige "SELL")
         string direction = (type == DEAL_TYPE_BUY) ? "SELL" : (type == DEAL_TYPE_SELL) ? "BUY" : "OTHER";
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         if(digits == 0) digits = 2;
         double dealResult = profit + commission + swap;
         
         closedTrades += StringFormat("  [%s] %s | %s %.2f @ %s | P/L: %.2f\n",
                                      symbol,
                                      TimeToString(dealTime, TIME_DATE | TIME_MINUTES),
                                      direction,
                                      volume,
                                      DoubleToString(price, digits),
                                      dealResult);
         closedCount++;
      }
   }
   
   double monthResult = totalProfit + totalComm + totalSwap;
   string currency    = AccountInfoString(ACCOUNT_CURRENCY);
   
   string monthNames[] = {"", "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
                              "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"};
   string monthName = (dtNow.mon >= 1 && dtNow.mon <= 12) ? monthNames[dtNow.mon] : IntegerToString(dtNow.mon);
   
   string subject = InpEmailSubjectPrefix + "Monatsreport " + monthName + " " +
                    IntegerToString(dtNow.year) +
                    StringFormat(" %+.2f %s", monthResult, currency);
   
   string body = "=== MQL5 MONATSREPORT ===\n\n";
   body += StringFormat("Account: %d (%s)\nServer: %s\nBalance: %.2f %s\nEquity: %.2f %s\n"
                        "Zeitraum: %s - %s\n\n",
                        AccountInfoInteger(ACCOUNT_LOGIN),
                        AccountInfoString(ACCOUNT_NAME),
                        AccountInfoString(ACCOUNT_SERVER),
                        AccountInfoDouble(ACCOUNT_BALANCE), currency,
                        AccountInfoDouble(ACCOUNT_EQUITY),  currency,
                        TimeToString(monthStart, TIME_DATE),
                        TimeToString(TimeCurrent(), TIME_DATE));
   
   body += "=== MONATSERGEBNIS ===\n";
   body += StringFormat("Profit: %.2f %s\n",     totalProfit, currency);
   body += StringFormat("Commission: %.2f %s\n", totalComm,   currency);
   body += StringFormat("Swap: %.2f %s\n",       totalSwap,   currency);
   body += StringFormat("GESAMT: %+.2f %s\n\n",  monthResult, currency);
   
   if(closedCount > 0)
      body += StringFormat("--- %d TRADE(S) DIESEN MONAT ---\n%s\n", closedCount, closedTrades);
   else
      body += "--- KEINE TRADES DIESEN MONAT ---\n\n";
   
   body += GetOpenPositionsInfo();
   body += "\n=== Ende Monatsreport ===";
   
   bool mailSent = SendMail(subject, body);
   
   if(!mailSent)
   {
      Print("FEHLER: Monatsreport E-Mail konnte nicht gesendet werden!");
   }
   else
   {
      g_lastNotificationTime = TimeCurrent();
      g_notificationCount++;
      UpdateChartInfo();
      if(InpLogToExperts)
         Print("Monatsreport gesendet: ", subject);
   }
   
   HistorySelect(0, TimeCurrent());
   return mailSent;
}
//+------------------------------------------------------------------+