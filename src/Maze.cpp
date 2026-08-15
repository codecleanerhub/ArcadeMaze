#include "Maze.h"
#include <cstdlib>
#include <algorithm>
#include <random>

Maze::Maze() {
    grid.resize(MAZE_COLS, std::vector<Cell>(MAZE_ROWS));
    generate();
}

void Maze::generate() {
    for (int c = 0; c < MAZE_COLS; ++c)
        for (int r = 0; r < MAZE_ROWS; ++r)
            grid[c][r].type = CELL_WALL;

    std::vector<Vec2> stack;
    grid[1][1].type = CELL_EMPTY;
    stack.push_back({1, 1});
    int dc[] = {0, 2, 0, -2}, dr[] = {-2, 0, 2, 0};

    while (!stack.empty()) {
        Vec2 curr = stack.back();
        std::vector<int> neighbors;
        for (int i = 0; i < 4; ++i) {
            int nc = curr.x + dc[i], nr = curr.y + dr[i];
            if (nc > 0 && nc < MAZE_COLS - 1 && nr > 0 && nr < MAZE_ROWS - 1 && grid[nc][nr].type == CELL_WALL) neighbors.push_back(i);
        }
        if (!neighbors.empty()) {
            int dir = neighbors[rand() % neighbors.size()];
            grid[curr.x + dc[dir]/2][curr.y + dr[dir]/2].type = CELL_EMPTY;
            grid[curr.x + dc[dir]][curr.y + dr[dir]].type = CELL_EMPTY;
            stack.push_back({curr.x + dc[dir], curr.y + dr[dir]});
        } else stack.pop_back();
    }

    for (int i = 0; i < 15; ++i) {
        int c = 1 + rand() % (MAZE_COLS - 2), r = 1 + rand() % (MAZE_ROWS - 2);
        if (grid[c][r].type == CELL_WALL && countNeighboringWalls(c, r) == 2) grid[c][r].type = CELL_EMPTY;
    }

    std::vector<Vec2> emptyCells;
    for (int c = 1; c < MAZE_COLS - 1; ++c)
        for (int r = 1; r < MAZE_ROWS - 1; ++r)
            if (grid[c][r].type == CELL_EMPTY) emptyCells.push_back({c, r});
    
    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(emptyCells.begin(), emptyCells.end(), g);

    for(int i=0; i<8 && !emptyCells.empty(); i++) {
        Vec2 p = emptyCells.back(); emptyCells.pop_back();
        grid[p.x][p.y].type = CELL_TREASURE;
        grid[p.x][p.y].treasure = static_cast<TreasureType>(rand() % 5);
    }
    for(int i=0; i<5 && !emptyCells.empty(); i++) {
        Vec2 p = emptyCells.back(); emptyCells.pop_back();
        grid[p.x][p.y].type = CELL_WEAPON;
        grid[p.x][p.y].weapon = Weapon::generateRandom();
    }

    wallColor = sf::Color(rand() % 50 + 40, rand() % 50 + 40, rand() % 50 + 40);
    bgColor = sf::Color(15, 15, 15);
}

int Maze::countNeighboringWalls(int c, int r) {
    int count = 0;
    if (grid[c-1][r].type == CELL_WALL) count++;
    if (grid[c+1][r].type == CELL_WALL) count++;
    if (grid[c][r-1].type == CELL_WALL) count++;
    if (grid[c][r+1].type == CELL_WALL) count++;
    return count;
}

bool Maze::isWall(int col, int row) {
    if (col < 0 || col >= MAZE_COLS || row < 0 || row >= MAZE_ROWS) return true;
    return grid[col][row].type == CELL_WALL;
}

CellType Maze::getCellType(int col, int row) {
    if (col < 0 || col >= MAZE_COLS || row < 0 || row >= MAZE_ROWS) return CELL_WALL;
    return grid[col][row].type;
}

