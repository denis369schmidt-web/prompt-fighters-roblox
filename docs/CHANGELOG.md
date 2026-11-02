# Changelog

## Bestenlisten, Analytics, Einladen, Einstellungen, Touch und Match-Tempo (2026-11-02)

- Lobby-Bestenliste wechselt alle 10 s zwischen SIEGE DIESE WOCHE, SIEGE GESAMT und HÖCHSTES LEVEL
  (OrderedDataStores, Anzeigenamen, `Server/Leaderboard/LeaderboardService`, Regeln in `Meta/Leaderboards`).
- Analytics (`Server/Analytics/Analytics`): Onboarding-Funnel, Funnel „Spielrunde“, Münz-Economy-Events.
- FREUNDE EINLADEN und EINSTELLUNGEN in der Lobby (`UI/Settings`): Kamera-Wackeln reduzieren, Sound,
  weniger Partikel (im Profil gespeichert, `SaveSetting`), Benachrichtigungen erlauben. Einmaliger Gruppenbonus.
- Touch-Steuerung neu (`UI/TouchButtons`): größere Knöpfe in der Safe Area, sichtbarer Stick, AUSWEICHEN,
  SUPER!-Anzeige, Finisher-Hinweis für Touch. Tastatur O / Gamepad L2 = Ausweichen.
- Lobby-HUD rutscht unter die Roblox-Leiste; oben rechts bleibt Platz für den Shop-Knopf.
- Match-Tempo: 2 Stocks im Jeder-gegen-jeden, etwas stärkere Abschüsse bei hohem Prozent; Matches enden
  meist nach 60–120 s durch KOs statt durch die Uhr (`scripts/pacing.luau`).

## Bots mit Charakter, Match-Kino und Revanche (2026-11-02)

- Bots (`Combat/Bot`): Persönlichkeit aus dem Archetyp (Draufgänger, Fernkämpfer, Packer, Konterer, Allrounder),
  Stufe 1–9 steuert Reaktionszeit, Fehler, Schild/Ausweichen auf sichtbare Angriffe, Combos (Jab → Ftilt,
  Utilt → Uair), Bestrafen von Fehlschlägen, Kantenwache und Ledge-Trap, Würfe Richtung Kante, Signatur mit voller
  Superleiste, Items aufheben und werfen. Zielwahl verteilt sich (kein Dreier-Angriff auf einen Spieler), Bots
  provozieren nach einem KO. Bot-Stufe nach Spielerfortschritt, gestaffelt pro Bot; erstes Match: sanfte Bots
  der Stufe 1 mit 2 Stocks.
- Intro: Letterbox, Arena-Karte, Namensschilder mit VS, Kameraschwenk, 3 · 2 · 1 · KAMPF!; Revanche mit
  REVANCHE!-Karte.
- Ansagen (`UI/Announcer`): ERSTER KO!, LETZTER STOCK!, COMBO x5, SUDDEN DEATH, 10 SEKUNDEN!, PARIERT!, Finisher-Name.
- Ende: GAME!-Standbild, Kamera kreist um den Sieger in Siegerpose (`Pose` Zustände `Victory`/`Taunt`),
  Podium mit Platz, KOs, Schaden, Combo, danach Belohnungskarte und NOCHMAL / Zur Lobby (`VoteRematch`).
  Ergebnisphase endet, sobald alle abgestimmt haben; Lobby-Start 5 s statt 8 s, wenn alle bereit sind.

## Neue Kämpfer-Modelle (2026-10-30)

- Alle 16 Startkämpfer neu modelliert, weiterhin nur aus Parts (keine Meshes): Kapsel-Glieder mit Kugelgelenken,
  V-förmiger Oberkörper, sichtbarer Hals, Fäuste mit Knöcheln und Daumen, Stiefel mit Sohle und Kappe,
  runder Kopf. Körperbau leicht/mittel/schwer (`Looks.BUILDS`).
- Eigene Silhouette pro Kämpfer: Felsbrocken und Glutrisse (MAGMOR), Hörnerhelm, Flügel und Schwanz (TEMPLAR),
  Flammenkamm und Neon-Flügel (SCARLET), Visier, Raketen und Reaktor (CYBORG MECH), Vollplatte mit Federbusch,
  Wappenrock und Drachenschild (CARDINAL), Flügelhelm, Zöpfe und Lanze (BOLTAR), fünf Fuchsschwänze und Sterne
  (CELESTIAL FOX), Kapuze, Knochenschmuck und Seelenlicht (NEKRA), Kapuze, Maske und Blitz-Schal (VOLT NINJA) usw.
