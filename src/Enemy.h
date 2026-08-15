#ifndef ENEMY_H
#define ENEMY_H

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include "Maze.h"
#include "Weapon.h"
#include <queue>
#include <string>
#include <cstdint>

enum EnemyType {
    ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT, 
    ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
    ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
    ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST
};

class Enemy {
public:
    Enemy(EnemyType type, int startCol, int startRow);
    void update(Maze& maze, const Vec2& playerGridPos, const sf::Vector2f& playerPixelPos, std::vector<Projectile>& enemyProjectiles);
    void render(sf::RenderTarget& target) const;
    void takeDamage(int dmg);
    bool isDead() const { return health <= 0; }
    Vec2 getGridPos() const;
    sf::Vector2f getPixelPos() const { return pos; }
    EnemyType getType() const { return type; }

private:
    sf::Vector2f pos;
    int dx, dy;
    int speed;
    int health;
    int maxHealth;
    EnemyType type;
    uint32_t pathUpdateTimer;
    uint32_t shootCooldown;
    bool bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep);
    void moveGreedy(Maze& maze, const Vec2& target);
};

#endif