#ifndef ENEMY_H
#define ENEMY_H

#include <SDL2/SDL.h>
#include "Utils.h"
#include "Maze.h"
#include <queue>

enum EnemyType {
    ENEMY_ALIEN,
    ENEMY_GHOST,
    ENEMY_ROBOT,
    ENEMY_FANTASY,
    ENEMY_ZOMBIE // NUOVO NEMICO
};

class Enemy {
public:
    Enemy(EnemyType type, int startCol, int startRow);
    
    void update(Maze& maze, const Vec2& playerGridPos);
    void render(SDL_Renderer* renderer) const;
    void takeDamage(int dmg);
    
    bool isDead() const { return health <= 0; }
    Vec2 getGridPos() const;
    EnemyType getType() const { return type; }

private:
    float x, y;
    int dx, dy;
    int speed;
    int health;
    EnemyType type;
    Uint32 pathUpdateTimer;
    
    bool bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep);
    void moveGreedy(Maze& maze, const Vec2& target);
};

#endif