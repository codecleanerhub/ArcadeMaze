# ===========================================================================
# build_and_run.ps1 - Script PowerShell per Windows
#
# Compila ed esegue il gioco su Windows usando:
#   * Visual Studio (MSVC) se installato
#   * MinGW (g++) come fallback
#
# Supporta SFML installata in:
#   * C:/SFML (default)
#   * C:/vcpkg/vcpkg/packages/sfml_x64-windows (vcpkg)
#   * C:/msys64/mingw64 (MSYS2 MinGW)
#
# USO (PowerShell):
#   .\build_and_run.ps1              # build + run
#   .\build_and_run.ps1 -Action build    # solo build
#   .\build_and_run.ps1 -Action run     # solo run
#   .\build_and_run.ps1 -Action clean   # pulisci
#
# USO (CMD):
#   powershell -ExecutionPolicy Bypass -File build_and_run.ps1
#   powershell -ExecutionPolicy Bypass -File build_and_run.ps1 -Action build
# ===========================================================================

param(
    [string]$Action = "all"
)

$ErrorActionPreference = "Stop"

Write-Host "=============================================="
Write-Host " ArcadeMazeFantasy - Build & Run (Windows)"
Write-Host " Action: $Action"
Write-Host "=============================================="

$ExeName = "ArcadeMazeFantasy.exe"

function Find-SFML {
    # Cerca SFML nei percorsi comuni su Windows
    $candidates = @(
        "C:\SFML",
        "C:\SFML-2.5.1",
        "C:\libraries\SFML",
        "$env:USERPROFILE\SFML",
        "C:\vcpkg\installed\x64-windows",
        "C:\vcpkg\vcpkg\packages\sfml_x64-windows",
        "C:\msys64\mingw64"
    )
    foreach ($path in $candidates) {
        if (Test-Path "$path\include\SFML\Graphics.hpp") {
            Write-Host "[find] SFML trovata in: $path"
            return $path
        }
    }
    Write-Host "[find] WARNING: SFML non trovata nei percorsi comuni."
    Write-Host "[find] Percorsi cercati:"
    foreach ($p in $candidates) { Write-Host "  - $p" }
    Write-Host "[find] Assicurati che SFML sia installata e che il CMakeLists.txt"
    Write-Host "[find] sia configurato per trovarla (CMAKE_PREFIX_PATH o SFML_DIR)."
    return $null
}

function Do-Clean {
    Write-Host "[clean] rimuovo cartella build..."
    if (Test-Path "build") {
        Remove-Item -Recurse -Force "build"
    }
    Write-Host "[clean] done"
}

