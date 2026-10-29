#!/usr/bin/env bash
# test_spawn_guard_visual.sh — TASK 40 (regressione: "quando il player muore
# non si vede lampeggiare il player ma soltanto l'arma"): verifica che il
# CORPO del player lampeggi visibilmente durante la guardia di nascita.
#
# Sostituisce test_spawn_guard_visual.gd/.tscn: il vecchio test campionava
# il viewport con get_image() agganciato alle fasi ON/OFF del modulate, ma
# sotto llvmpipe/Xvfb il rendering interattivo scorre a ~8-15 fps effettivi
# con frame completati in ritardo rispetto alla fisica: il campionamento
# mischiava frame ON e OFF e il test falliva anche a gioco perfetto (2 dei
# 2 fallimenti "pre-esistenti" della suite). Questa pipeline usa
# --write-movie (frame deterministici, stessa pipeline degli screenshot di
# verifica dei task 84-91) + analisi Python della serie temporale.
#
# Uso: test_spawn_guard_visual.sh
# Exit 0 = PASS. Richiede: Godot 4.7.2, Xvfb, python3 + Pillow.
set -u

GODOT="${GODOT_BIN:-/tmp/my-project/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../ArcadeMaze/scripts
PROJECT="$(dirname "$HERE")/godot"
OUT_DIR="/tmp/spawn_blink_movie"
FPS=30
FRAMES=150

export DISPLAY=":66"
pkill -f "Xvfb :66" 2>/dev/null
rm -f /tmp/.X66-lock /tmp/.X11-unix/X66 2>/dev/null
Xvfb :66 -screen 0 1920x1080x24 -nolisten tcp &
XVFB_PID=$!
sleep 1

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"$GODOT" --path "$PROJECT" res://tests/shot_spawn_blink.tscn \
    --resolution 1920x1080 \
    --write-movie "$OUT_DIR/frame.png" \
    --fixed-fps "$FPS" \
    --quit-after "$FRAMES" > "$OUT_DIR/run.log" 2>&1
RC_GODOT=$?

kill $XVFB_PID 2>/dev/null
pkill -f "Xvfb :66" 2>/dev/null

if [ $RC_GODOT -ne 0 ]; then
    echo "[TEST FAIL] run Godot movie fallita (rc=$RC_GODOT), vedi $OUT_DIR/run.log"
    exit 1
fi

python3 "$HERE/spawn_blink_analyze.py" "$OUT_DIR" /tmp/spawn_blink_meta.txt
exit $?
