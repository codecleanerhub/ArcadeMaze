#ifndef BOSS_H
#define BOSS_H

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include <cstdint>

struct Projectile;

class Boss {
public:
    Boss(int level, int w, int h);
    void update(float playerX, float playerY, std::vector<Projectile>& bossProjectiles);
    void render(sf::RenderTarget& target) const;
    void takeDamage(int dmg);
    bool isDead() const { return health <= 0; }
    sf::Vector2f getPos() const { return pos; }
    int getSize() const { return size; }
private:
    sf::Vector2f pos;
    int dx, dy, size, health, maxHealth, speed;
    sf::Color color;
    uint32_t shootTimer; // <-- CORRETTO IN uint32_t
    int level;
    int screenWidth, screenHeight;
};

#endif