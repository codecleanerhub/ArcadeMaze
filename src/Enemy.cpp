#include "Enemy.h"
#include <cstdlib>

Enemy::Enemy(EnemyType t, int startCol, int startRow) {
    type = t;
    x = startCol * TILE_SIZE + TILE_SIZE / 2.0f;
    y = startRow * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;
    pathUpdateTimer = 0;
    
    // Imposta energia massima 5
    if (type == ENEMY_ALIEN) {
        speed = 1; health = 2;
    } else if (type == ENEMY_GHOST) {
        speed = 2; health = 1;
    } else if (type == ENEMY_ROBOT) {
        speed = 1; health = 4;
    } else if (type == ENEMY_FANTASY) {
        speed = 1; health = 5; // Massimo 5 colpi
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
    int s = TILE_SIZE / 2 - 4;
    
    if (type == ENEMY_ALIEN) {
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        SDL_Rect body = {px - s, py - s, s * 2, s * 2};
        SDL_RenderFillRect(renderer, &body);
    } else if (type == ENEMY_GHOST) {
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        SDL_Rect body = {px - s, py - s, s * 2, s * 2};
        SDL_RenderFillRect(renderer, &body);
    } else if (type == ENEMY_ROBOT) {
        SDL_SetRenderDrawColor(renderer, 150, 150, 150, 255);
        SDL_Rect body = {px - s, py - s + 2, s * 2, s * 2 - 4};
        SDL_RenderFillRect(renderer, &body);
        SDL_Rect head = {px - 4, py - s - 2, 8, 6};
        SDL_RenderFillRect(renderer, &head);
    } else if (type == ENEMY_FANTASY) {
        SDL_SetRenderDrawColor(renderer, 150, 0, 255, 255);
        SDL_Point points[5] = {
            {px, py - s}, {px + s, py}, {px, py + s}, {px - s, py}, {px, py - s}
        };
        SDL_RenderDrawLines(renderer, points, 5);
        SDL_Rect inner = {px - 4, py - 8, 8, 16};
        SDL_RenderFillRect(renderer, &inner);
    }
}