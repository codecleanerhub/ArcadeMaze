#include "Enemy.h"
#include <cstdlib>

Enemy::Enemy(EnemyType t, int startCol, int startRow) {
    type = t;
    x = startCol * TILE_SIZE + TILE_SIZE / 2.0f;
    y = startRow * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;
    pathUpdateTimer = 0;
    
    if (type == ENEMY_ALIEN) {
        speed = 1; health = 2;
    } else if (type == ENEMY_GHOST) {
        speed = 2; health = 1;
    } else if (type == ENEMY_ROBOT) {
        speed = 1; health = 4;
    } else if (type == ENEMY_FANTASY) {
        speed = 1; health = 5;
    }
}

bool Enemy::bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep) {
    if (start.x == target.x && start.y == target.y) return false;
    
    std::queue<Vec2> q;
    std::vector<std::vector<bool>> visited(MAZE_COLS, std::vector<bool>(MAZE_ROWS, false));
    std::vector<std::vector<Vec2>> parent(MAZE_COLS, std::vector<Vec2>(MAZE_ROWS, {-1, -1}));
    
    q.push(start);
    visited[start.x][start.y] = true;
    
    int dc[] = {0, 1, 0, -1};
    int dr[] = {-1, 0, 1, 0};
    
    bool found = false;
    while (!q.empty()) {
        Vec2 curr = q.front();
        q.pop();
        
        if (curr.x == target.x && curr.y == target.y) {
            found = true;
            break;
        }
        
        for (int i = 0; i < 4; ++i) {
            int nc = curr.x + dc[i];
            int nr = curr.y + dr[i];
            
            if (nc >= 0 && nc < MAZE_COLS && nr >= 0 && nr < MAZE_ROWS && !visited[nc][nr] && !maze.isWall(nc, nr)) {
                visited[nc][nr] = true;
                parent[nc][nr] = curr;
                q.push({nc, nr});
            }
        }
    }
    
    if (found) {
        Vec2 curr = target;
        while (!(parent[curr.x][curr.y].x == start.x && parent[curr.x][curr.y].y == start.y)) {
            curr = parent[curr.x][curr.y];
        }
        nextStep = curr;
        return true;
    }
    return false;
}

void Enemy::moveGreedy(Maze& maze, const Vec2& target) {
    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    
    int bestDx = 0, bestDy = 0;
    float minDist = 999999.0f;
    
    int dc[] = {0, 1, 0, -1};
    int dr[] = {-1, 0, 1, 0};
    
    for (int i = 0; i < 4; ++i) {
        int nc = col + dc[i];
        int nr = row + dr[i];
        if (!maze.isWall(nc, nr)) {
            float dist = (nc - target.x) * (nc - target.x) + (nr - target.y) * (nr - target.y);
            if (dc[i] == -dx && dr[i] == -dy) dist += 10; 
            if (dist < minDist) {
                minDist = dist;
                bestDx = dc[i];
                bestDy = dr[i];
            }
        }
    }
    
    dx = bestDx;
    dy = bestDy;
}

void Enemy::update(Maze& maze, const Vec2& playerGridPos) {
    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
    float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    
    pathUpdateTimer += 16;
    
    if (fabs(x - centerX) < speed && fabs(y - centerY) < speed) {
        x = centerX;
        y = centerY;
        
        if (type == ENEMY_ROBOT || type == ENEMY_FANTASY) {
            if (pathUpdateTimer > 250) {
                pathUpdateTimer = 0;
                Vec2 nextStep;
                if (bfsPath(maze, {col, row}, playerGridPos, nextStep)) {
                    dx = nextStep.x - col;
                    dy = nextStep.y - row;
                }
            }
        } else {
            moveGreedy(maze, playerGridPos);
        }
        
        if (maze.isWall(col + dx, row + dy)) {
            dx = 0; dy = 0;
        }
    }
    
    x += dx * speed;
    y += dy * speed;
}

void Enemy::takeDamage(int dmg) {
    health -= dmg;
}

