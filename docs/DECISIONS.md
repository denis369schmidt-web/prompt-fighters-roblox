# Entscheidungen

Format: Datum, Entscheidung, Grund. Umkehrbare Standardentscheidungen, die ohne Rückfrage getroffen wurden.

| Datum | Entscheidung | Grund |
|---|---|---|
| 2026-10-17 | Kampf-, Signatur-, Boss-, Waffen- und Fortschrittswerte werden per `tools/import_godot.py` aus dem Godot-Repo erzeugt statt abgetippt. | Eine Quelle der Wahrheit, keine Tippfehler bei ~260 KB Werten; erneuter Import nach Godot-Änderungen in Sekunden. |
| 2026-10-17 | Eigener kleiner Test-Runner unter Lune (`tests/run.luau`) statt Jest-Lua. | Jest-Lua braucht eine Roblox-Laufzeit; unter Lune wäre dafür ein großer Shim nötig. Die Matcher sind Jest-kompatibel, ein Wechsel bleibt billig. |
| 2026-10-17 | Spielcode nutzt `require(script.Parent.X)`; der Test-Loader bildet Instanzen nach. | Idiomatischer Roblox-Code, kein Umbau für Studio nötig. |
| 2026-10-17 | Wally-Pakete (ProfileStore) sind deklariert, aber erst ab Phase 3 installiert; Rojo bindet `Packages` optional ein. | Phase 0 braucht keine Pakete; Paketname und Version beim ersten `wally install` prüfen. |
| 2026-10-17 | Freischaltpreise der 48 gesperrten Kämpfer: in Roster-Reihenfolge je 16 zu 600, 900 und 1200 Münzen. | Spec nennt die Stufen, aber keine Zuordnung. Später nach Beliebtheit neu sortieren. |
| 2026-10-17 | Boss-Lebenspunkte skalieren wie in Godot: `hp * (0.5 + 0.25 * Spieler)`. | Godot-Werte sind auf 2 Spieler abgestimmt. |
| 2026-10-17 | Lebenspunkte für Boss/Abenteuer = `90 + Vitalität * 1.6` (Godot). Vorruk landet bei 141,2 statt der in der Spec genannten Obergrenze 138. | Godot-Daten sind die Quelle; Spec-Wert war gerundet. |
| 2026-10-17 | Münz-Boni (VIP, Doppelte Münzen, Events, Abo) werden addiert, nicht multipliziert (`Progression.matchCoins`). | Gestapelte Pässe bleiben berechenbar, die Wirtschaft kippt nicht. |
| 2026-10-17 | Abstimmungsgewicht für Arenen höchstens 3 (1 + Besitz + VIP). | Spec nennt zwei Extrastimmen-Quellen; ohne Deckel könnten Zahler jede Wahl bestimmen. |
| 2026-10-17 | Mutator BLUTDURST heißt auf Roblox ENERGIEDURST, Text ohne Blut. | Inhalts-Rating „Mild“. |
| 2026-10-17 | 15 Kämpfer tragen `ipReview` in `Roster.luau`. | Godot-IDs zeigen, dass sie von bekannten Marken abgeleitet sind (siehe `docs/ASSET_LICENSES.md`). Neugestaltung vor Launch. |
| 2026-10-17 | Abenteuer-Läufe mit gekaufter Rettung zählen nicht für die globale Bestenliste. | Sonst kauft man sich einen Platz in der Bestenliste (Pay-to-Win über die Hintertür). |
| 2026-10-17 | „Premium Payouts“ aus der Spec ersetzt durch **Creator Rewards**. | Roblox hat Engagement-Based Payouts am 24.07.2025 abgeschaltet (siehe `roblox/roadmap.md`). |
| 2026-10-17 | Treffer-Rückstoß nutzt die Godot-Angriffsformel (`Knockback.attack`), nicht die Explosionsformel aus Spec 4.4. | Spec 4.4 ist in Godot nur die Explosionsformel; Angriffe rechnen anders. Godot ist die Quelle. |
| 2026-10-17 | Finisher wie in Godot: Letzter Stock verloren → 5 s Finish-Phase, Code innerhalb von 2 s eingeben. | Godot-Verhalten, getestet in `Simulation.spec`. Bildschirmtext „FINISHER!“ (eigene Formulierung, keine fremden Spielzitate). |
| 2026-10-17 | Respawn-Unverwundbarkeit 2,0 s (Spec), Sudden Death bei Gleichstand: 150 % und 1 Leben (Spec). | Spec-Werte. |
| 2026-10-17 | Signatur-Mechaniken, Items, Projektile, Gefahren, Mutatoren und Bosse kommen in späteren Phasen; Neutral-Spezial nutzt bis dahin den Basis-Spezialangriff. | Vertical Slice zuerst spielbar machen. |
| 2026-10-17 | Vertical Slice: 1 bis 4 Spieler, freie Plätze füllen Bots (Stufe 4), 4 Kämpfer (VOLT NINJA, MAGMOR, JUBEI, LEPORA), Arena NEON-GASSE. | 4er-Chaos ist auf Roblox unterhaltsamer und clip-tauglicher als 1-gegen-1; leere Server fühlen sich nie leer an. |
| 2026-10-17 | Snapshots 30/s per `UnreliableRemoteEvent`, Ereignisse zuverlässig; Client glättet Positionen. | Hält Bandbreite klein (Payload unter 900 Byte), verlorene Snapshots stören nicht. |
| 2026-10-17 | Tastendrücke werden pro Tick gelatcht (`MatchRunner`). | Paket- und Tick-Takt sind nie synchron; ohne Latch gehen Sprünge verloren oder doppeln sich. |
| 2026-10-17 | Spielfiguren in Phase 1 sind Platzhalter-Blöcke in Elementfarbe. | Eigene Modelle und Animationen kommen in Phase 4; Schnittstelle von `FighterView` bleibt gleich. |
| 2026-10-20 | `StreamingEnabled = false`. | Das Spiel nutzt keine Roblox-Spielfigur; mit Streaming kam die Arena nie beim Client an (erster Studio-Test). Die Arena ist klein genug für volles Laden. |
| 2026-10-20 | Grafik vor Multiplayer gezogen (Entscheidung des Nutzers). Kämpfer sind R15-Figuren aus `HumanoidDescription` plus Ausrüstung aus einfachen Parts (`Data/Looks`, `World/RigFactory`). | Lesbare Figuren für Tests und erste Clips; keine Katalog- oder Fremd-Assets, also keine Lizenzfragen. |
| 2026-10-20 | Animation prozedural (`Visual/Pose` setzt Gelenkwinkel), keine Animations-Assets. | Funktioniert sofort ohne hochgeladene Animationen, ist testbar und folgt exakt dem Simulationszustand. Echte Keyframe-Animationen können später pro Move ergänzt werden. |
| 2026-10-20 | Lighting `Future`, Atmosphäre, Bloom, Farbkorrektur, Regen auf NEON-GASSE. | Neon-Look für Thumbnails und Clips. |
| 2026-10-20 | Figuren aus eigenen Parts statt `CreateHumanoidModelFromDescription` (`Visual/RigBuilder`, baut jeder Client selbst). | Im unveröffentlichten Studio-Ort konnte Roblox die R15-Meshes nicht laden („Wrap-deformer … error“), die Figuren waren unsichtbar. Parts brauchen keinen Asset-Abruf und sind headless testbar. |
| 2026-10-20 | Projektil-Positionen über eigenes Unreliable-Remote `Shots` (flach `id, x, y, Größe`, höchstens 24), Entstehen und Ende über `MatchEvent`. | Hält den Fighter-Snapshot unter 900 Byte, auch wenn Pfeilregen und Geschütze gleichzeitig laufen. |
| 2026-10-20 | Signaturen bekommen im Snapshot ihren Mechanik-Namen als Move (`Pose.MOVE_KIND` ordnet ihn einer Körperhaltung zu). | Der Client zeigt die passende Pose (Wurf, Sprung, Drehung) ohne eigene Netzwerkfelder. |
| 2026-10-20 | Ein Spezial-Druck während der Erholung eines Angriffs verfällt (wie in Godot). Die Kombo-Fenster der Folgeangriffe sind lang genug. | Gleiches Spielgefühl wie das Original; Eingabepuffer kann später global kommen. |
| 2026-10-20 | Einfrieren hält Treffer-Stun mindestens so lange wie das Eis und sperrt alle Eingaben. | Godot setzt Tempo auf 0 und blockiert Angriffe; so ist es ein einziger Zustand. |
| 2026-10-20 | Power-ups kürzer als in Godot: Schutzstern 6 s (statt 10), Titan 12 s (15), Tempo 10 s (12), Hammer 10 s (12). Herz heilt 30 % statt 60 LP. | Mit 4 Spielern liegt ein Power-up sonst zu lange beim selben Spieler; Roblox-Kämpfe zählen Prozent, keine Lebenspunkte. |
| 2026-10-20 | Startitems nur Wurfobjekte (Kiste, Stein, Fass, Explosiv-Fass); Power-ups fallen erst im Match. | Ein Schutzstern zum Start entscheidet sonst die ersten Sekunden. |
| 2026-10-20 | Items über eigenes Unreliable-Remote `Items` mit 10 Hz (`id, Art, x, y, Halter`). | Items bewegen sich selten; hält Snapshot und Shots klein. |
| 2026-10-20 | Im Match fallen nur klassische Waffen. Shop-Waffen bleiben außen vor, bis Besitz und Modus (nicht Ranked) geprüft werden (Phase Shop). | Kein Pay-to-Win in normalen Matches. |