Weapon Maze::collectWeapon(int col, int row) {
    Weapon w = grid[col][row].weapon;
    grid[col][row].type = CELL_EMPTY;
    return w;
}

void Maze::collectTreasure(int col, int row) { grid[col][row].type = CELL_EMPTY; }

int Maze::getRemainingTreasures() {
    int count = 0;
    for (int c = 0; c < MAZE_COLS; ++c)
        for (int r = 0; r < MAZE_ROWS; ++r)
            if (grid[c][r].type == CELL_TREASURE) count++;
    return count;
}

void Maze::render(sf::RenderTarget& target) {
    sf::RectangleShape rect(sf::Vector2f(TILE_SIZE, TILE_SIZE));
    sf::Color outline(10, 10, 10);
    
    for (int c = 0; c < MAZE_COLS; ++c) {
        for (int r = 0; r < MAZE_ROWS; ++r) {
            rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
            if (grid[c][r].type == CELL_WALL) {
                // Muro 3D pietra
                rect.setFillColor(wallColor);
                target.draw(rect);
                rect.setSize(sf::Vector2f(TILE_SIZE, 8.f));
                rect.setFillColor(sf::Color(wallColor.r + 30, wallColor.g + 30, wallColor.b + 30));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);
                rect.setSize(sf::Vector2f(TILE_SIZE, 8.f));
                rect.setFillColor(sf::Color(wallColor.r - 20, wallColor.g - 20, wallColor.b - 20));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT + TILE_SIZE - 8);
                target.draw(rect);
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE));
            } else {
                rect.setFillColor(bgColor);
                target.draw(rect);
                
                float cx = c * TILE_SIZE + TILE_SIZE/2.f;
                float cy = r * TILE_SIZE + TILE_SIZE/2.f + UI_HEIGHT;

                if (grid[c][r].type == CELL_TREASURE) {
                    // Pedistallo
                    sf::CircleShape ped(20.f); ped.setFillColor(sf::Color(30, 30, 30, 150));
                    ped.setPosition(cx-20.f, cy-12.f); target.draw(ped);

                    if (grid[c][r].treasure == TRES_CROWN) {
                        sf::RectangleShape base(sf::Vector2f(28.f, 8.f)); base.setFillColor(sf::Color(255, 215, 0)); base.setOutlineThickness(1.5f); base.setOutlineColor(outline);
                        base.setPosition(cx-14.f, cy+4.f); target.draw(base);
                        sf::RectangleShape s1(sf::Vector2f(6.f, 8.f)); s1.setFillColor(sf::Color(255, 215, 0)); s1.setOutlineThickness(1.f); s1.setOutlineColor(outline);
                        s1.setPosition(cx-14.f, cy-2.f); target.draw(s1);
                        s1.setSize(sf::Vector2f(6.f, 14.f)); s1.setPosition(cx-3.f, cy-8.f); target.draw(s1);
                        s1.setSize(sf::Vector2f(6.f, 8.f)); s1.setPosition(cx+8.f, cy-2.f); target.draw(s1);
                        // Gemme
                        sf::CircleShape gem(2.f); gem.setFillColor(sf::Color::Red);
                        gem.setPosition(cx-12.f, cy+4.f); target.draw(gem);
                        gem.setFillColor(sf::Color::Blue);
                        gem.setPosition(cx+10.f, cy+4.f); target.draw(gem);
                    } 
                    else if (grid[c][r].treasure == TRES_GEM) {
                        // Glow
                        sf::CircleShape glow(16.f); glow.setFillColor(sf::Color(0, 255, 255, 50));
                        glow.setPosition(cx-16.f, cy-16.f); target.draw(glow);
                        
                        sf::ConvexShape gem; gem.setPointCount(4);
                        gem.setFillColor(sf::Color(0, 255, 255)); gem.setOutlineThickness(1.5f); gem.setOutlineColor(outline);
                        gem.setPoint(0, sf::Vector2f(cx, cy-16)); gem.setPoint(1, sf::Vector2f(cx+12, cy));
                        gem.setPoint(2, sf::Vector2f(cx, cy+16)); gem.setPoint(3, sf::Vector2f(cx-12, cy));
                        target.draw(gem);
                        // Riflesso
                        sf::ConvexShape gleam; gleam.setPointCount(3);
                        gleam.setFillColor(sf::Color(255, 255, 255));
                        gleam.setPoint(0, sf::Vector2f(cx-4, cy-8)); gleam.setPoint(1, sf::Vector2f(cx, cy-12)); gleam.setPoint(2, sf::Vector2f(cx-8, cy));
                        target.draw(gleam);
                    }
                    else if (grid[c][r].treasure == TRES_CHEST) {
                        sf::RectangleShape body(sf::Vector2f(28.f, 18.f)); body.setFillColor(sf::Color(139, 69, 19)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
                        body.setPosition(cx-14.f, cy-4.f); target.draw(body);
                        sf::RectangleShape top(sf::Vector2f(28.f, 6.f)); top.setFillColor(sf::Color(100, 50, 10)); top.setOutlineThickness(1.f); top.setOutlineColor(outline);
                        top.setPosition(cx-14.f, cy-10.f); target.draw(top);
                        sf::RectangleShape band1(sf::Vector2f(2.f, 18.f)); band1.setFillColor(sf::Color(200, 200, 200));
                        band1.setPosition(cx-8.f, cy-4.f); target.draw(band1);
                        band1.setPosition(cx+6.f, cy-4.f); target.draw(band1);
                        sf::RectangleShape lock(sf::Vector2f(6.f, 6.f)); lock.setFillColor(sf::Color(255, 215, 0));
                        lock.setPosition(cx-3.f, cy-2.f); target.draw(lock);
                    }
                    else if (grid[c][r].treasure == TRES_CUP) {
                        sf::RectangleShape cup(sf::Vector2f(16.f, 12.f)); cup.setFillColor(sf::Color(255, 215, 0)); cup.setOutlineThickness(1.5f); cup.setOutlineColor(outline);
                        cup.setPosition(cx-8.f, cy-8.f); target.draw(cup);
                        sf::RectangleShape stand(sf::Vector2f(6.f, 4.f)); stand.setFillColor(sf::Color(200, 180, 0));
                        stand.setPosition(cx-3.f, cy+4.f); target.draw(stand);
                        sf::RectangleShape base(sf::Vector2f(16.f, 4.f)); base.setFillColor(sf::Color(255, 215, 0)); base.setOutlineThickness(1.f); base.setOutlineColor(outline);
                        base.setPosition(cx-8.f, cy+8.f); target.draw(base);
                        sf::CircleShape gem(3.f); gem.setFillColor(sf::Color::Red);
                        gem.setPosition(cx-3.f, cy-4.f); target.draw(gem);
                    }
                    else if (grid[c][r].treasure == TRES_GOLD) {
                        sf::CircleShape coin1(8.f); coin1.setFillColor(sf::Color(255, 215, 0)); coin1.setOutlineThickness(1.f); coin1.setOutlineColor(outline);
                        coin1.setPosition(cx-12.f, cy+4.f); target.draw(coin1);
                        sf::CircleShape coin2(8.f); coin2.setFillColor(sf::Color(255, 235, 50)); coin2.setOutlineThickness(1.f); coin2.setOutlineColor(outline);
                        coin2.setPosition(cx+2.f, cy+4.f); target.draw(coin2);
                        sf::CircleShape coin3(10.f); coin3.setFillColor(sf::Color(255, 255, 100)); coin3.setOutlineThickness(1.f); coin3.setOutlineColor(outline);
                        coin3.setPosition(cx-5.f, cy-6.f); target.draw(coin3);
                    }
                } else if (grid[c][r].type == CELL_WEAPON) {
                    grid[c][r].weapon.render(target, c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                }
            }
        }
    }
}