//+------------------------------------------------------------------+
//|                                      CC_FXSSI10_Secure_v162.mq5  |
//|                               Copyright 2026, Algorithm Factory  |
//|       Feature: 48h Grace, 50% ADR, Entry-Block News Filter       |
//+------------------------------------------------------------------+
#property copyright "Jan Kotzorek"
#property link      ""
#property version   "1.62"
#property strict

#define EA_VERSION "v1.62 (Secure Volatility Edition)"

#include <Trade\Trade.mqh>

//--- ENUMS ---
enum ENUM_ENTRY_MODE { MODE_ADR = 0, MODE_RSI = 1 };
enum ENUM_DIR_FILTER { FILTER_BOTH = 0, FILTER_LONG = 1, FILTER_SHORT = 2, FILTER_NEUTRAL = 3 };
enum ENUM_NEWS_IMPORTANCE { NEWS_HIGH_ONLY = 0, NEWS_MEDIUM_HIGH = 1 };

//--- INPUT PARAMETERS ---
input group "=== Global Risk Management ==="
input int      InpMaxGlobalBaskets   = 3;           // Max Baskets accountweit
input bool     InpUseOverlapFilter   = true;        // Blockiere gleiche Währungen
input bool     InpUseRoRoFilter      = false;       // Blockiere RoRo Zwillinge

input group "=== Trading Hours (First Entry Only) ==="
input int      InpStartHour          = 2;           
input int      InpEndHour            = 18;          
input int      InpEndMinute          = 30;          

input group "=== CSV Sentiment & 48h Grace Period ==="
input bool     InpUseCSVSignals      = true;        
input int      InpCSVCheckInterval   = 15;          
input int      InpSentimentCheckHour = 12;          
input string   InpCSVFilename        = "last_known_signals.csv"; 

input group "=== News Filter (Block Entry Only) ==="
input bool     InpUseNewsFilter           = true;           
input ENUM_NEWS_IMPORTANCE InpNewsImportance = NEWS_HIGH_ONLY; // Nur High Impact Standard
input int      InpMinutesBeforeNews       = 30;             
input int      InpMinutesAfterNews        = 30;             

input group "--- Direction Filter ---"
input ENUM_DIR_FILTER InpStartDirection = FILTER_BOTH; 

input group "--- Positions Management ---"
input double   InpFirstLot          = 0.03;        
input double   InpGridLot           = 0.03;        
input int      InpMaxPositions      = 10;          
input double   InpIndividualSL_ADR  = 1.5;         

input group "--- ADR Settings ---"
input int      InpADRPeriod         = 14;          
input double   InpEntryADR_Pct      = 50.0;        // 50% ADR Threshold
input double   InpGridStep_ADR_Pct  = 10.0;        

input group "--- Dynamic Exit Targets ---"
input double   InpStartTarget_ADR   = 10.0;        
input double   InpTargetDecay_ADR   = 0.0;         

input group "--- Stochastic Settings (H1) ---"
input int      InpStochK            = 5;
input int      InpStochUpper        = 85;
input int      InpStochLower        = 15;

input int      InpMagicNumber       = 101;      

//--- GLOBALS ---
CTrade trade;
int handleStoch;
int handleRSI = INVALID_HANDLE;
double adrValue = 0.0, dayRange = 0.0;
datetime lastProcessedH1Bar = 0;

// Stats
double stat_HighWaterMark = 0.0, stat_MaxDD_Equity_Percent = 0.0;
string stat_EA_Action = "Initializing...";

// Sentiment Logic
ENUM_DIR_FILTER g_currentFilter = FILTER_NEUTRAL, g_csvLatestSignal = FILTER_NEUTRAL, g_pendingFilter = FILTER_NEUTRAL;
int g_gracePeriodCounter = 0, g_LastDailyCheckDay = -1;
bool g_CSVMode = false; string g_CSVSignalText_Raw = "N/A";

// News State
bool g_NewsBlockActive = false; string g_NextNewsInfo = "Clear";

