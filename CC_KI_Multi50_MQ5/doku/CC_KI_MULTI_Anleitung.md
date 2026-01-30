# CC_KI_MULTI Expert Advisor - Anleitung

## Übersicht

Der **CC_KI_MULTI** ist ein MetaTrader 5 Expert Advisor, der **50 Währungspaare parallel** handelt. Die Handelsrichtung wird über eine externe CSV-Datei gesteuert.

---

## Installation

1. **EA-Datei kopieren**
   - Kopiere `CC_KI_MULTI.mq5` nach: `MQL5\Experts\`
   
2. **In MetaEditor kompilieren**
   - Öffne MetaEditor → Datei öffnen → `CC_KI_MULTI.mq5`
   - Drücke `F7` zum Kompilieren
   - Stelle sicher: **0 Errors**

3. **CSV-Datei erstellen**
   - Erstelle die Datei `last_known_signals.csv` im Ordner: `MQL5\Files\`

---

## CSV-Datei Format

```csv
Waehrungspaar;Letztes_Signal
EUR/USD;BUY
USD/JPY;SELL
GBP/USD;BUY
EUR/GBP;NEUTRAL
```

### Gültige Signale

| Signal | Bedeutung |
|--------|-----------|
| `BUY` | Nur Long-Trades erlaubt |
| `SELL` | Nur Short-Trades erlaubt |
| `NEUTRAL` | Keine neuen Trades, bestehende halten |
| `PANIC` | Alle Trades sofort schließen |

---

## EA starten

1. **Chart öffnen** (beliebiges Symbol, z.B. EURUSD)
2. **EA auf Chart ziehen** (Navigator → Expert Advisors → CC_KI_MULTI)
3. **AutoTrading aktivieren** (grüner Button oben)

> **Wichtig:** Der EA muss nur **einmal** geladen werden - er handelt automatisch alle 50 Paare!

---

## Chart-Anzeige

### Info-Bereich (oben links)
- **MaxDD** - Maximaler Drawdown in %
- **Positionen** - Anzahl offener Trades + Long/Short Verteilung
- **CSV Status** - Ob CSV-Datei erfolgreich gelesen wurde
- **News Status** - Ob News-Filter aktiv ist

### Symbol-Grid
Zeigt alle 50 Währungspaare mit Farbcodierung:

| Symbol | Farbe | Bedeutung |
|--------|-------|-----------|
| ▲ EURUSD | 🟢 Grün | BUY (Long) |
| ▼ USDJPY | 🔴 Rot | SELL (Short) |
| - EURGBP | ⚪ Grau | NEUTRAL |
| X GBPJPY | 🔴 Rot | PANIC |

---

## Wichtige Parameter

### CSV Integration
| Parameter | Standard | Beschreibung |
|-----------|----------|--------------|
| InpUseCSVSignals | true | CSV-Steuerung aktivieren |
| InpCSVCheckInterval | 15 | Prüfintervall in Minuten |
| InpCSVFilename | last_known_signals.csv | Dateiname |

### Trading
| Parameter | Standard | Beschreibung |
|-----------|----------|--------------|
| InpFirstLot | 0.03 | Start-Lotgröße |
| InpGridLot | 0.03 | Grid-Nachkauf Lot |
| InpMaxPositions | 20 | Max. Positionen pro Symbol |
| InpGridStep_ADR_Pct | 10.0 | Grid-Abstand in % von ADR |
| InpStartTarget_ADR | 10.0 | Take-Profit in % von ADR |

### News Filter
| Parameter | Standard | Beschreibung |
|-----------|----------|--------------|
| InpUseNewsFilter | true | News-Filter aktivieren |
| InpMinutesBeforeNews | 30 | Minuten vor News blockieren |
| InpMinutesAfterNews | 30 | Minuten nach News blockieren |

---

## Magic Numbers

Jedes Währungspaar hat eine eindeutige Magic Number:

| Magic | Symbol | Magic | Symbol |
|-------|--------|-------|--------|
| 1001 | EURUSD | 1026 | CADJPY |
| 1002 | USDJPY | 1027 | CADCHF |
| 1003 | GBPUSD | 1028 | CHFJPY |
| 1004 | AUDUSD | 1029 | USDMXN |
| 1005 | USDCAD | 1030 | USDZAR |
| ... | ... | ... | ... |

---

## Unterstützte Währungspaare

### Majors (1-7)
EURUSD, USDJPY, GBPUSD, AUDUSD, USDCAD, USDCHF, NZDUSD

### Crosses (8-28)
EURGBP, EURJPY, EURCHF, EURCAD, EURAUD, EURNZD, GBPJPY, GBPCHF, GBPCAD, GBPAUD, GBPNZD, AUDJPY, AUDCHF, AUDCAD, AUDNZD, NZDJPY, NZDCHF, NZDCAD, CADJPY, CADCHF, CHFJPY

### Exotics (29-50)
USDMXN, USDZAR, USDTRY, USDSEK, USDNOK, USDDKK, USDPLN, USDHKD, USDSGD, USDTHB, EURSEK, EURNOK, EURPLN, GBPSEK, GBPNOK, AUDSEK, AUDNOK, NZDSEK, NZDNOK, USDCNY, USDINR, USDBRL

---

## Fehlerbehebung

### "Symbole: X / 50 aktiv"
- Nicht alle Symbole bei deinem Broker verfügbar
- Der EA überspringt automatisch fehlende Symbole

### CSV wird nicht gelesen
1. Prüfe Dateipfad: `MQL5\Files\last_known_signals.csv`
2. Prüfe Format: Semikolon (`;`) als Trennzeichen
3. Aktiviere `InpDebugMode = true` für Details im Log

### Keine Trades
1. Prüfe ob `AutoTrading` aktiviert ist
2. Prüfe CSV-Signal (nicht NEUTRAL?)
3. Prüfe News-Filter (blockiert?)

---

## Version

- **Version:** 2.00
- **Copyright:** Algorithm Factory 2025
