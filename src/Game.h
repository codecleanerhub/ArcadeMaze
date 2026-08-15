#ifndef GAME_H
#define GAME_H
#include <SFML/Graphics.hpp>
#include <vector>
#include "Maze.h"
#include "Player.h"
#include "Enemy.h"
#include "UI.h"
#include "Utils.h"
#include "AudioManager.h"
#include "Boss.h"

enum GameState { STATE_MENU, STATE_PLAYING, STATE_BOSS, STATE_WIN, STATE_LOSE };

struct BossRoomWeapon {
    Weapon w;
    sf::Vector2f pos;
};

class Game {
public:
    Game();
    bool init();
    void run();
private:
    sf::RenderWindow window;
    Maze maze;
    Player player;
    UI ui;
    AudioManager audio;
    std::vector<Enemy> enemies;
    Boss* boss;
    std::vector<Projectile> bossProjectiles;
    std::vector<BossRoomWeapon> bossRoomWeapons;
    std::vector<Particle> particles;
    
    Config config;
    GameState state;
    bool isRunning;
    int currentLevel;
    std::vector<sf::VideoMode> displayModes;
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