# Bau-Prompt: „Prompt Fighters“ als Roblox-Experience

> **So benutzt du diese Datei:** Kopiere alles ab der Linie „PROMPT START“ in eine neue Claude-Code-Sitzung
> (am besten in einem leeren Git-Repo, z. B. `prompt-fighters-roblox`). Claude baut das Spiel dann Phase für Phase.
> Grundlage ist das Godot-Projekt `denis369schmidt-web/Ultimate-Prompt-Fighters`, Stand `main` @ `8d6e9ba`
> (2026-10-08). Lokale, nicht gepushte Änderungen vom PC sind darin **nicht** enthalten (z. B. fehlt
> `roster_unlocks.gd`, das `docs/STATUS.md` schon erwähnt).

---

<!-- ============================== PROMPT START ============================== -->

## 0. Deine Rolle und dein Ziel

Du bist Lead-Entwickler (Luau, Roblox Studio, Rojo), Game Designer und Monetarisierungs-Experte für Roblox.
Du baust **„Prompt Fighters“**: einen Plattform-Kampf im Stil von Super Smash Bros. (Prozent-Schaden, Wegschleudern
aus der Arena, Stocks) mit 58 Kämpfern, Signatur-Spezialangriffen, Finisher-Codes, Waffen-Items, Bossen und
Mutatoren, als **Multiplayer-Experience auf Roblox**, die langfristig gut und fair Geld verdient.

Die Vorlage ist ein fertiges Godot-Spiel. Alle Werte in diesem Prompt stammen daraus. Übernimm sie als
Startwerte und balanciere danach im Playtest nach.

**Erfolg heißt:** ein Spiel, das sich auf Handy, PC und Konsole sofort gut anfühlt, Spieler jeden Tag
zurückholt (Retention) und über Game Passes, Developer Products, Season Pass und Abo Umsatz macht,
**ohne Pay-to-Win und ohne bezahlte Zufallsboxen**.

---

## 1. Arbeitsweise (verbindlich)

1. **Code-first mit Rojo.** Der ganze Code liegt als `.luau` im Git-Repo, Rojo synct nach Studio.
   Projektdatei `default.project.json`. Werkzeuge über `rokit` (oder `aftman`): `rojo`, `wally`, `selene`, `stylua`,
   `lune`. Alle Skripte mit `--!strict`.
2. **Arbeite in Phasen (Abschnitt 13).** Jede Phase endet mit: lauffähigem Build, grünen Tests, kurzem Bericht
   (was gebaut, was getestet, was offen), Commit. Beginne die nächste Phase erst, wenn die Abnahmekriterien erfüllt sind.
3. **Daten getrennt von Logik.** Kämpfer, Moves, Signaturen, Waffen, Arenen, Bosse, Mutatoren, Shop-Produkte und
   Progressions-Werte sind reine Daten-Module in `ReplicatedStorage/Shared/Data`. Logik liest nur daraus.
   Ein neuer Kämpfer = ein neuer Dateneintrag + (optional) eine neue Mechanik.
4. **Reine Logik ist testbar.** Kampfsimulation (Schaden, Rückstoß, Zustände), Progression, Belohnungen,
   Shop-Regeln sind reine Module ohne Instanzen und werden mit **Jest-Lua** (oder TestEZ) unter **Lune** headless getestet.
5. **Frag nur, wenn eine Entscheidung nicht umkehrbar ist** (z. B. echte Robux-Preise veröffentlichen, Datenschema
   nach Launch ändern). Sonst triff eine sinnvolle Standardentscheidung, schreib sie in `docs/DECISIONS.md` und mach weiter.
6. **Keine fremden Marken, Figuren oder Assets.** Alles muss original sein (Namen, Looks, Sounds). Keine Modelle oder
   Animationen mit unklarer Lizenz. Jede Fremddatei mit Quelle und Lizenz in `docs/ASSET_LICENSES.md`.
   Einige Godot-Kämpfer sind an bekannte Anime-Archetypen angelehnt (Gummi-Faust, Ein-Schlag-Held, Ki-Prinz):
   **gestalte Aussehen und Namen so, dass keine Verwechslung mit fremden Marken möglich ist.**
7. **Dokumentation:** `README.md` (Start, Build, Tests), `docs/ARCHITECTURE.md`, `docs/ECONOMY.md` (alle Preise,
   Quellen und Senken der Währung), `docs/CHANGELOG.md`, `docs/LIVEOPS.md`.

---

## 2. Das Spiel in einem Absatz

Bis zu 4 Spieler (plus Bots) kämpfen auf einer schwebenden Plattform-Arena. Jeder Treffer erhöht den
**Schadensprozentsatz** des Gegners (0–999 %). Je höher der Prozentwert, desto weiter fliegt er. Wer aus der
Arena-Grenze fliegt, verliert einen **Stock** (Standard 3). Wer zuletzt steht, gewinnt; nach **99 Sekunden**
entscheidet die Anzahl Stocks, bei Gleichstand **Sudden Death**. Jeder Kämpfer hat 17 Angriffe, eine eigene
**Signatur** (neutraler Spezialangriff mit eigener Mechanik), eine **Super-Leiste** und einen eigenen
**Finisher**, ausgelöst per Richtungs-Code. Waffen fallen in die Arena und können aufgehoben werden.
Alleinstellungsmerkmal: **Prompt-Kämpfer**. Spieler beschreiben einen Kämpfer in einem Satz („Eisgolem mit
Frosthammer, langsam aber stark“), das Spiel baut daraus einen spielbaren Kämpfer (Abschnitt 8.6).

---

## 3. Technische Architektur

### 3.1 Projektstruktur (Rojo)

```
src/
  ReplicatedStorage/Shared/
    Data/            -- Fighters, Moves, Signatures, Weapons, Arenas, Bosses, Mutators, Products, Progression, Ranks
    Combat/          -- reine Simulation: Physics, Knockback, Hitbox-Mathe, StateMachine, Moveset-Builder
    Net/             -- RemoteEvent-Definitionen + Schema-Validierung
    Util/
  ServerScriptService/
    Services/        -- MatchService, MatchmakingService, CombatService, DataService, ShopService,
                        ReceiptService, ProgressionService, QuestService, EventService, AnalyticsService,
                        ModerationService (Textfilter), BotService (KI)
  StarterPlayer/StarterPlayerScripts/
    Controllers/     -- InputController (Tastatur/Gamepad/Touch), CameraController, HUDController,
                        VFXController, AudioController, ShopUIController, LobbyUIController
  ServerStorage/     -- Arena-Modelle, Boss-Modelle
tests/               -- Jest-Lua-Specs für alle reinen Module
docs/
```

### 3.2 Netzwerk und Anti-Cheat

- **Server-autoritativ.** Der Server simuliert den Kampf mit festen 60 Hz (`RunService.Heartbeat` + Akkumulator),
  berechnet Treffer, Schaden, Rückstoß und KOs. Clients senden **nur Eingaben** (Bitmaske + Richtung + Sequenznummer).
- **Client-Vorhersage** nur für die eigene Bewegung und für Effekte (Animation, Funken, Sound sofort), Korrektur per
  Server-Snapshot (Interpolation 100 ms für fremde Kämpfer).
- Hitboxen serverseitig mit `workspace:GetPartBoundsInBox` / `Shapecast` oder rein mathematisch in der 2D-Ebene
  (empfohlen: der Kampf ist 2,5D, siehe 4.1, also reichen Rechteck-Tests in X/Y).
- Jedes Remote: Typ- und Wertebereich prüfen, Rate-Limit pro Spieler, Kauf- und Belohnungslogik **nie** auf dem Client.
- Lag-Ausgleich: Treffer gegen die Position des Ziels vor `min(ping/2, 100 ms)` prüfen.

### 3.3 Datenspeicherung

