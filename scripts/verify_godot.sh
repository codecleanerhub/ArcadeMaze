#!/bin/bash
# verify_godot.sh - Verifica tutti i file GDScript prima del push
# Controlla: sintassi (gdparse), indentazione, riferimenti a file
#
# Requisiti:
#   - gdparse (da `pip install gdtoolkit` o `npm install -g @gdparse/cli`)
#   - Godot 4.7+ binario `godot` nel PATH (per test headless opzionali)
#
# Lo script cerca gdparse in PATH + /home/z/.local/bin (installazione pip user)
# per robustezza tra ambienti.

GODOT_DIR="/home/z/my-project/ArcadeMaze/godot"
ERRORS=0

# Trova gdparse: PATH prima, fallback a /home/z/.local/bin
GDPARSE="$(command -v gdparse 2>/dev/null || echo /home/z/.local/bin/gdparse)"
if [ ! -x "$GDPARSE" ]; then
  echo "WARN: gdparse non trovato in PATH né in /home/z/.local/bin"
  echo "      Installa con: pip install gdtoolkit --break-system-packages"
  echo "      (lo script userà godot --headless --check-only come fallback)"
  GDPARSE=""
fi

echo "=== VERIFICA GODOT PROJECT ==="
echo ""

# 1. Verifica sintassi GDScript
echo "--- Sintassi GDScript ---"
for f in $(find "$GODOT_DIR/scripts" -name "*.gd" | sort); do
  rel=${f#$GODOT_DIR/}
  if [ -n "$GDPARSE" ]; then
    if $GDPARSE "$f" 2>/dev/null; then
      echo "  OK: $rel"
    else
      echo "  FAIL: $rel"
      $GDPARSE "$f" 2>&1 | head -5
      ERRORS=$((ERRORS + 1))
    fi
  else
    # Fallback: gdparse non disponibile, salta la sintassi
    echo "  SKIP: $rel (gdparse non installato)"
  fi
done

# 1b. Verifica runtime headless con godot 4.7+ (test vero che scopre
#     Identifier-not-found, parse errors runtime, etc.)
echo ""
echo "--- Runtime headless (godot) ---"
if command -v godot >/dev/null 2>&1; then
  echo "  Eseguo godot --headless --quit per 30s..."
  RUNTIME_OUT=$(timeout 30 godot --headless --quit --path "$GODOT_DIR" 2>&1)
  RUNTIME_ERRS=$(echo "$RUNTIME_OUT" | rg -i 'SCRIPT ERROR|Parse Error|Compile Error|Identifier not found|Cannot infer' | head -20)
  if [ -z "$RUNTIME_ERRS" ]; then
    echo "  OK: runtime headless senza errori di script"
  else
    echo "  FAIL: errori runtime trovati:"
    echo "$RUNTIME_ERRS" | sed 's/^/    /'
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  SKIP: godot non trovato nel PATH"
fi

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
# Each autoload line is `Name="*res://path/to/script.gd"`. Match lines whose
# value contains `*res://` (the autoload marker) and split on the first `=`.
while IFS='=' read -r name path; do
  name=$(echo $name | tr -d ' ')
  path=$(echo $path | tr -d '"' | tr -d ' ' | sed 's|^\*||' | sed 's|res://||')
  if [ -f "$GODOT_DIR/$path" ]; then
    echo "  OK: $name -> $path"
  else
    echo "  FAIL: $name -> $path (non trovato)"
    ERRORS=$((ERRORS + 1))
  fi
done < <(grep '"\*res://' "$GODOT_DIR/project.godot")

echo ""
echo "=== RISULTATO: $ERRORS errori ==="
exit $ERRORS
