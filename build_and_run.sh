#!/bin/bash
mkdir -p build
cd build
cmake ..
cmake --build .
cd ..
echo "Avvio del gioco..."
./build/ArcadeMaze