- **ProfileStore** (Nachfolger von ProfileService, via Wally) mit Session-Lock. Ein Profil pro Spieler, Schema-Version
  im Profil, Migrationsfunktion pro Version.
- Gespeichert wird alles aus Abschnitt 9 (Level, XP, Münzen, Meisterschaft, Besitz, Tages-/Wochenaufgaben,
  Login-Kalender, Liga-Punkte, Ruhmespfad, Statistiken, Erfolge, gekaufte Produkte mit Receipt-IDs).
- Bestenlisten über `OrderedDataStore` (Siege, Liga-Punkte, Abenteuer-Rekord), stündlich aktualisiert.

### 3.4 Performance (Handy zuerst)

- Ziel 60 FPS auf Mittelklasse-Handy. `StreamingEnabled` an, Arena als ein Modell mit wenigen Teilen,
  Partikel-Budget pro Arena, Effekte über einen **Pool** statt neu erzeugen.
- Kämpfer-Modelle: R15-basiert, max. ~10k Dreiecke, eine Textur-Atlas-Map pro Kämpfer.
- Grafik-Qualitätsstufe des Geräts lesen und Effekte drosseln.

### 3.5 Einheiten

Godot-Werte sind in Metern. **1 m = 3,57 Studs** (1 Stud = 0,28 m). Rechne alle Geschwindigkeiten,
Reichweiten und Hitboxen mit diesem Faktor um und lege ihn als Konstante `METER = 3.57` an.

---

## 4. Kampfsystem (Werte aus dem Godot-Kern `combat.gd`)

### 4.1 Ebene und Kamera

- Kampf auf der **X/Y-Ebene**, Z ist gesperrt (2,5D wie Smash). Kamera seitlich, zoomt dynamisch auf alle Kämpfer.
- Arena = Hauptplattform + 2–3 Schwebeplattformen (durchspringbar von unten, mit „Unten“ durchfallen).
- **Blast-Zonen** links, rechts, oben und unten. Berührung = Stock verloren, Respawn auf Plattform mit 2 s Unverwundbarkeit.

### 4.2 Bewegung (Standardwerte, pro Kämpfer überschreibbar)

| Wert | Standard |
|---|---|
| Sprungkraft | 8,5 m/s |
| Schwerkraft | 20 m/s² |
| Schnellfall | 13 m/s |
| Luftsteuerung | 0,9 × Lauftempo |
| Luftsprünge | 2 |
| Rennen-Faktor | 1,35 (nach 0,3 s Bewegung gilt man als rennend) |
| Bodenbeschleunigung / -bremsung | 55 / 42 m/s² |
| Coyote-Time | 0,1 s |
| Luft-Dash | 11,5 m/s, Aufstieg 6,8, Sturz −9 |
| Schild | max 50, verliert 11/s gehalten, regeneriert 9/s, Blockschaden × 1,3; Schildbruch = 2,2 s Betäubung |
| Rolle / Ausweichen / Luftausweichen | 0,34 s @ 7,2 m/s / 0,28 s / 0,38 s @ 8 m/s; unverwundbar 0,24 s |
| Kante | max 6 Griffe pro Leben, Unverwundbarkeit 1,0 / 0,6 / 0,35 / 0,15 / 0 / 0 s, max 5 s hängen |
| Smash-Angriff | Taste < 0,1 s = Tilt, länger halten = aufladen bis 1,0 s |
| Einfluss auf Flugbahn (DI) | max 15° |

### 4.3 Moveset (17 Angriffe pro Kämpfer)

`jab, ftilt, utilt, dtilt, fsmash, usmash, dsmash, dash_attack, nair, fair, bair, uair, dair, nspecial (=Signatur),
uspecial, dspecial` + Griff/Würfe (vor, zurück, hoch, runter).

Jeder Move ist ein Datensatz:
`{name, dmg, windup, active, recovery, xMin, xMax, yMin, yMax, angle, kb, extras}`
- `dmg`/`kb` sind Faktoren auf den Basisangriff des Kämpfers, Zeiten in Sekunden, Hitbox in Metern relativ zu den Füßen
  (x nach vorn, y nach oben).
- `extras`: `free_angle, all_around, back, rehit, motion_vx/vy, armor, shot, blink, intangible, cooldown,
  super_gain, repel, use_sig`.
- Beispiel (Kalyx): `fsmash = {"Zwiefaust", 1.65, 0.15, 0.12, 0.32, -0.3, 2.4, -0.1, 2.0, 38, 2.25}`.
- Kämpfer ohne eigene Move-Tabelle bekommen ein **generiertes Moveset** aus Standard- und Spezialangriff
  (Moveset-Builder). Gib trotzdem jedem Kämpfer mindestens eigene Namen und eine eigene Hitbox-Form für
  fsmash, Signatur, uspecial, dspecial, damit sich alle unterschiedlich spielen.

### 4.4 Schaden und Rückstoß

```
schaden  = basis * (1 - verteidigung * 0.01)  -- auf 0.55..0.90 begrenzt
prozent  = clamp(prozent + schaden, 0, 999)
gewicht  = clamp(kaempfer.gewicht, 0.85, 1.35)
skala    = 1 + prozent*0.009 + prozent^1.35 * 0.0017
impuls   = basisRueckstoss * 4.25 * skala / gewicht
vx       = richtung * impuls * 0.85
vy       = max(impuls * 0.5, 1.8)
hitstun  = clamp(0.30 + prozent*0.002, 0.18, 0.70) s; Luftsteuerung gesperrt für 60 % davon
Wurf     = 15 Schaden, skala = 1 + p*0.008 + p^1.38*0.0016; vor 2.9, zurück 3.2, hoch 3.0 (× skala / gewicht)
```
Lege das als reine Funktion `Knockback.compute(...)` an und teste sie mit festen Zahlen.

### 4.5 Super-Leiste und Finisher

- `MAX_SUPER = 100`. Treffer mit Standard +6 / Spezial +12 für den Angreifer, +4 / +8 für das Ziel,
  langsames Auffüllen +2,2/s, Konter-Treffer +25.
- Spezial bei voller Leiste = **Super-Version** der Signatur.
- **Finisher:** Hat der Gegner nur noch einen Stock und ≥ 100 %, öffnet sich nach einem Treffer ein kurzes
  Zeitfenster: Spieler gibt den Code des Kämpfers ein (F = vor, B = zurück, U = hoch, D = runter, A = Angriff,
  S = Spezial). Richtig → Finisher-Kinoszene (Kamera, Zeitlupe, Effekte) → KO.
- **Roblox-Regel: keine Zerstückelung, kein Blut.** Der Godot-Finisher hat Gore-Optionen. Auf Roblox sind
  Finisher **stilisiert** (Licht, Explosion, Eis, Siegel, Kamera-Show), damit die Experience im
  Inhalts-Rating „Mild“ bleibt und für alle Altersgruppen sichtbar ist.

### 4.6 Weitere Regeln

- **Clash:** Treffen zwei Angriffe gleichzeitig, prallen beide ab (Funken, kurzer Stopp).
- **Sudden Death** im Versus bei Zeitablauf und Gleichstand: alle starten mit 150 % (wie der Mutator), der nächste KO entscheidet.
- **Gefahren-Glut / Funkenschweif:** ab 120 % zieht ein Kämpfer einen glühenden Schweif (Lesbarkeit).
- **Waffen-Items** spawnen alle ~8 s (Tabelle 7). Jede Waffe zerbricht nach `uses` Angriffen.
- **KI-Bots:** 9 Stufen. Stufe steuert Reaktionszeit, Combo-Nutzung, Schildnutzung, Signatur-Aufladung
  (`0.3 + stufe*0.12`), Finisher-Wahrscheinlichkeit (`0.35 + stufe*0.07`). Bots nutzen **dieselben Eingaben und
  dieselbe Simulation** wie Spieler (wichtig: kein Sonderweg für KI).

---

## 5. Kämpfer (58)

### 5.1 Datenformat pro Kämpfer