- Gesichter: große Augen mit Iris, Pupille und Glanzpunkt, Lidstrich (Wimpern), geformte Brauen, Nase,
  Mundformen (Grinsen, Lächeln, Schmunzeln …), Wangenröte; folgen der Kopfrundung.
- Ausrüstung als Daten mit Generatoren (Kette, Fächer, Ring, Spiegeln, Spitze) für Schwänze, Umhänge, Flügel,
  Röcke und Kronen; 88–119 Teile pro Kämpfer (Test hält das Budget).
- Vorschau: `export-scene.luau portrait <ids> <winkel>` für Nahaufnahmen.

## Animationen mit Gewicht (2026-10-30)

- Angriffe als Keyframes mit Zeit in der Phase (`Visual/Pose`): Ausholen, schneller Schlag mit Überschwinger,
  Halten, Nachschwung, Zurückfedern. 30 eigene Bewegungen: Jab-1-2 (Hände wechseln), Gerade, Smash mit großem
  Ausholen und Zittern, Uppercut mit Absprung, Feger, Breakdance-Drehung, fliegendes Knie, Salto-Axtkick (fair),
  Rückwärtssalto (bair), Scherenkick, Stampfer, Zauber-Stoß, Strahl, Beschwörung, Korkenzieher-Uppercut,
  Bodenschlag, Wurf, Konter, Iai-Schnitt, Trommelfeuer, Wirbel.
- Waffen in der Hand: diagonaler Überkopfhieb, Vor-/Rückhand-Querhieb, Stich, beidhändiger Hieb, Aufwärts- und
  Tiefschnitt, Drehhieb, Zielen mit Rückstoß (Ausrüstung des Kämpfers oder aufgehobene Waffe).
- Bewegung: Gehen/Sprinten mit Schrittphasen, Armen gegen die Beine, Hüft-/Schulterdrehung, ruhigem Kopf und
  Vorlage; Wenden mit Rutschen und Drehung zur Kamera; Absprung-Streckung, Hocke im Steigen, Schweben am
  Scheitel, Fallhaltung; Salto beim Doppelsprung; Landungs-Stauchung je nach Fallhöhe; Füße stehen flach.
- Stand mit Atmung, Gewichtsverlagerung und Eigenart: schwere Kämpfer (Golem, Grimbolt, Mech, Drache …) tiefer,
  breiter, langsamer; leichte (Ninja, Zip, Lepora …) federn auf den Fußballen.
- Treffer: Zucken weg vom Schlag, Salto-Taumeln bei starkem Wegschleudern; Rolle als ganze Drehung, Ausweichen
  auf der Stelle, Luft-Ausweichen mit Schraube; Benommen-Taumeln, Kanten-Hängen, Greifen, Wurf, Smash-Laden.
- `FighterView`: Federn pro Gelenk statt Lerp (Schläge schnappen mit leichtem Überschwingen), Vorlage beim
  Beschleunigen, Zeitlupe bremst auch die Animation. Vorschau: `export-scene.luau poses` rendert Posen-Bögen.

## Treffer-Gefühl („Juice“) (2026-10-30)

- Treffer nach Stärke (`Visual/GameFeel`): leicht = Funken in Schlagrichtung + weißer Einschlag-Stern;
  mittel/schwer zusätzlich Schockwelle, Bild-Halt (lokaler Hitstop 50–120 ms, `Juice.hold`/`Juice.frozen`) mit
  Zittern des Getroffenen; schwer zusätzlich Impact-Frame (Kontrast), Speed-Lines und Splitter.
- Kamera: Trauma-Wackeln mit Rauschen, Kick in Schlagrichtung, Zoom-Punch bei schweren Treffern, FOV-Puls beim
  Super, Zeitlupe + Zoom auf den entscheidenden KO. „Reduzierte Bewegung“ von Roblox (oder Attribut
  `ReduceShake`) dämpft Wackeln und Blitze; `Juice.SHAKE_SCALE` als Regler.
- KO: Strahl vom Blast-Punkt quer über die Bühne, Stern-Blitz, Schockwellen, Bildblitz; beim letzten KO ein
  „K.O.“-Banner.
- Schlag-Bögen (Beam-Kurven) in der Leuchtfarbe des Kämpfers, schönere Spuren; Staub beim Laufen, Landen,
  Springen und Ausweichen.
