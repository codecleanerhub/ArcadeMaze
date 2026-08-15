#ifndef MAZE_H
#define MAZE_H
#include <SDL2/SDL.h>
#include <vector>
#include "Utils.h"
#include "Weapon.h"
enum CellType { CELL_EMPTY, CELL_WALL, CELL_DOT, CELL_WEAPON };
struct Cell { CellType type; Weapon weapon; };
class Maze {
public:
    Maze();
    void generate();
    void render(SDL_Renderer* renderer);
    bool isWall(int col, int row);
    CellType getCellType(int col, int row);
    Weapon collectWeapon(int col, int row);
    void collectDot(int col, int row);
    int getRemainingDots();
    SDL_Color getWallColor() const { return wallColor; }
    SDL_Color getBgColor() const { return bgColor; }
private:
    std::vector<std::vector<Cell>> grid;
    SDL_Color wallColor;
    SDL_Color bgColor;
    int countNeighboringWalls(int c, int r);
};
#endif
