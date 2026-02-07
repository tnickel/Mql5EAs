# MQL5Notify - Expert Advisor Dokumentation

**Version:** 1.04  
**Autor:** Thomas  
**Plattform:** MetaTrader 5

---

## Warum MQL5Notify?

Als aktiver Trader kennen Sie das Problem: Sie können nicht 24 Stunden am Tag vor dem Bildschirm sitzen und Ihre Trades überwachen. Dennoch möchten Sie jederzeit informiert sein, wenn sich etwas auf Ihrem Konto tut – sei es eine neue Position, ein geschlossener Trade oder einfach eine Übersicht über Ihren Handelstag.

**MQL5Notify** löst dieses Problem elegant. Der Expert Advisor läuft im Hintergrund auf Ihrem MetaTrader 5 und informiert Sie automatisch per E-Mail über alle wichtigen Ereignisse. So behalten Sie auch unterwegs, im Büro oder während Sie schlafen die volle Kontrolle über Ihr Trading-Konto.

### Die wichtigsten Vorteile:

- **Nie wieder wichtige Trades verpassen** – Erhalten Sie sofort eine Benachrichtigung, wenn ein Trade eröffnet oder geschlossen wird, inklusive aller Details wie Einstiegspreis, Stop Loss und Take Profit.

- **Tägliche Übersicht** – Am Ende jedes Handelstages erhalten Sie einen kompakten Tagesreport mit allen geschlossenen Trades, Ihrem Tagesergebnis und allen noch offenen Positionen.

- **Equity-Überwachung** – Sehen Sie auf einen Blick, wie hoch Ihr maximaler Gewinn und größter Drawdown während des Tages waren. So erkennen Sie Optimierungspotenzial in Ihrer Trading-Strategie.

- **Ressourcenschonend** – Der EA arbeitet extrem effizient und belastet weder Ihr System noch Ihre Trading-Performance. Keine Tick-by-Tick-Auswertung, keine unnötige CPU-Last.

- **Vollständig konfigurierbar** – Entscheiden Sie selbst, welche Reports Sie erhalten möchten und in welchen Intervallen. Alles lässt sich an Ihre Bedürfnisse anpassen.

Ob Sie ein Vollzeit-Trader sind, der seine Strategien automatisiert laufen lässt, oder ein Hobby-Trader, der neben dem Beruf handelt – **MQL5Notify** gibt Ihnen die Sicherheit, immer informiert zu sein, ohne ständig auf den Bildschirm schauen zu müssen.

---

## Installation

1. Kopiere `Mql5Notify.mq5` in das Verzeichnis:
   ```
   %APPDATA%\MetaQuotes\Terminal\[Terminal-ID]\MQL5\Experts\
   ```

2. Öffne MetaEditor und kompiliere die Datei (F7)

3. Aktiviere den EA auf einem beliebigen Chart

4. **Wichtig:** E-Mail muss im Terminal konfiguriert sein:
   - Menü: `Extras → Optionen → E-Mail`
   - SMTP-Server und Zugangsdaten eintragen

---

## Konfiguration

### Input-Parameter

#### Übersicht

| Parameter | Typ | Standard | Beschreibung |
|-----------|-----|----------|--------------|
| InpCheckIntervalMinutes | int | 5 | Prüf-Intervall in Minuten |
| InpEmailSubjectPrefix | string | [MT5]  | E-Mail Betreff-Prefix |
| InpLogToExperts | bool | true | Log-Ausgabe im Experts-Tab |
| InpTradeReportEnabled | bool | true | Trade-Report aktivieren |
| InpDailyReportEnabled | bool | true | Tagesreport aktivieren |
| InpDailyReportHour | int | 23 | Tagesreport Stunde (0-23) |
| InpDailyReportMinute | int | 55 | Tagesreport Minute (0-59) |

#### Details

**`InpCheckIntervalMinutes`** (int, Standard: 5)
- Prüf-Intervall in Minuten
- Bestimmt wie oft der EA auf neue Trades prüft
- **Wichtig:** Dieses Intervall bestimmt auch die Genauigkeit der Equity-Überwachung!

**`InpEmailSubjectPrefix`** (string, Standard: "[MT5] ")
- Prefix für den E-Mail-Betreff

**`InpLogToExperts`** (bool, Standard: true)
- Log-Ausgabe im Experts-Tab aktivieren

**`InpTradeReportEnabled`** (bool, Standard: true)
- Trade-Report bei Eröffnung/Schluss ein-/ausschalten

**`InpDailyReportEnabled`** (bool, Standard: true)
- Tagesreport ein-/ausschalten

**`InpDailyReportHour`** (int, Standard: 23)
- Stunde für den Tagesreport (0-23)

**`InpDailyReportMinute`** (int, Standard: 55)
- Minute für den Tagesreport (0-59)

