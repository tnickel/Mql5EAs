# MQL5Notify - Expert Advisor Dokumentation

**Version:** 1.24  
**Autor:** Thomas  
**Plattform:** MetaTrader 5

---

## Warum MQL5Notify?

Als aktiver Trader kennen Sie das Problem: Sie können nicht 24 Stunden am Tag vor dem Bildschirm sitzen und Ihre Trades überwachen. Dennoch möchten Sie jederzeit informiert sein, wenn sich etwas auf Ihrem Konto tut – sei es eine neue Position, ein geschlossener Trade oder einfach eine Übersicht über Ihren Handelstag.

**MQL5Notify** löst dieses Problem elegant. Der Expert Advisor läuft im Hintergrund auf Ihrem MetaTrader 5 und informiert Sie automatisch per E-Mail über alle wichtigen Ereignisse. So behalten Sie auch unterwegs, im Büro oder während Sie schlafen die volle Kontrolle über Ihr Trading-Konto.

### Die wichtigsten Vorteile:

- **Nie wieder wichtige Trades verpassen** – Erhalten Sie sofort eine Benachrichtigung, wenn ein Trade eröffnet oder geschlossen wird, inklusive aller Details wie Einstiegspreis, Stop Loss und Take Profit.

- **Tägliche, wöchentliche und monatliche Übersicht** – Flexible Report-Zyklen: Tagesreport am Abend, Wochenreport freitags und Monatsreport am letzten Tag des Monats. Alle Zeiten konfigurierbar.

- **Equity-Überwachung** – Sehen Sie auf einen Blick, wie hoch Ihr maximaler Gewinn und größter Drawdown während des Tages waren. So erkennen Sie Optimierungspotenzial in Ihrer Trading-Strategie.

- **Magic-Number-Gruppierung** – Der EA zeigt die Equity gruppiert nach Magic Number direkt auf dem Chart an. So sehen Sie auf einen Blick, wie jede einzelne Strategie performt – inklusive offener und heute geschlossener Positionen.

- **Ressourcenschonend** – Der EA arbeitet extrem effizient und belastet weder Ihr System noch Ihre Trading-Performance. Keine Tick-by-Tick-Auswertung, keine unnötige CPU-Last. Geschlossene Trades werden gecacht.

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
| InpCheckIntervalMinutes | int | 5 | Prüf-Intervall in Minuten (1–n) |
| InpEmailSubjectPrefix | string | [MT5]  | E-Mail Betreff-Prefix |
| InpLogToExperts | bool | true | Log-Ausgabe im Experts-Tab |
| InpTradeReportEnabled | bool | true | Trade-Report bei Eröffnung/Schluss |
| InpDailyReportEnabled | bool | true | Tagesreport aktivieren |
| InpDailyReportHour | int | 22 | Tagesreport Stunde (0-23) |
| InpDailyReportMinute | int | 00 | Tagesreport Minute (0-59) |
| InpOpenEquityReport | bool | false | Open Equity Reporting aktivieren |
| InpWeeklyReportEnabled | bool | true | Wochenreport aktivieren (Freitag) |
| InpWeeklyReportHour | int | 20 | Wochenreport Stunde (0-23) |
| InpMonthlyReportEnabled | bool | true | Monatsreport aktivieren (Monatsende) |
| InpMonthlyReportHour | int | 20 | Monatsreport Stunde (0-23) |

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
- Ist der Report deaktiviert, werden neue Deals trotzdem intern als bekannt markiert (kein Rückstau)

**`InpDailyReportEnabled`** (bool, Standard: true)
- Tagesreport ein-/ausschalten

**`InpDailyReportHour`** / **`InpDailyReportMinute`** (int, Standard: 22 / 00)
- Stunde und Minute für den Tagesreport (Broker-Zeit)
- Der Report wird gesendet wenn die aktuelle Zeit innerhalb des Prüf-Intervalls ab dieser Zielzeit liegt

