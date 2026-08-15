#include "Enemy.h"
#include <cstdlib>
#include <cmath>

Enemy::Enemy(EnemyType t, int startCol, int startRow) : pathUpdateTimer(0), shootCooldown(0) {
    type = t;
    pos.x = startCol * TILE_SIZE + TILE_SIZE / 2.0f;
    pos.y = startRow * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;
    
    if (type == ENEMY_ZOMBIE) { speed = 1; health = 4; maxHealth = 4; }
    else if (type == ENEMY_SKELETON) { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_GHOST) { speed = 2; health = 1; maxHealth = 1; }
    else if (type == ENEMY_BAT) { speed = 3; health = 1; maxHealth = 1; }
    else if (type == ENEMY_SPIDER) { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_SLIME) { speed = 1; health = 5; maxHealth = 5; }
    else if (type == ENEMY_DEMON) { speed = 1; health = 5; maxHealth = 5; }
    else if (type == ENEMY_ROBOT) { speed = 1; health = 6; maxHealth = 6; }
    else if (type == ENEMY_GOBLIN) { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_ORC) { speed = 1; health = 6; maxHealth = 6; }
    else if (type == ENEMY_WRAITH) { speed = 2; health = 3; maxHealth = 3; }
    else if (type == ENEMY_GHOUL) { speed = 2; health = 3; maxHealth = 3; }
    else if (type == ENEMY_IMP) { speed = 3; health = 1; maxHealth = 1; }
    else if (type == ENEMY_RAT) { speed = 3; health = 2; maxHealth = 2; }
    else if (type == ENEMY_CULTIST) { speed = 1; health = 3; maxHealth = 3; }
}

bool Enemy::bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep) {
    if (start.x == target.x && start.y == target.y) return false;
    std::queue<Vec2> q;
    std::vector<std::vector<bool>> visited(MAZE_COLS, std::vector<bool>(MAZE_ROWS, false));
    std::vector<std::vector<Vec2>> parent(MAZE_COLS, std::vector<Vec2>(MAZE_ROWS, {-1, -1}));
    q.push(start);
    visited[start.x][start.y] = true;
    int dc[] = {0, 1, 0, -1}, dr[] = {-1, 0, 1, 0};
    bool found = false;
    while (!q.empty()) {
        Vec2 curr = q.front(); q.pop();
        if (curr.x == target.x && curr.y == target.y) { found = true; break; }
        for (int i = 0; i < 4; ++i) {
            int nc = curr.x + dc[i], nr = curr.y + dr[i];
            if (nc >= 0 && nc < MAZE_COLS && nr >= 0 && nr < MAZE_ROWS && !visited[nc][nr] && !maze.isWall(nc, nr)) {
                visited[nc][nr] = true;
                parent[nc][nr] = curr;
                q.push({nc, nr});
            }
        }
    }
    if (found) {
        Vec2 curr = target;
        while (!(parent[curr.x][curr.y].x == start.x && parent[curr.x][curr.y].y == start.y)) curr = parent[curr.x][curr.y];
        nextStep = curr;
        return true;
    }
    return false;
}

void Enemy::moveGreedy(Maze& maze, const Vec2& target) {
    int col = (int)(pos.x / TILE_SIZE);
    int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
    int bestDx = 0, bestDy = 0;
    float minDist = 999999.0f;
    int dc[] = {0, 1, 0, -1}, dr[] = {-1, 0, 1, 0};
    for (int i = 0; i < 4; ++i) {
        int nc = col + dc[i], nr = row + dr[i];
        if (!maze.isWall(nc, nr)) {
            float dist = (nc - target.x) * (nc - target.x) + (nr - target.y) * (nr - target.y);
            if (dc[i] == -dx && dr[i] == -dy) dist += 10; 
            if (dist < minDist) { minDist = dist; bestDx = dc[i]; bestDy = dr[i]; }
        }
    }
    dx = bestDx; dy = bestDy;
}