```lua
{
  id = "ninja", name = "VOLT NINJA", element = "electric", archetype = "Rushdown",
  weight = 0.88, runSpeed = 4.4, -- m/s
  stats = {vitality=18, power=18, defense=14, speed=29, technique=21},
  phys = { jump=8.5, gravity=20, fastFall=13, air=0.9, airJumps=2, run=1.35, shield=1.0 },
  standardName = "...", specialName = "...",
  moves = { ... }, -- optional, sonst generiert
  signature = { mech = "mark", ... },
  finisher = { name = "RAIJIN-HINRICHTUNG", code = {"B","F","S"}, kind = "storm" },
  unlock = { kind = "starter" } | { kind = "coins", price = 600 } | { kind = "mastery", ... },
  lore = { epithet = "...", origin = "..." },
}
```

### 5.2 Roster (Werte aus der Vorlage)

G = Gewicht, T = Lauftempo (m/s). Signatur = Mechanik (Beschreibung in 5.3). Finisher-Code: F B U D A S.

| # | ID | Name | Archetyp | Element | G | T | Signatur | Finisher (Code) |
|---|---|---|---|---|---|---|---|---|
| 1 | ninja | VOLT NINJA | Rushdown | Blitz | 0.88 | 4.4 | mark | Raijin-Hinrichtung (B F S) |
| 2 | golem | MAGMOR | Schwergewicht (Rüstung, Glut) | Feuer | 1.34 | 2.95 | magma | Vulkangrab (D D S) |
| 3 | valkyrie | BOLTAR | Allrounder (Lanze, Flügel) | Licht | 1.08 | 3.8 | javelin | Lichturteil (U U S) |
| 4 | dragon | TEMPLAR | Schwergewicht (Flammenschwert) | Feuer | 1.24 | 3.2 | flame_wall | Drachengericht (D B A) |
| 5 | kairo | KAIRO | Allrounder (Ki-Ladung) | Wind | 1.04 | 3.75 | charge_beam | Solarflut (B F A) |
| 6 | varakh | VARAKH | Druck-Zoner (Ki-Salven) | Ki Gold | 1.06 | 3.9 | volley | Sternenfall (U D A) |
| 7 | xylar | XYLAR | Zoner (schwebend) | Ki Violett | 0.95 | 3.6 | nova | Supernova (U U A) |
| 8 | glaciem | GLACIEM | Assassine (Frost) | Eis | 0.9 | 4.15 | ice_decoy | Ewiges Eis (D F A) |
| 9 | oryn | ORYN | Kontrolle (Schwerkraft) | Gravitation | 1.08 | 3.3 | singularity | Planetenbann (B U S) |
| 10 | tobi | TOBI | Brawler (Federfaust) | Gummi | 1.0 | 3.8 | sling_fist | Federsturm (B B S) |
| 11 | jubei | JUBEI | Schwertkämpfer (Drei Klingen) | Windklinge | 1.02 | 3.85 | tri_slash | Drei-Welten-Schnitt (F F S) |
| 12 | ren | REN | Trickser (Doppelgänger) | Windspirale | 0.98 | 4.0 | shadow_clone | Kirschsturm (F B S) |
| 13 | amethya | AMETHYA | Rushdown (Blitz) | Blitzbogen | 0.95 | 4.35 | trail_dash | Donnersturz (D B S) |
| 14 | bruno | BRUNO | Punisher (Meteorfaust) | Wucht | 1.02 | 3.9 | one_punch | Meteorfaust (F D A) |
| 15 | hikaru | HIKARU | Allrounder (Glutatem) | Sonnenflamme | 0.98 | 3.85 | sun_wheel | Dreizehnte Form (U F S) |
| 16 | arber | ARBËR | Brawler (Doppelbohrer, Flieger) | Wind | 1.08 | 3.9 | eagle | Flug der Shqiponja (U B S) |
| 17 | zip | ZIP | Speedster (Turbo) | Wind | 0.86 | 4.6 | turbo | Lichtmauer (F U A) |
| 18 | raiga | RAIGA | Konter-Brawler (Sternsiegel) | Blut-Oni | 1.08 | 3.6 | star_seal | Kompassnova (D U S) |
| 19 | albion | ALBION | Drachenzoner (Sturmstrahl) | Heiliges Licht | 1.28 | 3.2 | beam | Silbergewitter (F F U S) |
| 20 | pyrax | PYRAX | Luftkämpferin (Flügel, Feueratem) | Feuer | 1.12 | 3.4 | breath | Glutsturz (D D A) |
| 21 | anubis | AURUM | Konter-Duellant (zwei Khopesh) | Schattengold | 1.02 | 3.6 | soul_weigh | Wägung des Herzens (B U A) |
| 22 | specter | RAVENNA | Trickserin (Teleport, Leerenlanze) | Leere | 0.94 | 3.8 | teleport | Kein Spiegelbild (B D A) |
| 23 | phoenix | SCARLET | Luftkämpferin (Gleve, Wiedergeburt) | Feuer | 0.95 | 3.7 | rebirth | Neunte Asche (U B A) |
| 24 | brunhild | BRUNHILD | Schwergewicht (Axt, Rüstung) | Gold-Metall | 1.36 | 3.0 | war_horn | Walhalls Ruf (F D S) |
| 25 | lepora | LEPORA | Schützin (Bogen, Pfeilregen) | Windpfeil | 0.88 | 3.9 | arrow_rain | Mondfinsternis (U U F A) |
| 26 | thorn_witch | THORN WITCH | Fallenstellerin (Dornen) | Natur | 0.94 | 3.5 | bramble | Rosengrab (D B D S) |
| 27 | nyx | NYX HARVESTER | Luftjägerin (Sense, Lebensraub) | Seele | 1.04 | 3.6 | reap | Letzte Ernte (B D B S) |
| 28 | shira | SHIRA | Rushdown (Krallen) | Kralle | 0.86 | 4.4 | barrage | Neun Leben (F U S) |
| 29 | frostwyrm | FROSTWYRM | Bestie (Eis, Flächenkontrolle) | Eis | 1.32 | 3.2 | blizzard | Ewiger Winter (D U D A) |
| 30 | cyborg_mech | CYBORG MECH | Artillerie (Raketen) | Plasma | 1.18 | 3.3 | missile_salvo | Protokoll Omega (D D U S) |
| 31 | reaper_hound | REAPER HOUND | Rushdown (Vierbeiner) | Tod | 0.9 | 4.5 | dash | Der letzte Heimweg (D F S) |
| 32 | treant | TREANT GOLEM | Schwergewicht (Wurzeln) | Holz | 1.45 | 2.8 | root_snare | Urwald (D D F A) |
| 33 | celestial_fox | CELESTIAL FOX | Geisterzonerin (Fuchsfeuer) | Neunfeuer | 0.92 | 3.9 | fox_orbit | Neun Schweife (U F A) |
| 34 | mossback | MOSSBACK | Bestie (Ansturm) | Waldbestie | 1.28 | 3.6 | stampede | Bergrutsch (F F D A) |
| 35 | steel_knight | CARDINAL | Verteidiger (Schild) | Eis | 1.25 | 3.0 | bulwark | Schildrichter (F F A) |
| 36 | vanguard_soldier | VANGUARD | Artillerie (Orbitalschlag) | Plasma | 1.15 | 3.3 | orbital_strike | Photonenschlag (U F U A) |
| 37 | sorceress_medea | SORCERESS | Fluchwirkerin (Zoner) | Dunkle Magie | 0.9 | 3.4 | hex | Sternenbann (U D U S) |
| 38 | skeleton_reaper | FLAYER | Kontrolle (Knochensense) | Schattenknochen | 1.0 | 3.5 | bone_prison | Knochenthron (B B D A) |
| 39 | mutant_titan | MUTANT | Koloss (Gift, Supertank) | Säure | 1.5 | 2.7 | toxic_cloud | Toxischer Koloss (D D D A) |
| 40 | swat_specops | SWAT AGENT | Taktiker (Blendgranaten) | Blitz | 1.0 | 3.7 | flashbang | Zugriff (F B F A) |
| 41 | samurai_dreyar | KOMMANDANT | Punisher (Iaido) | Eis | 1.05 | 3.7 | iai | Tausend Schnitte (B D S) |
| 42 | pirate_captain | SERAPHINE | Mix (Säbel & Pistole) | Wind | 1.02 | 3.6 | board | Breitseite (B B A) |
| 43 | vampire_lord | VLAD | Lebensräuber (Fledermausgestalt) | Blut | 1.0 | 3.6 | bat_form | Blutmond (B U B S) |
| 44 | wizard_sorcerer | PYRUS | Zoner (Glaskanone, Meteore) | Feuer | 0.86 | 3.3 | meteor | Sternenfall von Pyrus (U D S) |
| 45 | warrok_brute | WARROK | Schwergewicht (Berserker) | Feuer | 1.42 | 2.8 | leap_slam | Erdbrecher (D U A) |
| 46 | nekra | NEKRA | Beschwörerin (Knochendiener) | Seele | 0.9 | 3.4 | revenant | Knochengarten (D B U S) |
| 47 | grimbolt | GRIMBOLT | Tüftler (Haftbomben) | Feuer | 0.82 | 3.8 | time_bomb | Kettenreaktion (B F D A) |
| 48 | echo | ECHO | Trickser (Phasentausch) | Plasma | 0.88 | 4.0 | phase_swap | Speicherfehler (F U B S) |
| 49 | kettenwart | KETTENWART | Kerkermeister (Fesselketten) | Eis | 1.22 | 3.1 | chain_leash | Ewige Verwahrung (B B F S) |
| 50 | don_valente | DON VALENTE | Beschwörer (Geschütze) | Ki Gold | 1.22 | 3.0 | turret | Das letzte Angebot (F B A) |
| 51 | kalyx | KALYX | Elementwechsler (Frost / Glut) | Eis/Feuer | 1.05 | 3.8 | crown_shift | Zwiekristall (U D B S) |
| 52 | vorruk | VORRUK | Sternenkoloss (Krallen, Hund) | Sterne | 1.48 | 2.7 | pack_hound | Heimweh der Sterne (D D B A) |
| 53 | neris | NERIS | Kettenkämpferin (Anker, Glasflügler) | Leere | 0.92 | 4.2 | anchor_chain | Kristallkerker (B U F S) |
| 54 | konrad | KONRAD | Schmied (Hammer, Amboss) | Metall | 1.24 | 3.2 | anvil | Meisterstück (F D F A) |
| 55 | bogdan | BOGDAN | Koloss (Streitkolben, Frost) | Eis | 1.34 | 2.9 | frost_roar | Weiße Nacht (U B U S) |
| 56 | kaan | KAAN | Duellant (Säbel, Halbmond) | Sturm | 1.0 | 4.0 | crescent | Halbmond und Stern (D F U S) |
| 57 | amra | AMRA | Luftakrobatin (Brückensprung) | Wasser | 0.9 | 4.3 | bridge_dive | Sprung von der alten Brücke (U U D S) |
| 58 | dusty | DUSTY | Rodeo-Grappler (Lasso) | Wüste | 1.04 | 3.8 | lasso | High Noon (B D F A) |

