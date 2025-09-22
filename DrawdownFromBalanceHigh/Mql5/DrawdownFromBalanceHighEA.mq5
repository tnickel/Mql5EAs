
//+------------------------------------------------------------------+
//|                                 DrawdownFromBalanceHighEA.mq5    |
//|                                Copyright 2025, Dein Name hier    |
//|                                      http://www.deinlink.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Thomas Nickel"
#property link      "https://monitortool.jimdofree.com/"
#property version   "1.03"

#property strict

// Eingabeparameter
input color TextColor = clrYellow;      // Textfarbe
input int FontSize = 14;                // Schriftgröße
input string FontName = "Arial Bold";   // Schriftart
input int Corner = 0;                   // Ecke für Anzeige (0=links oben, 1=rechts oben, 2=links unten, 3=rechts unten)
input int DistanceX = 20;               // X-Abstand
input int DistanceY = 20;               // Y-Abstand
input double AlarmDrawdownProzent = 5.0; // Alarmschwelle für Drawdown in %
input bool PlaySound = true;           // Sound bei Alarm abspielen
input color AlarmTextColor = clrRed;    // Farbe für Alarmtext

// Globale Variablen
string objectName = "DrawdownLabel";
string alarmLabelName = "AlarmLabel";
string errorLabelName = "ErrorLabel";
double maxBalance = 0;
bool alarmTriggered = false;
double alarmEquity = 0;
bool lastAccessSuccessful = true;   // Flag für erfolgreichen Zugriff auf Kontodaten