**`InpOpenEquityReport`** (bool, Standard: true)
- Aktiviert/deaktiviert das Open Equity Reporting
- Betrifft: Per-Trade Max Equity, Account-weites Tages-Min/Max, Magic-Number-Gruppierung auf dem Chart
- Wenn deaktiviert werden keine Equity-Werte auf dem Chart und in den Reports angezeigt

**`InpWeeklyReportEnabled`** (bool, Standard: true)
- Wochenreport ein-/ausschalten
- Wird freitags zur konfigurierten Stunde gesendet

**`InpWeeklyReportHour`** (int, Standard: 20)
- Stunde für den Wochenreport (Broker-Zeit, nur freitags)
- **Hinweis:** Standard ist 20:00 statt 22:00, da der Forex-Markt freitags oft um 22:00 schließt und `TimeCurrent()` dann nicht mehr aktualisiert wird

**`InpMonthlyReportEnabled`** (bool, Standard: true)
- Monatsreport ein-/ausschalten
- Wird am letzten Tag des Monats zur konfigurierten Stunde gesendet

**`InpMonthlyReportHour`** (int, Standard: 20)
- Stunde für den Monatsreport (Broker-Zeit, nur letzter Monatstag)
- **Hinweis:** Alle Reports werden freitags automatisch auf spätestens 20:00 begrenzt, da der Forex-Markt um ~22:00 schließt

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

- **Nur wöchentliche Zusammenfassung (Freitag 20:00):**
  - `InpTradeReportEnabled = false`
  - `InpDailyReportEnabled = false`
  - `InpWeeklyReportEnabled = true`
  - `InpWeeklyReportHour = 20`

- **Alle Reports aktiv, Equity-Tracking aus:**
  - `InpOpenEquityReport = false`

---

## Features

### 1. Trade-Report (Eröffnung)

Bei jeder Trade-Eröffnung wird eine E-Mail gesendet mit:
- Symbol und Richtung (BUY/SELL) im Betreff
- Volumen und Einstiegspreis
- Stop Loss und Take Profit (falls gesetzt)
- Liste aller offenen Positionen
- Tagesbilanz (heute geschlossener P/L)

### 2. Trade-Report (Schluss)

Bei jedem Trade-Schluss wird eine E-Mail gesendet mit:
- Profit/Verlust inkl. Commission und Swap
- **Max Open Equity** – höchster Gewinn während der Trade-Laufzeit (falls Equity-Report aktiviert)
- Trade-Kommentar (falls vorhanden)
- Liste aller offenen Positionen
- Tagesbilanz (heute geschlossener P/L)

### 3. Tagesreport

Täglich zur konfigurierten Uhrzeit:
- Tagesergebnis (Profit, Commission, Swap)
- **Max Account Equity** – höchster Gewinn aller Positionen (falls aktiviert)
- **Min Account Equity** – größter Drawdown aller Positionen (falls aktiviert)
- Liste geschlossener Trades mit Ein-/Ausstiegspreis und Max Equity
- Liste offener Positionen

### 4. Wochenreport

Jeden Freitag zur konfigurierten Stunde:
- Wochenergebnis (Profit, Commission, Swap) mit Kalenderwoche
- Zeitraum (Montag – Freitag)
- Liste aller geschlossenen Trades der Woche mit Datum, Symbol, Richtung, Volumen, Preis und P/L
- Liste offener Positionen

### 5. Monatsreport

Am letzten Tag des Monats zur konfigurierten Stunde:
- Monatsergebnis (Profit, Commission, Swap) mit Monatsname
- Zeitraum (1. – letzter Monatstag)
- Liste aller geschlossenen Trades des Monats mit Datum, Symbol, Richtung, Volumen, Preis und P/L
- Liste offener Positionen

### 6. Equity-Tracking

Der EA trackt im konfigurierten Intervall (wenn `InpOpenEquityReport = true`):
- **Per-Trade:** Maximale Open Equity für jeden einzelnen Trade
- **Account-weit:** Maximum und Minimum über alle offenen Positionen (täglich reset)