---

### ⚠️ Wichtiger Hinweis zur Equity-Überwachung

> **Die Equity-Überwachung erfolgt NICHT auf Tick-Ebene!**
> 
> Die Equity-Werte (Max/Min) werden nur im konfigurierten Intervall erfasst.
> 
> - Bei `InpCheckIntervalMinutes = 5` wird die Equity nur alle 5 Minuten geprüft
> - Bei `InpCheckIntervalMinutes = 1` wird die Equity jede Minute geprüft
> 
> **Für genaueres Equity-Tracking muss das Intervall auf 1 Minute gesetzt werden.**
> 
> Diese Entscheidung wurde bewusst getroffen, um Rechenzeit zu sparen. Der EA wertet grundsätzlich nichts auf Tick-Ebene aus.

---

### Beispiel-Konfiguration

- **Nur Tagesreport um 18:00:**
  - `InpTradeReportEnabled = false`
  - `InpDailyReportEnabled = true`
  - `InpDailyReportHour = 18`
  - `InpDailyReportMinute = 0`

- **Trade-Report alle 10 Minuten, kein Tagesreport:**
  - `InpCheckIntervalMinutes = 10`
  - `InpTradeReportEnabled = true`
  - `InpDailyReportEnabled = false`

- **Genaues Equity-Tracking (jede Minute):**
  - `InpCheckIntervalMinutes = 1`

---

## Features

### 1. Trade-Report (Eröffnung)

Bei jeder Trade-Eröffnung wird eine E-Mail gesendet mit:
- Symbol und Richtung (BUY/SELL)
- Volumen und Einstiegspreis
- Stop Loss und Take Profit (falls gesetzt)
- Liste aller offenen Positionen

### 2. Trade-Report (Schluss)

Bei jedem Trade-Schluss wird eine E-Mail gesendet mit:
- Profit/Verlust inkl. Commission und Swap
- **Max Open Equity** - höchster Gewinn während der Trade-Laufzeit
- Liste aller offenen Positionen

### 3. Tagesreport

Täglich zur konfigurierten Uhrzeit:
- Tagesergebnis (Profit, Commission, Swap)
- **Max Account Equity** - höchster Gewinn aller Positionen
- **Min Account Equity** - größter Drawdown aller Positionen
- Liste geschlossener Trades mit Ein-/Ausstiegspreis
- Liste offener Positionen

### 4. Equity-Tracking

Der EA trackt im konfigurierten Intervall:
- **Per-Trade:** Maximale Open Equity für jeden einzelnen Trade
- **Account-weit:** Maximum und Minimum über alle offenen Positionen

---

## E-Mail-Beispiele

### Trade-Report (Eröffnung)

**Betreff:** `[MT5] 1 Trade(s) eröffnet`

```
=== MQL5 Trade Notification ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 10250.00 EUR
Equity: 10285.50 EUR
Zeitpunkt: 2026.02.07 12:45

--- 1 TRADE(S) ERÖFFNET ---
  [EURUSD]   2026.02.07 12:45 | OPEN BUY 0.10 Lots @ 1.08250 | Pos#987654
    SL: 1.08050 | TP: 1.08650

--- 2 OFFENE POSITION(EN) ---
  [EURUSD] BUY 0.10 Lots @ 1.08250 (aktuell: 1.08265) | P/L: +15.00 | Swap: 0.00 | Max: +15.00 | Offen seit: 2026.02.07 12:45
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26480) | P/L: +10.00 | Swap: -0.50 | Max: +25.00 | SL: 1.26700 | TP: 1.26200 | Offen seit: 2026.02.06 14:30
  Gesamt offener P/L: 24.50 EUR

=== Ende der Benachrichtigung ===
```

### Trade-Report (Schluss)

**Betreff:** `[MT5] 1 Trade(s) geschlossen`

```
=== MQL5 Trade Notification ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 10375.50 EUR
Equity: 10410.00 EUR
Zeitpunkt: 2026.02.07 18:30

--- 1 TRADE(S) GESCHLOSSEN ---
  [EURUSD]   2026.02.07 18:30 | CLOSE SELL 0.10 Lots @ 1.08450 | Pos#987654
    P/L: +125.50 (Profit: 128.00, Comm: -2.50)
    Max Open Equity: +185.30

--- 1 OFFENE POSITION(EN) ---
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26350) | P/L: +75.00 | Swap: -1.20 | Max: +95.00 | SL: 1.26700 | TP: 1.26200 | Offen seit: 2026.02.06 14:30
  Gesamt offener P/L: 73.80 EUR

=== Ende der Benachrichtigung ===
```

### Tagesreport

**Betreff:** `[MT5] Tagesreport 2026.02.07 +285.50 EUR`