// Neue globale Variablen für Open Equity Tracking
double currentOpenEquity = 0;
double currentOpenEquityCurrency = 0;
double dailyMinOpenEquity = 0;
double dailyMaxOpenEquity = 0;
double dailyMinOpenEquityCurrency = 0;
double dailyMaxOpenEquityCurrency = 0;
datetime lastResetTime = 0;
string openEquityLabelName = "OpenEquityLabel";
string minMaxLabelName = "MinMaxLabel";
string minMaxCurrencyLabelName = "MinMaxCurrencyLabel";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Lösche die Labels, falls sie bereits existieren
   ObjectDelete(0, objectName);
   ObjectDelete(0, alarmLabelName);
   ObjectDelete(0, openEquityLabelName);
   ObjectDelete(0, minMaxLabelName);
   ObjectDelete(0, minMaxCurrencyLabelName);
   
   // Erstelle ein neues Label für die Drawdown-Anzeige
   ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objectName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, DistanceX);
   ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, DistanceY);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, objectName, OBJPROP_FONT, FontName);
   
   // Erstelle ein Label für die Alarmschwelle
   ObjectCreate(0, alarmLabelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, alarmLabelName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, alarmLabelName, OBJPROP_XDISTANCE, DistanceX);
   ObjectSetInteger(0, alarmLabelName, OBJPROP_YDISTANCE, DistanceY + FontSize + 25);
   ObjectSetInteger(0, alarmLabelName, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, alarmLabelName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, alarmLabelName, OBJPROP_FONT, FontName);
   
   // Erstelle Label für aktuelle Open Equity
   ObjectCreate(0, openEquityLabelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, openEquityLabelName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, openEquityLabelName, OBJPROP_XDISTANCE, DistanceX);
   ObjectSetInteger(0, openEquityLabelName, OBJPROP_YDISTANCE, DistanceY + (FontSize + 25) * 2);
   ObjectSetInteger(0, openEquityLabelName, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, openEquityLabelName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, openEquityLabelName, OBJPROP_FONT, FontName);
   
   // Erstelle Label für Min/Max Open Equity
   ObjectCreate(0, minMaxLabelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, minMaxLabelName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, minMaxLabelName, OBJPROP_XDISTANCE, DistanceX);
   ObjectSetInteger(0, minMaxLabelName, OBJPROP_YDISTANCE, DistanceY + (FontSize + 25) * 3);
   ObjectSetInteger(0, minMaxLabelName, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, minMaxLabelName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, minMaxLabelName, OBJPROP_FONT, FontName);
   
   // Erstelle Label für Min/Max Open Equity in Währung
   ObjectCreate(0, minMaxCurrencyLabelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, minMaxCurrencyLabelName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, minMaxCurrencyLabelName, OBJPROP_XDISTANCE, DistanceX);
   ObjectSetInteger(0, minMaxCurrencyLabelName, OBJPROP_YDISTANCE, DistanceY + (FontSize + 25) * 4);
   ObjectSetInteger(0, minMaxCurrencyLabelName, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, minMaxCurrencyLabelName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, minMaxCurrencyLabelName, OBJPROP_FONT, FontName);
   
   // Reset Alarm-Status
   alarmTriggered = false;
   alarmEquity = 0;
   lastAccessSuccessful = true;
   
   // Initialisiere Open Equity Tracking
   InitializeOpenEquityTracking();
   
   // Aktiviere Timer für regelmäßige Updates (1 Sekunde)
   EventSetTimer(1);
   
   // Ausgabe im Log
   double initialAlarmEquityThreshold = maxBalance > 0 ? maxBalance * (1 - AlarmDrawdownProzent/100) : 0;
   Print("DrawdownFromBalanceHighEA gestartet mit Alarmschwelle: ", AlarmDrawdownProzent, 
         "% (Equity-Wert bei Alarm: ", DoubleToString(initialAlarmEquityThreshold, 2), ")");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Schreibe aktuelle Werte ins Logfile bevor der EA beendet wird
   if(dailyMinOpenEquity != 0 || dailyMaxOpenEquity != 0) // Nur loggen wenn Daten vorhanden
   {
      WriteEquityLogEntry();
      Print("Aktuelle Equity Drawdown Daten beim EA-Stop ins Logfile geschrieben");
   }
   
   // Lösche die Labels
   ObjectDelete(0, objectName);
   ObjectDelete(0, alarmLabelName);
   ObjectDelete(0, errorLabelName);
   ObjectDelete(0, openEquityLabelName);
   ObjectDelete(0, minMaxLabelName);
   ObjectDelete(0, minMaxCurrencyLabelName);
   
   // Stoppe den Timer
   EventKillTimer();
   
   // Ausgabe im Log
   Print("DrawdownFromBalanceHighEA beendet");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Diese Funktion wird bei jedem Tick aufgerufen
   // Die Hauptberechnung erfolgt in OnTimer für regelmäßige Updates
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Versuche, aktuelle Kontostand-Informationen zu holen
   double currentBalance = 0;
   double currentEquity = 0;
   bool accessSuccessful = true;
   
   // Versuche Kontoinformationen zu lesen und fange mögliche Fehler ab
   currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Prüfe, ob die gelesenen Werte gültig sind
   if(currentBalance <= 0 || currentEquity <= 0)
   {
      accessSuccessful = false;
      
      // Setze Fehlermeldung im Chart
      ObjectSetString(0, errorLabelName, OBJPROP_TEXT, "FEHLER: Keine Kontodaten verfügbar!");
      
      // Logge den Fehler, aber nur beim ersten Auftreten, um das Log nicht zu überfluten
      if(lastAccessSuccessful)
      {
         Print("WARNUNG: Konnte keine Kontoinformationen abrufen. Es ist möglicherweise Wochenende oder der Markt ist geschlossen.");
         lastAccessSuccessful = false;
      }
      
      // Fordere Chart-Aktualisierung an
      ChartRedraw();
      return; // Beende die Funktion, da keine weiteren Berechnungen möglich sind
   }
   
   // Wenn wir hier ankommen, war der Zugriff erfolgreich
   if(!lastAccessSuccessful)
   {
      // Lösche die Fehlermeldung, wenn der Zugriff wieder funktioniert
      ObjectSetString(0, errorLabelName, OBJPROP_TEXT, "");
      Print("INFO: Kontoinformationen können wieder abgerufen werden.");
      lastAccessSuccessful = true;
   }
   
   // Prüfe täglichen Reset um 10 Uhr
   CheckDailyReset();
   
   // Berechne Open Equity in Prozent und Währung
   if(currentBalance > 0)
   {
      currentOpenEquity = (currentEquity - currentBalance) / currentBalance * 100;
      currentOpenEquityCurrency = currentEquity - currentBalance;
   }
   
   // Aktualisiere Min/Max für den Tag
   UpdateDailyMinMax();
   
   // Aktualisiere das Maximum des Kontostands, wenn nötig
   if(currentBalance > maxBalance)
   {
      maxBalance = currentBalance;
      // Bei neuem Balance-High den Alarm zurücksetzen
      alarmTriggered = false;
   }
   
   // Berechne den Drawdown in Prozent
   double drawdownPercent = 0;
   if(maxBalance > 0) // Vermeide Division durch Null
      drawdownPercent = (maxBalance - currentEquity) / maxBalance * 100;
   
   // Aktualisiere die Textanzeige
   string drawdownText = "Drawdown: " + DoubleToString(drawdownPercent, 2) + "% vom Balance-High (" + DoubleToString(maxBalance, 2) + ")";
   
   // Aktualisiere auch die Alarmschwellen-Anzeige
   double alarmEquityThreshold = maxBalance * (1 - AlarmDrawdownProzent/100);
   string alarmText = "Alarmschwelle: " + DoubleToString(AlarmDrawdownProzent, 2) + 
                    "% (Equity " + DoubleToString(alarmEquityThreshold, 2) + ")";
   ObjectSetString(0, alarmLabelName, OBJPROP_TEXT, alarmText);
   
   // Aktualisiere Open Equity Anzeige
   color equityColor = currentOpenEquity >= 0 ? clrLime : clrRed;
   string openEquityText = "Open Equity: " + DoubleToString(currentOpenEquity, 2) + "% (" + DoubleToString(currentOpenEquityCurrency, 2) + ")";
   ObjectSetString(0, openEquityLabelName, OBJPROP_TEXT, openEquityText);
   ObjectSetInteger(0, openEquityLabelName, OBJPROP_COLOR, equityColor);
   
   // Aktualisiere Min/Max Anzeige in Prozent
   string minMaxText = "Heute Min: " + DoubleToString(dailyMinOpenEquity, 2) + "% | Max: " + DoubleToString(dailyMaxOpenEquity, 2) + "%";
   ObjectSetString(0, minMaxLabelName, OBJPROP_TEXT, minMaxText);
   
   // Aktualisiere Min/Max Anzeige in Währung
   string currencySymbol = AccountInfoString(ACCOUNT_CURRENCY);
   string minMaxCurrencyText = "Min/Max " + currencySymbol + ": " + DoubleToString(dailyMinOpenEquityCurrency, 2) + " | " + DoubleToString(dailyMaxOpenEquityCurrency, 2);
   ObjectSetString(0, minMaxCurrencyLabelName, OBJPROP_TEXT, minMaxCurrencyText);
   
   // Füge Alarminformation hinzu, wenn ausgelöst
   if(alarmTriggered)
   {
      drawdownText += " | Alarm bei " + DoubleToString(alarmEquity, 2);
      // Setze Alarmtext in roter Farbe
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, AlarmTextColor);
   }
   else
   {
      // Normaler Text in der konfigurierten Farbe
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, TextColor);
   }
   
   ObjectSetString(0, objectName, OBJPROP_TEXT, drawdownText);
   
   // Überprüfe, ob die Alarmschwelle überschritten wurde
   if(!alarmTriggered && drawdownPercent >= AlarmDrawdownProzent)
   {
      // Alarm auslösen
      alarmTriggered = true;
      alarmEquity = currentEquity;
      
      // Popup-Fenster anzeigen
      string alarmMessage = "ACHTUNG: Drawdown-Schwelle überschritten!\n" +
                           "Aktueller Drawdown: " + DoubleToString(drawdownPercent, 2) + "%\n" +
                           "Aktuelle Equity: " + DoubleToString(currentEquity, 2) + "\n" +
                           "Balance-High: " + DoubleToString(maxBalance, 2) + "\n" +
                           "Alarm-Equity-Schwelle: " + DoubleToString(alarmEquityThreshold, 2);
      
      Alert(alarmMessage);
      Print("ALARM: Drawdown-Schwelle von " + DoubleToString(AlarmDrawdownProzent, 2) + "% überschritten! " +
            "Equity-Alarmschwelle: " + DoubleToString(alarmEquityThreshold, 2));
      
      // Optional Sound abspielen
      if(PlaySound)
         PlaySound("alert.wav");
   }
   
   // Fordere Chart-Aktualisierung an
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Initialisiert das Open Equity Tracking                          |
//+------------------------------------------------------------------+
void InitializeOpenEquityTracking()
{
   datetime currentTime = TimeLocal();
   lastResetTime = currentTime;
   dailyMinOpenEquity = 0;
   dailyMaxOpenEquity = 0;
   dailyMinOpenEquityCurrency = 0;
   dailyMaxOpenEquityCurrency = 0;
   
   Print("Open Equity Tracking initialisiert um ", TimeToString(currentTime));
}

