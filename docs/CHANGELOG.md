# Changelog

## Phase 0: Grundgerüst (2026-10-17)

- Rojo-Projekt, Rokit-Toolchain, Wally-Manifest, StyLua, Selene, CI (Format, Lint, Tests, Build, Build-Prüfung).
- Godot-Importer `tools/import_godot.py`: 58 Kämpfer (Werte, 15 Moves, Physik, Finisher), 58 Signatur-Parameter,
  19 Bosse mit 42 Angriffsmustern, 13 Mutatoren, 16 Waffen, 11 Tages- und 8 Wochenaufgaben, 36 Erfolge, Skins, Titel.
- Daten-Module: Fighters, Roster, Signatures, Weapons, Arenas, Bosses, Mutators, Progression, Ranks, Products, Constants.
- Reine Logik: `Combat/Knockback` (Treffer und Würfe wie Godot), `Util/Seed` (gleicher Prompt-Hash wie Godot),
  `Net/Remotes` (Rate-Limits und Argument-Schemas).
- Test-Runner für Lune mit Rojo-kompatiblem Modul-Loader; 46 Tests.
- Doku: Architektur, Entscheidungen, Economy, Growth, Live-Ops, Lizenzen und Marken-Check.
