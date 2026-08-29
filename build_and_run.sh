#!/bin/bash
# ===========================================================================
# build_and_run.sh - Script cross-platform per compilare ed eseguire il gioco
#
# Supporta:
#   * Linux (gcc + SFML system-install)
#   * Windows con Git Bash (MinGW o MSVC + vcpkg)
#   * macOS (clang + SFML Homebrew)
#
# Rileva automaticamente il sistema operativo e usa il toolchain appropriato.
#
# USO:
#   ./build_and_run.sh         # build + run
#   ./build_and_run.sh build   # solo build, senza run
#   ./build_and_run.sh clean   # pulisci build e ricompila
#   ./build_and_run.sh run     # solo run (build se manca l'eseguibile)
#   ./build_and_run.sh debug   # build + run con ARCADE_DEBUG_SPRITES=1
#                              # (log diagnostico caricamento sprite)
# ===========================================================================

set -e  # esci al primo errore

# --- Parametri ---
ACTION="${1:-all}"  # all|build|run|clean|debug

# --- Rilevamento OS ---
OS="unknown"
case "$(uname -s)" in
    Linux*)  OS="linux";;
    Darwin*) OS="macos";;
    MINGW*|MSYS*|CYGWIN*) OS="windows";;
    *) echo "ERROR: OS non riconosciuto: $(uname -s)"; exit 1;;
esac

echo "=============================================="
echo " ArcadeMazeFantasy - Build & Run"
echo " OS rilevato: $OS"
echo " Action: $ACTION"
echo "=============================================="

# --- Verifica che gli asset esistano (warning se mancano) ---
if [ ! -d "assets/sprites" ]; then
    echo "[WARN] Cartella 'assets/sprites' non trovata!"
    echo "[WARN] Il gioco andra' in fallback procedurale (no sprite AI)."
    echo "[WARN] Assicurati di eseguire questo script dalla root del repo."
fi

# --- Determina il nome dell'eseguibile (con .exe su Windows) ---
if [ "$OS" = "windows" ]; then
    EXE="ArcadeMazeFantasy.exe"
else
    EXE="ArcadeMazeFantasy"
fi

# --- Funzione: clean ---
do_clean() {
    echo "[clean] rimuovo cartella build..."
    rm -rf build
    echo "[clean] done"
}

# --- Funzione: build ---
do_build() {
    echo "[build] creo cartella build..."
    mkdir -p build
    cd build

    # Configura CMake in base all'OS
    if [ "$OS" = "windows" ]; then
        # Su Windows: tenta prima MSVC (Visual Studio), poi MinGW come fallback
        echo "[build] configurazione Windows..."
        # Prova MSVC (se cl.exe e' nel PATH, oppure se si lancia da Developer Command Prompt)
        if command -v cl.exe >/dev/null 2>&1 || [ -n "$VCINSTALLDIR" ]; then
            echo "[build] uso MSVC (Visual Studio)"
            cmake .. -G "Visual Studio 17 2022" 2>/dev/null || \
            cmake .. -G "Visual Studio 16 2019" 2>/dev/null || \
            cmake .. -G "Visual Studio 15 2017" 2>/dev/null || \
            cmake ..  # fallback: lascia scegliere a CMake
        else
            echo "[build] uso MinGW (gcc)"
            # MinGW Makefiles: cerca gcc/g++ nel PATH
            cmake .. -G "MinGW Makefiles" -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
        fi
    elif [ "$OS" = "macos" ]; then
        echo "[build] configurazione macOS (clang + Homebrew)..."
        # Homebrew installato SFML in /opt/homebrew (Apple Silicon) o /usr/local (Intel)
        if [ -d "/opt/homebrew" ]; then
            export CMAKE_PREFIX_PATH="/opt/homebrew:$CMAKE_PREFIX_PATH"
        fi
        cmake .. -G "Unix Makefiles"
    else
        # Linux: default
        echo "[build] configurazione Linux (gcc)..."
        cmake .. -G "Unix Makefiles"
    fi

    # Compila
    echo "[build] compilazione..."
    cmake --build . --config Release 2>&1 | tail -30

    cd ..

    # Verifica che l'eseguibile esista
    if [ -f "build/$EXE" ] || [ -f "build/Release/$EXE" ] || [ -f "build/Debug/$EXE" ]; then
        echo "[build] OK: $EXE creato"
    else
        echo "[build] WARNING: $EXE non trovato nei percorsi attesi"
        echo "[build] Cerco l'eseguibile..."
        find build -name "$EXE" -type f 2>/dev/null | head -5
    fi
}

# --- Funzione: run ---
# Esegue il gioco DALLA ROOT DEL REPO (non da build/), cosi' i path relativi
# "assets/sprites/..." vengono risolti correttamente.
do_run() {
    # Trova l'eseguibile (può essere in build/, build/Release/, build/Debug/)
    EXE_PATH=""
    for candidate in "build/$EXE" "build/Release/$EXE" "build/Debug/$EXE"; do
        if [ -f "$candidate" ]; then
            EXE_PATH="$candidate"
            break
        fi
    done

    if [ -z "$EXE_PATH" ]; then
        echo "[run] Eseguibile non trovato, eseguo prima il build..."
        do_build
        # Riprova
        for candidate in "build/$EXE" "build/Release/$EXE" "build/Debug/$EXE"; do
            if [ -f "$candidate" ]; then
                EXE_PATH="$candidate"
                break
            fi
        done
    fi

    if [ -z "$EXE_PATH" ]; then
        echo "[run] ERROR: $EXE non trovato dopo il build"
        echo "[run] Verifica che la compilazione sia andata a buon fine."
        exit 1
    fi

    # IMPORTANTE: esegui dalla root del repo, NON da build/.
    # Il codice carica gli asset con path relativi ("assets/sprites/..."),
    # che vengono risolti a partire dalla CWD. Se si esegue da build/,
    # i path non verrebbero trovati e il gioco farebbe fallback procedurale.
    # Usiamo un path assoluto per l'eseguibile ma manteniamo la CWD = root repo.
    REPO_ROOT="$(pwd)"
    EXE_ABSOLUTE="$REPO_ROOT/$EXE_PATH"
    echo "[run] avvio: $EXE_ABSOLUTE (CWD=$REPO_ROOT)"
    # Su Windows con Git Bash, ./xxx.exe funziona nativamente
    "$EXE_ABSOLUTE"
}

# --- Switch principale ---
case "$ACTION" in
    all)
        do_build
        do_run
        ;;
    build)
        do_build
        ;;
    run)
        do_run
        ;;
    clean)
        do_clean
        ;;
    clean-build|rebuild)
        do_clean
        do_build
        ;;
    debug)
        # Build + run con log diagnostico sprite attivo
        do_build
        echo "[debug] attivando ARCADE_DEBUG_SPRITES=1"
        export ARCADE_DEBUG_SPRITES=1
        do_run
        ;;
    *)
        echo "Uso: $0 [all|build|run|clean|clean-build|debug]"
        echo "  all          (default) build + run"
        echo "  build        solo compilazione"
        echo "  run          solo esecuzione (build se manca)"
        echo "  clean        pulisci cartella build"
        echo "  clean-build  pulisci + ricompila"
        echo "  debug        build + run con ARCADE_DEBUG_SPRITES=1"
        exit 1
        ;;
esac

echo "=============================================="
echo " Fatto."
echo "=============================================="
