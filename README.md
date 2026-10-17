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
| Lint | `selene src tests scripts` |
| Place bauen | `rojo build -o build/PromptFighters.rbxl` und `lune run scripts/check-build.luau` |
| Live-Sync nach Studio | `rojo serve`, dann im Rojo-Plugin in Studio „Connect“ |
| Godot-Werte neu importieren | `python3 tools/import_godot.py <Godot-Repo>/godot/scripts`, danach `stylua src` |

CI (`.github/workflows/ci.yml`) führt Format, Lint, Tests, Build und Build-Prüfung bei jedem Push aus.

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