void Enemy::update(Maze& maze, const Vec2& playerGridPos, const sf::Vector2f& playerPixelPos, std::vector<Projectile>& enemyProjectiles) {
    int col = (int)(pos.x / TILE_SIZE);
    int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
    float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
    float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    pathUpdateTimer += 16;
    if (fabs(pos.x - centerX) < speed && fabs(pos.y - centerY) < speed) {
        pos.x = centerX; pos.y = centerY;
        if (type == ENEMY_ROBOT || type == ENEMY_SLIME || type == ENEMY_DEMON || type == ENEMY_ORC) {
            if (pathUpdateTimer > 250) {
                pathUpdateTimer = 0;
                Vec2 nextStep;
                if (bfsPath(maze, {col, row}, playerGridPos, nextStep)) {
                    dx = nextStep.x - col; dy = nextStep.y - row;
                }
            }
        } else { moveGreedy(maze, playerGridPos); }
        if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
    }
    pos.x += dx * speed; pos.y += dy * speed;

    // Logica sparo nemici (molto più frequente ora: 1 - 2.5 sec)
    if (type == ENEMY_SKELETON || type == ENEMY_CULTIST || type == ENEMY_DEMON || type == ENEMY_WRAITH || type == ENEMY_ROBOT) {
        if (shootCooldown > 0) shootCooldown -= 16;
        else {
            shootCooldown = 1000 + rand() % 1500; 
            float dxp = playerPixelPos.x - pos.x;
            float dyp = playerPixelPos.y - pos.y;
            float dist = sqrt(dxp*dxp + dyp*dyp);
            if (dist > 0 && dist < 500) { // Sparano se sei nel raggio
                enemyProjectiles.push_back({pos, sf::Vector2f(dxp/dist * 3.f, dyp/dist * 3.f), 1, true, WPN_PISTOL});
            }
        }
    }
}

void Enemy::takeDamage(int dmg) { health -= dmg; }
Vec2 Enemy::getGridPos() const { return { (int)(pos.x / TILE_SIZE), (int)((pos.y - UI_HEIGHT) / TILE_SIZE) }; }

