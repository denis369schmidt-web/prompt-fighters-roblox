#!/usr/bin/env bash
# Renders preview images of arenas, the lobby and the fighter roster into an output folder.
#   scripts/preview/shots.sh <out-dir> [arenaId ...]     (no ids: every arena, plus a contact sheet)
#   SKIP_LOBBY=1 / SKIP_FIGHTERS=1 skip those shots.
# Needs: lune (~/tools/bin), node, `npm i` in scripts/preview, Chromium (CHROMIUM_PATH or Playwright's),
# ImageMagick `montage` for the contact sheet (optional).
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$1"; shift
mkdir -p "$out"
LUNE="${LUNE:-$HOME/tools/bin/lune}"
ids=("$@")
all=0
if [ ${#ids[@]} -eq 0 ]; then
	all=1
	mapfile -t ids < <(grep -o '{ id = "[a-z_]*"' src/ReplicatedStorage/Shared/Data/Arenas.luau | cut -d'"' -f2)
fi
# Fight camera as in CameraController: focus 1.6 m above the stage, eye a bit above and in front.
for id in "${ids[@]}"; do
	"$LUNE" run scripts/export-scene.luau arena "$id" "$out/$id.json" >/dev/null
	node scripts/preview/render.mjs "$out/$id.json" "$out/arena_$id.png" --eye 0,70,48 --look 0,65,0 --fov 40 >/dev/null
	rm "$out/$id.json"
	echo "arena_$id.png"
done
if [ "$all" = 1 ] && command -v montage >/dev/null; then
	tiles=()
	for id in "${ids[@]}"; do tiles+=(-label "$id" "$out/arena_$id.png"); done
	montage "${tiles[@]}" -tile 4x -geometry 480x270+0+0 -background black -fill white -pointsize 12 \
		-gravity northwest -depth 8 "PNG24:$out/alle_arenen.png"
	echo alle_arenen.png
fi
if [ -z "${SKIP_LOBBY:-}" ]; then
	"$LUNE" run scripts/export-scene.luau lobby "$out/lobby.json" >/dev/null
	# Walking in from the spawn, and from high above (wayfinding has to read from there too).
	node scripts/preview/render.mjs "$out/lobby.json" "$out/lobby.png" --eye 0,62,1510 --look 0,24,1385 --fov 55 >/dev/null
	node scripts/preview/render.mjs "$out/lobby.json" "$out/lobby_top.png" --eye 0,230,1520 --look 0,20,1395 --fov 50 >/dev/null
	node scripts/preview/render.mjs "$out/lobby.json" "$out/lobby_showcase.png" --eye 22,34,1432 --look 0,28,1398 --fov 50 >/dev/null
	rm "$out/lobby.json"
	echo lobby.png lobby_top.png lobby_showcase.png
fi
if [ -z "${SKIP_FIGHTERS:-}" ]; then
	"$LUNE" run scripts/export-scene.luau fighters "$out/fighters.json" >/dev/null
	node scripts/preview/render.mjs "$out/fighters.json" "$out/fighters.png" --eye 0,9,-50 --look 0,4.5,6 --fov 34 --size 1600x800 >/dev/null
	rm "$out/fighters.json"
	echo fighters.png
fi
