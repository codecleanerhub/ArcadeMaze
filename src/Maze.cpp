#include "Maze.h"
#include <cstdlib>
#include <algorithm>

Maze::Maze() {
    grid.resize(MAZE_COLS, std::vector<Cell>(MAZE_ROWS));
    generate();
}

void Maze::generate() {
    for (int c = 0; c < MAZE_COLS; ++c)
        for (int r = 0; r < MAZE_ROWS; ++r)
            grid[c][r].type = CELL_WALL;

    std::vector<Vec2> stack;
    int startC = 1, startR = 1;
    grid[startC][startR].type = CELL_EMPTY;
    stack.push_back({startC, startR});

    int dc[] = {0, 2, 0, -2};
    int dr[] = {-2, 0, 2, 0};

    while (!stack.empty()) {
        Vec2 current = stack.back();
        std::vector<int> neighbors;
        for (int i = 0; i < 4; ++i) {
            int nc = current.x + dc[i];
            int nr = current.y + dr[i];
            if (nc > 0 && nc < MAZE_COLS - 1 && nr > 0 && nr < MAZE_ROWS - 1 && grid[nc][nr].type == CELL_WALL) {
                neighbors.push_back(i);
            }
        }
        if (!neighbors.empty()) {
            int dir = neighbors[rand() % neighbors.size()];
            int nc = current.x + dc[dir];
            int nr = current.y + dr[dir];
            grid[current.x + dc[dir]/2][current.y + dr[dir]/2].type = CELL_EMPTY;
            grid[nc][nr].type = CELL_EMPTY;
            stack.push_back({nc, nr});
        } else {
            stack.pop_back();
        }
    }

    for (int i = 0; i < 10; ++i) {
        int c = 1 + rand() % (MAZE_COLS - 2);
        int r = 1 + rand() % (MAZE_ROWS - 2);
        if (grid[c][r].type == CELL_WALL && countNeighboringWalls(c, r) == 2) {
            grid[c][r].type = CELL_EMPTY;
        }
    }

    for (int c = 1; c < MAZE_COLS - 1; ++c) {
        for (int r = 1; r < MAZE_ROWS - 1; ++r) {
            if (grid[c][r].type == CELL_EMPTY) {
                if (rand() % 100 < 5) {
                    grid[c][r].type = CELL_WEAPON;
                    grid[c][r].weapon = Weapon::generateRandom();
                } else {
                    grid[c][r].type = CELL_DOT;
                }
            }
        }
    }
    wallColor = { (Uint8)(rand() % 100 + 50), (Uint8)(rand() % 100 + 50), (Uint8)(rand() % 100 + 50), 255 };
    bgColor = { (Uint8)(rand() % 20), (Uint8)(rand() % 20), (Uint8)(rand() % 20), 255 };
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

void Maze::collectDot(int col, int row) { grid[col][row].type = CELL_EMPTY; }

int Maze::getRemainingDots() {
    int count = 0;
    for (int c = 0; c < MAZE_COLS; ++c)
        for (int r = 0; r < MAZE_ROWS; ++r)
            if (grid[c][r].type == CELL_DOT) count++;
    return count;
}

void Maze::render(SDL_Renderer* renderer) {
    SDL_SetRenderDrawColor(renderer, bgColor.r, bgColor.g, bgColor.b, 255);
    SDL_RenderClear(renderer);

    for (int c = 0; c < MAZE_COLS; ++c) {
        for (int r = 0; r < MAZE_ROWS; ++r) {
            SDL_Rect rect = {c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT, TILE_SIZE, TILE_SIZE};
            if (grid[c][r].type == CELL_WALL) {
                // Effetto 3D per i muri
                SDL_SetRenderDrawColor(renderer, wallColor.r + 30, wallColor.g + 30, wallColor.b + 30, 255);
                SDL_Rect top = {rect.x, rect.y, TILE_SIZE, TILE_SIZE - 4};
                SDL_RenderFillRect(renderer, &top);
                
                SDL_SetRenderDrawColor(renderer, wallColor.r - 30, wallColor.g - 30, wallColor.b - 30, 255);
                SDL_Rect right = {rect.x + TILE_SIZE - 4, rect.y, 4, TILE_SIZE};
                SDL_RenderFillRect(renderer, &right);
                
                SDL_Rect bottom = {rect.x, rect.y + TILE_SIZE - 4, TILE_SIZE, 4};
                SDL_RenderFillRect(renderer, &bottom);
            } else if (grid[c][r].type == CELL_DOT) {
                drawFilledCircle(renderer, c * TILE_SIZE + TILE_SIZE/2, r * TILE_SIZE + TILE_SIZE/2 + UI_HEIGHT, 4, {255, 255, 255, 255});
            } else if (grid[c][r].type == CELL_WEAPON) {
                grid[c][r].weapon.render(renderer, c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
            }
        }
    }
}