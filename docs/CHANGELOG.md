# Changelog

## Grafik-Upgrade (2026-10-20)

- Kämpfer als R15-förmige Figuren aus eigenen Parts mit eigenem Look: VOLT NINJA (Stirnband, Maske, Klingen), MAGMOR (Steinschultern,
  Magma-Risse, Glutfäuste), JUBEI (Katana, Scheide, Schärpe), LEPORA (Hasenohren, Bogen, Köcher).
- Prozedurale Animationen für Stand, Laufen, Sprung, Fall, Schild, Kante, Treffer, Benommenheit und alle Angriffsarten.
- Effekte: Schlag-Trails, Treffer-Funken, Schadenszahlen, Schockwellen, KO-Explosion mit Bildschirmblitz.
- NEON-GASSE: nasser Spiegelboden, Neon-Kanten, beleuchtete Plattformen, Laternen, Skyline, Schilder, Regen, Nebel.
- Fix: Arena war im Spiel unsichtbar (Streaming).

## Phase 1: Kampfkern und Vertical Slice (2026-10-17)

- `Combat/Simulation`: Kampfschleife aus `combat.gd` portiert (Laufen, Sprünge, Plattformen, Kanten, Schild, Parade,
  Ausweichen, Greifen und Würfe, Smash-Aufladung, Combos, Super, Rüstung, Konter, Clash, KO und Respawn,
  Finisher-Phase, Zeitablauf und Sudden Death).
- `Combat/Bot`: 9 Stufen mit Reaktionszeit `22 - 2 * Stufe` + 0..3 Frames, Erholung, Kantenwache, Finisher-Eingabe.
- `Combat/MatchRunner`, `Net/Guard`: fester 60-Hz-Takt, gelatchte Eingaben, Rate-Limits und Typprüfung für Remotes.
- Roblox: MatchService (Lobby → Match → Ergebnis), Arena NEON-GASSE, Eingabe für Tastatur, Gamepad und Touch,
  Kamera mit Zoom und Wackeln, HUD mit Prozent, Leben, Super, Timer und Bannern.
- 76 Tests, darunter ein komplettes 4-Bot-Match und ein Determinismus-Test.

## Phase 0: Grundgerüst (2026-10-17)

- Rojo-Projekt, Rokit-Toolchain, Wally-Manifest, StyLua, Selene, CI (Format, Lint, Tests, Build, Build-Prüfung).
- Godot-Importer `tools/import_godot.py`: 58 Kämpfer (Werte, 15 Moves, Physik, Finisher), 58 Signatur-Parameter,
  19 Bosse mit 42 Angriffsmustern, 13 Mutatoren, 16 Waffen, 11 Tages- und 8 Wochenaufgaben, 36 Erfolge, Skins, Titel.
- Daten-Module: Fighters, Roster, Signatures, Weapons, Arenas, Bosses, Mutators, Progression, Ranks, Products, Constants.
- Reine Logik: `Combat/Knockback` (Treffer und Würfe wie Godot), `Util/Seed` (gleicher Prompt-Hash wie Godot),
  `Net/Remotes` (Rate-Limits und Argument-Schemas).
- Test-Runner für Lune mit Rojo-kompatiblem Modul-Loader; 46 Tests.
- Doku: Architektur, Entscheidungen, Economy, Growth, Live-Ops, Lizenzen und Marken-Check.
