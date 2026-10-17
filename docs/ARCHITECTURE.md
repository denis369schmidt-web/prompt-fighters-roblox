# Architektur

## Grundsätze

1. **Server-autoritativ.** Der Server simuliert den Kampf mit 60 Hz. Clients schicken nur Eingaben
   (`Net/Remotes.luau`: Bitmaske, Stick, Sequenznummer). Käufe, Belohnungen und Treffer entscheidet nur der Server.
2. **Daten getrennt von Logik.** Alles Spielbare steht in `Shared/Data`. Logik liest nur über diese Module
   (`Fighters.get(id)`, `Weapons.spawnPool(mode, owned)` …). Ein neuer Kämpfer = ein Eintrag in `Roster.luau`
   plus seine Werte im Godot-Import (oder ein Handeintrag, sobald Godot nicht mehr die Quelle ist).
3. **Reine Logik ist testbar.** Module in `Shared/Combat`, `Shared/Util` und die Formeln in `Data/Progression`
   benutzen keine Instanzen und laufen headless unter Lune.

## Datenfluss

```
Godot-Repo (*.gd) ──tools/import_godot.py──▶ Data/Generated/*.luau
                                                   │
Data/Roster.luau (Namen, Freischaltung, IP-Check) ─┴─▶ Data/Fighters.luau ──▶ Combat / Services / UI
```

Der Importer liest nur Dictionary-Literale aus den `.gd`-Dateien (er führt nichts aus) und lässt Felder weg,
die auf Godot-Assets zeigen (`body`, `model`, `look`, `pose`, `variant`), weil diese Assets nicht für Roblox lizenziert sind.

## Tests ohne Studio

`tests/runtime/Loader.luau` bildet Rojos Dateizuordnung nach (`Foo.luau` → ModuleScript, Ordner → Folder,
`init.luau` → Modul mit Kindern) und gibt jedem Modul ein eigenes `script`. Dadurch bleibt der Spielcode im normalen
Roblox-Stil (`require(script.Parent.X)`) und läuft trotzdem unter Lune. `tests/runtime/Expect.luau` bietet
Jest-kompatible Matcher, damit ein späterer Wechsel zu Jest-Lua keine Specs umschreibt.

## Einheiten

Godot rechnet in Metern. `Constants.METER = 3.57` Studs. Die Kampfsimulation rechnet intern weiter in Metern
(so bleiben alle Godot-Werte und Tests vergleichbar) und rechnet erst bei der Darstellung in Studs um.

## Geplante Services (ab Phase 1)

Server: MatchService, MatchmakingService, CombatService, DataService (ProfileStore), ShopService, ReceiptService,
ProgressionService, QuestService, EventService, AnalyticsService, ModerationService (Textfilter), BotService.
Client: InputController, CameraController, HUDController, VFXController, AudioController, ShopUIController, LobbyUIController.
