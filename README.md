# 📊 DrawdownFromBalanceHighEA
## Professionelles Risikomanagement für MetaTrader 5

---

### 🏆 Expert Advisor für maximale Kontrolle über Ihr Trading-Risiko

**Version 1.00** | **Juli 2025** | **MetaTrader 5**

---

## 📋 Inhaltsverzeichnis

1. [🎯 Einleitung](#-einleitung)
2. [⚡ Hauptfunktionen](#-hauptfunktionen)
3. [🎛️ Konfiguration & Installation](#️-konfiguration--installation)
4. [📺 Anzeigenerklärung](#-anzeigenerklärung)
5. [🔄 Täglicher Reset](#-täglicher-reset)
6. [🚨 Alarm-System](#-alarm-system)
7. [📁 Logfile-System](#-logfile-system)
8. [⚙️ Technische Details](#️-technische-details)
9. [❓ FAQ](#-faq)
10. [📞 Support](#-support)

---

## 🎯 Einleitung

Der **DrawdownFromBalanceHighEA** ist ein hochentwickelter Expert Advisor für MetaTrader 5, der speziell für professionelles Risikomanagement entwickelt wurde. Er bietet Tradern eine umfassende Echtzeit-Überwachung ihrer Kontoperformance und warnt automatisch vor kritischen Drawdown-Situationen.

### 🎯 Zielgruppe
- **Professionelle Trader** mit hohem Risikobewusstsein
- **Portfolio-Manager** die multiple Strategien überwachen
- **Prop-Trader** mit strikten Drawdown-Limits
- **Alle Trader** die ihre Performance systematisch verfolgen möchten

---

## ⚡ Hauptfunktionen

```
┌─────────────────────────────────────────────────────────┐
│                   🎯 CORE FEATURES                      │
├─────────────────────────────────────────────────────────┤
│ ✅ Drawdown-Überwachung vom Balance-High                │
│ ✅ Real-time Open Equity Tracking                       │
│ ✅ Tägliche Min/Max Verfolgung                          │
│ ✅ Automatische Alarme & Warnungen                      │
│ ✅ Historische CSV-Dokumentation                        │
│ ✅ Mehrwährungs-Unterstützung                           │
└─────────────────────────────────────────────────────────┘
```

### 🔍 Was überwacht der EA?

| **Kennzahl** | **Beschreibung** | **Nutzen** |
|-------------|------------------|------------|
| **📉 Drawdown** | Verlust vom höchsten Kontostand | Risikokontrolle |
| **💰 Open Equity** | Unrealisierte P&L in Echtzeit | Performance-Tracking |
| **📊 Min/Max Daily** | Tägliche Extremwerte | Volatilitäts-Analyse |
| **🚨 Alarme** | Automatische Warnungen | Frühwarnsystem |
| **📁 Historie** | Langzeit-Dokumentation | Trend-Analyse |

---

## 🎛️ Konfiguration & Installation

### 📦 Installation

```
Schritt 1: 📁 Datei kopieren
┌─────────────────────────────────────────┐
│ DrawdownFromBalanceHighEA.mq5          │
│           ↓                             │
│ MQL5/Experts/ Ordner                    │
└─────────────────────────────────────────┘

Schritt 2: 🔨 Kompilieren
┌─────────────────────────────────────────┐
│ MetaEditor → Kompilieren (F7)          │
└─────────────────────────────────────────┘

Schritt 3: 📈 Auf Chart ziehen
┌─────────────────────────────────────────┐
│ Expert Advisor auf beliebigen Chart     │
└─────────────────────────────────────────┘

Schritt 4: ⚡ AutoTrading aktivieren
┌─────────────────────────────────────────┐
│ Für Timer-Funktionen erforderlich      │
└─────────────────────────────────────────┘
```

### ⚙️ Konfigurationsparameter

#### 🎨 **Anzeigeeinstellungen**

| Parameter | Standard | Beschreibung | Optionen |
|-----------|----------|--------------|----------|
| **TextColor** | 🟡 Gelb | Normale Textfarbe | Alle MT5-Farben |
| **FontSize** | 14 | Schriftgröße | 8-24 empfohlen |
| **FontName** | Arial Bold | Schriftart | System-Fonts |
| **Corner** | 0 | Anzeigeposition | 0-3 (siehe unten) |
| **DistanceX** | 20 | Horizontaler Abstand | Pixel |
| **DistanceY** | 20 | Vertikaler Abstand | Pixel |

#### 📍 **Position-Optionen (Corner)**

```
┌─────────────────┬─────────────────┐
│ 0: Links Oben   │ 1: Rechts Oben  │
│ ■               │               ■ │
│                 │                 │
│                 │                 │
│                 │                 │
│ ■               │               ■ │
│ 2: Links Unten  │ 3: Rechts Unten │
└─────────────────┴─────────────────┘
```

#### 🚨 **Alarm-Einstellungen**

| Parameter | Standard | Beschreibung |
|-----------|----------|--------------|
| **AlarmDrawdownProzent** | 5.0% | Warngrenze für Drawdown |
| **PlaySound** | ✅ Ein | Sound bei Alarm |
| **AlarmTextColor** | 🔴 Rot | Farbe bei Alarm |

---

## 📺 Anzeigenerklärung

Der EA zeigt **5 Informationszeilen** in Ihrem Chart an:

### 📊 **Live-Display Layout**

```
┌────────────────────────────────────────────────────────┐
│ 📉 Drawdown: 2.35% vom Balance-High (1250.75)         │
│ 🚨 Alarmschwelle: 5.00% (Equity 1187.71)              │
│ 💰 Open Equity: -1.25% (-15.67 EUR)                   │
│ 📊 Heute Min: -2.10% | Max: 1.85%                     │
│ 💎 Min/Max EUR: -26.25 | 23.13                        │
└────────────────────────────────────────────────────────┘
```

### 📖 **Detaillierte Erklärung**

#### 1️⃣ **📉 Drawdown-Anzeige**
```
Drawdown: 2.35% vom Balance-High (1250.75)
```
- **📉 Drawdown**: Aktueller Verlust vom höchsten Kontostand
- **🏆 Balance-High**: Höchster jemals erreichter Kontostand
- **🎨 Farbe**: 🟡 Normal / 🔴 Bei Alarm

#### 2️⃣ **🚨 Alarmschwelle**
```
Alarmschwelle: 5.00% (Equity 1187.71)
```
- **⚠️ Schwelle**: Eingestellter Alarm-Prozentsatz
- **💰 Equity-Wert**: Absoluter Auslöse-Wert

#### 3️⃣ **💰 Open Equity (Unrealisierte P&L)**
```
Open Equity: -1.25% (-15.67 EUR)
```
- **📈 Prozent**: Unrealisierte Gewinne/Verluste in %
- **💱 Währung**: Absoluter Betrag in Kontowährung
- **🎨 Farbe**: 🟢 Gewinn / 🔴 Verlust

#### 4️⃣ **📊 Tägliche Min/Max Prozent**
```
Heute Min: -2.10% | Max: 1.85%
```
- **⬇️ Min**: Niedrigster Wert seit 10:00 Uhr
- **⬆️ Max**: Höchster Wert seit 10:00 Uhr

#### 5️⃣ **💎 Tägliche Min/Max Währung**
```
Min/Max EUR: -26.25 | 23.13
```
- **💰 Extremwerte**: In Kontowährung
- **🌍 Multi-Währung**: EUR, USD, GBP, etc.

---

## 🔄 Täglicher Reset

### ⏰ **Reset-Zeit: 10:00 Uhr lokale Zeit**

```
🌅 09:59:59 → Alte Werte aktiv
⏰ 10:00:00 → ✨ RESET ✨
🌞 10:00:01 → Neue Zählung beginnt
```

### 🤔 **Warum 10:00 Uhr?**

| **Grund** | **Vorteil** |
|-----------|-------------|
| 🌍 **Global Markets** | Berücksichtigt verschiedene Zeitzonen |
| 📈 **Trading Sessions** | Vermeidet Reset während aktiver Sessions |
| ⏱️ **Vorbereitung** | Zeit für Morgen-Analyse |
| 🔄 **Konsistenz** | Einheitlicher täglicher Rhythmus |

### 🔄 **Was wird zurückgesetzt?**

```
✅ WIRD ZURÜCKGESETZT:
├── 📊 Tägliche Min/Max Open Equity (%)
├── 💰 Tägliche Min/Max Open Equity (Währung)
└── 📁 Logfile-Eintrag erstellt

❌ BLEIBT ERHALTEN:
├── 🏆 Balance-High Wert
├── 🚨 Alarm-Status
└── 📜 Historische Logdaten
```

---

## 🚨 Alarm-System

### 🎯 **Alarm-Trigger**

```
Beispiel: Balance-High = 1000€, Alarm = 5%
┌────────────────────────────────────────┐
│ Equity sinkt unter 950€ (5% Drawdown)  │
│              ↓                         │
│         🚨 ALARM! 🚨                   │
└────────────────────────────────────────┘
```

### 📢 **Alarm-Funktionen**

| **Funktion** | **Beschreibung** | **Konfigurierbar** |
|--------------|------------------|-------------------|
| 🔊 **Sound** | Alarm-Ton abspielen | ✅ Ein/Aus |
| 📱 **Popup** | Detaillierte Info-Box | ❌ Immer aktiv |
| 🎨 **Visuell** | Text wird rot | ❌ Automatisch |
| 📝 **Log** | MT5-Journal Eintrag | ❌ Automatisch |

### 🔄 **Alarm-Reset**

```
🚨 Alarm aktiv → 📈 Neues Balance-High → ✅ Alarm reset
```

---

## 📁 Logfile-System

### 📍 **Speicherort**

```
[MT5 Installation]
    └── MQL5/
        └── Files/
            └── 📁 equitydrawdown.log
```

**🔍 Pfad finden**: MetaEditor → File → Open Data Folder → MQL5 → Files

### 📄 **Dateiformat**

```
📊 Format: CSV (Semikolon-getrennt)
🔤 Encoding: ANSI (Universal lesbar)
📈 Excel: Direkt importierbar
🔧 Tools: Google Sheets, LibreOffice, etc.
```

### 🗂️ **Spalten-Struktur**

| **Spalte** | **Beispiel** | **Beschreibung** |
|------------|-------------|------------------|
| **📅 Datum** | 2025-07-14 | YYYY-MM-DD Format |
| **📉 Min_Prozent** | -1.25 | Niedrigster % Wert |
| **📈 Max_Prozent** | 2.50 | Höchster % Wert |
| **💰 Min_Währung** | -67.89 | Niedrigster Währungswert |
| **💎 Max_Währung** | 135.78 | Höchster Währungswert |
| **🌍 Währung** | EUR | Kontowährung |

### 📋 **Beispiel-Logfile**

```csv
Datum;Min_Prozent;Max_Prozent;Min_Währung;Max_Währung;Währung
2025-07-14;-1.25;2.50;-67.89;135.78;EUR
2025-07-15;-0.89;1.95;-48.50;106.25;EUR
2025-07-16;-2.10;3.25;-114.75;177.90;EUR
2025-07-17;-0.45;1.67;-22.30;83.45;EUR
```

### ⏰ **Schreibzeiten**

```
🕐 10:00 Uhr → Automatischer Tageseintrag
🛑 EA Stop → Sicherung aktueller Daten
✅ Einmalig → Keine Doppeleinträge
```

### 📊 **Datennutzung**

| **Anwendung** | **Nutzen** |
|---------------|------------|
| 📈 **Excel Import** | Direkte Analyse & Diagramme |
| 📊 **Trend-Analyse** | Langfristige Performance |
| 🎯 **Risk Assessment** | Maximale tägliche Risiken |
| 📉 **Benchmark** | Vergleich verschiedener Perioden |

---

## ⚙️ Technische Details

### 💻 **System-Anforderungen**

```
🔧 MetaTrader 5
├── Build 3815+ (empfohlen)
├── Beliebiges Symbol/Timeframe
└── AutoTrading aktiviert

⚡ Performance
├── Update: Alle 1 Sekunde
├── RAM: Minimal (nur Labels)
├── CPU: Sehr gering
└── Netzwerk: Nicht erforderlich
```

### 🛡️ **Fehlerbehandlung**

| **Problem** | **Lösung** | **Status** |
|-------------|------------|------------|
| 🔌 **Verbindung** | Auto-Erkennung | ✅ Robust |
| 📁 **Datei-Fehler** | Fehler-Protokoll | ✅ Sicher |
| 💾 **Kontodaten** | Graceful Degradation | ✅ Stabil |

### 🔄 **Update-Zyklus**

```
Timer: 1 Sekunde
    ↓
🔍 Kontodaten prüfen
    ↓
🧮 Berechnungen
    ↓
📺 Display Update
    ↓
📁 Logfile (bei Bedarf)
    ↓
⏱️ Nächster Zyklus
```

---

## ❓ FAQ

### 📋 **Häufige Fragen**

#### 🔄 **Funktioniert der EA am Wochenende?**
```
✅ EA läuft weiter
⚠️ Zeigt evtl. "Keine Kontodaten verfügbar"
🔄 Löst sich Montag automatisch
```

#### 🔀 **Mehrere EAs gleichzeitig?**
```
✅ Möglich mit anderen EAs
❌ Nur ein DrawdownFromBalanceHighEA pro Installation
⚠️ Konflikte vermeiden
```

#### 🔄 **MT5-Neustart?**
```
🏆 Balance-High: Bleibt erhalten
📊 Min/Max: Werden zurückgesetzt
📁 Logfile: Bleibt komplett erhalten
```

#### 🔒 **Datensicherheit?**
```
💾 Lokale Speicherung
🚫 Keine externe Übertragung
✅ Vollständige Kontrolle
```

#### 👁️ **Anzeige ausblenden?**
```
🎨 Farbe auf "None" setzen
🗑️ EA vom Chart entfernen
📁 Logfile läuft weiter
```

### 🛠️ **Troubleshooting**

| **Problem** | **Lösung** |
|-------------|------------|
| 🚫 **Keine Anzeige** | AutoTrading aktivieren |
| 📁 **Kein Logfile** | Dateiberechtigungen prüfen |
| ⚠️ **Fehler am WE** | Normal - Markt geschlossen |
| 🔄 **Werte falsch** | EA neu starten |

---

## 📞 Support

### 🔧 **Bei Problemen**

```
1. 📋 MT5-Log auf Fehlermeldungen prüfen
2. ⚡ AutoTrading Aktivierung kontrollieren  
3. 📁 Dateiberechtigungen im MQL5/Files prüfen
4. 🔄 EA neu starten
5. 📖 Handbuch erneut lesen
```

### 📋 **Version-Info**

```
┌─────────────────────────────────────────┐
│ 🎯 DrawdownFromBalanceHighEA            │
├─────────────────────────────────────────┤
│ Version: 1.00                           │
│ Platform: MetaTrader 5                  │
│ Update: Juli 2025                       │
│ Kompatibilität: Build 3815+             │
└─────────────────────────────────────────┘
```

---

## 🏆 Fazit

Der **DrawdownFromBalanceHighEA** ist Ihr zuverlässiger Partner für professionelles Risikomanagement. Mit seiner umfassenden Überwachung, automatischen Alarmen und historischen Dokumentation haben Sie stets die volle Kontrolle über Ihr Trading-Risiko.

```
🎯 Maximale Kontrolle + 📊 Datenbasierte Entscheidungen = 🏆 Trading-Erfolg
```

**Viel Erfolg mit Ihrem Trading!** 📈

---

*© 2025 - DrawdownFromBalanceHighEA - Professional Risk Management Solution*
