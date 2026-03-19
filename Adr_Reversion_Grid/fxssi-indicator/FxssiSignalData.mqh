//+------------------------------------------------------------------+
//|                                           FxssiSignalData.mqh    |
//|                              FXSSI Signal Data - Include File    |
//|                                                                  |
//| Include-Datei für Expert Advisors, um auf FXSSI-Sentiment-      |
//| Daten zuzugreifen, die vom FxssiSignalReader-Indikator           |
//| bereitgestellt werden.                                           |
//|                                                                  |
//| Der Indikator nutzt 4 Buffers:                                   |
//|   Buffer 0 = Anzahl geladener Symbole                            |
//|   Buffer 1 = Buy-Prozent für das Chart-Symbol                    |
//|   Buffer 2 = Sell-Prozent für das Chart-Symbol                   |
//|   Buffer 3 = Signal (+1=BUY, -1=SELL, 0=NEUTRAL)                |
//|                                                                  |
//| Verwendung:                                                      |
//|   #include "FxssiSignalData.mqh"                                 |
//+------------------------------------------------------------------+
#ifndef FXSSI_SIGNAL_DATA_MQH
#define FXSSI_SIGNAL_DATA_MQH

//+------------------------------------------------------------------+
//| Enum für FXSSI-Handelssignale                                    |
//+------------------------------------------------------------------+
enum ENUM_FXSSI_SIGNAL
  {
   FXSSI_BUY     =  1,   // Kaufsignal (Mehrheit verkauft -> Contrarian BUY)
   FXSSI_SELL    = -1,   // Verkaufssignal (Mehrheit kauft -> Contrarian SELL)
   FXSSI_NEUTRAL =  0    // Kein klares Signal
  };

//+------------------------------------------------------------------+
//| Struktur für FXSSI-Signal-Informationen                          |
//+------------------------------------------------------------------+
struct FxssiSignalInfo
  {
   string            symbol;       // Symbol-Name (z.B. "EUR_USD")
   double            buyPercent;   // Buy-Anteil in Prozent (z.B. 43.00)
   double            sellPercent;  // Sell-Anteil in Prozent (z.B. 57.00)
   ENUM_FXSSI_SIGNAL signal;      // Handelssignal
   bool              valid;        // true wenn Daten erfolgreich geladen
   
   // Konstruktor
   void FxssiSignalInfo()
     {
      symbol      = "";
      buyPercent   = 0.0;
      sellPercent  = 0.0;
      signal       = FXSSI_NEUTRAL;
      valid        = false;
     }
  };

//+------------------------------------------------------------------+
//| Normalisiert einen Symbolnamen vom Broker-Format ins FXSSI-Format|
//| z.B. "EURUSD" -> "EUR_USD", "XAUUSD" -> "XAU_USD"              |
//+------------------------------------------------------------------+
string FxssiNormalizeSymbol(string brokerSymbol)
  {
   // Entferne mögliche Suffixe (z.B. "EURUSD.m", "EURUSD.raw")
   int dotPos = StringFind(brokerSymbol, ".");
   if(dotPos > 0)
      brokerSymbol = StringSubstr(brokerSymbol, 0, dotPos);
   
   // Schon im FXSSI-Format?
   if(StringFind(brokerSymbol, "_") >= 0)
      return brokerSymbol;
   
   // Standard-Forex-Paare (6 Zeichen -> 3+3)
   int len = StringLen(brokerSymbol);
   if(len >= 6)
     {
      string base  = StringSubstr(brokerSymbol, 0, 3);
      string quote = StringSubstr(brokerSymbol, 3, 3);
      return base + "_" + quote;
     }
   
   return brokerSymbol;
  }

//+------------------------------------------------------------------+
//| Konvertiert double-Wert in ENUM_FXSSI_SIGNAL                    |
//+------------------------------------------------------------------+
ENUM_FXSSI_SIGNAL FxssiDoubleToSignal(double value)
  {
   if(value > 0.5)  return FXSSI_BUY;
   if(value < -0.5) return FXSSI_SELL;
   return FXSSI_NEUTRAL;
  }

//+------------------------------------------------------------------+
//| Gibt den Signal-Namen als String zurück                          |
//+------------------------------------------------------------------+
string FxssiSignalToString(ENUM_FXSSI_SIGNAL signal)
  {
   switch(signal)
     {
      case FXSSI_BUY:     return "BUY";
      case FXSSI_SELL:    return "SELL";
      case FXSSI_NEUTRAL: return "NEUTRAL";
      default:            return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//| Prüft ob der FXSSI-Indikator bereit ist (Daten geladen hat)     |
//|                                                                  |
//| Liest Buffer 0 (Anzahl geladener Symbole).                       |
//| Wenn > 0 sind Daten verfügbar.                                   |
//+------------------------------------------------------------------+
bool IsFxssiReady(int indicatorHandle)
  {
   if(indicatorHandle == INVALID_HANDLE)
      return false;
   
   double values[];
   if(CopyBuffer(indicatorHandle, 0, 0, 1, values) <= 0)
      return false;
   
   return (values[0] > 0);
  }

//+------------------------------------------------------------------+
//| Gibt die Anzahl geladener Symbole zurück                         |
//+------------------------------------------------------------------+
int GetFxssiLoadedSymbolCount(int indicatorHandle)
  {
   if(indicatorHandle == INVALID_HANDLE)
      return 0;
   
   double values[];
   if(CopyBuffer(indicatorHandle, 0, 0, 1, values) <= 0)
      return 0;
   
   return (int)values[0];
  }

//+------------------------------------------------------------------+
//| Holt FXSSI-Signal-Daten für das aktuelle Chart-Symbol            |
//|                                                                  |
//| Buffer 0 = SymbolCount                                           |
//| Buffer 1 = Buy%                                                  |
//| Buffer 2 = Sell%                                                 |
//| Buffer 3 = Signal                                                |
//+------------------------------------------------------------------+
bool GetFxssiSignal(int indicatorHandle, string symbol, FxssiSignalInfo &info)
  {
   info.valid = false;
   
   if(indicatorHandle == INVALID_HANDLE)
     {
      Print("FXSSI ERROR: Ungültiger Handle!");
      return false;
     }
   
   double values[];
   
   // Buffer 1: Buy Percent
   if(CopyBuffer(indicatorHandle, 1, 0, 1, values) <= 0)
     {
      return false;
     }
   info.buyPercent = values[0];
   
   // Buffer 2: Sell Percent
   if(CopyBuffer(indicatorHandle, 2, 0, 1, values) <= 0)
     {
      return false;
     }
   info.sellPercent = values[0];
   
   // Buffer 3: Signal
   if(CopyBuffer(indicatorHandle, 3, 0, 1, values) <= 0)
     {
      return false;
     }
   info.signal = FxssiDoubleToSignal(values[0]);
   
   // Symbol und Gültigkeit setzen
   info.symbol = FxssiNormalizeSymbol(symbol);
   info.valid  = true;
   
   return true;
  }

#endif // FXSSI_SIGNAL_DATA_MQH
