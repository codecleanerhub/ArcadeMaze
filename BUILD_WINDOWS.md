# Build su Windows - Istruzioni dettagliate

Questo documento spiega come compilare ed eseguire ArcadeMazeFantasy su Windows usando Visual Studio Code.

## Prerequisiti

### 1. Visual Studio Code
- Scarica da: https://code.visualstudio.com/
- Estensioni consigliate:
  - **C/C++** (Microsoft) - per l'intellisense
  - **CMake Tools** (Microsoft) - per integrazione CMake
  - **Git Bash** (opzionale ma consigliato per usare `build_and_run.sh`)

### 2. Compilatore C++

Hai tre opzioni (scegline una):

#### Opzione A: Visual Studio Build Tools (MSVC) - CONSIGLIATA
- Scarica da: https://visualstudio.microsoft.com/visual-cpp-build-tools/
- Durante l'installazione, seleziona **"Sviluppo di applicazioni desktop C++"**
- Questo installa il compilatore MSVC (`cl.exe`) e le librerie Windows SDK
- Dopo l'installazione, apri VS Code dal **"Developer Command Prompt for VS"** per avere il compilatore nel PATH

#### Opzione B: MinGW-w64 (alternativa leggera)
- Scarica da: https://www.mingw-w64.org/ o https://www.msys2.org/
- Installa MSYS2 e poi: `pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake`
- Aggiungi `C:\msys64\mingw64\bin` al PATH di sistema

#### Opzione C: Clang (non testato)
- Scarica da: https://releases.llvm.org/
- Meno comune per questo progetto, preferisci MSVC o MinGW

### 3. CMake
- Scarica da: https://cmake.org/download/
- Durante l'installazione, seleziona **"Add CMake to the system PATH"**
- Verifica: apri un terminale e digita `cmake --version`

### 4. SFML 2.5+
Hai tre opzioni:

#### Opzione A: Download diretto (più semplice)
- Vai su: https://www.sfml-dev.org/download.php
- Scarica **SFML 2.5.1 - Visual C++ 14 (2015) - 64-bit** (per MSVC)
  - oppure **SFML 2.5.1 - GCC 7.3.0 MinGW (DW2) - 64-bit** (per MinGW)
- Estrai in `C:\SFML` (in modo che i percorsi siano `C:\SFML\include`, `C:\SFML\lib`, `C:\SFML\bin`)
- **IMPORTANTE**: La versione di SFML deve combaciare col compilatore:
  - MSVC 2017/2019/2022 → usa SFML "Visual C++ 14 (2015)" o superiore
  - MinGW GCC → usa SFML "GCC 7.3.0 MinGW"

