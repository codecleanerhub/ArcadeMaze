#ifndef PLAYER_H
#define PLAYER_H

#include <SDL2/SDL.h>
#include "Weapon.h"
#include "Maze.h"
#include "Utils.h"

class Player {
public:
    Player();
    
    void reset();
    void resetPosition();
    void setPosition(float newX, float newY);
    void handleInput(SDL_Scancode key, const Config& config, Maze& maze);
    void update(Maze& maze, bool freeMovement);
    void render(SDL_Renderer* renderer);
    
    void takeDamage();
    void collectWeapon(Weapon w);
    
    Vec2 getGridPos() const;
    Vec2 getPixelPos() const;
    
    int getLives() const { return lives; }
    int getEnergy() const { return energy; }
    int getMaxEnergy() const { return maxEnergy; }
    
    void addScore(int points);
    int getScore() const { return score; }
    int getNextLifeThreshold() const { return nextLifeThreshold; }
    
    Weapon getCurrentWeapon() const { return currentWeapon; }
    std::vector<Projectile>& getProjectiles() { return projectiles; }
    
    bool isJumping() const { return jumpTimer > 0; }
    bool isInvulnerable() const { return damageTimer > 0; }

private:
    float x, y;
    int dx, dy;
    int nextDx, nextDy;
    int lastDx, lastDy;
    
    int speed;
    int lives;
    int energy;
    int maxEnergy;
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