### 7. Chart-Anzeige mit Magic-Number-Gruppierung

Der EA zeigt folgende Informationen auf dem Chart an:
- Version, Intervall, letzte E-Mail, Anzahl gesendeter Mails, nächste Prüfzeit (lokale Uhrzeit)
- **Tages-Equity:** Min/Max Account-Equity des Tages
- **Magic-Number-Equity:** Gruppierte Anzeige pro Magic Number (max. 20 Einträge):
  - `M<MagicNr>  <aktuelle Equity>  Max:<max Equity>` – für Magics mit offenen Trades
  - `M<MagicNr>  <closed P/L>  (closed)` – für Magics mit nur heute geschlossenen Trades
  - Farbe: **Grün** bei positiver Equity, **Rot** bei negativer Equity
- Der Chart wird beim Start bereinigt (Kerzen, Last-Price-Linie, Bid/Ask, Trade-History-Pfeile ausgeblendet)

### 8. Intelligenter E-Mail-Betreff

Der E-Mail-Betreff enthält kontextabhängig:
- Bei nur eröffneten Trades: Symbol(e) und Richtung (z.B. `[MT5] EURUSD BUY EURUSD 1 Trade(s) eröffnet`)
- Bei nur geschlossenen Trades: Symbol(e) und Profit-Summe (z.B. `[MT5] EURUSD 1 Trade(s) geschlossen: Profit +125.50 EUR`)
- Bei gemischten Events: Kombination beider Informationen

### 9. Closed-Trades-Cache

Für die Magic-Number-Gruppierung auf dem Chart werden geschlossene Trades des Tages gecacht:
- Cache wird nur bei Änderungen (neuer Tag oder neue Deals) neu aufgebaut
- Reduziert History-Abfragen erheblich

---

## E-Mail-Beispiele

### Trade-Report (Eröffnung)

**Betreff:** `[MT5] EURUSD BUY EURUSD 1 Trade(s) eröffnet`

```
=== MQL5 Trade Notification ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 10250.00 EUR
Equity: 10285.50 EUR
Zeitpunkt: 2026.02.07 12:45

--- 1 TRADE(S) ERÖFFNET ---
  [EURUSD]   2026.02.07 12:45 | OPEN BUY 0.10 Lots @ 1.08250 | Pos#987654
    | SL: 1.08050 | TP: 1.08650

--- 2 OFFENE POSITION(EN) ---
  [EURUSD] BUY 0.10 Lots @ 1.08250 (aktuell: 1.08265) | P/L: +15.00 | Swap: 0.00 | Max: +15.00 | Offen seit: 2026.02.07 12:45
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26480) | P/L: +10.00 | Swap: -0.50 | Max: +25.00 | SL: 1.26700 | TP: 1.26200 | Offen seit: 2026.02.06 14:30
  Gesamt offener P/L: 24.50 EUR

--- TAGESBILANZ (heute geschlossen): +50.00 EUR ---

=== Ende der Benachrichtigung ===
```

### Trade-Report (Schluss)

**Betreff:** `[MT5] EURUSD 1 Trade(s) geschlossen: Profit +125.50 EUR`

```
=== MQL5 Trade Notification ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 10375.50 EUR
Equity: 10410.00 EUR
Zeitpunkt: 2026.02.07 18:30

--- 1 TRADE(S) GESCHLOSSEN ---
  [EURUSD]   2026.02.07 18:30 | CLOSE SELL 0.10 Lots @ 1.08450 | Pos#987654
    | P/L: +125.50 (Profit: 128.00, Comm: -2.50) | Max Open Equity: +185.30

--- 1 OFFENE POSITION(EN) ---
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26350) | P/L: +75.00 | Swap: -1.20 | Max: +95.00 | SL: 1.26700 | TP: 1.26200 | Offen seit: 2026.02.06 14:30
  Gesamt offener P/L: 73.80 EUR

--- TAGESBILANZ (heute geschlossen): +175.50 EUR ---

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

### Wochenreport

**Betreff:** `[MT5] Wochenreport KW7 +1250.00 EUR`

```
=== MQL5 WOCHENREPORT ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 11500.00 EUR
Equity: 11650.00 EUR
Zeitraum: 2026.02.03 - 2026.02.07