//+------------------------------------------------------------------+
//| Prüft ob ein täglicher Reset um 10 Uhr erforderlich ist         |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime currentTime = TimeLocal();
   MqlDateTime currentStruct, lastResetStruct;
   
   TimeToStruct(currentTime, currentStruct);
   TimeToStruct(lastResetTime, lastResetStruct);
   
   // Prüfe ob ein neuer Tag ist und es nach 10 Uhr ist
   if((currentStruct.day != lastResetStruct.day || 
       currentStruct.mon != lastResetStruct.mon || 
       currentStruct.year != lastResetStruct.year) && 
      currentStruct.hour >= 10)
   {
      // Schreibe aktuelle Werte ins Logfile BEVOR sie zurückgesetzt werden
      if(dailyMinOpenEquity != 0 || dailyMaxOpenEquity != 0) // Nur loggen wenn Daten vorhanden
      {
         WriteEquityLogEntry();
      }
      
      // Reset der täglichen Min/Max Werte
      dailyMinOpenEquity = currentOpenEquity;
      dailyMaxOpenEquity = currentOpenEquity;
      dailyMinOpenEquityCurrency = currentOpenEquityCurrency;
      dailyMaxOpenEquityCurrency = currentOpenEquityCurrency;
      lastResetTime = currentTime;
      
      Print("Täglicher Reset der Open Equity Min/Max Werte um ", TimeToString(currentTime));
   }
}

