//+------------------------------------------------------------------+
//|                                                   MQL5Notify.mq5 |
//|                                          Trade Monitor & Notifier |
//|                              Überwacht Trades und sendet E-Mails  |
//+------------------------------------------------------------------+
#property copyright "Thomas"
#property link      ""
#property version   "1.01"
#property description "Überwacht Trade-Aktivitäten und sendet E-Mail-Benachrichtigungen"
#property description "bei neuen oder geschlossenen Trades in konfigurierbaren Intervallen."

//+------------------------------------------------------------------+
//| Input-Parameter                                                   |
//+------------------------------------------------------------------+
input int    InpCheckIntervalMinutes = 5;       // Prüf-Intervall in Minuten (1-n)
input string InpEmailSubjectPrefix  = "[MT5] "; // E-Mail Betreff-Prefix
input bool   InpLogToExperts        = true;     // Log-Ausgabe im Experts-Tab

//+------------------------------------------------------------------+
//| Konstanten                                                        |
//+------------------------------------------------------------------+
#define EA_VERSION "1.01"
#define LABEL_PREFIX "MQL5Notify_"

//+------------------------------------------------------------------+
//| Globale Variablen                                                 |
//+------------------------------------------------------------------+
datetime g_lastCheckTime         = 0;       // Zeitpunkt der letzten Prüfung
datetime g_lastNotificationTime  = 0;       // Zeitpunkt der letzten E-Mail
int      g_lastDealsTotal        = 0;       // Anzahl Deals bei letzter Prüfung
int      g_knownDealTickets[];              // Array mit bereits bekannten Deal-Tickets
int      g_notificationCount     = 0;       // Anzahl gesendeter E-Mails

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
   
   // Timer starten (jede Minute prüfen, ob Intervall erreicht)
   EventSetTimer(60);
   g_lastCheckTime = TimeCurrent();
   
   Print("MQL5Notify gestartet - Prüf-Intervall: ", InpCheckIntervalMinutes, " Minute(n)");
   Print("Bekannte Deals beim Start: ", ArraySize(g_knownDealTickets));
   
   // Chart-Info anzeigen
   UpdateChartInfo();
   
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
   ChartRedraw(0);
   
   Print("MQL5Notify gestoppt. Grund: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function - wird jede Minute aufgerufen                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime currentTime = TimeCurrent();
   
   // Chart-Info immer aktualisieren (zeigt auch Countdown etc.)
   UpdateChartInfo();
   
   // Prüfen ob das konfigurierte Intervall erreicht ist
   if(currentTime - g_lastCheckTime < InpCheckIntervalMinutes * 60)
      return;
   
   g_lastCheckTime = currentTime;
   
   // History aktualisieren
   if(!HistorySelect(0, TimeCurrent()))
   {
      Print("WARNUNG: Konnte Trade-History nicht aktualisieren!");
      return;
   }
   
   // Neue Deals suchen
   CheckForNewDeals();
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
      g_knownDealTickets[i] = (int)ticket;
   }
   
   g_lastDealsTotal = totalDeals;
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
   string openedTrades  = "";
   string closedTrades  = "";
   int    openCount     = 0;
   int    closeCount    = 0;
   
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
      
      if(entry == DEAL_ENTRY_IN)
      {
         // Trade eröffnet
         openedTrades += dealInfo + "\n";
         openCount++;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         // Trade geschlossen
         closedTrades += dealInfo + "\n";
         closeCount++;
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
      }
   }
   
   g_lastDealsTotal = totalDeals;
   
   // E-Mail zusammenstellen und senden
   if(openCount > 0 || closeCount > 0)
   {
      SendNotificationEmail(openedTrades, closedTrades, openCount, closeCount);
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
      if(g_knownDealTickets[i] == (int)ticket)
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
   g_knownDealTickets[size] = (int)ticket;
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
   string direction = "";
   if(type == DEAL_TYPE_BUY)       direction = "BUY";
   else if(type == DEAL_TYPE_SELL) direction = "SELL";
   else                            direction = "OTHER";
   
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
   
   // Bei geschlossenen Trades: Profit anzeigen
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
   {
      double totalResult = profit + commission + swap;
      info += StringFormat("\n    P/L: %.2f (Profit: %.2f, Comm: %.2f, Swap: %.2f)",
                           totalResult, profit, commission, swap);
   }
   
   // Kommentar hinzufügen falls vorhanden
   if(comment != "")
      info += "\n    Kommentar: " + comment;
   
   // Symbol hervorheben
   info = "  [" + symbol + "] " + info;
   
   return info;
}

//+------------------------------------------------------------------+
//| E-Mail-Benachrichtigung senden                                    |
//+------------------------------------------------------------------+
void SendNotificationEmail(string openedTrades, string closedTrades, int openCount, int closeCount)
{
   // Betreff erstellen
   string subject = InpEmailSubjectPrefix;
   
   if(openCount > 0 && closeCount > 0)
      subject += StringFormat("%d Trade(s) eröffnet, %d Trade(s) geschlossen", openCount, closeCount);
   else if(openCount > 0)
      subject += StringFormat("%d Trade(s) eröffnet", openCount);
   else
      subject += StringFormat("%d Trade(s) geschlossen", closeCount);
   
   // Account-Info
   string accountInfo = StringFormat(
      "Account: %d (%s)\n"
      "Server: %s\n"
      "Balance: %.2f %s\n"
      "Equity: %.2f %s\n"
      "Zeitpunkt: %s\n",
      AccountInfoInteger(ACCOUNT_LOGIN),
      AccountInfoString(ACCOUNT_NAME),
      AccountInfoString(ACCOUNT_SERVER),
      AccountInfoDouble(ACCOUNT_BALANCE),
      AccountInfoString(ACCOUNT_CURRENCY),
      AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoString(ACCOUNT_CURRENCY),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)
   );
   
   // E-Mail-Body zusammenstellen
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
      body += "\n";
   }
   
   // Offene Positionen anhängen
   body += GetOpenPositionsInfo();
   
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
      ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, 9);
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
   int lineHeight = 18;
   
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
   
   // Zeile 5: Status (nächste Prüfung)
   y += lineHeight;
   string statusStr = "Status: Aktiv";
   if(g_lastCheckTime > 0)
   {
      datetime nextCheck = g_lastCheckTime + InpCheckIntervalMinutes * 60;
      int secsLeft = (int)(nextCheck - TimeCurrent());
      if(secsLeft < 0) secsLeft = 0;
      statusStr = StringFormat("Nächste Prüfung in: %d:%02d", secsLeft / 60, secsLeft % 60);
   }
   CreateChartLabel("Status", x, y, statusStr, clrLimeGreen);
   
   ChartRedraw(0);
}
//+------------------------------------------------------------------+