=== WOCHENERGEBNIS ===
Profit: 1300.00 EUR
Commission: -35.00 EUR
Swap: -15.00 EUR
GESAMT: +1250.00 EUR

--- 12 TRADE(S) DIESE WOCHE ---
  [EURUSD] 2026.02.03 10:15 | SELL 0.10 @ 1.08350 | P/L: +100.00
  [GBPUSD] 2026.02.04 14:30 | BUY 0.05 @ 1.26500 | P/L: +85.50
  ...

--- 1 OFFENE POSITION(EN) ---
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26250) | P/L: +125.00 | Swap: -1.80 | Offen seit: 2026.02.06 14:30
  Gesamt offener P/L: 123.20 EUR

=== Ende Wochenreport ===
```

### Monatsreport

**Betreff:** `[MT5] Monatsreport Feb 2026 +3500.00 EUR`

```
=== MQL5 MONATSREPORT ===

Account: 12345678 (Thomas)
Server: ICMarkets-Demo
Balance: 13500.00 EUR
Equity: 13650.00 EUR
Zeitraum: 2026.02.01 - 2026.02.28

=== MONATSERGEBNIS ===
Profit: 3700.00 EUR
Commission: -120.00 EUR
Swap: -80.00 EUR
GESAMT: +3500.00 EUR

--- 48 TRADE(S) DIESEN MONAT ---
  [EURUSD] 2026.02.01 09:30 | BUY 0.10 @ 1.08100 | P/L: +120.00
  [USDJPY] 2026.02.01 14:00 | SELL 0.20 @ 149.500 | P/L: +85.00
  ...

--- 2 OFFENE POSITION(EN) ---
  [GBPUSD] SELL 0.05 Lots @ 1.26500 (aktuell: 1.26100) | P/L: +200.00 | Swap: -3.50 | Offen seit: 2026.02.25 10:00
  [EURUSD] BUY 0.10 Lots @ 1.08500 (aktuell: 1.08600) | P/L: +100.00 | Swap: -1.20 | Offen seit: 2026.02.27 08:15
  Gesamt offener P/L: 295.30 EUR

=== Ende Monatsreport ===
```

---

## Technische Details

### Architektur

```
OnInit()
  ├── Parameter-Validierung (Intervall >= 1)
  ├── E-Mail-Konfiguration prüfen
  ├── HistorySelect(0, TimeCurrent())     // Komplette History laden
  ├── InitializeKnownDeals()              // Bekannte Deals beim Start erfassen
  ├── EventSetTimer(60)                   // Timer jede Minute
  ├── UpdateChartInfo()                   // Chart-Anzeige initialisieren
  └── Chart bereinigen                    // Kerzen, Linien, Pfeile ausblenden

OnTimer()  [jede Minute]
  ├── CheckAndSendDailyReport()           // Tagesreport prüfen (wenn aktiviert)
  ├── CheckAndSendWeeklyReport()          // Wochenreport prüfen (wenn aktiviert)
  ├── CheckAndSendMonthlyReport()         // Monatsreport prüfen (wenn aktiviert)
  ├── [Intervall-Prüfung]                 // Nur weiter wenn Intervall erreicht
  ├── UpdateEquityTracking()              // Equity-Werte tracken
  ├── UpdateChartInfo()                   // Chart aktualisieren (inkl. Magic-Gruppierung)
  ├── HistorySelect()                     // History aktualisieren
  └── CheckForNewDeals()                  // Neue Trades suchen & melden
      └── (oder UpdateKnownDealsWithoutNotification() wenn Report deaktiviert)

