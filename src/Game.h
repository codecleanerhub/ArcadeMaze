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

enum GameState { 
    STATE_MENU, 
    STATE_CONFIG_JOY, 
    STATE_PLAYING, 
    STATE_BOSS, 
    STATE_LOSE, 
    STATE_WIN_STORY, 
    STATE_WIN_INFINITE 
};

enum GameMode { MODE_STORY, MODE_INFINITE };

struct BossRoomWeapon {
    Weapon w;
    sf::Vector2f pos;
};

struct Firework {
    sf::Vector2f pos;
    sf::Vector2f vel;
    sf::Color color;
    int life;
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
    std::vector<Projectile> enemyProjectiles;
    std::vector<BossRoomWeapon> bossRoomWeapons;
    std::vector<Particle> particles;
    std::vector<Firework> fireworks;
    
    Config config;
    GameState state;
    GameMode gameMode;
    bool isRunning;
    int currentLevel;
    std::vector<sf::VideoMode> displayModes;
    int selectedModeIndex;
    int menuItemIndex;
    bool musicEnabled;
    int lightningTimer;
    int configJoyStep;
    
    void handleEvents();
    void update();
    void render();
    void spawnEnemies();
    void startLevel(int lvl);
    void startBossFight();
    void spawnBossRoomWeapons();
    SoundType getWeaponSound(WeaponType wt);
    void drawMenu();
    void drawConfigJoy();
    void spawnFirework();
};

#endif