// GUI Names
string lblMaxDDName="L1", lblPosName="L2", lblStatusName="L3", lblCSVInfoName="L4", lblGraceName="L5", lblNewsInfoName="L6";

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit() {
   stat_HighWaterMark = AccountInfoDouble(ACCOUNT_BALANCE);
   handleStoch = iStochastic(_Symbol, PERIOD_H1, InpStochK, 3, 3, MODE_SMA, STO_LOWHIGH);
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   CreateLabels();
   if(InpUseCSVSignals) { CheckCSVFile(); EventSetTimer(InpCSVCheckInterval * 60); }
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, "Lbl_"); }

void OnTimer() { if(InpUseCSVSignals) CheckCSVFile(); }

//+------------------------------------------------------------------+
//| Main Loop                                                        |
//+------------------------------------------------------------------+
void OnTick() {
   // 1. MONITORING
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(AccountInfoDouble(ACCOUNT_BALANCE) > stat_HighWaterMark) stat_HighWaterMark = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd = (stat_HighWaterMark > 0) ? ((stat_HighWaterMark - currentEquity) / stat_HighWaterMark) * 100.0 : 0.0;
   if(dd > stat_MaxDD_Equity_Percent) stat_MaxDD_Equity_Percent = dd;

   CalculateADR_and_Range();
   CheckUpcomingNews(); // News Filter Check
   
   ENUM_POSITION_TYPE openType;
   int openPositions = CountOpenPositions(openType);
   
   // 2. SENTIMENT CHECK (48h Rule)
   ProcessDailySentiment(openPositions);

   // 3. BASKET MANAGEMENT (GRID)
   if(openPositions > 0) {
      CheckBasketExit(openType, openPositions);
      
      datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
      if(currentH1Bar != lastProcessedH1Bar && openPositions < InpMaxPositions) {
         if(g_NewsBlockActive) {
            stat_EA_Action = "News Block: Kein Grid-Eintrag!";
         } else {
            lastProcessedH1Bar = currentH1Bar;
            double lastEntry = GetLastEntryPrice(openType);
            double reqDist = adrValue * (InpGridStep_ADR_Pct / 100.0);
            double sl = adrValue * InpIndividualSL_ADR;
            
            if(openType == POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= (lastEntry + reqDist))
               trade.Sell(GetDynamicLot(InpGridLot), _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), SymbolInfoDouble(_Symbol, SYMBOL_ASK) + sl, 0, "Grid Sell");
            if(openType == POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID) <= (lastEntry - reqDist))
               trade.Buy(GetDynamicLot(InpGridLot), _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_BID) - sl, 0, "Grid Buy");
         }
      }
   }

   // 4. FIRST ENTRY LOGIC
   if(openPositions == 0) {
      MqlDateTime tm; TimeToStruct(TimeTradeServer(), tm);
      bool timeOk = (tm.hour * 60 + tm.min >= InpStartHour * 60 && tm.hour * 60 + tm.min <= InpEndHour * 60 + InpEndMinute);
      
      if(!timeOk) stat_EA_Action = "Outside Hours";
      else if(g_NewsBlockActive) stat_EA_Action = "News Block: " + g_NextNewsInfo;
      else {
         string block;
         if(!IsGlobalFilterOK(block)) stat_EA_Action = "Global Guard: " + block;
         else if(dayRange > (adrValue * (InpEntryADR_Pct/100.0))) {
            double k[], d[];
            if(CopyBuffer(handleStoch,0,0,3,k)>=3) {
               if(k[2]>=InpStochUpper && k[1]<InpStochUpper && (g_currentFilter==FILTER_SHORT || g_currentFilter==FILTER_BOTH))
                  trade.Sell(GetDynamicLot(InpFirstLot), _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), SymbolInfoDouble(_Symbol, SYMBOL_ASK)+adrValue*InpIndividualSL_ADR, 0, "First Sell");
               else if(k[2]<=InpStochLower && k[1]>InpStochLower && (g_currentFilter==FILTER_LONG || g_currentFilter==FILTER_BOTH))
                  trade.Buy(GetDynamicLot(InpFirstLot), _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_BID)-adrValue*InpIndividualSL_ADR, 0, "First Buy");
               stat_EA_Action = "Scanning Stoch...";
            }
         } else stat_EA_Action = StringFormat("Wait Range (%.0f%%/%.0f%%)", (dayRange/adrValue)*100.0, InpEntryADR_Pct);
      }
   }

   UpdateVisuals(openPositions);
}