- Schild-Welle beim Blocken, Parade-Blitz mit kurzer Zeitlupe, Clash-Funken mit Rückstoß beider Kämpfer.
- Schadenszahlen poppen mit Überschwinger, Farbe nach Schaden; Combo-Zähler („3 HIT COMBO“) beim Angreifer.
- Projektile mit weißem Kern, pulsierendem Halo, Funkenspur, Mündungsblitz und Einschlag.
- Sounds nur aus dem Roblox-Client (`Controllers/Sfx`, abschaltbar).

## Fortschritt, Kämpfer-Shop und Vorschau-Bilder (2026-10-30)

- Fortschritt wird gespeichert (DataStore): Münzen, Level mit Titel, Siege, Kämpfer-XP, freigeschaltete Kämpfer.
  Ohne DataStore-Zugang (Studio) läuft ein vorläufiges Profil, das nie etwas überschreibt.
- Belohnung nach jedem Kampf: Note S bis D, XP, Münzen, Level-Aufstieg; jeder 3. Sieg schaltet den günstigsten
  gesperrten Kämpfer gratis frei. Ergebnis-Karte zeigt alles nach dem Kampf.
- Täglicher Login-Bonus (7-Tage-Kalender, 50 bis 300 Münzen).
- Kämpferwahl mit 3D-Porträts; 6 der 16 Kämpfer sind mit Münzen freizuschalten (Tippen zeigt den Preis, zweites Tippen kauft).
- Profil-Leiste oben links: Level, Titel, XP-Balken, Münzen.
- Gesichter: Augen mit Pupillen, Augenbrauen, Mund (passt sich Helmen und Masken an).
- Arenen: schlanke schwebende Bühne statt großem Block, Kolosseum mit drei Bogenreihen weiter hinten,
  dezentere Plattform-Leuchten, Schilder und Stadion-Bildschirm wieder im Bild.
- Werkzeug: `scripts/export-scene.luau` + `scripts/preview/render.mjs` rendern Arenen, Lobby und Kämpfer als PNG
  (`scripts/preview/shots.sh <ordner>`).

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

## 2026-10-30: Marketing-Artworks

- `export-scene.luau scene`: Arena mit frei platzierten, posierten Kämpfern für Key-Art.
- `scripts/preview/compose-art.mjs`: Thumbnails (Type Any Fighter, 999%, 16 Fighters), Icon, TikTok-Cover und Quadrat-Post aus Renders plus Text.

## 2026-11-02: Prompt-Kämpfer

- `Shared/Prompt/Interpreter` (rein, getestet): Schlüsselwörter Deutsch und Englisch (20 Elemente, 25 Körpertypen,
  15 Waffen, 3 Tempo-/Kraftwörter, Komposita wie „Sternendrache“), Statuspunkte (Budget 100, je 8–36), Kit eines
  Roster-Kämpfers als Moveset, Signatur passend zum Element, generierter Look (Element-Palette + Seed-Variation,
  Körperbau, Haare, Glühaugen bei magischen Elementen), Ausrüstung aus GearData + neuem `Visual/PromptGear`
  (Hammer, Axt, Sense, Blaster, Zauberstab, Fäuste, Zauberhut, Umhänge, Heiligenschein, Hörner, Ohren, Schweif, Krone),
  Name aus den erkannten Wörtern („EISGOLEM“), Titel („Eisiger Koloss“).
- `Shared/Prompt/Code`: 6-stelliger Teile-Code (Crockford Base32) baut den Kämpfer ohne Text exakt nach.
- `Shared/Prompt/Registry`: registriert Prompt-Kämpfer als `prompt_<CODE>`; `Fighters.get` löst solche Ids überall
  (Server, Client, Simulation, RigBuilder, FighterView) aus dem Code auf.