Hinweise:
- Kalyx, Vorruk und Neris haben **Helfertiere** (Zirra, Glimm, Fenn). Konrad, Bogdan, Kaan, Amra und Dusty sind die
  „Länder-Kämpfer“ (je eine Nation, Erfolg „Weltreise“).
- Lebenspunkte für Boss-/Abenteuer-Modus: 110–138 je nach Vitalität (Schwergewichte mehr).

### 5.3 Signatur-Mechaniken (neutraler Spezial)

Baue jede Mechanik **einmal** als Modul `Signatures/<mech>.luau` mit Parametern (Farbe, Form, Tempo, Schaden …),
damit neue Kämpfer sie wiederverwenden können:

| Mechanik | Verhalten |
|---|---|
| projectile | Geschoss; Optionen: Streuung, Schwerkraft, Durchschlag, Zielsuche, Welle, Bumerang, Einfrieren, Explosion, Zünder, Ziehen |
| meteor | Geschoss fällt von oben auf den Bereich vor dem Kämpfer |
| beam / charge_beam | langer Sofort-Strahl; aufladbar: voll geladen über die ganze Arena |
| dash / trail_dash / turbo | Vorwärtsansturm; Funkenspur am Boden; Turbo-Stiefel mit Körpertreffern bei Vollgas |
| teleport | blinzelt hinter den nächsten Gegner und schlägt zu |
| eruption | Bodenwelle aus Säulen, die nach vorn wandert |
| whirl | Rundum-Mehrfachtreffer, optional mit Sog |
| barrage | schnelle Trefferserie nach vorn |
| power / one_punch | langsamer Riesenschlag; one_punch bricht Schilde, Rückstoß wächst mit %, sicherer KO ab Schwelle |
| counter | Konterhaltung, Treffer wird automatisch beantwortet |
| mine / time_bomb | Falle / Haftbombe, explodiert bei Kontakt oder nach Zünder |
| turret | stellt ein Geschütz auf, das einige Sekunden feuert |
| rage | zeitweise mehr Kraft und Tempo |
| clone / shadow_clone | Schattendoppel läuft vor und schlägt / bleibt stehen und kopiert die Angriffe |
| mark | Kunai markiert, nochmal Spezial = Blitzschlag auf die Markierung |
| javelin | Speer werfen, steckt im Boden, nochmal Spezial = zurückrufen (trifft auf dem Rückweg) |
| magma | Lavaklumpen hinterlässt brennende Pfütze; volle Hitze-Leiste = Kernschmelze |
| board | Enterhaken, zieht heran, Tritt |
| bulwark | Schildwall, stoppt Frontaltreffer, reflektiert Schüsse, dann Schildstoß |
| iai | Iaido-Haltung: erster Gegner in Reichweite wird mit einem Schnitt getroffen |
| leap_slam | Sprung auf den Gegner, Landebeben trifft alle am Boden |
| volley | sechs gezielte Ki-Schüsse, der letzte explodiert |
| nova | Kugel wächst über dem Kopf, wird geworfen, größer = stärker |
| singularity | Schwerkraftkern zieht Gegner an, explodiert |
| tri_slash | Schwert-Dash, bis zu dreimal im Zeitfenster, der dritte schleudert hoch |
| sun_wheel | Flammenrad rollt im Bogen nach vorn |
| sling_fist | Spezial halten zum Ausholen, Faust fliegt weiter, Spitze trifft am härtesten |
| star_seal | Sternmandala am Boden schockt Gegner, Raiga darin wird rasend |
| ice_decoy | Eisstatue bleibt zurück, Kämpfer blinzelt weg; wer die Statue berührt, friert ein |
| eagle | Doppeladler trägt den Kämpfer: freier Flug, Adler stößt auf Gegner herab |
| flame_wall | Schwert in den Boden: Feuerwand, die brennt und Schüsse stoppt |
| breath | Feueratem-Kegel, Mehrfachtreffer; in der Luft schwebt der Kämpfer |
| rebirth | Phönixfeuer rundum, heilt (mehr, je verletzter), lange Abklingzeit |
| soul_weigh | Haken zieht heran, Schaden wächst mit dem % des Gegners |
| war_horn | breite Welle schleudert weit, danach kurz Rüstung |
| fox_orbit | drei Fuchsfeuer kreisen; nochmal Spezial = auf den nächsten Gegner schleudern (zielsuchend) |
| missile_salvo | Raketen steigen auf, suchen das Ziel, explodieren |
| blizzard | Schneewolke folgt dem Gegner, Hagel friert kurz ein |
| arrow_rain | Pfeile regnen in einer Reihe über dem Gegner herab |
| reap | weiter Sensenschwung, zieht heran, heilt anteilig |
| bramble | Dornenhecke wächst am Boden entlang, brennt |
| root_snare | Wurzeln brechen nach Warnung unter dem Gegner hervor und halten fest |
| stampede | langer gepanzerter Ansturm |
| hex | langsame Fluchkugel (zielsuchend), Verfluchte nehmen mehr Schaden |
| bone_prison | Knochenkäfig schließt sich um den Gegner und platzt |
| toxic_cloud | Giftwolke folgt dem Besitzer |
| flashbang | Blendgranate betäubt alle in der Explosion |
| orbital_strike | markiert die Stelle, nach Warnung trifft ein Strahl aus dem Orbit die ganze Säule |
| bat_form | Fledermausschwarm: unverwundbar vorwärts, beißt rundum, heilt |
| revenant | beschwört einen Skelettdiener, der zum Gegner läuft und zuschlägt |
| phase_swap | Glitch-Schuss: bei Treffer tauschen Echo und Ziel die Plätze |
| chain_leash | Seelenkette zieht heran und hält den Gegner kurz an der Kette |
| crown_shift, pack_hound, anchor_chain, anvil, frost_roar, crescent, bridge_dive, lasso | eigene Mechaniken der neuen Kämpfer (Elementwechsel Frost/Glut, Sternenhund, Ankerkette, Amboss-Fall, Frostgebrüll, Halbmond-Sichel, Sturzflug, Lasso-Fang); entwirf sie passend zu Name und Archetyp |

