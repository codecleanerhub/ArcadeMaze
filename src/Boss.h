#ifndef BOSS_H
#define BOSS_H

#include <SDL2/SDL.h>
#include "Utils.h"
#include <vector> // <-- AGGIUNTO PER std::vector

struct Projectile;

class Boss {
public:
    Boss(int level, int w, int h);
    
    void update(int playerX, int playerY, std::vector<Projectile>& bossProjectiles);
    void render(SDL_Renderer* renderer) const;
    void takeDamage(int dmg);
    
    bool isDead() const { return health <= 0; }
    Vec2 getPos() const { return {(int)x, (int)y}; }
    int getSize() const { return size; }

private:
    float x, y;
    int dx, dy;
    int size;
    int health;
    int maxHealth;
    int speed;
    SDL_Color color;
    Uint32 shootTimer;
    int level;
    int screenWidth, screenHeight;
};

#endif