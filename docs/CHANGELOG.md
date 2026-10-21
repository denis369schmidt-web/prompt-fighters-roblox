# Changelog

## Aufgeräumte Oberfläche (2026-10-21)

- Schadens-Karten schmal am unteren Rand; die eigene Karte ist hervorgehoben („DU · Name“), Bots tragen „CPU“.
- Über den Kämpfern nur noch „DU ▼“ für dich und ein farbiger Pfeil für die anderen (Farbe wie die Karte).
- Kamera näher am Kampf, Figuren größer im Bild.
- Lobby-Anleitung links („So geht's“) hakt Kämpferwahl und Arena-Feld ab und zeigt den Countdown.
- Oberfläche skaliert auf kleinen Bildschirmen, Roblox-Spielerliste nur in der Lobby, kein Rucksack.
- Kolosseum-Mauern stehen nicht mehr vor dem Kampf, Tag-Arenen blenden weniger, Plattform-Leuchten dezenter.

## Lobby und 23 Arenen (2026-10-20)

- Begehbare Lobby: Spieler laufen mit ihrem Avatar über einen Neon-Platz, die 16 Startkämpfer stehen als Statuen auf Sockeln, ein großer Bildschirm zeigt Countdown und Bereitschaft.
- Arena-Abstimmung: drei zufällige Arenen pro Runde, abstimmen durch Draufstellen auf ein Feld oder per Knopf rechts oben. Die meisten Stimmen gewinnen, Gleichstand entscheidet der Zufall.
- Countdown: 20 s ab der ersten Kämpferwahl, 8 s sobald alle gewählt haben. Während des Kampfs ist der Avatar eingefroren und die Kamera zeigt die Arena.
- Alle 23 Arenen aus dem Original haben ein eigenes Aussehen (13 Stile): Neon-Straße, Dach, Holo-Stadt, Tempel, Dschungel, Dojo, Kolosseum, Stadion, Berge mit Polarlicht, Lagerhalle, Eiswerk, Gießerei mit Lavasee, Orbitalring, Raumschiff-Hangar, Niemandsland, Ruinenstadt. Eigenes Licht und Wetter (Regen, Schnee, Glut, Staub, Glühwürmchen).
- Kämpferwahl schließt sich nach der Wahl und lässt sich mit einem Knopf wieder öffnen.

## 16 Startkämpfer mit eigenem Look (2026-10-20)

- Kämpferwahl zeigt 16 Startkämpfer im 8×2-Raster: VOLT NINJA, MAGMOR, BOLTAR, KAIRO, GLACIEM, JUBEI, ZIP, LEPORA, CARDINAL, GRIMBOLT, TEMPLAR, SCARLET, CELESTIAL FOX, CYBORG MECH, NEKRA, DUSTY.
- 39 neue Ausrüstungs-Sets als Daten (`Visual/GearData`): Helme, Flügel, Umhänge, Schwerter, Schild, Raketenkapseln, Lasso und mehr. `RigBuilder` baut sie mit Farben aus dem Look.
- Eigenständige Neugestaltung von KAIRO (kahler Mönch mit Gebetskette), GLACIEM (Eis-Assassinin ohne Ninja-Maske), ZIP (orangener Kurier mit Düsen) und JUBEI (Rot statt Grün).
- Arena: Schilder mit großer, lesbarer Schrift, ruhigere Skyline (kleine Fenster statt Neonstreifen), Bühnenfront aus dunklen Stahlplatten.
- Bots eine Stufe leichter; wer alle Leben verliert, sieht „DU BIST RAUS“.

## Items, Waffen und Power-ups (2026-10-20)

- `Combat/Items`: Leichte Kiste, Schwerer Stein, Holzfass und Explosiv-Fass liegen ab Start in der Arena; Greifen hebt
  sie auf, Angriff oder Spezial wirft. Das Explosiv-Fass explodiert bei Treffer, Wurf oder hartem Aufprall.
- Alle 13 bis 18 Sekunden fällt eine klassische Waffe (60 %) oder ein Power-up: Titan-Pilz, Schutzstern,
  Blitz-Schuhe, Wucht-Hammer, Herz, Frostbombe. Waffen verlängern Reichweite und Wucht, Spezial wird zur
  Waffenfähigkeit (Strahl, Beben, Frostnova, Laser, Bumerang); nach ihren Einsätzen zerbrechen sie.
- Client: `ItemView` baut alle Items und Waffen aus Parts, Waffen in der Hand, Getragenes über dem Kopf,
  Explosionen, Titan-Wachstum der Figur.

## Signatur-Spezialangriffe (2026-10-20)

- Alle 59 Signaturen aus Godot portiert (`Combat/Signature`, `Combat/Projectiles`, `Moveset.signatureAbility`): Geschosse
  mit Zielsuche, Bumerang, Schwerkraft, Explosion, Lava-Pfützen, Feuerwände, Orbitalstrahl, Schneesturm, Pfeilregen,
  Diener, Sternenhund, Schattendoppel, Fuchsfeuer, Geschütze, Minen, Haftbomben; Zustände Turbo, Adlerflug, Iaido,
  Ki-Salve, Sprungbeben, Sturzflug, Schildwall, Eis, Fluch, Kette, Markierung, Hitze-Gauge mit Kernschmelze.
- Zweistufige Signaturen: zweites Drücken von Spezial löst Folgeangriff aus (Drei-Welten-Schnitt, Blitzschlag zum
  Markierten, Speer-Rückruf, Fuchsfeuer-Flug, Kernschmelze).
- Client: `ProjectileView` zeichnet Geschosse, Pfützen, Wände, Wolken und Kreaturen; Eisblock, Adlerflügel, farbiges
  Leuchten für Wut, Fluch, Rüstung und Markierung; Namen der Spezialangriffe, Teleport- und Iaido-Streifen.
- Bots schätzen die Reichweite ihrer Signatur und nutzen Folgeangriffe.

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
