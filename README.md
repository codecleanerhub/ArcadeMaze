# ArcadeMazeFantasy

Gioco arcade fantasy in C++ con SFML: labirinti, nemici fantasy (LOTR/D&D),
boss, mini-boss, calice dell'immortalità, scettro magico e fulmini.

## Piattaforme supportate

- **Linux** (gcc + SFML system-install)
- **Windows** (Visual Studio MSVC o MinGW + SFML)
- **macOS** (clang + SFML Homebrew)

## Build rapido

### Linux

```bash
# Prerequisiti (Ubuntu/Debian)
sudo apt-get install libsfml-dev cmake g++

# Build + run
./build_and_run.sh
```

### Windows

Vedi [BUILD_WINDOWS.md](BUILD_WINDOWS.md) per istruzioni dettagliate.

Setup rapido:
1. Installa [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) con "Sviluppo di applicazioni desktop C++"
2. Installa [CMake](https://cmake.org/download/)
3. Scarica [SFML 2.5.1 - Visual C++ 14 (2015) - 64-bit](https://www.sfml-dev.org/download.php) ed estrai in `C:\SFML`
4. Apri una CMD in questa cartella ed esegui:
   ```cmd
   build_and_run.bat
   ```

In alternativa, usa Git Bash con `./build_and_run.sh` (cross-platform).

### macOS

```bash
# Prerequisiti
brew install sfml cmake

# Build + run
./build_and_run.sh
```

## Comandi dello script `build_and_run.sh`

```bash
./build_and_run.sh          # build + run (default)
./build_and_run.sh build    # solo compilazione
./build_and_run.sh run       # solo esecuzione (build se manca)
./build_and_run.sh clean     # pulisci cartella build
./build_and_run.sh clean-build  # pulisci + ricompila
```

Su Windows puoi usare equivalentemente:
- `build_and_run.bat` (CMD / doppio-click)
- `.\build_and_run.ps1` (PowerShell)

## Controlli di gioco

- **Frecce / WASD**: movimento
- **Space / Q**: salto
- **LAlt / E**: sparo
- **Enter**: conferma nei menu
- **ESC**: annulla / indietro
- Joystick supportato (configurabile dal menu)

## Struttura del progetto

```
src/                  -- Codice C++ (Game, Player, Enemy, Boss, MiniBoss, ...)
assets/sprites/       -- Sprite PNG (personaggi, nemici, boss, effetti)
scripts/              -- Generatori Python per gli sprite
CMakeLists.txt        -- Configurazione CMake cross-platform
build_and_run.sh      -- Script bash cross-platform (Linux/macOS/Git Bash)
build_and_run.ps1     -- Script PowerShell per Windows
build_and_run.bat     -- Wrapper CMD per PowerShell
BUILD_WINDOWS.md      -- Istruzioni Windows dettagliate
```

## Branch Git

- `main`: codice stabile di produzione
- `linux`: versione corrente funzionante su Linux Mint
- `multi_plat`: versione cross-platform (Linux + Windows + macOS)
- `gameplay`: branch di sviluppo principale