//+------------------------------------------------------------------+
//| News Filter (Block Entries only)                                 |
//+------------------------------------------------------------------+
void CheckUpcomingNews() {
   if(!InpUseNewsFilter) return;
   datetime now = TimeTradeServer();
   MqlCalendarValue values[];
   // Prüfe Fenster: 30 Min vor bis 30 Min nach jetzt
   if(CalendarValueHistory(values, now - (InpMinutesAfterNews*60), now + (InpMinutesBeforeNews*60), NULL, StringSubstr(_Symbol,0,3))) {
      for(int i=0; i<ArraySize(values); i++) {
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id, ev)) {
            ENUM_CALENDAR_EVENT_IMPORTANCE minImp = (InpNewsImportance == NEWS_HIGH_ONLY) ? CALENDAR_IMPORTANCE_HIGH : CALENDAR_IMPORTANCE_MODERATE;
            if(ev.importance >= minImp) {
               g_NewsBlockActive = true;
               g_NextNewsInfo = ev.name;
               return;
            }
         }
      }
   }
   g_NewsBlockActive = false;
   g_NextNewsInfo = "Clear";
}

//+------------------------------------------------------------------+
//| 48h Sentiment Logic                                              |
//+------------------------------------------------------------------+
void ProcessDailySentiment(int openPos) {
   if(!InpUseCSVSignals) return;
   MqlDateTime tm; TimeToStruct(TimeTradeServer(), tm);
   if(openPos == 0 && g_gracePeriodCounter > 0) { g_currentFilter = g_pendingFilter; g_gracePeriodCounter = 0; }
   
   if(tm.hour == InpSentimentCheckHour && tm.day != g_LastDailyCheckDay) {
      g_LastDailyCheckDay = tm.day;
      if(openPos == 0) { g_currentFilter = g_csvLatestSignal; g_gracePeriodCounter = 0; }
      else {
         if(g_csvLatestSignal != g_currentFilter) {
            g_gracePeriodCounter++; g_pendingFilter = g_csvLatestSignal;
            if(g_gracePeriodCounter >= 3) { // 3. Check = 48h um
               CloseOppositePositions(g_csvLatestSignal);
               g_currentFilter = g_csvLatestSignal; g_gracePeriodCounter = 0;
            }
         } else g_gracePeriodCounter = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsGlobalFilterOK(string &reason) {
   string syms[]; int count = 0;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
         string s = PositionGetString(POSITION_SYMBOL); bool found=false;
         for(int j=0; j<count; j++) if(syms[j]==s) found=true;
         if(!found) { ArrayResize(syms, count+1); syms[count]=s; count++; }
      }
   }
   for(int j=0; j<count; j++) if(syms[j]==_Symbol) return true;
   if(count >= InpMaxGlobalBaskets) { reason="Max Baskets"; return false; }
   if(InpUseOverlapFilter) {
      string b1=StringSubstr(_Symbol,0,3), q1=StringSubstr(_Symbol,3,3);
      for(int j=0; j<count; j++) {
         string b2=StringSubstr(syms[j],0,3), q2=StringSubstr(syms[j],3,3);
         if(b1==b2 || b1==q2 || q1==b2 || q1==q2) { reason="Overlap "+syms[j]; return false; }
      }
   }
   return true;
}

void CheckCSVFile() {
   int h = FileOpen(InpCSVFilename, FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h)) {
      string line = FileReadString(h); string p[];
      if(StringSplit(line, ';', p) >= 2) {
         string s = p[0]; StringTrimLeft(s); StringTrimRight(s);
         if(s == _Symbol || StringFind(_Symbol, s) == 0) {
            string sig = p[1]; StringToUpper(sig); g_CSVSignalText_Raw = sig;
            g_csvLatestSignal = (StringFind(sig,"BUY")>=0)?FILTER_LONG:(StringFind(sig,"SELL")>=0)?FILTER_SHORT:FILTER_NEUTRAL;
            g_CSVMode = true; break;
         }
      }
   }
   FileClose(h);
}

int CountOpenPositions(ENUM_POSITION_TYPE &t) {
   int c=0; for(int i=0; i<PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) {
         c++; t=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      }
   } return c;
}