Jede Signatur hat Abklingzeit, Super-Version (volle Leiste) und klare Vorwarnung (Telegraph) für Gegner.

---

## 6. Arenen und Bosse

### 6.1 Arenen (23, Freischaltung mit Münzen)

NEON-GASSE (gratis), MONDTEMPEL 250, HOLO-METROPOLE 400, LAGERHALLE 300, CYBER-STADION 500, ORBITALRING 900,
NEON-SKYLINE 350, KOLOSSEUM 400, POLARLICHT-GIPFEL 600, RAUMSCHIFF-HANGAR 800, GRAFFITI-GASSE 300,
NIEMANDSLAND 500, SONNENSTADION 450, REGENDACH 350, DOJO 450, NACHTMARKT 350, RUINENSTADT 550, SONNENARENA 600,
STURMDACH 700, DSCHUNGELRUINEN 650, EISWERK 700, GIESSEREI 750, SCHMELZOFEN 1000.

Jede Arena: eigene Plattform-Anordnung, eine Gefahr (z. B. Lava-Fontäne, Blitzschlag, fahrender Zug), Ambient-Musik,
zerstörbare Requisiten. In Online-Matches wird die Arena **per Abstimmung** gewählt; wer eine Arena besitzt,
bekommt eine Extra-Stimme (Besitz wird sichtbar, ohne Vorteil im Kampf).

### 6.2 Bosse (19)

Himmel (9 Chöre): ANGELUS, MICHAEL, PRINCIPATUS, POTESTAS, VIRTUS, DOMINATIO, OPHANIEL, KERUVIM, SERAPHAEL.
Hölle (10 Fürsten): AHRIMAN, LILITH, ASMODEUS, BEELZEBUB, MAMMON, BAPHOMET, BELPHEGOR, BEL MARDUK, LEVIATHAN, LUCIFER.

Pro Boss: Lebenspunkte (Start 450, steigend um ~60 pro Boss, skaliert mit Spielerzahl), Basisschaden 11–20,
Schwebehöhe, Hurtbox, **zwei Phasen** (Phase 2 ab 50 % mit zusätzlichem Angriffsmuster), Intro-Satz.
Angriffsmuster aus der Vorlage: `feather_volley, sweep_short, wing_gale, holy_rain, sword_sweep, dive,
judgement_beam, thorn_volley, wreath_ring, spear_rain, charge, fire_pillars, scroll_beam, stillness,
scepter_orbs, holy_nova, eye_lasers, wheel_roll, ring_burst, eye_storm, fire_breath` (Hölle analog).
Bosse sind **nicht wegschleuderbar**, haben eine Lebensleiste und werden im **Boss-Raid** (2–4 Spieler Koop) bekämpft.
Aussehen: große Statuen-Körper (Marmor, Gold, Obsidian) mit Flügeln, Heiligenschein, Hörnern. Keine religiösen
Spott-Darstellungen, Ton „mythisch-episch“.

---

## 7. Waffen (Items)

| ID | Name | Reichweite | Schaden × | Rückstoß × | Nutzungen | Spezial |
|---|---|---|---|---|---|---|
| sword_hero | HELDENKLINGE | 0.9 | 1.45 | 1.25 | 14 | Strahl |
| sword_buster | RIESENBRECHER | 1.25 | 1.9 | 1.7 | 10 | Beben |
| sword_plasma | PLASMASÄBEL | 1.0 | 1.35 | 1.15 | 16 | Säbelwurf |
| sword_frost | SEELENFROST | 0.9 | 1.4 | 1.2 | 12 | Frostnova (friert 0,6 s) |
| sword_crescent | MONDSICHEL | 1.0 | 1.5 | 1.3 | 12 | Sichel |
| blaster | LASERBLASTER | Schuss | 1.0 | 1.0 | 18 | Laser |
| boomerang | STURMBUMERANG | Schuss | 1.0 | 1.0 | 9 | Bumerang |
| flail | KETTENMORGENSTERN | 1.7 | 1.7 | 1.8 | 10 | Beben |

Shop-Waffen (mit Münzen kaufbar, danach spawnen sie auch in Arenen, eine davon als Startwaffe wählbar):
SCHATTENKATANA 350, FROSTAXT 450, FEUERPEITSCHE 500, KRISTALLBOGEN 600, DRACHENLANZE 700, SEELENSENSE 800,
DONNERHAMMER 900, PLASMAKANONE 1200.

**Fairness-Regel für Online:** In **Ranked** gibt es keine Startwaffen und nur die 8 klassischen Item-Waffen.
Startwaffen nur in Casual, Abenteuer, Boss-Raid und privaten Servern.

---

## 8. Spielmodi auf Roblox

### 8.1 Lobby (Hub)
Begehbarer Hub mit: Kämpfer-Galerie (Statuen, anfassen = Vorschau), Trainingspuppe, Shop-Stand, Ruhmespfad-Tafel,
Bestenlisten-Wand, Tagesaufgaben-Brett, Portale zu den Modi, Emote-Bühne. Spieler sehen die Skins, Titel und
Siegerposen anderer (soziale Sichtbarkeit verkauft Kosmetik).

### 8.2 Schnellkampf (Casual)
Bis 4 Spieler, Freie-für-alle oder 2v2, freie Plätze mit Bots aufgefüllt (Stufe nach Spielerlevel).
Match-Start spätestens nach 20 s Warten. Arena per Abstimmung.

### 8.3 Ranked 1v1 (Ligen)
Ligen aus der Vorlage: BRONZE 0, SILBER 100, GOLD 250, PLATIN 450, DIAMANT 700, MEISTER 1000, CHAMPION 1400 Punkte.
Erstes Erreichen belohnt: Silber 200 Münzen, Gold 300 + Truhe, Platin 500 + Truhe, Diamant 800 + Truhe,
Meister 1200 + 2 Truhen, Champion 2000 + 3 Truhen. Saisonende alle 8 Wochen mit Liga-Rahmen als Belohnung.
Matchmaking nach verstecktem Elo, `MemoryStoreService` als Warteschlange, `TeleportService:ReserveServer` für Matches.

### 8.4 Boss-Raid (Koop)
2–4 Spieler gegen einen der 19 Bosse. Boss-Lebenspunkte skalieren mit Spielerzahl. Reihenfolge wie in der Vorlage
(Hölle Kreis für Kreis, dann Himmel). Erster Sieg pro Boss gibt Münzen und einen Boss-Titel.