- Server `Prompt/PromptService`: `SubmitPrompt` (max. 120 Zeichen, TextService-Filter, „#“ = abgelehnt) und
  `LoadPromptCode`; letzte 3 Prompt-Kämpfer im Profil (Profil v2). MatchService erlaubt Prompt-Kämpfer in der Auswahl.
- Client `UI/PromptTerminal`: Eingabe, 3 Vorschlag-Chips, Code-Eingabe, Enthüllung (Lichtburst, drehender Kämpfer,
  Name, Titel, Werte, Signatur, Code), „Mit diesem Kämpfer spielen“; `UI/PromptRow` zeigt die eigenen Prompt-Kämpfer
  im Kämpfer-Picker.
- `export-scene.luau prompts`: Vorschau für Prompt-Kämpfer.
## 2026-11-02: Lobby und Arenen schöner, Statuen günstiger

- Lobby neu aufgebaut (180×180): zentrale Showcase-Bühne mit drehendem Kämpfer in voller Detailstufe (`LobbyBuilder.setFeatured`), Tor „ARENA-WAHL“, Lichtsäulen über den drei Abstimmungsfeldern, leuchtende Chevron-Wege von Spawn zu allen Bereichen (farbcodiert), Bodenschrift, Wegweiser.
- Bestenliste (`LobbyBuilder.setLeaderboard(rows, title?)`), Prompt-Terminal-Platz (Anker-Part `PromptTerminal` mit `PromptAttachment`, `LobbyBuilder.terminalCFrame()`), Trainingspuppen, Lounge mit Brunnen, Fahnen, Skyline rund um den Platz.
- Statuen: reduzierte Detailstufe (keine Gesichtsdetails außer Augen, keine Kleinteile, keine Knochen). Lobby 1996 → 1330 Parts, Schatten-Parts 1827 → 148.
- Arenen: Parallax-Ebenen (Skylines, Hügel), Publikum in Stadien und Kolosseum, Berge als echte Dreiecke, Polarlicht als Band, Fabrikfenster, Hochöfen, Lavaflüsse statt Neonboden, Abendlicht im Kriegsgebiet, weniger Überblendung (Cyber-Stadion, Hangar, Eiswerk, Gießerei).
- Bewegte Deko (Züge, Blimp, Flugzeuge, Helikopter, Seilbahn, Kranhaken, Ventilatoren, Station, Fahnen, Laternen, Suchscheinwerfer, pulsierendes Neon) über `Shared/Visual/DecorMotion` + `DecorAnimator.client` (nur Client, BulkMoveTo, 30 Hz, nur in Kameranähe).
- Alle Deko verankert, ohne Kollision/Touch/Query; Schatten nur für große Parts nahe der Kamera (`World/Decor.finalize`).
- `scripts/part-budget.luau`, `shots.sh` mit Kontaktbogen und Lobby-Draufsicht; Renderer kann Text auf der Oberseite.

## 2026-11-02: Boss-Raid, Modus-Wahl und Tages-Challenge

- Boss-Raid (`Combat/BossFight`): 1–4 Spieler plus Bot-Helfer gegen einen riesigen prozeduralen Boss (`Visual/BossRig`, ≤ 140 Parts). Er hat eine HP-Leiste und angekündigte Angriffsmuster aus `BossData` (emit, beam, charge, gale, ring, dive, nova, pillars, slow, sweep). Bei 50 % zerspringt die Hülle und Phase 2 beginnt. Wut ab 150 s, Niederlage bei 210 s. Gemeinsamer Lebenspool (1,5 pro Held), 3 s bis zum Respawn.
- Raid-Arenen „HÖLLENSCHLUND“ und „HIMMELSSPHÄREN“ (Layout `raid`, `ArenaBuilder.raidSanctum`).
- Tages-Challenge (`Data/DailyChallenge`): pro UTC-Tag für alle gleich. Kämpfer, Gegner, 2 Mutatoren (`Combat/MutatorRules`), Ziel (Sieg / unter 60 s / ohne Stockverlust / 1 gegen 2) und Bot-Stufe 4–7. Münzen einmal pro Tag, Serie bis 7.
- Modus-Wahl in der Lobby: Felder und Tafeln (`World/ModeBoard`) sowie ein Panel (`UI/ModeHud`) mit SCHNELLKAMPF / BOSS-RAID / TAGES-CHALLENGE. Remote `VoteMode`, unzuverlässiges Remote `BossState` (15 Hz).
- Client: Boss-Leiste mit Phasenmarke, Wut-Uhr und Teamleben (`UI/BossHud`). Namenskarte, Telegraph-Decals, Hüllen-Zerspringen, Sieg- und Niederlage-Panel (`Controllers/BossView`). Im Raid zeigt das HUD LP statt Stocks.
- Belohnungen pro Boss datengetrieben (`Bosses.REWARD`, `Meta/ModeRewards`), Titel „BEZWINGER: …“ beim ersten Sieg. Profil: `challengeDay`, `challengeStreak`, `bossWins` (mit Migration).
- Tests: `BossRaid.spec`, `DailyChallenge.spec`, `RaidWorld.spec`. `export-scene.luau boss <id> [shattered]`.
