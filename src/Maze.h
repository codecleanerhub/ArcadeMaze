#ifndef MAZE_H
#define MAZE_H

#include <SFML/Graphics.hpp>
#include <vector>
#include "Utils.h"
#include "Weapon.h"

enum CellType { CELL_EMPTY, CELL_WALL, CELL_TREASURE, CELL_WEAPON };
enum TreasureType { TRES_CROWN, TRES_GOLD, TRES_CHEST, TRES_GEM, TRES_CUP };

struct Cell {
    CellType type;
    Weapon weapon;
    TreasureType treasure;
};

class Maze {
public:
    Maze();
    void generate();
    void render(sf::RenderTarget& target);
    bool isWall(int col, int row);
    CellType getCellType(int col, int row);
    Weapon collectWeapon(int col, int row);
    void collectTreasure(int col, int row);
    int getRemainingTreasures();
    sf::Color getWallColor() const { return wallColor; }
    sf::Color getBgColor() const { return bgColor; }
private:
    std::vector<std::vector<Cell>> grid;
    sf::Color wallColor;
    sf::Color bgColor;
    int countNeighboringWalls(int c, int r);
};

#endif