### 8.5 Abenteuer (Solo, Endlos-Wellen)
Ein Kämpfer, endlose Gegner. Jede Welle schwerer (KI +1 bis 9), jede 5. Welle ein Boss, 120 s pro Welle,
nach jeder gewonnenen Welle heilen 35 % des Schadens. Punkte: Wellen, Tempo, Restleben, Combos, Bosse.
Bestenliste pro Kämpfer und gesamt.

### 8.6 Prompt-Kämpfer (Alleinstellungsmerkmal)
Spieler tippt bis 120 Zeichen. **Pflicht:** Text erst über `TextService:FilterStringAsync` filtern; ungefilterten
Text nie anzeigen oder speichern. Danach Schlüsselwort-Erkennung (wie `prompt_interpreter.gd`): Element
(Blitz/Feuer/Eis/Wind …), Körpertyp (Golem, Ninja, Drache …), Waffe, Tempo-/Kraftwörter → Statuspunkte
(Budget 100 auf Vitalität, Kraft, Verteidigung, Tempo, Technik), Basis-Körper, Ausrüstung, Farbe und eine passende
Signatur-Mechanik. Gleicher Text = gleicher Kämpfer (Seed aus Text-Hash). **Prompt-Text wird nie ausgeführt.**
Prompt-Kämpfer sind in Casual, Abenteuer und privaten Servern spielbar, nicht in Ranked.
Erweiterung „Fusionskammer“: Spieler kombinieren Körper, Waffe und Element aus Baukasten-Teilen.

### 8.7 Tages-Herausforderung und Mutatoren
Jeden Tag für alle gleich (Seed aus Datum): vorgegebener Kämpfer, Gegner, 2 Mutatoren, ein Ziel
(gewinnen / unter 60 s / ohne Stock-Verlust / allein gegen zwei), KI-Stufe 4–7.
Belohnung nach Serie: 120, 150, 180, 220, 260, 320, 500 Münzen (Tag 7 + Truhe).

13 Mutatoren: MONDSPRUNG (Schwerkraft × 0,45), TURBO (× 1,5 Tempo), GLASKANONEN (Schaden × 2),
SCHWERGEWICHTE (Rückstoß × 0,55), RIESEN (Größe 1,45, Kraft 1,25, Rückstoß 0,75), WINZLINGE (Größe 0,6, Rückstoß 1,35),
SUDDEN DEATH (Start 150 %), VOLLE KRAFT (volle Super-Leiste), BOMBENHAGEL, BLUTDURST (40 % Lebensraub,
auf Roblox umbenennen in **ENERGIEDURST**), PLATZTAUSCH (alle 15 s), ESKALATION (nach 60 s doppelter Schaden),
GESCHENKREGEN. „Riesen“ und „Winzlinge“ nie zusammen. Eigener Mutator-Modus in der Lobby („Chaos-Portal“).

### 8.8 Herausforderer
Nach einem gewonnenen Solo-Kampf erscheint mit 18 % Chance ein „HERAUSFORDERER!“ (stärkerer Bot, Extra-Belohnung).

### 8.9 Story (spätere Phase)
- **Legenden:** pro Kämpfer 4 Kapitel (Herkunft, Der Rivale, Der Abgrund, Legende), freigeschaltet über
  Meisterschafts-Sterne. Kapitel IV gibt die Reliquie (goldener Kartenrahmen, 400 Münzen).
- **Die göttliche Prüfung** (21 Kapitel: Erde → Hölle → Himmel, alle 19 Bosse) und
  **Der Riss zwischen den Welten** (12 Splitter, 9 Bündnisse, 3 Enden) als Koop-Kampagnen in Phase 7.

---

## 9. Progression (Werte aus `progression.gd` und `rewards.gd`)

- **Spielerlevel:** XP bis nächstes Level = `120 + (level-1) * 45`.
- **Ränge (Titel nach Level):** 1 REKRUT, 5 KÄMPFER, 10 VETERAN, 15 CHAMPION, 20 MEISTER, 30 GROSSMEISTER,
  40 LEGENDE, 50 MYTHOS.
- **Meisterschaft pro Kämpfer:** 1–5 Sterne bei 150 / 500 / 1200 / 2500 / 5000 Kämpfer-XP.
  Belohnungen pro Stern: Legenden-Kapitel, Siegerpose, Kartenrahmen, bei 5 Sternen ein Meister-Titel.
- **Tagesaufgaben:** 3 pro Tag aus 11 (z. B. „Gewinne 2 Kämpfe“ 120 XP, „Lande 60 Treffer“ 100 XP,
  „6er-Combo“ 110 XP, „1 Finisher“ 150 XP, „4 KOs“ 120 XP, „3 verschiedene Kämpfer“ 130 XP), alle drei = +200 XP.
- **Wochenaufgaben:** 3 aus 8, zahlen Münzen (200–400), alle drei = Gratis-Truhe.
- **Login-Kalender (7 Tage):** 50, 75, 100, 125, 150, 200, 300 Münzen; Tag 7 + Truhe; verpasster Tag = Neustart.
- **Spielserie:** Tage in Folge; **Comeback-Geschenk** nach 3+ Tagen Abwesenheit.
- **Ruhmespfad (Gratis-Spur):** alle 400 XP eine Stufe, 30 Stufen. Stufe 10 Schattenkatana, 15 Skin HIMMELSGLANZ,
  20 Drachenlanze, 30 Skin HÖLLENFÜRST, jede 5. Stufe Truhe, sonst `80 + stufe*10` Münzen.
- **Kampfnote:** S / A / B / C / D (Punkte ≥150 / 100 / 60 / 30 / sonst), Münz-Multiplikator 1,5 / 1,25 / 1,1 / 1,0 / 0,9.
- **Siegesserien**, **Erster Sieg des Tages** (Bonus), **Wochen-Events** (rotierend):
  DOPPEL-XP-WOCHE, GOLDRAUSCH (+50 % Münzen), MUTATOREN-FESTIVAL, WOCHE DER HERAUSFORDERER, LEGENDEN-WOCHE.
- **Erfolge (36):** übernimm die Liste aus der Vorlage (Erstes Blut, Aufsteiger, Arenaheld, Unbesiegbar, Vollstrecker,
  Henker, Kettenreaktion, Combo-Gott, Rausschmeißer, Makellos, Unberührbar, Waffennarr, Signatur-Künstler, Vielseitig,
  Sammler, Spezialist, Stammgast, Pflichtbewusst, Veteran, Dauerbrenner, Götterdämmerung, Himmelsstürmer, Goldliga,
  Champion, Stilikone, Unaufhaltsam, Chronist, Weltreise, Neue Gesichter, Rudelführer, Chaos-Liebhaber, Regelbrecher,
  Vollständige Sammlung …), jeweils als Roblox-**Badge** (`BadgeService`) für die wichtigsten 15, Rest im Spiel.
- **Truhen:** Die Vorlage hat Glücksrad und Zufallstruhen bewusst entfernt. Auf Roblox: Truhen geben das
  **nächste fehlende Item einer sichtbaren Liste** oder feste Münzen, **niemals Zufall gegen Robux**.

### 9.1 Kämpfer freischalten
- **10 Startkämpfer** (gratis): VOLT NINJA, MAGMOR, BOLTAR, KAIRO, JUBEI, ZIP, GLACIEM, CARDINAL, LEPORA, GRIMBOLT
  (deckt Rushdown, Schwergewicht, Allrounder, Schwert, Speed, Kontrolle, Verteidiger, Zoner, Fallen ab).
- Rest: durch Spielen (jeder 3. Sieg schaltet den nächsten frei) **oder** mit Münzen 600 / 900 / 1200 (nach Seltenheit)
  **oder** direkt per Developer Product (Abschnitt 10). Jeder Kämpfer ist **ohne Geld erreichbar**.

