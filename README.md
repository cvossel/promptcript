# Promptcript

Ein Teleprompter für macOS, der deiner Stimme folgt. Er zeigt die Zeile, die du gerade liest,
und darüber bzw. darunter einstellbar viele weitere Zeilen (Standard: je eine). Die Spracherkennung läuft komplett auf dem Mac.

## Bauen und starten

```bash
./build.sh --open
```

Die App liegt danach in `build/Promptcript.app` und kann in den Programme-Ordner gezogen werden.
Beim ersten Start fragt macOS nach dem Mikrofon. Beim ersten Play wird außerdem einmalig das
Sprachmodell geladen.

Voraussetzungen: macOS 26 und die Xcode Command Line Tools (`xcode-select --install`).

## Bedienung

1. Text in den Editor kopieren (Markdown geht: `**fett**`, `*kursiv*`, `# Überschrift`, Listen).
2. Sprache wählen: unten im Fenster oder im Menü **Sprache**.
3. **Play** (⌘↩) öffnet den Prompter oben mittig unter der Kamera.
4. Lesen. Der Prompter scrollt mit.

Überschriften werden angezeigt, aber nicht als gesprochener Text erwartet. Gut für Kapitelmarken.

Im Prompter-Fenster:

| Taste           | Aktion                       |
| --------------- | ---------------------------- |
| Leertaste       | Pause / Weiter               |
| ↓ / →           | eine Zeile vor               |
| ↑ / ←           | eine Zeile zurück            |
| + / −           | Schrift größer / kleiner     |
| 0               | zurück zum Anfang            |
| Esc             | Prompter beenden             |

In den **Einstellungen** (⌘, oder Zahnrad im Editor) legst du fest, wie viele Zeilen vor und nach
der aktuellen Zeile angezeigt werden (jeweils 0–8). Mehr Zeilen danach helfen beim Vorauslesen,
wenn die Erkennung mal hinterherhängt. Das geht auch live über das Rechtsklick-Menü im Prompter.

Das Fenster lässt sich überall anfassen und verschieben, an den Rändern in der Breite ändern
und merkt sich die Position. Rechtsklick öffnet ein Menü. Der Punkt oben rechts zeigt den Status
(grün = hört zu, gelb = lädt/pausiert, rot = Fehler).

Der Prompter ist bei Bildschirmaufnahmen absichtlich unsichtbar, damit er nicht im Video landet.

## Wie das Mitlesen funktioniert

- **Spracherkennung:** Apples `SpeechAnalyzer` (macOS 26). Im Menü **Prompter → Spracherkennung**
  kann man auf die klassische Apple-Erkennung umschalten. Weitere Engines (z. B. WhisperKit)
  lassen sich über das Protokoll `SpeechEngine` ergänzen.
- **Fachbegriffe:** Wörter aus dem Skript, die nach Fachbegriffen aussehen (CamelCase, Abkürzungen,
  englisch wirkende Wörter), werden der Erkennung als Vokabelhinweise mitgegeben.
- **Abgleich** (`ScriptMatcher`): Die letzten acht erkannten Wörter werden unscharf gegen den Text
  rund um die aktuelle Stelle abgeglichen (Smith-Waterman-Alignment). Das toleriert falsch erkannte
  Wörter, Füllwörter, ausgelassene Wörter, Abschweifungen und getrennt bzw. zusammengeschrieben
  erkannte Begriffe. Nach vorne springt der Prompter leicht, zurück nur bei deutlicher Übereinstimmung,
  z. B. wenn du einen Satz neu beginnst.

## Entwicklung

```bash
./test.sh                                                  # Tests
swift run PromptcriptBench skript.md aufnahme.aiff de-DE   # Audiodatei durch Erkennung + Abgleich schicken
```

Testaufnahmen lassen sich z. B. mit `say -v Anna -o test.aiff "…"` erzeugen.
Mit `PromptcriptBench` kann man die Fehlertoleranz ohne Mikrofon prüfen und die Werte in
`ScriptMatcher.Configuration` anpassen.