OnDeinit()
  ├── EventKillTimer()
  └── Chart-Labels entfernen
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

// Closed-Trades-Cache (Magic-Number-Gruppierung)
long   g_closedMagicNumbers[];  // Magic Numbers mit geschlossenen Trades heute
double g_closedMagicProfit[];   // Profit pro Magic (geschlossen)
int    g_closedCacheDay;        // Tag für den der Cache gilt
int    g_closedCacheDealsCount; // Anzahl Deals beim letzten Cache-Update
```

### Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| `OnInit()` | Initialisierung: Parameter-Validierung, History-Laden, Timer-Start, Chart-Bereinigung |
| `OnTimer()` | Hauptschleife: Reports prüfen, Equity tracken, neue Deals suchen |
| `OnDeinit()` | Aufräumen: Timer stoppen, Chart-Labels entfernen |
| `InitializeKnownDeals()` | Initiale Deal-Liste aufbauen (keine Altdaten mailen) |
| `InitReportLog()` | Report-Logdatei initialisieren, beim ersten Start vergangene Zeiten markieren |
| `IsReportAlreadySent()` | Prüft in der Logdatei ob ein Report (Typ+Datum) bereits gesendet wurde |
| `LogReportSent()` | Protokolliert einen gesendeten Report in der Logdatei |
| `CheckForNewDeals()` | Prüft auf neue Deals und sendet Trade-Report E-Mail |
| `UpdateKnownDealsWithoutNotification()` | Deals als bekannt markieren ohne E-Mail (wenn Report deaktiviert) |
| `FormatDealInfo()` | Formatiert Deal-Informationen (Symbol, Richtung, Preis, SL/TP, P/L, Max Equity) |
| `SendNotificationEmail()` | Erstellt und sendet Trade-Report mit intelligentem Betreff |
| `GetOpenPositionsInfo()` | Formatiert alle offenen Positionen als Text |
| `CheckAndSendDailyReport()` | Prüft ob Tagesreport gesendet werden soll (Uhrzeit + einmal pro Tag) |
| `SendDailyReport()` | Erstellt und sendet Tagesreport mit Ein-/Ausstiegspreis und Max Equity |
| `CheckAndSendWeeklyReport()` | Prüft ob Wochenreport gesendet werden soll (nur freitags) |
| `SendWeeklyReport()` | Erstellt und sendet Wochenreport (Montag–Freitag) |
| `CheckAndSendMonthlyReport()` | Prüft ob Monatsreport gesendet werden soll (letzter Monatstag) |
| `SendMonthlyReport()` | Erstellt und sendet Monatsreport (1.–letzter Tag) mit Monatsname |
| `IsLastDayOfMonth()` | Prüft ob heute der letzte Tag des Monats ist |
| `UpdateEquityTracking()` | Aktualisiert per-Trade und Account-weite Max/Min Equity-Werte |
| `UpdateTradeMaxEquity()` | Max-Equity für einzelnen Trade aktualisieren |
| `GetMaxEquityForPosition()` | Max-Equity für eine Position abrufen |
| `RemoveTradeFromEquityTracking()` | Trade aus Equity-Tracking entfernen (bei Schluss) |
| `UpdateChartInfo()` | Chart-Labels aktualisieren inkl. Magic-Number-Gruppierung |
| `CreateChartLabel()` | Chart-Label erstellen oder aktualisieren (Consolas, 11pt) |
| `GetTodayClosedPL()` | Heutigen geschlossenen P/L berechnen (Tagesbilanz) |
| `AddUniqueSymbol()` | Symbol eindeutig zur Betreff-Liste hinzufügen |
| `IsDealKnown()` | Prüfen ob ein Deal bereits bekannt ist |
| `AddKnownDeal()` | Deal zur bekannten Liste hinzufügen |

---

## Chart-Anzeige

Der EA zeigt folgende Informationen auf dem Chart an (Schriftart: Consolas, 11pt):

```
MQL5Notify v1.24
Intervall: 5 Min
Letzte Mail: 2026.02.07 18:30
Gesendete Mails: 12
Nächste Prüfung: 18:35                    ← lokale Uhrzeit
Tages-Equity: Min -180.00 / Max +425.50   ← nur wenn OpenEquityReport=true
  M12345678       +245.50  Max:  +320.00   ← Magic mit offenen Trades (grün)
  M87654321        -45.30  Max:   +12.50   ← Magic mit offenen Trades (rot)
  M11111111       +180.00  (closed)        ← Magic nur geschlossene Trades heute