double GetLastEntryPrice(ENUM_POSITION_TYPE t) {
   double lp=0; for(int i=0; i<PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) {
         double p=PositionGetDouble(POSITION_PRICE_OPEN);
         if(t==POSITION_TYPE_SELL) { if(p>lp) lp=p; } else { if(lp==0||p<lp) lp=p; }
      }
   } return lp;
}

void CloseOppositePositions(ENUM_DIR_FILTER d) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) {
         ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if((d==FILTER_LONG && t==POSITION_TYPE_SELL)||(d==FILTER_SHORT && t==POSITION_TYPE_BUY)) trade.PositionClose(PositionGetTicket(i));
      }
   }
}

void CheckBasketExit(ENUM_POSITION_TYPE t, int c) {
   double tl=0, wp=0;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) {
         double v=PositionGetDouble(POSITION_VOLUME); wp+=(PositionGetDouble(POSITION_PRICE_OPEN)*v); tl+=v;
      }
   }
   if(tl<=0) return;
   double tgt = (wp/tl) + ((t==POSITION_TYPE_BUY?1:-1)*(adrValue*(MathMax(InpStartTarget_ADR-(c-1)*InpTargetDecay_ADR,0.1)/100.0)));
   if((t==POSITION_TYPE_BUY && SymbolInfoDouble(_Symbol, SYMBOL_BID)>=tgt) || (t==POSITION_TYPE_SELL && SymbolInfoDouble(_Symbol, SYMBOL_ASK)<=tgt)) {
      for(int i=PositionsTotal()-1; i>=0; i--) if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) trade.PositionClose(PositionGetTicket(i));
   }
}

void CalculateADR_and_Range() {
   if(iTime(_Symbol, PERIOD_D1, 0) != lastProcessedH1Bar || adrValue == 0) {
      double s=0; int v=0; for(int i=1; i<=InpADRPeriod; i++) { double h=iHigh(_Symbol,PERIOD_D1,i), l=iLow(_Symbol,PERIOD_D1,i); if(h>0){s+=(h-l); v++;}}
      adrValue=(v>0)?s/v:100*_Point;
   }
   dayRange = iHigh(_Symbol,PERIOD_D1,0)-iLow(_Symbol,PERIOD_D1,0);
}

double GetDynamicLot(double b) { return b; } // MM hier optional ergänzbar

//+------------------------------------------------------------------+
//| GUI                                                              |
//+------------------------------------------------------------------+
void CreateLabels() {
   int y=50; 
   string names[]={lblMaxDDName, lblPosName, lblStatusName, lblCSVInfoName, lblGraceName, lblNewsInfoName};
   for(int i=0; i<6; i++) {
      ObjectCreate(0, names[i], OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, names[i], OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, names[i], OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, names[i], OBJPROP_COLOR, clrWhite);
      y+=25;
   }
}

void UpdateVisuals(int p) {
   ObjectSetString(0, lblMaxDDName, OBJPROP_TEXT, StringFormat("MaxDD: %.2f%%", stat_MaxDD_Equity_Percent));
   ObjectSetString(0, lblPosName, OBJPROP_TEXT, StringFormat("Positions: %d / %d", p, InpMaxPositions));
   ObjectSetString(0, lblStatusName, OBJPROP_TEXT, "Status: " + stat_EA_Action);
   ObjectSetString(0, lblCSVInfoName, OBJPROP_TEXT, StringFormat("CSV-Raw: %s | Filter: %s", g_CSVSignalText_Raw, EnumToString(g_currentFilter)));
   ObjectSetString(0, lblGraceName, OBJPROP_TEXT, (g_gracePeriodCounter>0)?StringFormat("48h-WAIT (Tag %d/2)", g_gracePeriodCounter):"Direction OK");
   ObjectSetInteger(0, lblGraceName, OBJPROP_COLOR, (g_gracePeriodCounter>0)?clrOrangeRed:clrLime);
   ObjectSetString(0, lblNewsInfoName, OBJPROP_TEXT, "News: " + g_NextNewsInfo);
   ObjectSetInteger(0, lblNewsInfoName, OBJPROP_COLOR, g_NewsBlockActive?clrRed:clrGray);
}