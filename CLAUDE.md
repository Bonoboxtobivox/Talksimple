# CLAUDE.md — TalkSimple

<!--
  Diese Datei ist das Wichtigste im ganzen Kit.
  Claude liest sie automatisch zu Beginn JEDER Sitzung und behandelt sie als
  verbindliche Anweisung. Alles, was Claude ueber dein Projekt wissen soll, ohne
  dass du es jedes Mal neu erklaerst, gehoert hierher.

  So benutzt du die Vorlage:
   1. Diese Datei nach `CLAUDE.md` (ohne `.template`) in deinen Projekt-Ordner kopieren.
   2. Jeden <PLATZHALTER> ausfuellen.
   3. Was nicht passt, loeschen. Kurz und ehrlich schlaegt lang und vage.

  Faustregel: Wenn du Claude dieselbe Sache zum zweiten Mal erklaerst,
  schreib sie stattdessen hier rein.
-->

## Was das hier ist

TalkSimple ist eine Unterstuetzte-Kommunikation-App (AAC/UK), die sich an
Metatalk, Metacom und GoTalk Now orientiert — aber bewusst intuitiver und
einfacher gehalten ist. Zielgruppe: Menschen mit schweren motorischen und/oder
geistigen Beeintraechtigungen. Kernanforderungen:

- Bedienbarkeit auch bei stark eingeschraenkter Motorik/Kognition (grosse
  Zielflaechen, wenig Ablenkung, sehr geringe Fehlertoleranz noetig).
- Symbole einfuegbar: sowohl Metacom-Bildsymbole als auch eigene Alltagsfotos.
- Ein neues Auswahlmenue (Board) muss in **unter 30 Sekunden** erstellt werden
  koennen — Alltagstauglichkeit, um z.B. Meltdowns vorzubeugen, hat oberste
  Prioritaet vor Feature-Vielfalt.

## Tech-Stack & Werkzeuge

Zielplattformen: **Android zuerst** (Play Store), spaeter **iOS/iPadOS**
(App Store) — ein gemeinsamer Flutter-Code fuer alle drei.

- Sprache / Framework: Dart + Flutter (stable channel)
- Paketmanager: `flutter pub` (siehe `pubspec.yaml`)
- Starten (Dev): `flutter run`
- Tests: `flutter test`
- Analyse/Lint: `flutter analyze`
- Build Android: `flutter build apk` bzw. `flutter build appbundle`
- Build iOS (spaeter): `flutter build ios`

## So ist der Code aufgebaut

- `lib/` — Dart-Quellcode der App (Einstieg: `lib/main.dart`)
- `test/` — Flutter-Widget-/Unit-Tests
- `android/` — natives Android-Projekt (Gradle), von Flutter verwaltet
- `.claude/` — Claude-Code-Konfiguration (Settings, Worktree-Guard-Hooks)

## Metacom-Symbole

- Liegen NUR im Google Drive des Nutzers, Ordner `metabonsymbole`
  (ID in `lib/services/drive_symbol_source.dart`), ein Unterordner je
  Kategorie (Zeit, Tiere, Lebensmittel_Trinken, ...).
- Dateinamen: klein, Umlaute umschrieben (`getraenk`, `weiss`), Varianten
  mit `_` (`wein_rot`), Schwarz-Weiss-Version mit Suffix `SW`.
- Lizenzpflichtig: Symbole **nie** ins Repo committen oder in die App bundeln.

## Konventionen (bitte einhalten)

<!-- Deine Regeln. Beispiele - anpassen/loeschen: -->

- Schreib Code im Stil der umliegenden Dateien (gleiche Benennung, gleiche Struktur).
- Keine neuen Abhaengigkeiten ohne kurze Rueckfrage.
- <z.B. Alle Texte, die der Nutzer sieht, laufen ueber die Uebersetzungs-Datei — nichts fest im Code.>
- <z.B. Neue Funktionen bekommen einen Test.>

## Arbeitsweise mit Claude (wichtig)

- **Worktree-first:** Fuer groessere Aenderungen arbeitet Claude in einem eigenen
  Git-Branch/Worktree, nicht direkt auf `main`. (Wird durch die Hooks in
  `.claude/hooks/` erzwungen.) Kleine Ein-Zeilen-Korrekturen und reine Fragen
  duerfen direkt auf `main` bleiben.
- **Committen/pushen nur, wenn ich darum bitte.**
- **Erst verstehen, dann aendern:** bei Unklarheit lieber kurz nachfragen als raten.

## Was es NICHT tun soll

<!-- Grenzen. Beispiele: -->

- Keine Dateien loeschen oder umbenennen, die du nicht selbst angelegt hast, ohne Rueckfrage.
- Nichts nach aussen schicken (Deploy, E-Mails, Veroeffentlichungen) ohne ausdrueckliche Freigabe.