```

**Hinweis:** Beim Start des EA werden die Chart-Kerzen, Bid/Ask-Linien, Last-Price-Linie und Trade-History-Pfeile ausgeblendet, damit die Anzeige gut lesbar ist.

---

## Voraussetzungen

- MetaTrader 5
- E-Mail im Terminal konfiguriert (`Extras → Optionen → E-Mail`)
- EA muss auf einem Chart aktiv sein
- Automatischer Handel muss aktiviert sein

---

## Changelog

### Version 1.24
- **Report-Tracking komplett überarbeitet:** GlobalVariables durch Logdatei (`MQL5Notify_ReportLog.txt`) ersetzt
- Logdatei protokolliert jeden gesendeten Report mit Datum, Typ und Status
- Vor jedem Report wird die Logdatei geprüft, ob bereits ein Report gesendet wurde
- Beim allerersten Start werden bereits vergangene Report-Zeiten als gesendet markiert (kein Rückstau)
- **Wochenreport und Monatsreport Default-Stunde von 22:00 auf 20:00 geändert** (Forex-Markt schließt freitags um ~22:00, `TimeCurrent()` stoppt)
- **Freitags-Sicherheit:** Alle Reports werden freitags automatisch auf spätestens 20:00 begrenzt, auch wenn eine spätere Stunde konfiguriert ist

### Version 1.23
- **Bugfix:** Neustart-Schutz verbessert (Warmup-Phase, GlobalVariable-Persistenz)
- Verhindert fehlerhafte Reports nach EA-Neustart

### Version 1.22
- **Bugfix:** Richtungsanzeige bei geschlossenen Trades korrigiert (zeigte "CLOSE BUY" statt "CLOSE SELL" und umgekehrt)
- Fix in allen Reports: Trade-Notification, Tagesreport, Wochenreport, Monatsreport
- `InpOpenEquityReport` Default auf `false` geändert

### Version 1.21
- Wochenreport (Freitag, konfigurierbare Stunde)
- Monatsreport (letzter Monatstag, konfigurierbare Stunde)
- Open Equity Reporting als konfigurierbarer Toggle (`InpOpenEquityReport`)
- Magic-Number-gruppierte Equity-Anzeige auf dem Chart (offen + closed)
- Closed-Trades-Cache für optimierte Chart-Aktualisierung
- Intelligenter E-Mail-Betreff mit Symbolen und Richtung
- Tagesbilanz in Trade-Report-E-Mails
- Chart-Bereinigung beim Start (Kerzen, Linien, Pfeile ausgeblendet)
- Nächste Prüfzeit in lokaler Uhrzeit auf dem Chart
- `UpdateKnownDealsWithoutNotification()` verhindert Rückstau bei deaktiviertem Trade-Report
- Konfigurierbare Report-Stunden für Wochen-/Monatsreport

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

### Equity-Werte ungenau
1. Equity wird nur im konfigurierten Intervall geprüft (nicht tick-basiert)
2. Setze `InpCheckIntervalMinutes = 1` für höchste Genauigkeit
3. Prüfe ob `InpOpenEquityReport = true`

### Chart-Anzeige fehlt
1. Equity-Anzeige nur wenn `InpOpenEquityReport = true`
2. Magic-Number-Labels werden nur angezeigt wenn offene oder heute geschlossene Trades existieren
3. Maximal 20 Magic-Number-Einträge werden angezeigt
