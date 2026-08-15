#ifndef GAME_H
#define GAME_H

#include <SDL2/SDL.h>
#include <vector>
#include "Maze.h"
#include "Player.h"
#include "Enemy.h"
#include "UI.h"
#include "Utils.h"
#include "AudioManager.h"
#include "Boss.h"

enum GameState {
    STATE_MENU,
    STATE_PLAYING,
    STATE_BOSS,
    STATE_WIN,
    STATE_LOSE
};

// Struttura per le armi nella boss room
struct BossRoomWeapon {
    Weapon w;
    float x, y;
};

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
    AudioManager audio;
    std::vector<Enemy> enemies;
    Boss* boss;
    std::vector<Projectile> bossProjectiles;
    std::vector<BossRoomWeapon> bossRoomWeapons;
    
    Config config;
    GameState state;
    bool isRunning;
    int currentLevel;
    
    std::vector<SDL_DisplayMode> displayModes;
    int selectedModeIndex;
    
    void handleEvents();
    void update();
    void render();
    
    void spawnEnemies();
    void startLevel(int lvl);
    void startBossFight();
    void spawnBossRoomWeapons();
    SoundType getWeaponSound(WeaponType wt);
};

#endif