void Enemy::render(sf::RenderTarget& target) const {
    float px = pos.x;
    float py = pos.y;
    sf::Color outline(20, 20, 20, 255);

    // Barra HP
    sf::RectangleShape hbBg(sf::Vector2f(36.f, 4.f));
    hbBg.setFillColor(sf::Color(50, 0, 0, 200));
    hbBg.setPosition(px - 18.f, py - 36.f);
    target.draw(hbBg);
    sf::RectangleShape hbFg(sf::Vector2f(36.f * health / maxHealth, 4.f));
    hbFg.setFillColor(sf::Color(255, 50, 50));
    hbFg.setPosition(px - 18.f, py - 36.f);
    target.draw(hbFg);

    if (type == ENEMY_ZOMBIE) {
        sf::RectangleShape arm1(sf::Vector2f(12.f, 8.f)); arm1.setFillColor(sf::Color(100, 150, 80)); arm1.setOutlineThickness(1.5f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - 18.f, py - 2.f); target.draw(arm1);
        sf::RectangleShape arm2(sf::Vector2f(12.f, 8.f)); arm2.setFillColor(sf::Color(100, 150, 80)); arm2.setOutlineThickness(1.5f); arm2.setOutlineColor(outline);
        arm2.setPosition(px + 6.f, py - 2.f); target.draw(arm2);
        sf::RectangleShape leg1(sf::Vector2f(8.f, 16.f)); leg1.setFillColor(sf::Color(60, 80, 40)); leg1.setOutlineThickness(1.5f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 8.f, py + 8.f); target.draw(leg1);
        sf::RectangleShape body(sf::Vector2f(20.f, 18.f)); body.setFillColor(sf::Color(80, 100, 60)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 10.f, py - 8.f); target.draw(body);
        sf::CircleShape head(10.f); head.setFillColor(sf::Color(150, 180, 120)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 10.f, py - 28.f); target.draw(head);
        sf::RectangleShape e1(sf::Vector2f(4.f, 4.f)); e1.setFillColor(sf::Color::Black);
        e1.setPosition(px - 6.f, py - 22.f); target.draw(e1);
        sf::RectangleShape e2(sf::Vector2f(4.f, 4.f)); e2.setFillColor(sf::Color::Black);
        e2.setPosition(px + 2.f, py - 22.f); target.draw(e2);
    } 
    else if (type == ENEMY_SKELETON) {
        sf::RectangleShape skull(sf::Vector2f(16.f, 14.f)); skull.setFillColor(sf::Color(240, 240, 220)); skull.setOutlineThickness(1.5f); skull.setOutlineColor(outline);
        skull.setPosition(px - 8.f, py - 24.f); target.draw(skull);
        sf::RectangleShape body(sf::Vector2f(16.f, 16.f)); body.setFillColor(sf::Color(240, 240, 220)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        sf::RectangleShape leg1(sf::Vector2f(6.f, 14.f)); leg1.setFillColor(sf::Color(240, 240, 220)); leg1.setOutlineThickness(1.5f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 8.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(6.f, 14.f)); leg2.setFillColor(sf::Color(240, 240, 220)); leg2.setOutlineThickness(1.5f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 0.f, py + 8.f); target.draw(leg2);
        sf::RectangleShape e1(sf::Vector2f(4.f, 4.f)); e1.setFillColor(sf::Color::Black);
        e1.setPosition(px - 6.f, py - 22.f); target.draw(e1);
        sf::RectangleShape e2(sf::Vector2f(4.f, 4.f)); e2.setFillColor(sf::Color::Black);
        e2.setPosition(px + 2.f, py - 22.f); target.draw(e2);
        // Arco
        sf::ConvexShape bow; bow.setPointCount(4);
        bow.setFillColor(sf::Color(139, 69, 19));
        bow.setPoint(0, sf::Vector2f(px+8, py-8)); bow.setPoint(1, sf::Vector2f(px+14, py-4));
        bow.setPoint(2, sf::Vector2f(px+12, py+8)); bow.setPoint(3, sf::Vector2f(px+6, py+4));
        target.draw(bow);
    } 
    else if (type == ENEMY_GOBLIN) {
        sf::RectangleShape body(sf::Vector2f(16.f, 14.f)); body.setFillColor(sf::Color(50, 150, 50)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 4.f); target.draw(body);
        sf::RectangleShape leg1(sf::Vector2f(5.f, 10.f)); leg1.setFillColor(sf::Color(40, 120, 40)); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 8.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(5.f, 10.f)); leg2.setFillColor(sf::Color(40, 120, 40)); leg2.setOutlineThickness(1.f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 1.f, py + 8.f); target.draw(leg2);
        sf::CircleShape head(8.f); head.setFillColor(sf::Color(70, 180, 70)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 8.f, py - 20.f); target.draw(head);
        sf::ConvexShape ear1; ear1.setPointCount(3); ear1.setFillColor(sf::Color(70, 180, 70));
        ear1.setPoint(0, sf::Vector2f(px-8, py-18)); ear1.setPoint(1, sf::Vector2f(px-16, py-16)); ear1.setPoint(2, sf::Vector2f(px-8, py-14));
        target.draw(ear1);
        sf::ConvexShape ear2; ear2.setPointCount(3); ear2.setFillColor(sf::Color(70, 180, 70));
        ear2.setPoint(0, sf::Vector2f(px+8, py-18)); ear2.setPoint(1, sf::Vector2f(px+16, py-16)); ear2.setPoint(2, sf::Vector2f(px+8, py-14));
        target.draw(ear2);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - 5.f, py - 16.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 16.f); target.draw(eye);
        sf::RectangleShape dagger(sf::Vector2f(2.f, 8.f)); dagger.setFillColor(sf::Color(200, 200, 200));
        dagger.setPosition(px + 8.f, py - 2.f); target.draw(dagger);
    }
    else if (type == ENEMY_ORC) {
        sf::RectangleShape arm1(sf::Vector2f(10.f, 14.f)); arm1.setFillColor(sf::Color(80, 120, 60)); arm1.setOutlineThickness(1.5f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - 16.f, py - 6.f); target.draw(arm1);
        sf::RectangleShape arm2(sf::Vector2f(10.f, 14.f)); arm2.setFillColor(sf::Color(80, 120, 60)); arm2.setOutlineThickness(1.5f); arm2.setOutlineColor(outline);
        arm2.setPosition(px + 6.f, py - 6.f); target.draw(arm2);
        sf::RectangleShape body(sf::Vector2f(24.f, 20.f)); body.setFillColor(sf::Color(100, 140, 80)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 12.f, py - 8.f); target.draw(body);
        sf::RectangleShape armor(sf::Vector2f(16.f, 8.f)); armor.setFillColor(sf::Color(100, 100, 100)); armor.setOutlineThickness(1.f); armor.setOutlineColor(outline);
        armor.setPosition(px - 8.f, py - 6.f); target.draw(armor);
        sf::RectangleShape leg1(sf::Vector2f(8.f, 12.f)); leg1.setFillColor(sf::Color(60, 100, 40)); leg1.setOutlineThickness(1.5f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 8.f, py + 10.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(8.f, 12.f)); leg2.setFillColor(sf::Color(60, 100, 40)); leg2.setOutlineThickness(1.5f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 0.f, py + 10.f); target.draw(leg2);
        sf::CircleShape head(12.f); head.setFillColor(sf::Color(120, 160, 100)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 12.f, py - 28.f); target.draw(head);
        sf::ConvexShape tusk1; tusk1.setPointCount(3); tusk1.setFillColor(sf::Color(255, 255, 200));
        tusk1.setPoint(0, sf::Vector2f(px-6, py-12)); tusk1.setPoint(1, sf::Vector2f(px-8, py-6)); tusk1.setPoint(2, sf::Vector2f(px-2, py-10));
        target.draw(tusk1);
        sf::ConvexShape tusk2; tusk2.setPointCount(3); tusk2.setFillColor(sf::Color(255, 255, 200));
        tusk2.setPoint(0, sf::Vector2f(px+6, py-12)); tusk2.setPoint(1, sf::Vector2f(px+8, py-6)); tusk2.setPoint(2, sf::Vector2f(px+2, py-10));
        target.draw(tusk2);
    }
    else if (type == ENEMY_WRAITH) {
        sf::ConvexShape cloak; cloak.setPointCount(5);
        cloak.setFillColor(sf::Color(40, 0, 60, 200)); cloak.setOutlineThickness(1.5f); cloak.setOutlineColor(sf::Color(100, 0, 150));
        cloak.setPoint(0, sf::Vector2f(px, py-24)); cloak.setPoint(1, sf::Vector2f(px+16, py-8));
        cloak.setPoint(2, sf::Vector2f(px+12, py+16)); cloak.setPoint(3, sf::Vector2f(px-12, py+16));
        cloak.setPoint(4, sf::Vector2f(px-16, py-8));
        target.draw(cloak);
        sf::CircleShape hood(10.f); hood.setFillColor(sf::Color(20, 0, 30, 255)); hood.setOutlineThickness(1.f); hood.setOutlineColor(outline);
        hood.setPosition(px - 10.f, py - 24.f); target.draw(hood);
        sf::CircleShape eye1(3.f); eye1.setFillColor(sf::Color(255, 0, 0));
        eye1.setPosition(px - 6.f, py - 18.f); target.draw(eye1);
        sf::CircleShape eye2(3.f); eye2.setFillColor(sf::Color(255, 0, 0));
        eye2.setPosition(px + 0.f, py - 18.f); target.draw(eye2);
    }
    else if (type == ENEMY_GHOUL) {
        sf::RectangleShape body(sf::Vector2f(18.f, 14.f)); body.setFillColor(sf::Color(150, 160, 140)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 9.f, py - 4.f); target.draw(body);
        sf::ConvexShape claw1; claw1.setPointCount(3); claw1.setFillColor(sf::Color(200, 200, 200));
        claw1.setPoint(0, sf::Vector2f(px-12, py-2)); claw1.setPoint(1, sf::Vector2f(px-18, py+2)); claw1.setPoint(2, sf::Vector2f(px-12, py+4));
        target.draw(claw1);
        sf::ConvexShape claw2; claw2.setPointCount(3); claw2.setFillColor(sf::Color(200, 200, 200));
        claw2.setPoint(0, sf::Vector2f(px+12, py-2)); claw2.setPoint(1, sf::Vector2f(px+18, py+2)); claw2.setPoint(2, sf::Vector2f(px+12, py+4));
        target.draw(claw2);
        sf::RectangleShape leg1(sf::Vector2f(6.f, 10.f)); leg1.setFillColor(sf::Color(120, 130, 110)); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 8.f); target.draw(leg1);
        sf::CircleShape head(8.f); head.setFillColor(sf::Color(180, 190, 170)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 8.f, py - 18.f); target.draw(head);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Black);
        eye.setPosition(px - 5.f, py - 14.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 14.f); target.draw(eye);
    }
    else if (type == ENEMY_IMP) {
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(120, 0, 0)); wing.setOutlineThickness(1.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px-2, py-4)); wing.setPoint(1, sf::Vector2f(px-16, py-12));
        wing.setPoint(2, sf::Vector2f(px-12, py-2)); wing.setPoint(3, sf::Vector2f(px-2, py+2));
        target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px+2, py-4); target.draw(wing);
        sf::CircleShape body(8.f); body.setFillColor(sf::Color(200, 50, 50)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(outline);
        horn.setPoint(0, sf::Vector2f(px-4, py-8)); horn.setPoint(1, sf::Vector2f(px-8, py-16)); horn.setPoint(2, sf::Vector2f(px-2, py-10));
        target.draw(horn);
        horn.setPoint(0, sf::Vector2f(px+4, py-8)); horn.setPoint(1, sf::Vector2f(px+8, py-16)); horn.setPoint(2, sf::Vector2f(px+2, py-10));
        target.draw(horn);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - 5.f, py - 4.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 4.f); target.draw(eye);
    }
    else if (type == ENEMY_RAT) {
        sf::ConvexShape body; body.setPointCount(4); body.setFillColor(sf::Color(80, 70, 60)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-12, py-4)); body.setPoint(1, sf::Vector2f(px+8, py-8));
        body.setPoint(2, sf::Vector2f(px+12, py+4)); body.setPoint(3, sf::Vector2f(px-10, py+8));
        target.draw(body);
        sf::RectangleShape tail(sf::Vector2f(16.f, 2.f)); tail.setFillColor(sf::Color(255, 200, 200));
        tail.rotate(45); tail.setPosition(px-12, py+2); target.draw(tail);
        sf::CircleShape head(6.f); head.setFillColor(sf::Color(100, 90, 80)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px + 6.f, py - 8.f); target.draw(head);
        sf::CircleShape ear(3.f); ear.setFillColor(sf::Color(100, 90, 80));
        ear.setPosition(px + 8.f, py - 14.f); target.draw(ear);
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px + 10.f, py - 6.f); target.draw(eye);
    }
    else if (type == ENEMY_CULTIST) {
        sf::ConvexShape robe; robe.setPointCount(5);
        robe.setFillColor(sf::Color(80, 0, 80)); robe.setOutlineThickness(1.5f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py-20)); robe.setPoint(1, sf::Vector2f(px+12, py-4));
        robe.setPoint(2, sf::Vector2f(px+8, py+16)); robe.setPoint(3, sf::Vector2f(px-8, py+16));
        robe.setPoint(4, sf::Vector2f(px-12, py-4));
        target.draw(robe);
        sf::CircleShape face(6.f); face.setFillColor(sf::Color::Black);
        face.setPosition(px - 6.f, py - 12.f); target.draw(face);
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 215, 0));
        eye.setPosition(px - 4.f, py - 8.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 8.f); target.draw(eye);
        sf::RectangleShape dagger(sf::Vector2f(2.f, 10.f)); dagger.setFillColor(sf::Color(200, 200, 200));
        dagger.setPosition(px + 8.f, py + 2.f); target.draw(dagger);
    }
    else if (type == ENEMY_GHOST) {
        sf::CircleShape top(12.f); top.setFillColor(sf::Color(150, 200, 255, 150));
        top.setPosition(px - 12.f, py - 16.f); target.draw(top);
        sf::RectangleShape body(sf::Vector2f(24.f, 16.f)); body.setFillColor(sf::Color(150, 200, 255, 150));
        body.setPosition(px - 12.f, py - 4.f); target.draw(body);
        sf::CircleShape eye1(3.f); eye1.setFillColor(sf::Color(100, 100, 255, 200));
        eye1.setPosition(px - 8.f, py - 8.f); target.draw(eye1);
        sf::CircleShape eye2(3.f); eye2.setFillColor(sf::Color(100, 100, 255, 200));
        eye2.setPosition(px + 2.f, py - 8.f); target.draw(eye2);
    } 
    else if (type == ENEMY_BAT) {
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(80, 0, 80)); wing.setOutlineThickness(1.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(0, 0)); wing.setPoint(1, sf::Vector2f(-20, -8));
        wing.setPoint(2, sf::Vector2f(-16, 4)); wing.setPoint(3, sf::Vector2f(-4, 4));
        wing.setPosition(px, py); target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px, py); target.draw(wing);
        sf::CircleShape body(8.f); body.setFillColor(sf::Color(120, 0, 120)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - 3.f, py - 6.f); target.draw(eye);
    } 
    else if (type == ENEMY_SPIDER) {
        sf::Color web(200, 200, 200);
        for(int i=0; i<4; i++) {
            sf::RectangleShape l1(sf::Vector2f(12.f, 2.f)); l1.setFillColor(web);
            l1.rotate(-30 + i*20); l1.setPosition(px - 8.f, py - 2 + i*3); target.draw(l1);
            sf::RectangleShape l2(sf::Vector2f(12.f, 2.f)); l2.setFillColor(web);
            l2.rotate(30 - i*20); l2.setPosition(px + 8.f, py - 2 + i*3); target.draw(l2);
        }
        sf::CircleShape body(10.f); body.setFillColor(sf::Color(30, 30, 30)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(px - 10.f, py - 4.f); target.draw(body);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - 2.f, py - 6.f); target.draw(eye);
    } 
    else if (type == ENEMY_SLIME) {
        sf::CircleShape body(14.f); body.setFillColor(sf::Color(50, 200, 50, 200)); body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(0, 100, 0));
        body.setPosition(px - 14.f, py - 6.f); target.draw(body);
        sf::CircleShape eye1(3.f); eye1.setFillColor(sf::Color::White);
        eye1.setPosition(px - 8.f, py - 2.f); target.draw(eye1);
        sf::CircleShape eye2(3.f); eye2.setFillColor(sf::Color::White);
        eye2.setPosition(px + 2.f, py - 2.f); target.draw(eye2);
        sf::CircleShape p1(1.5f); p1.setFillColor(sf::Color::Black);
        p1.setPosition(px - 5.f, py); target.draw(p1);
        sf::CircleShape p2(1.5f); p2.setFillColor(sf::Color::Black);
        p2.setPosition(px + 5.f, py); target.draw(p2);
    }
    else if (type == ENEMY_DEMON) {
        sf::RectangleShape body(sf::Vector2f(24.f, 20.f)); body.setFillColor(sf::Color(150, 0, 0)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 12.f, py - 8.f); target.draw(body);
        sf::CircleShape head(12.f); head.setFillColor(sf::Color(180, 0, 0)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 12.f, py - 28.f); target.draw(head);
        sf::ConvexShape horn1; horn1.setPointCount(3);
        horn1.setFillColor(sf::Color(80, 0, 0));
        horn1.setPoint(0, sf::Vector2f(0, 0)); horn1.setPoint(1, sf::Vector2f(-6, -10)); horn1.setPoint(2, sf::Vector2f(2, -10));
        horn1.setPosition(px - 8.f, py - 26.f); target.draw(horn1);
        horn1.setPosition(px + 8.f, py - 26.f); target.draw(horn1);
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(120, 0, 0));
        wing.setPoint(0, sf::Vector2f(0, 0)); wing.setPoint(1, sf::Vector2f(-20, -4));
        wing.setPoint(2, sf::Vector2f(-16, 12)); wing.setPoint(3, sf::Vector2f(-4, 10));
        wing.setPosition(px - 12.f, py - 4.f); target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px + 12.f, py - 4.f); target.draw(wing);
        sf::CircleShape eye(3.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - 8.f, py - 22.f); target.draw(eye);
        eye.setPosition(px + 2.f, py - 22.f); target.draw(eye);
    }
    else if (type == ENEMY_ROBOT) {
        sf::RectangleShape tracks(sf::Vector2f(32.f, 12.f)); tracks.setFillColor(sf::Color(30, 30, 30)); tracks.setOutlineThickness(1.f); tracks.setOutlineColor(outline);
        tracks.setPosition(px - 16.f, py + 8.f); target.draw(tracks);
        sf::RectangleShape body(sf::Vector2f(28.f, 20.f)); body.setFillColor(sf::Color(150, 150, 150)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 14.f, py - 12.f); target.draw(body);
        sf::RectangleShape head(sf::Vector2f(22.f, 16.f)); head.setFillColor(sf::Color(180, 180, 180)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 11.f, py - 28.f); target.draw(head);
        sf::RectangleShape ant(sf::Vector2f(2.f, 8.f)); ant.setFillColor(sf::Color(80, 80, 80));
        ant.setPosition(px - 1.f, py - 36.f); target.draw(ant);
        sf::CircleShape led(3.f); led.setFillColor(sf::Color(255, 50, 50));
        led.setPosition(px - 3.f, py - 39.f); target.draw(led);
        sf::CircleShape eye(5.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - 5.f, py - 18.f); target.draw(eye);
    }
}