//+------------------------------------------------------------------+
//| Aktualisiert die täglichen Min/Max Werte                        |
//+------------------------------------------------------------------+
void UpdateDailyMinMax()
{
   // Beim ersten Mal initialisieren
   if(dailyMinOpenEquity == 0 && dailyMaxOpenEquity == 0)
   {
      dailyMinOpenEquity = currentOpenEquity;
      dailyMaxOpenEquity = currentOpenEquity;
      dailyMinOpenEquityCurrency = currentOpenEquityCurrency;
      dailyMaxOpenEquityCurrency = currentOpenEquityCurrency;
   }
   else
   {
      if(currentOpenEquity < dailyMinOpenEquity)
      {
         dailyMinOpenEquity = currentOpenEquity;
         dailyMinOpenEquityCurrency = currentOpenEquityCurrency;
      }
      
      if(currentOpenEquity > dailyMaxOpenEquity)
      {
         dailyMaxOpenEquity = currentOpenEquity;
         dailyMaxOpenEquityCurrency = currentOpenEquityCurrency;
      }
   }
}

//+------------------------------------------------------------------+
//| Schreibt einen Eintrag ins Equity Drawdown Logfile              |
//+------------------------------------------------------------------+
void WriteEquityLogEntry()
{
   string filename = "equitydrawdown.log";
   int fileHandle;
   
   // Versuche die Datei zum Anhängen zu öffnen, falls sie nicht existiert wird sie erstellt
   fileHandle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ";");
   
   if(fileHandle != INVALID_HANDLE)
   {
      // Gehe ans Ende der Datei
      FileSeek(fileHandle, 0, SEEK_END);
      
      // Erstelle Header falls die Datei leer ist
      if(FileSize(fileHandle) == 0)
      {
         FileWrite(fileHandle, "Datum", "Min_Prozent", "Max_Prozent", "Min_Waehrung", "Max_Waehrung", "Waehrung");
      }
      
      // Erstelle Datumsstring für den gestrigen Tag (da um 10 Uhr resettet wird)
      datetime yesterday = TimeLocal() - 86400; // Minus 1 Tag
      MqlDateTime dateStruct;
      TimeToStruct(yesterday, dateStruct);
      string dateString = StringFormat("%04d-%02d-%02d", dateStruct.year, dateStruct.mon, dateStruct.day);
      
      // Hole Währungssymbol
      string currencySymbol = AccountInfoString(ACCOUNT_CURRENCY);
      
      // Schreibe die Daten
      FileWrite(fileHandle, 
                dateString,
                DoubleToString(dailyMinOpenEquity, 2),
                DoubleToString(dailyMaxOpenEquity, 2), 
                DoubleToString(dailyMinOpenEquityCurrency, 2),
                DoubleToString(dailyMaxOpenEquityCurrency, 2),
                currencySymbol);
      
      // Schließe die Datei
      FileClose(fileHandle);
      
      Print("Equity Drawdown Daten für ", dateString, " ins Logfile geschrieben: Min ", 
            DoubleToString(dailyMinOpenEquity, 2), "% (", DoubleToString(dailyMinOpenEquityCurrency, 2), " ", currencySymbol, "), Max ", 
            DoubleToString(dailyMaxOpenEquity, 2), "% (", DoubleToString(dailyMaxOpenEquityCurrency, 2), " ", currencySymbol, ")");
   }
   else
   {
      Print("FEHLER: Konnte Equity Drawdown Logfile nicht öffnen. Fehlercode: ", GetLastError());
   }
}