#### Opzione B: vcpkg (per utenti avanzati)
```cmd
git clone https://github.com/Microsoft/vcpkg.git C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
C:\vcpkg\vcpkg install sfml:x64-windows
```
SFML sarà installata in `C:\vcpkg\installed\x64-windows\`

#### Opzione C: MSYS2 (per MinGW)
```bash
pacman -S mingw-w64-x86_64-sfml
```
SFML sarà installata in `C:\msys64\mingw64\`

## Setup del progetto

1. **Clona il repository**:
   ```cmd
   git clone https://github.com/codecleanerhub/ArcadeMaze.git
   cd ArcadeMaze
   git checkout multi_plat
   ```

2. **Apri in VS Code**:
   ```cmd
   code .
   ```

## Build ed esecuzione

### Metodo 1: Script batch (più semplice)

Doppio-click su `build_and_run.bat` oppure da CMD:
```cmd
build_and_run.bat              :: build + run
build_and_run.bat build        :: solo build
build_and_run.bat run          :: solo run (build se manca)
build_and_run.bat clean        :: pulisci cartella build
```

### Metodo 2: Script PowerShell

Da PowerShell:
```powershell
.\build_and_run.ps1              # build + run
.\build_and_run.ps1 -Action build    # solo build
.\build_and_run.ps1 -Action run     # solo run
.\build_and_run.ps1 -Action clean   # pulisci
```

### Metodo 3: Git Bash (se hai installato Git for Windows)

Se hai Git Bash (viene con Git for Windows), puoi usare lo stesso script di Linux:
```bash
./build_and_run.sh
./build_and_run.sh build
./build_and_run.sh run
./build_and_run.sh clean
```

### Metodo 4: VS Code con estensione CMake Tools

1. Apri la Command Palette (Ctrl+Shift+P)
2. Cerca **"CMake: Configure"** - CMake rileverà automaticamente il compilatore
3. Seleziona il kit (MSVC o MinGW)
4. **"CMake: Build"** (F7)
5. **"CMake: Run Without Debugging"** (Ctrl+F5)

### Metodo 5: Da terminale manuale

```cmd
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022"
:: oppure: cmake .. -G "MinGW Makefiles"
cmake --build . --config Release
:: L'eseguibile sarà in build\Release\ArcadeMazeFantasy.exe (MSVC)
:: oppure build\ArcadeMazeFantasy.exe (MinGW)
```

## Risoluzione problemi comuni

### "sfml-graphics-2.dll non trovata"

Le DLL di SFML non sono nel PATH. Soluzioni:

1. **Lo script lo fa automaticamente**: se SFML è in `C:\SFML`, `build_and_run.bat` copia le DLL accanto all'exe
2. **Manuale**: copia tutti i file `*.dll` da `C:\SFML\bin` a `build\Release\` (o `build\Debug\`)
3. **PATH**: aggiungi `C:\SFML\bin` al PATH di sistema

### "SFML not found" da CMake

CMake non trova SFML. Soluzioni:

1. Verifica che SFML sia estratta in `C:\SFML` (deve esistere `C:\SFML\include\SFML\Graphics.hpp`)
2. Specifica manualmente:
   ```cmd
   cmake .. -DSFML_DIR="C:/SFML/lib/cmake/SFML"
   :: oppure
   cmake .. -DCMAKE_PREFIX_PATH="C:/SFML"
   ```
3. Per vcpkg:
   ```cmd
   cmake .. -DCMAKE_TOOLCHAIN_FILE="C:/vcpkg/scripts/buildsystems/vcpkg.cmake"
   ```

### "cl.exe non trovato" (MSVC)

Stai usando MSVC ma il compilatore non è nel PATH. Soluzioni:

1. Apri VS Code dal **"Developer Command Prompt for VS 2019/2022"** (lo trovi nel menu Start)
2. Oppure installa "Visual Studio Build Tools" con il workload "Sviluppo di applicazioni desktop C++"

### "g++.exe non trovato" (MinGW)

MinGW non è nel PATH. Soluzioni:

1. Aggiungi `C:\msys64\mingw64\bin` al PATH di sistema (variabili d'ambiente)
2. Riavvia VS Code dopo la modifica del PATH

### L'eseguibile si avvia e si chiude subito

Causa probabile: DLL di SFML mancanti. Vedi sezione "DLL non trovata" sopra.

### Schermo nero o crash in fullscreen

Su Windows con monitor multipli, il fullscreen potrebbe dare problemi. Eventualmente modifica `src/Game.cpp` riga 42:
```cpp
// Prima: window(sf::VideoMode::getDesktopMode(), "Arcade Maze Fantasy", sf::Style::Fullscreen)
// Dopo: window(sf::VideoMode(1024, 1024), "Arcade Maze Fantasy", sf::Style::Default)
```

## Struttura del progetto

```
ArcadeMaze/
├── src/                       -- Codice sorgente C++
├── assets/sprites/            -- Sprite PNG
├── scripts/                   -- Script Python per generare sprite
├── CMakeLists.txt             -- Configurazione CMake (cross-platform)
├── build_and_run.sh           -- Script bash (Linux/macOS/Windows Git Bash)
├── build_and_run.ps1          -- Script PowerShell (Windows nativo)
├── build_and_run.bat          -- Wrapper CMD per PowerShell
├── BUILD_WINDOWS.md           -- Questo file
└── README.md                  -- Documentazione generale
```

## Verifica dell'installazione

Per verificare che tutto sia configurato correttamente:

```cmd
:: Verifica compilatore MSVC
cl 2>&1 | findstr "Microsoft"
:: oppure MinGW:
g++ --version

:: Verifica CMake
cmake --version

:: Verifica SFML (deve esistere il file)
dir C:\SFML\include\SFML\Graphics.hpp
```

Se tutti i comandi sopra funzionano, sei pronto per compilare!

## Note tecniche

- Il codice C++ è completamente portatile (usa solo STL e SFML, niente API Windows/Linux specifiche)
- I percorsi dei file usano forward slash `/` che funziona su entrambi gli OS
- `M_PI` è definito con `#ifndef` guard per compatibilità MSVC
- Il CMakeLists.txt rileva automaticamente Windows (`WIN32`) e configura la copia delle DLL e della cartella assets
- Su Linux il gioco si avvia dalla root del progetto, su Windows dalla cartella build (lo script copia assets/config.ini automaticamente)
