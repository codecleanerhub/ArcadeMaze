#ifndef BOSS_H
#define BOSS_H

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include <cstdint>

enum BossType { 
    BOSS_GOLEM, BOSS_LICH, BOSS_DEMON, BOSS_SPIDER, 
    BOSS_ABOMINATION, BOSS_KRAKEN, BOSS_DRAGON, 
    BOSS_WRAITH_LORD, BOSS_VAMPIRE, BOSS_BEHOLDER 
};

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
    BossType type;
    uint32_t shootTimer;
    int level;
    int screenWidth, screenHeight;
    float animTime; // <-- AGGIUNTO PER ANIMAZIONI
};

#endif