---

## 10. Monetarisierung (Roblox)

### 10.1 Grundsätze
1. **Kein Pay-to-Win.** Gekauftes verändert keine Kampfwerte. Kämpfer sind gleich stark, egal wie freigeschaltet.
2. **Keine bezahlten Zufallsitems** (keine Lootboxen, kein Glücksrad gegen Robux). Jeder Kauf zeigt genau, was drin ist.
3. **Kosmetik und Zeit sind das Produkt.** Spieler zahlen für Aussehen, Ausdruck, Status und Abkürzungen.
4. **Nur eine Spielwährung:** Münzen (erspielbar und kaufbar) plus direkte Robux-Käufe. Keine zweite Premium-Währung
   wie „Gems“: weniger Verwirrung für Spieler, leichter fair zu halten und zu prüfen.
5. Alle Preise in `Data/Products.luau`, Produkt-IDs aus dem Creator Dashboard dort eintragen (Platzhalter bis dahin).

### 10.2 Game Passes (einmalig, dauerhaft)

| Pass | Robux (Startwert) | Inhalt |
|---|---|---|
| VIP | 399 | Goldener Name + Chat-Tag, +1 Abstimmungsstimme, VIP-Bereich in der Lobby, 1 exklusive Siegerpose, +10 % Münzen |
| Doppelte Münzen | 349 | ×2 Münzen aus Kämpfen (verkürzt Freischalt-Zeit, kein Kampfvorteil) |
| Doppelte XP | 299 | ×2 Spieler- und Kämpfer-XP |
| Finisher-Kino Plus | 249 | Alternative Kamerafahrten und Effekte für alle Finisher, Finisher-Replay als teilbarer Clip |
| Waffenkammer | 299 | alle 8 Shop-Waffen (gilt nicht in Ranked) |
| Arena-Sammlung | 499 | alle 22 Zusatz-Arenen |
| Prompt-Labor Plus | 199 | 10 statt 3 gespeicherte Prompt-Kämpfer, Farbwahl, eigener Name auf der Karte, Aura-Stile |
| Private Server | 100/Monat | Roblox-Privatserver mit Mutator-, Waffen- und Bot-Einstellungen |

### 10.3 Developer Products (mehrfach kaufbar)

| Produkt | Robux | Inhalt |
|---|---|---|
| Münzbeutel S / M / L / XL | 49 / 149 / 399 / 899 | 500 / 1 700 / 5 000 / 12 000 Münzen (Bonus wächst mit Größe) |
| Startpaket (einmalig, erste 72 h) | 99 | 1 Kämpfer nach Wahl + 1 000 Münzen + Skin CHROM |
| Kämpfer sofort | 149 / 199 / 299 | einen gesperrten Kämpfer der Münz-Stufe 600 / 900 / 1200 direkt freischalten |
| Skin direkt | 99–449 | Skin aus dem Rotations-Shop |
| Kosmetik-Pakete | 299–599 | z. B. NEON-NÄCHTE (5 Arenen + 2 Skins), HIMMEL & HÖLLE (4 Skins + 2 Waffen) aus der Vorlage |
| Abenteuer-Rettung | 25 | einmal pro Lauf weiterspielen statt Neustart (nur Solo-Abenteuer); Lauf zählt danach nicht für die globale Bestenliste |
| Ruhmespfad Premium (pro Saison) | 499 | Premium-Spur, siehe 10.4 |
| Ruhmespfad Premium+ (pro Saison) | 899 | Premium + 15 Stufen (Preisanker) |
| Ruhmespfad +10 Stufen | 199 | Stufen überspringen |

### 10.4 Ruhmespfad als Season Pass (Hauptumsatz)
- Saison 8 Wochen, 50 Stufen. Gratis-Spur (Münzen, 2 Skins, Titel) + Premium-Spur (exklusive Skins, Finisher-Effekte,
  KO-Effekte, Siegerposen, Emotes, Kartenrahmen, Titel, Lobby-Spuren, 2 000 Münzen verteilt).
- Wer Premium kauft, bekommt **sofort** alles bis zur aktuellen Stufe (Kaufanreiz mitten in der Saison).
- Jede Saison ein Thema (z. B. „Himmelssturm“, „Höllenschmiede“), passend zu einem neuen Kämpfer oder Boss.

### 10.5 Roblox-Abo (Subscription)
„Arena-Gönner“ monatlich (Preisstufe ~ 4,99 €): täglich 150 Münzen, monatlich 1 exklusiver Skin, Abo-Rahmen, +1 Tagesaufgaben-Neuwurf.
Abo-Status über die Subscription-API prüfen und bei jedem Login neu lesen.

### 10.6 Was zusätzlich Geld bringt
- **Creator Rewards:** Die Premium Payouts wurden am 24.07.2025 durch Creator Rewards ersetzt (Robux für aktive,
  ausgebende und neu gewonnene Spieler). Premium-Spieler bekommen trotzdem +10 % XP (`Player.MembershipType`), damit sie bleiben.
- **Münz-Boni addieren sich** (VIP + Doppelte Münzen = ×2,1), Arena-Stimmen höchstens 3 pro Spieler.
- **Rotations-Shop:** täglich 4 Skins/Emotes, wöchentlich ein „Hervorgehobenes Set“ (Knappheit ohne Zufall).
- **Kosmetik-Kategorien:** Skins (Material-Looks aus der Vorlage: Gold, Chrom, Marmor, Smaragd, Frost, Obsidian,
  Neon, Schatten, Lava, Kristall, Geist, Galaxie, Himmelsglanz, Höllenfürst), KO-Effekte, Siegerposen, Emotes,
  Spuren (Trails), Kartenrahmen, Titel, Namensfarben, Ansager-Stimmen.
- **Avatar-Modus:** Spieler können einen freigeschalteten Kämpfer-Kit mit **eigenem Roblox-Avatar** spielen
  (Casual/Privat). Das macht das Spiel für Roblox-Spieler persönlich und verkauft Kosmetik weiter.
- **Rewarded Video Ads** (falls für die Experience verfügbar): freiwillig, z. B. +50 % Münzen nach einem Kampf.
  Nie Pflicht, nie mitten im Kampf.
- **Gruppen-Bonus:** wer der Roblox-Gruppe beitritt, bekommt einmalig 300 Münzen (über `GroupService` prüfen).
- **Freunde einladen:** `SocialService:PromptGameInvite`, Belohnung wenn ein eingeladener Freund ein Match beendet.

### 10.7 Kaufabwicklung (Pflicht)
- `MarketplaceService.ProcessReceipt` **idempotent**: Receipt-ID im Profil speichern, erst nach erfolgreichem
  Speichern `PurchaseGranted` zurückgeben, bei Fehler `NotProcessedYet`.
- Game-Pass-Besitz bei Join prüfen (`UserOwnsGamePassAsync`) und bei `PromptGamePassPurchaseFinished` aktualisieren.
- Jeder Kauf wird mit `AnalyticsService:LogEconomyEvent` geloggt.
- `PolicyService:GetPolicyInfoForPlayerAsync` prüfen (z. B. `ArePaidRandomItemsRestricted`, Werbung erlaubt) und
  Angebote danach ausblenden.
- Kaufdialog nur nach bewusster Spieleraktion, **kein Kauf-Popup nach einer Niederlage** und keine Fake-Countdowns.

### 10.8 Kennzahlen (in `docs/LIVEOPS.md` beobachten)
D1 / D7 / D30-Retention, durchschnittliche Sitzungsdauer, Anteil zahlender Spieler, Umsatz pro täglichem Spieler,
Funnel „Join → erstes Match → zweites Match → Tagesaufgabe“ (`LogFunnelStepEvent`), Münz-Zufluss/-Abfluss pro Tag.
Richtwerte, an denen du Entscheidungen festmachst: D1 ≥ 25 %, D7 ≥ 8 %, erstes Match < 60 s nach Join.

