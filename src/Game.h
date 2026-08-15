#ifndef GAME_H
#define GAME_H
#include <SDL2/SDL.h>
#include <vector>
#include "Maze.h"
#include "Player.h"
#include "Enemy.h"
#include "UI.h"
#include "Utils.h"
enum GameState { STATE_PLAYING, STATE_WIN, STATE_LOSE };
class Game {
public:
    Game();
    ~Game();
    bool init();
    void run();
    void cleanup();
private:
    SDL_Window* window;
    SDL_Renderer* renderer;
    Maze maze;
    Player player;
    UI ui;
    std::vector<Enemy> enemies;
    Config config;
    GameState state;
    bool isRunning;
    void handleEvents();
    void update();
    void render();
    void spawnEnemies();
    void resetGame();
};
#endif
