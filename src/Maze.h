#ifndef MAZE_H
#define MAZE_H

#include <SDL2/SDL.h>
#include <vector>
#include "Utils.h"
#include "Weapon.h"

enum CellType {
    CELL_EMPTY,
    CELL_WALL,
    CELL_TREASURE, // Sostituisce CELL_DOT
    CELL_WEAPON
};

enum TreasureType {
    TRES_CROWN,
    TRES_GOLD,
    TRES_CHEST,
    TRES_GEM,
    TRES_CUP
};

struct Cell {
    CellType type;
    Weapon weapon;
    TreasureType treasure;
};

class Maze {
public:
    Maze();
    
    void generate();
    void render(SDL_Renderer* renderer);
    
    bool isWall(int col, int row);
    CellType getCellType(int col, int row);
    Weapon collectWeapon(int col, int row);
    void collectTreasure(int col, int row);
    int getRemainingTreasures();
    
    SDL_Color getWallColor() const { return wallColor; }
    SDL_Color getBgColor() const { return bgColor; }

private:
    std::vector<std::vector<Cell>> grid;
    SDL_Color wallColor;
    SDL_Color bgColor;
    
    int countNeighboringWalls(int c, int r);
};

#endif