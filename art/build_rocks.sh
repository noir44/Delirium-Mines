#!/bin/sh
# Renders the four rocks (2 kinds x 2 facings) from the Meshy models and cuts
# them into the 36 frames, then the tile pack is built from art/tiles.json:
#   powershell -File E:\mods\tools\TilePack\build-tilepack.ps1 -Spec tiles.json -Media <mod>\42\media
# Models: meshy/quarry2.glb, meshy/mine2.glb (from concept/quarry2.png and
# mine2.png, the user's concepts of 2026-11-02). Args after the prefix:
# yaw, footprint, max height, z stretch (the mine model comes out flat).
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
A="E:/mods/Delirium-Mines/art"
for f in S:0 E:90; do
	"$B" --background --factory-startup --python "$A/render_rock.py" -- "$A/meshy/quarry2.glb" ${f#*:} "$A/raw/quarry_${f%%:*}" 0 2.9 2.7 1.0 2>&1 | grep -E "FIT|Error"
	"$B" --background --factory-startup --python "$A/render_rock.py" -- "$A/meshy/mine2.glb" ${f#*:} "$A/raw/mine_${f%%:*}" 0 2.9 2.7 1.6 2>&1 | grep -E "FIT|Error"
done
python "$A/cut_rock.py"
