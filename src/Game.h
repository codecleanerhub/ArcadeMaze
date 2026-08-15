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

// <-- AGGIUNTA LA STRUTTURA MANCANTE
struct BossRoomWeapon {
    Weapon w;
    sf::Vector2f pos;
};

struct MenuBat {
    sf::Vector2f pos;
    float speed;
    float phase;
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
    std::vector<MenuBat> menuBats;
    
    Config config;
    GameState state;
    bool isRunning;
    int currentLevel;
    std::vector<sf::VideoMode> displayModes;
    int selectedModeIndex;
    bool musicEnabled;
    int lightningTimer;
    
    void handleEvents();
    void update();
    void render();
    void spawnEnemies();
    void startLevel(int lvl);
    void startBossFight();
    void spawnBossRoomWeapons();
    SoundType getWeaponSound(WeaponType wt);
    void drawMenu();
};

#endif