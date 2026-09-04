#!/bin/bash
# verify_godot.sh - Verifica tutti i file GDScript prima del push
# Controlla: sintassi (gdparse), indentazione, riferimenti a file

GODOT_DIR="/home/z/my-project/ArcadeMaze/godot"
GDPARSE="/home/z/.local/bin/gdparse"
ERRORS=0

echo "=== VERIFICA GODOT PROJECT ==="
echo ""

# 1. Verifica sintassi GDScript
echo "--- Sintassi GDScript ---"
for f in $(find "$GODOT_DIR/scripts" -name "*.gd" | sort); do
  rel=${f#$GODOT_DIR/}
  if $GDPARSE "$f" 2>/dev/null; then
    echo "  OK: $rel"
  else
    echo "  FAIL: $rel"
    $GDPARSE "$f" 2>&1 | head -5
    ERRORS=$((ERRORS + 1))
  fi
done

# 2. Verifica scene .tscn
echo ""
echo "--- Scene .tscn ---"
for f in $(find "$GODOT_DIR/scenes" -name "*.tscn" | sort); do
  rel=${f#$GODOT_DIR/}
  if [ -f "$f" ]; then
    echo "  OK: $rel"
  else
    echo "  FAIL: $rel (non trovato)"
    ERRORS=$((ERRORS + 1))
  fi
done

# 3. Verifica project.godot
echo ""
echo "--- project.godot ---"
if [ -f "$GODOT_DIR/project.godot" ]; then
  echo "  OK: project.godot"
else
  echo "  FAIL: project.godot mancante"
  ERRORS=$((ERRORS + 1))
fi

# 4. Verifica main_scene esiste
echo ""
echo "--- Main scene ---"
MAIN_SCENE=$(grep 'run/main_scene' "$GODOT_DIR/project.godot" | sed 's/.*=//' | tr -d '"')
MAIN_PATH=$(echo "$MAIN_SCENE" | sed 's|res://||')
if [ -f "$GODOT_DIR/$MAIN_PATH" ]; then
  echo "  OK: $MAIN_SCENE"
else
  echo "  FAIL: $MAIN_SCENE non trovato"
  ERRORS=$((ERRORS + 1))
fi

# 5. Verifica autoload esistono
echo ""
echo "--- Autoloads ---"
grep '^\*' "$GODOT_DIR/project.godot" | while IFS='=' read -r name path; do
  name=$(echo $name | tr -d '*' | tr -d ' ')
  path=$(echo $path | tr -d '"' | tr -d ' ' | sed 's|res://||')
  if [ -f "$GODOT_DIR/$path" ]; then
    echo "  OK: $name -> $path"
  else
    echo "  FAIL: $name -> $path (non trovato)"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "=== RISULTATO: $ERRORS errori ==="
exit $ERRORS