```
=== MQL5 TAGESREPORT ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 10535.50 EUR
Equity: 10610.00 EUR
Datum: 2026.02.07

=== TAGESERGEBNIS ===
Profit: 295.00 EUR
Commission: -7.50 EUR
Swap: -2.00 EUR
GESAMT: 285.50 EUR
Max Account Equity heute: +425.50 EUR
Min Account Equity heute: -180.00 EUR

--- 3 TRADE(S) HEUTE GESCHLOSSEN ---
  [EURUSD] 10:15 | SELL 0.10 @ 1.08350 -> 1.08250 | P/L: +100.00 | Max: +145.00
  [EURUSD] 14:30 | BUY 0.05 @ 1.08100 -> 1.08280 | P/L: +85.50 | Max: +120.30
  [USDJPY] 18:45 | BUY 0.20 @ 149.250 -> 149.500 | P/L: +100.00 | Max: +160.20

--- 1 OFFENE POSITION(EN) ---
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26250) | P/L: +125.00 | Swap: -1.80 | Max: +150.00 | SL: 1.26700 | TP: 1.26200 | Offen seit: 2026.02.06 14:30
  Gesamt offener P/L: 123.20 EUR

=== Ende Tagesreport ===
```

---

## Technische Details

### Architektur

```
OnInit()
  └── InitializeKnownDeals()     // Bekannte Deals beim Start erfassen
  └── EventSetTimer(60)          // Timer alle 60 Sekunden
  └── UpdateChartInfo()          // Chart-Anzeige initialisieren

OnTimer()
  └── UpdateChartInfo()          // Chart aktualisieren
  └── CheckAndSendDailyReport()  // Tagesreport prüfen
  └── UpdateEquityTracking()     // Equity-Werte tracken
  └── CheckForNewDeals()         // Neue Trades suchen
```

### Datenstrukturen

```mql5
// Per-Trade Equity Tracking
struct TradeEquityInfo {
   ulong  positionId;  // Position-ID
   double maxEquity;   // Max Equity für diesen Trade
};
TradeEquityInfo g_tradeEquity[];

// Account-weites Tages-Tracking
double g_maxDailyEquity;  // Max Account-Equity des Tages
double g_minDailyEquity;  // Min Account-Equity des Tages
```

### Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| `CheckForNewDeals()` | Prüft auf neue Deals und sendet Report |
| `CheckAndSendDailyReport()` | Prüft ob Tagesreport gesendet werden soll |
| `SendDailyReport()` | Erstellt und sendet Tagesreport |
| `SendNotificationEmail()` | Erstellt und sendet Trade-Report |
| `UpdateEquityTracking()` | Aktualisiert Max/Min Equity-Werte |
| `GetMaxEquityForPosition()` | Liest Max-Equity für eine Position |
| `GetOpenPositionsInfo()` | Formatiert offene Positionen als Text |
| `FormatDealInfo()` | Formatiert Deal-Informationen |

---

## Chart-Anzeige

Der EA zeigt folgende Informationen auf dem Chart an:

```
MQL5Notify v1.04
Intervall: 5 Min
Letzte Mail: 2026.02.07 18:30
Gesendete Mails: 12
Nächste Prüfung in: 3:45
```

---

## Voraussetzungen

- MetaTrader 5
- E-Mail im Terminal konfiguriert
- EA muss auf einem Chart aktiv sein
- Automatischer Handel muss aktiviert sein

---

## Changelog

### Version 1.04
- Equity-Tracking für per-Trade Maximum
- Account-weites Tages-Equity-Tracking (Max + Min)
- Einstiegs- und Ausstiegspreis im Tagesreport

### Version 1.03
- Konfigurierbare Uhrzeit für Tagesreport
- Trade-Report ein-/ausschaltbar
- Tagesreport-Feature

### Version 1.02
- Trade-Report bei Eröffnung mit SL/TP
- Optimierte Profit-Anzeige

### Version 1.01
- Initiale Version
- Trade-Überwachung
- E-Mail-Benachrichtigungen

---

## Troubleshooting

### E-Mail wird nicht gesendet
1. Prüfe E-Mail-Konfiguration unter `Extras → Optionen → E-Mail`
2. Teste mit "Test"-Button in den E-Mail-Einstellungen
3. Prüfe Experts-Log auf Fehlermeldungen

### EA startet nicht
1. Stelle sicher, dass der EA kompiliert wurde (F7)
2. Prüfe auf Initialisierungs-Fehler im Experts-Log
3. Stelle sicher, dass `InpCheckIntervalMinutes >= 1`

### Keine Deals erkannt
1. Der EA erkennt nur neue Deals nach dem Start
2. Deals die vor dem Start existierten werden ignoriert
3. Prüfe ob `InpTradeReportEnabled = true`