---

## 11. Steuerung und UI

| Aktion | PC | Gamepad | Touch |
|---|---|---|---|
| Bewegen | A/D bzw. Pfeile | linker Stick | virtueller Stick |
| Springen | W / Leertaste | A | Taste oder Stick hoch antippen |
| Angriff | J / linke Maus | X | Taste |
| Spezial | K / rechte Maus | B | Taste |
| Schild / Ausweichen | L / Shift | RB/LB | Taste |
| Greifen | U | Y | Taste |
| Smash | Richtung + Angriff halten | rechter Stick | Wischen + Angriff |

- **Mobile zuerst:** große Tasten, Daumenzonen, Auto-Aim leicht für Signaturen auf Touch, Vibration bei Treffern.
- Eingabehinweise passen sich dem Gerät an (Tastatur-, Pad- oder Touch-Symbole), auch bei Finisher-Codes.
- HUD: Prozent groß und farbig (weiß → gelb → rot), Stocks als Kämpfer-Icons, Super-Leiste, Signatur-Abklingzeit.
- Ergebnis-Bildschirm: Note, XP-Balken, Meisterschafts-Fortschritt, Tagesaufgaben-Fortschritt, „Nochmal“-Taste groß.
- Sprache: Deutsch und Englisch über `LocalizationService` (Tabellen als CSV im Repo), Englisch als Standard für
  internationale Reichweite.

---

## 12. Grafik, Animation, Audio

- Kämpfer: R15-Rig mit eigener, originaler Ausrüstung (MeshParts/Accessories), wie in der Vorlage „Körper + Ausrüstung
  im Code“. Pro Kämpfer eine Silhouette, die man auf dem Handy auf Entfernung erkennt.
- Animationen mit dem Animation Editor oder Moon Animator: Idle, Laufen, Rennen, Sprung, Fallen, 17 Angriffe,
  Treffer, Schild, Rolle, Kante, Würfe, Siegerpose, Niederlage. **Keine unkontrollierte Root Motion.**
- VFX: Trefferfunken in der Elementfarbe, Hit-Stop (40–80 ms je nach Stärke), Kamera-Shake, Zeitlupe beim letzten KO.
- Audio: nur eigene oder lizenzfreie Sounds aus der Roblox-Creator-Store-Bibliothek; Musik pro Arena; Ansager-Rufe
  („GAME!“, „HERAUSFORDERER!“).
- **Inhalts-Rating:** Fülle den Maturity & Compliance-Fragebogen ehrlich aus. Ziel: **„Mild“** (stilisierte Gewalt,
  kein Blut, keine Zerstückelung).

---

## 13. Phasenplan mit Abnahmekriterien

**Phase 0 – Grundgerüst**
Rojo-Projekt, Wally-Pakete (ProfileStore, Jest-Lua), Selene/StyLua, Ordnerstruktur, Daten-Module mit allen Tabellen
aus diesem Prompt, CI (GitHub Actions: Lint + Tests unter Lune).
*Abnahme:* `rojo build` erzeugt eine `.rbxl`, Tests laufen grün, Daten-Module laden ohne Fehler.

**Phase 1 – Kampfkern offline (Vertical Slice)**
Simulation (Bewegung, 17 Moves, Schild, Ausweichen, Kante, Griffe, Rückstoß, Stocks, Zeit, Sudden Death, Clash),
4 Kämpfer (VOLT NINJA, MAGMOR, JUBEI, LEPORA), 1 Arena (NEON-GASSE), Bots Stufe 1–9, HUD, Kamera.
*Abnahme:* 1 Spieler gegen 3 Bots in Studio spielbar, 60 FPS auf Handy-Emulation, Tests für Knockback, Schaden, KO,
Kante, Schildbruch, Bot-Eingaben gleich wie Spieler-Eingaben.

**Phase 2 – Multiplayer**
Server-autoritativer Kampf, Eingabe-Replikation, Vorhersage/Interpolation, Lobby-Hub, Schnellkampf-Matchmaking,
reservierte Match-Server, Rückkehr in die Lobby.
*Abnahme:* 4 echte Spieler (Studio „Local Server“ mit 4 Clients) ohne Desync; bei 150 ms simuliertem Ping spielbar;
Remote-Spam wird abgewiesen.

**Phase 3 – Daten und Progression**
ProfileStore, Level, Ränge, Meisterschaft, Tages-/Wochenaufgaben, Login-Kalender, Ruhmespfad (gratis), Erfolge/Badges,
Kampfnote, Münzen, Freischalten von Kämpfern/Arenen/Waffen/Skins mit Münzen.
*Abnahme:* Fortschritt bleibt nach Rejoin erhalten; Tests für alle Formeln aus Abschnitt 9; Server-Abbruch verliert keine Daten.

**Phase 4 – Shop und Monetarisierung**
Shop-UI, Game Passes, Developer Products, ProcessReceipt, Season Pass, Rotations-Shop, Startpaket, Abo, Analytics.
*Abnahme:* Testkäufe in Studio werden genau einmal gutgeschrieben (auch bei doppeltem Callback); Wirtschaft in
`docs/ECONOMY.md` mit Zu- und Abfluss pro Tag für Gratis- und Zahlspieler berechnet.

**Phase 5 – Inhalt hochfahren**
Alle 58 Kämpfer mit Signatur und Finisher, alle 23 Arenen, alle Waffen, Mutatoren, Tages-Herausforderung,
Herausforderer, Ranked mit Ligen, Prompt-Kämpfer mit Textfilter.
*Abnahme:* Test pro Kämpfer: Kit lädt, Signatur trifft, Finisher-Code löst aus; Balance-Lauf (Bot gegen Bot,
je 200 Kämpfe pro Paarung) ohne Kämpfer über 60 % Siegquote.

**Phase 6 – Boss-Raid und Abenteuer**
19 Bosse mit zwei Phasen, Koop-Skalierung, Abenteuer-Wellen, Bestenlisten.
*Abnahme:* jeder Boss in Koop und solo besiegbar; Bestenlisten aktualisieren sich.

**Phase 7 – Live-Ops und Story**
Wochen-Events, Saison-System, Legenden-Kapitel, Story-Kampagnen, Lokalisierung DE/EN, Onboarding-Tutorial
(erste 3 Minuten geführt: Bewegen, Angriff, Spezial, KO).
*Abnahme:* neuer Spieler schafft Tutorial und erstes Match in unter 3 Minuten; Event wechselt automatisch nach Datum.

**Phase 8 – Launch-Checkliste**
Icon und Thumbnails, Beschreibung DE/EN, Maturity-Fragebogen, Preise final, Gruppe, Badges, Discord-Link (falls
erlaubt), Fehler-Logging, Soft-Launch mit kleinem Werbebudget (Sponsored Experience) und Messung der Kennzahlen aus 10.8.

---

## 14. Berichtsformat pro Phase

Am Ende jeder Phase antwortest du mit:
1. **Gebaut:** Liste der Features mit Dateipfaden.
2. **Getestet:** Testbefehl + Ergebnis (Anzahl grün/rot).
3. **Abweichungen** von diesem Prompt und warum.
4. **Offen / nächste Phase.**
5. **Was ich (der Mensch) tun muss:** z. B. Produkt-IDs anlegen, Game Pass Icons hochladen, Studio-Test durchführen.

Beginne jetzt mit **Phase 0**.

## 15. Growth (ergänzt 2026-10-17)

Viralität ist ein Feature, kein Marketing-Nachgedanke. Details in `docs/GROWTH.md`:
Prompt-Terminal als erster Bildschirm, garantierter Finisher in der ersten Minute, Clip-Knopf über die Captures-API,
Prompt-Codes zum Teilen, Launch mit 16 Kämpfern und danach ein neuer Kämpfer pro Woche.

<!-- ============================== PROMPT ENDE ============================== -->