function Do-Build {
    Write-Host "[build] creo cartella build..."
    if (-not (Test-Path "build")) {
        New-Item -ItemType Directory -Path "build" | Out-Null
    }
    Push-Location "build"

    # Cerca SFML
    $SFML_PATH = Find-SFML

    # Determina il generatore CMake
    $useMSVC = $false
    # Verifica se Visual Studio e' installato (cerca vswhere)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsVersion = & $vswhere -latest -property catalog_productLineVersion
        if ($vsVersion) {
            Write-Host "[build] Visual Studio trovato: $vsVersion"
            $useMSVC = $true
        }
    }

    # Costruisci i parametri per cmake
    $cmakeArgs = @("..")
    if ($useMSVC) {
        # Generatore Visual Studio (sceglie la versione piu' recente disponibile)
        $generators = @("Visual Studio 17 2022", "Visual Studio 16 2019", "Visual Studio 15 2017")
        $genFound = $false
        foreach ($gen in $generators) {
            Write-Host "[build] provo generatore: $gen"
            $test = Start-Process -FilePath "cmake" -ArgumentList @("-G", "`"$gen`"", "..") -Wait -PassThru -NoNewWindow -RedirectStandardOutput "cmake_test.log" -RedirectStandardError "cmake_test_err.log"
            if ($test.ExitCode -eq 0) {
                Write-Host "[build] uso generatore: $gen"
                $genFound = $true
                break
            } else {
                # Pulisci e riprova
                if (Test-Path "CMakeCache.txt") { Remove-Item "CMakeCache.txt" }
                if (Test-Path "CMakeFiles") { Remove-Item -Recurse -Force "CMakeFiles" }
            }
        }
        if (-not $genFound) {
            Write-Host "[build] Fallback: uso generatore default"
            & cmake ..
        }
    } else {
        # MinGW
        Write-Host "[build] uso MinGW Makefiles"
        $cmakeArgs = @("-G", "MinGW Makefiles", "-DCMAKE_C_COMPILER=gcc.exe", "-DCMAKE_CXX_COMPILER=g++.exe", "..")
        & cmake @cmakeArgs
    }

    # Aggiungi SFML_DIR se SFML e' stata trovata
    if ($SFML_PATH -and (Test-Path "$SFML_PATH\cmake")) {
        # Re-esegui cmake con SFML_DIR specificato (se non ha gia' trovato SFML)
        & cmake .. "-DSFML_DIR=$SFML_PATH\cmake"
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[build] ERROR: configurazione CMake fallita"
        Pop-Location
        exit 1
    }

    Write-Host "[build] compilazione..."
    & cmake --build . --config Release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[build] ERROR: compilazione fallita"
        Pop-Location
        exit 1
    }

    Pop-Location

    # Verifica che l'eseguibile esista
    $exePaths = @(
        "build\$ExeName",
        "build\Release\$ExeName",
        "build\Debug\$ExeName"
    )
    $found = $false
    foreach ($p in $exePaths) {
        if (Test-Path $p) {
            Write-Host "[build] OK: $p creato"
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "[build] WARNING: $ExeName non trovato nei percorsi attesi"
        Get-ChildItem -Path "build" -Recurse -Filter $ExeName -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "[build] trovato: $($_.FullName)"
        }
    }
}

function Do-Run {
    $exePaths = @(
        "build\$ExeName",
        "build\Release\$ExeName",
        "build\Debug\$ExeName"
    )
    $exePath = $null
    foreach ($p in $exePaths) {
        if (Test-Path $p) {
            $exePath = $p
            break
        }
    }

    if (-not $exePath) {
        Write-Host "[run] Eseguibile non trovato, eseguo prima il build..."
        Do-Build
        # Riprova
        foreach ($p in $exePaths) {
            if (Test-Path $p) {
                $exePath = $p
                break
            }
        }
    }

    if (-not $exePath) {
        Write-Host "[run] ERROR: $ExeName non trovato dopo il build"
        Write-Host "[run] Verifica che la compilazione sia andata a buon fine."
        exit 1
    }

    Write-Host "[run] avvio: $exePath"
    # Su Windows e' importante che le DLL di SFML siano nel PATH o accanto all'exe.
    # Se l'exe si avvia e si chiude subito, copia le DLL di SFML (bin/*.dll)
    # nella stessa cartella dell'eseguibile.
    & $exePath
}

# --- Switch principale ---
switch ($Action.ToLower()) {
    "all"   { Do-Build; Do-Run }
    "build" { Do-Build }
    "run"   { Do-Run }
    "clean" { Do-Clean }
    "clean-build" { Do-Clean; Do-Build }
    "rebuild" { Do-Clean; Do-Build }
    default {
        Write-Host "Uso: .\build_and_run.ps1 [-Action all|build|run|clean|clean-build]"
        Write-Host "  all          (default) build + run"
        Write-Host "  build        solo compilazione"
        Write-Host "  run          solo esecuzione (build se manca)"
        Write-Host "  clean        pulisci cartella build"
        Write-Host "  clean-build  pulisci + ricompila"
        exit 1
    }
}

Write-Host "=============================================="
Write-Host " Fatto."
Write-Host "=============================================="
