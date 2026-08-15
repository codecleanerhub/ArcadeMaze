#!/bin/bash
# Script per compilare ed eseguire il gioco su Linux

# Crea la cartella build se non esiste
mkdir -p build
cd build

# Esegue CMake e compila
cmake ..
cmake --build .

# Torna alla cartella principale e lancia il gioco
cd ..
echo "Avvio del gioco..."
./build/ArcadeMazeFantasy