Vec2 Enemy::getGridPos() const {
    return { (int)(x / TILE_SIZE), (int)((y - UI_HEIGHT) / TILE_SIZE) };
}

void Enemy::render(SDL_Renderer* renderer) const {
    int px = (int)x;
    int py = (int)y;
    
    // Ombra per tutti
    drawFilledCircle(renderer, px, py + 12, 8, {0, 0, 0, 100});

    if (type == ENEMY_ALIEN) {
        // Corpo
        SDL_SetRenderDrawColor(renderer, 0, 100, 0, 255);
        SDL_Rect body = {px - 4, py + 2, 8, 6};
        SDL_RenderFillRect(renderer, &body);
        // Testa
        drawFilledCircle(renderer, px, py - 4, 7, {50, 205, 50, 255});
        // Occhi neri
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_Rect e1 = {px - 5, py - 5, 4, 2};
        SDL_Rect e2 = {px + 1, py - 5, 4, 2};
        SDL_RenderFillRect(renderer, &e1);
        SDL_RenderFillRect(renderer, &e2);
    } 
    else if (type == ENEMY_GHOST) {
        // CorpoFantasma
        SDL_SetRenderDrawColor(renderer, 240, 240, 240, 255);
        drawFilledCircle(renderer, px, py - 2, 8, {240, 240, 240, 255});
        SDL_Rect body = {px - 8, py - 2, 16, 8};
        SDL_RenderFillRect(renderer, &body);
        // Onde inferiori
        SDL_Rect wave1 = {px - 8, py + 6, 4, 3};
        SDL_Rect wave2 = {px - 2, py + 6, 4, 3};
        SDL_Rect wave3 = {px + 4, py + 6, 4, 3};
        SDL_RenderFillRect(renderer, &wave1);
        SDL_RenderFillRect(renderer, &wave2);
        SDL_RenderFillRect(renderer, &wave3);
        // Occhi
        drawFilledCircle(renderer, px - 3, py - 3, 2, {0, 0, 0, 255});
        drawFilledCircle(renderer, px + 3, py - 3, 2, {0, 0, 0, 255});
    } 
    else if (type == ENEMY_ROBOT) {
        // Cingoli
        SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
        SDL_Rect tracks = {px - 8, py + 4, 16, 6};
        SDL_RenderFillRect(renderer, &tracks);
        // Corpo
        SDL_SetRenderDrawColor(renderer, 150, 150, 150, 255);
        SDL_Rect body = {px - 6, py - 4, 12, 10};
        SDL_RenderFillRect(renderer, &body);
        // Testa
        SDL_Rect head = {px - 4, py - 10, 8, 7};
        SDL_RenderFillRect(renderer, &head);
        // Antenna
        SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);
        SDL_Rect ant = {px - 1, py - 14, 2, 4};
        SDL_RenderFillRect(renderer, &ant);
        drawFilledCircle(renderer, px, py - 15, 2, {255, 50, 50, 255});
        // Occhio
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        SDL_Rect eye = {px - 2, py - 8, 4, 2};
        SDL_RenderFillRect(renderer, &eye);
    } 
    else if (type == ENEMY_FANTASY) {
        // Melma
        drawFilledCircle(renderer, px, py + 4, 8, {150, 0, 255, 255});
        SDL_SetRenderDrawColor(renderer, 150, 0, 255, 255);
        SDL_Rect body = {px - 8, py + 4, 16, 6};
        SDL_RenderFillRect(renderer, &body);
        drawFilledCircle(renderer, px, py + 4, 5, {200, 50, 255, 255});
        // Occhi
        drawFilledCircle(renderer, px - 3, py + 2, 2, {255, 255, 255, 255});
        drawFilledCircle(renderer, px + 3, py + 2, 2, {255, 255, 255, 255});
        drawFilledCircle(renderer, px - 3, py + 2, 1, {0, 0, 0, 255});
        drawFilledCircle(renderer, px + 3, py + 2, 1, {0, 0, 0, 255});
    }
}