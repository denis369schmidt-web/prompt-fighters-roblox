# Prompt Fighters (Roblox)

Plattform-Kampfspiel im Stil von Smash Bros. für Roblox: 58 Kämpfer, Signatur-Spezialangriffe, Finisher-Codes,
Bosse, Mutatoren und **Prompt-Kämpfer** (ein Satz Text wird zu einem spielbaren Kämpfer).
Vorlage ist das Godot-Projekt `denis369schmidt-web/Ultimate-Prompt-Fighters` (`main` @ `8d6e9ba`).

**Stand:** Phase 0 (Grundgerüst) fertig. Siehe `docs/CHANGELOG.md`.

## Start

Werkzeuge über [Rokit](https://github.com/rojo-rbx/rokit):

```sh
rokit install           # rojo, lune, selene, stylua, wally (Versionen in rokit.toml)
```

| Aufgabe | Befehl |
|---|---|
| Tests (headless) | `lune run tests/run.luau` (Filter: `lune run tests/run.luau knockback`) |
| Format prüfen | `stylua --check src tests scripts` |
| Lint | `selene src` und `selene --config selene.lune.toml tests scripts` |
| Typprüfung | `rojo sourcemap -o sourcemap.json` und `luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src` |
| Place bauen | `rojo build -o build/PromptFighters.rbxl` und `lune run scripts/check-build.luau` |
| Live-Sync nach Studio | `rojo serve`, dann im Rojo-Plugin in Studio „Connect“ |
| Godot-Werte neu importieren | `python3 tools/import_godot.py <Godot-Repo>/godot/scripts`, danach `stylua src` |

CI (`.github/workflows/ci.yml`) führt Format, Lint, Typprüfung, Tests, Build und Build-Prüfung bei jedem Push aus.

## Anspielen (Phase 1)

1. `rojo build -o build/PromptFighters.rbxl` und die Datei in Studio öffnen (oder `rojo serve` + Plugin).
2. **Play** drücken, einen der vier Kämpfer wählen. Nach 6 s startet ein Match gegen Bots.
3. Mehrspieler testen: Test → Clients and Servers → 2 bis 4 Spieler.

| Aktion | Tastatur | Gamepad | Touch |
|---|---|---|---|
| Laufen | A/D, Pfeile | linker Stick | linke Bildschirmhälfte (Stick) |
| Hoch / runter | W / S | Stick | Stick |
| Springen | Leertaste | A | SPRUNG |
| Angriff (halten = aufladen) | J | X | ANGRIFF |
| Spezial | K | B | SPEZIAL |
| Schild (+ Richtung = Ausweichen) | L oder Shift | L1/R1 | SCHILD |
| Greifen | U | R2 | GREIFEN |
| Smash | I | rechter Stick | SMASH |

## Ordner

```
src/ReplicatedStorage/Shared/
  Data/            reine Daten: Fighters, Roster, Weapons, Arenas, Bosses, Mutators, Products, Progression, Ranks
  Data/Generated/  aus Godot importiert (nicht von Hand ändern)
  Combat/          reine Kampfmathematik (Knockback)
  Net/             Remote-Definitionen mit Rate-Limit und Argument-Schema
  Util/            Seed (Prompt- und Tages-Seeds, identisch zu Godot)
src/ServerScriptService/   Server-Einstieg (Services ab Phase 1)
src/StarterPlayer/...      Client-Einstieg (Controller ab Phase 1)
tests/             *.spec.luau + Runner für Lune
tools/             Godot-Importer
docs/              Architektur, Entscheidungen, Economy, Growth, Live-Ops, Lizenzen
```
