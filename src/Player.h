#ifndef PLAYER_H
#define PLAYER_H

#include <SDL2/SDL.h>
#include "Weapon.h"
#include "Maze.h"
#include "Utils.h"

struct Projectile {
    float x, y;
    int dx, dy;
    int power;
    bool active;
};

class Player {
public:
    Player();
    
    void reset();
    void handleInput(SDL_Scancode key, const Config& config, Maze& maze); // Cambiato in SDL_Scancode
    void update(Maze& maze);
    void render(SDL_Renderer* renderer);
    
    void takeDamage();
    void collectWeapon(Weapon w);
    
    Vec2 getGridPos() const;
    Vec2 getPixelPos() const;
    
    int getLives() const { return lives; }
    void addScore(int points);
    int getScore() const { return score; }
    int getNextLifeThreshold() const { return nextLifeThreshold; }
    
    Weapon getCurrentWeapon() const { return currentWeapon; }
    std::vector<Projectile>& getProjectiles() { return projectiles; }
    
    bool isJumping() const { return jumpTimer > 0; }
    bool isInvulnerable() const { return damageTimer > 0; }

private:
    float x, y; // Posizione in pixel
    int dx, dy; // Direzione corrente
    int nextDx, nextDy; // Prossima direzione (buffer input)
    int lastDx, lastDy; // Ultima direzione usata per sparare da fermo
    
    int speed;
    int lives;
    int score;
    int nextLifeThreshold;
    
    Weapon currentWeapon;
    std::vector<Projectile> projectiles;
    
    Uint32 jumpTimer;
    Uint32 damageTimer;
    
    bool tryMove(int tDx, int tDy, Maze& maze);
    void shoot();
};

#endif