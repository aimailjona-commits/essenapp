# Phase 10 – Kochen

---

## 4 · Kochmodus

**Ziel:** Beim Kochen nur noch aufs Handy schauen, nichts tippen müssen.

**Ablauf**
- Rezeptdetail: großer Knopf „▶︎ Kochen starten“ (über „Zur Liste“/„Gekocht“).
- Vollbild, dunkler Hintergrund (schont Augen, gut lesbar), Bildschirm bleibt an (`isIdleTimerDisabled`).
- Erst **Vorbereitung**: alle Zutaten der gewählten Portionen zum Abhaken („Mise en place“).
- Dann **ein Schritt pro Seite** (horizontal wischen, große Schrift ≥ 28 pt, Schritt-Bild aus 9 oben), unten: Zutaten, die in diesem Schritt vorkommen (aus Schritttext erkannt), Fortschrittsbalken oben.
- Zeitangaben im Schritt („15 Minuten köcheln“) werden erkannt → Timer-Knopf direkt im Schritt (8).
- Letzter Schritt → „Fertig! 🎉“ (Konfetti-Animation) → Bewertung (3) + Vorrat abziehen (60).

**UI:** S18 Kochmodus; Animationen: Seitenwechsel mit Feder, Fortschrittsbalken gleitet, Haken-Haptik.

**Abnahme:** Bildschirm geht während des Kochens nicht aus; alle Schritte erreichbar; erkannte Zeiten haben Timer-Knopf; Abschluss führt zur Bewertung.

---

## 8 · Mehrere Timer + Sprachsteuerung

**Timer**
- Mehrere Timer gleichzeitig, jeder mit Namen aus dem Schritt („Reis 15:00“), schwebende Timer-Leiste unten im Kochmodus (Glas-Kapseln, Fortschrittsring), Pause/+1 min/Stop.
- Ablauf: Ton + Haptik + lokale Benachrichtigung (auch wenn App im Hintergrund/gesperrt).
- Timer überleben App-Wechsel (Endzeit gespeichert).

**Sprachsteuerung** (an/aus-Knopf 🎙 im Kochmodus, Erlaubnis Mikrofon + Spracherkennung)
- Auf dem Gerät (deutsch, `SFSpeechRecognizer` on-device), lauscht nur im Kochmodus.
- Befehle: „weiter“, „zurück“, „wiederholen“ (Schritt wird vorgelesen, `AVSpeechSynthesizer`), „Timer starten“ (Timer des Schritts), „Timer 10 Minuten“, „wie viel {Zutat}?“ (liest Menge vor), „Zutaten“ (liest Zutaten des Schritts).
- Sichtbares Feedback: kleine Glas-Pille „🎙 hört zu …“ mit Pegelanzeige, erkannter Befehl blinkt kurz.

**Abnahme:** 3 Timer parallel laufen korrekt, Benachrichtigung bei gesperrtem Gerät; alle Sprachbefehle funktionieren in ruhiger Küche (Test mit 10 Befehlen, ≥ 9 erkannt).

**Risiken:** Info.plist braucht `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (via `infoPath`, E26).

---

## 7 · Ersatzzutaten

**Ablauf**
- In Rezept/Kochmodus: Zutat lange drücken (oder ⋯) → „Ersatz finden“.
- Sheet: 2–4 Alternativen mit Mengenumrechnung und Hinweis zur Wirkung („Frischkäse statt Sahne: cremiger, weniger flüssig – 150 g + 50 ml Milch“), markiert: **im Vorrat** / **im Angebot** (Preis).
- Antippen → ersetzt die Zutat in *diesem* Rezept (Kopie für den Haushalt), Nährwerte/Kosten neu.
- Quelle: zuerst eingebaute Tabelle häufiger Ersetzungen (≈ 80 Einträge, ohne KI), sonst Haiku (berücksichtigt Allergien/Ernährung).

**Abnahme:** „Sahne“ → Vorschläge in < 2 s (Tabelle), exotische Zutat → KI-Vorschläge; Allergien werden nie vorgeschlagen.

---

## 10 · Rezept als Bildkarte teilen

- Rezeptdetail › Teilen-Knopf → Auswahl „Als Bild“ / „Als Link“ (Link = 56).
- Bildkarte (1080×1350, gerendert mit `ImageRenderer`): großes Tellerfoto, Titel (Mischgewicht v3), Infozeile (Zeit · kcal · Preis/Portion), Zutatenliste (max. 10), kleines App-Logo + „Mit Essenapp geplant“.
- Teilen über System-Sheet (WhatsApp, Instagram-Story, Speichern).

**Abnahme:** Bild sieht wie Design v3 aus, Text lesbar auf Handy, Teilen in Fotos möglich.
