#!/usr/bin/env bash
# Renders preview images of arenas, the lobby and the fighter roster into an output folder.
#   scripts/preview/shots.sh <out-dir> [arenaId ...]     (no ids: every arena)
# Needs: lune (~/tools/bin), node, `npm i` in scripts/preview, Chromium (CHROMIUM_PATH or Playwright's).
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$1"; shift
mkdir -p "$out"
LUNE="${LUNE:-$HOME/tools/bin/lune}"
ids=("$@")
if [ ${#ids[@]} -eq 0 ]; then
	mapfile -t ids < <(grep -o '{ id = "[a-z_]*"' src/ReplicatedStorage/Shared/Data/Arenas.luau | cut -d'"' -f2)
fi
# Fight camera as in CameraController: focus 1.6 m above the stage, eye a bit above and in front.
for id in "${ids[@]}"; do
	"$LUNE" run scripts/export-scene.luau arena "$id" "$out/$id.json" >/dev/null
	node scripts/preview/render.mjs "$out/$id.json" "$out/arena_$id.png" --eye 0,70,48 --look 0,65,0 --fov 40 >/dev/null
	rm "$out/$id.json"
	echo "arena_$id.png"
done
"$LUNE" run scripts/export-scene.luau lobby "$out/lobby.json" >/dev/null
node scripts/preview/render.mjs "$out/lobby.json" "$out/lobby.png" --eye 0,62,1490 --look 0,22,1360 --fov 55 >/dev/null
rm "$out/lobby.json"
echo lobby.png
"$LUNE" run scripts/export-scene.luau fighters "$out/fighters.json" >/dev/null
node scripts/preview/render.mjs "$out/fighters.json" "$out/fighters.png" --eye 0,9,-50 --look 0,4.5,6 --fov 34 --size 1600x800 >/dev/null
rm "$out/fighters.json"
echo fighters.png
