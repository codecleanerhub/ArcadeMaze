#ifndef PLAYER_H
#define PLAYER_H

#include <SFML/Graphics.hpp>
#include "Weapon.h"
#include "Maze.h"
#include "Utils.h"
#include <cstdint>

class Player {
public:
    Player();
    void reset();
    void resetPosition();
    void setPosition(float newX, float newY);
    void update(Maze& maze, bool freeMovement, std::vector<Particle>& particles);
    void render(sf::RenderTarget& target);
    void takeDamage();
    void collectWeapon(Weapon w);
    Vec2 getGridPos() const;
    sf::Vector2f getPixelPos() const { return pos; }
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
    
    void shoot();
    void activateJump() { if (jumpTimer == 0) { maxJumpTime = 40; jumpTimer = maxJumpTime; } } // Salto di 40 frame
    uint32_t getShootCooldown() const { return shootCooldown; }
    void setShootCooldown(uint32_t cd) { shootCooldown = cd; }

    void setDirection(int tDx, int tDy) {
        nextDx = tDx;
        nextDy = tDy;
    }

private:
    sf::Vector2f pos;
    int dx, dy, nextDx, nextDy, lastDx, lastDy;
    int speed, lives, energy, maxEnergy, score, nextLifeThreshold;
    Weapon currentWeapon;
    std::vector<Projectile> projectiles;
    uint32_t jumpTimer, maxJumpTime, damageTimer, shootCooldown;
    float jumpOffset;
    bool tryMove(int tDx, int tDy, Maze& maze);
};

#endif