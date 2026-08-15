#include "Player.h"
#include <iostream>
#include <algorithm>

Player::Player() { reset(); }

void Player::reset() {
    resetPosition();
    lives = 3;
    maxEnergy = 5;
    energy = maxEnergy;
    score = 0;
    nextLifeThreshold = 100000;
    currentWeapon = Weapon::generate(WPN_PISTOL);
    projectiles.clear();
}

void Player::resetPosition() {
    x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
    y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;
    nextDx = 0; nextDy = 0;
    lastDx = 1; lastDy = 0;
    speed = 2;
    jumpTimer = 0;
    damageTimer = 0;
}

void Player::setPosition(float newX, float newY) {
    x = newX; y = newY;
    dx = 0; dy = 0; nextDx = 0; nextDy = 0;
}

void Player::handleInput(SDL_Scancode key, const Config& config, Maze& maze) {
    if (key == config.key_up) { nextDx = 0; nextDy = -1; }
    else if (key == config.key_down) { nextDx = 0; nextDy = 1; }
    else if (key == config.key_left) { nextDx = -1; nextDy = 0; }
    else if (key == config.key_right) { nextDx = 1; nextDy = 0; }
    else if (key == config.key_jump) { if (jumpTimer == 0) jumpTimer = 500; }
    else if (key == config.key_shoot) { shoot(); }
}

bool Player::tryMove(int tDx, int tDy, Maze& maze) {
    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    if (!maze.isWall(col + tDx, row + tDy)) {
        dx = tDx; dy = tDy;
        lastDx = tDx; lastDy = tDy;
        return true;
    }
    return false;
}

void Player::update(Maze& maze, bool freeMovement) {
    // FIX CRITICO: Previene l'overflow di Uint32
    if (jumpTimer > 16) jumpTimer -= 16; else jumpTimer = 0;
    if (damageTimer > 16) damageTimer -= 16; else damageTimer = 0;

    if (freeMovement) {
        if (nextDx != 0 || nextDy != 0) {
            dx = nextDx; dy = nextDy;
            lastDx = dx; lastDy = dy;
            nextDx = 0; nextDy = 0;
        }
        x += dx * speed; y += dy * speed;
        if (x < 12) x = 12;
        if (x > WINDOW_WIDTH - 12) x = WINDOW_WIDTH - 12;
        if (y < UI_HEIGHT + 12) y = UI_HEIGHT + 12;
        if (y > WINDOW_HEIGHT - 12) y = WINDOW_HEIGHT - 12;
    } else {
        int col = (int)(x / TILE_SIZE);
        int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
        float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
        float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
        if (fabs(x - centerX) < speed && fabs(y - centerY) < speed) {
            x = centerX; y = centerY;
            if (nextDx != 0 || nextDy != 0) {
                tryMove(nextDx, nextDy, maze);
                nextDx = 0; nextDy = 0;
            }
            if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
        }
        x += dx * speed; y += dy * speed;
        if (maze.getCellType(col, row) == CELL_TREASURE) {
            maze.collectTreasure(col, row);
            addScore(10000);
        } else if (maze.getCellType(col, row) == CELL_WEAPON) {
            Weapon w = maze.collectWeapon(col, row);
            collectWeapon(w);
        }
    }

    for (auto& p : projectiles) {
        if (!p.active) continue;
        if (!freeMovement) {
            int pCol = (int)(p.x / TILE_SIZE);
            int pRow = (int)((p.y - UI_HEIGHT) / TILE_SIZE);
            if (maze.isWall(pCol, pRow)) { p.active = false; continue; }
        }
        p.x += p.dx * 6; p.y += p.dy * 6;
        if (p.x < 0 || p.x > WINDOW_WIDTH || p.y < UI_HEIGHT || p.y > WINDOW_HEIGHT) p.active = false;
    }
    projectiles.erase(std::remove_if(projectiles.begin(), projectiles.end(), [](const Projectile& p) { return !p.active; }), projectiles.end());
}

void Player::shoot() {
    if (currentWeapon.ammo > 0) {
        int shootDx = dx, shootDy = dy;
        if (shootDx == 0 && shootDy == 0) { shootDx = lastDx; shootDy = lastDy; }
        if (shootDx != 0 || shootDy != 0) {
            projectiles.push_back({x, y, shootDx, shootDy, currentWeapon.power, true, currentWeapon.type});
            currentWeapon.ammo--;
        }
    }
}

void Player::takeDamage() {
    if (!isJumping() && damageTimer == 0) {
        energy--;
        damageTimer = 1000; // 1 secondo di invulnerabilità
        if (energy <= 0) {
            lives--;
            energy = maxEnergy;
            resetPosition();
        }
    }
}

void Player::collectWeapon(Weapon w) { currentWeapon = w; }

void Player::addScore(int points) {
    score += points;
    if (score >= nextLifeThreshold) { lives++; nextLifeThreshold += 100000; }
}

Vec2 Player::getGridPos() const { return { (int)(x / TILE_SIZE), (int)((y - UI_HEIGHT) / TILE_SIZE) }; }
Vec2 Player::getPixelPos() const { return { (int)x, (int)y }; }

void Player::render(SDL_Renderer* renderer) {
    int px = (int)x;
    int py = (int)y;

    // Ombra più larga
    drawFilledCircle(renderer, px, py + 16, 12, {0, 0, 0, 100});

    SDL_Color skin = {255, 220, 177, 255};
    // Lampeggio quando invulnerabile
    SDL_Color clothes = isInvulnerable() ? (SDL_GetTicks() % 200 < 100 ? SDL_Color{100, 100, 255, 255} : SDL_Color{200, 200, 200, 255}) : (isJumping() ? SDL_Color{255, 255, 0, 255} : SDL_Color{70, 130, 180, 255});
    SDL_Color pants = {50, 50, 150, 255};
    SDL_Color hat = {110, 70, 40, 255};
    SDL_Color backpack = {40, 80, 40, 255};

    // Gambe più grandi
    SDL_SetRenderDrawColor(renderer, pants.r, pants.g, pants.b, 255);
    SDL_Rect leg1 = {px - 8, py + 2, 6, 14};
    SDL_Rect leg2 = {px + 2, py + 2, 6, 14};
    SDL_RenderFillRect(renderer, &leg1);
    SDL_RenderFillRect(renderer, &leg2);

    // Zaino grosso
    drawFilledCircle(renderer, px - (lastDx * 10), py + 4, 8, backpack);

    // Corpo torso
    SDL_SetRenderDrawColor(renderer, clothes.r, clothes.g, clothes.b, 255);
    SDL_Rect body = {px - 10, py - 6, 20, 14};
    SDL_RenderFillRect(renderer, &body);

    // Braccia
    SDL_Rect arm1 = {px - 14, py - 4, 5, 12};
    SDL_Rect arm2 = {px + 9, py - 4, 5, 12};
    SDL_RenderFillRect(renderer, &arm1);
    SDL_RenderFillRect(renderer, &arm2);

    // Testa grande
    drawFilledCircle(renderer, px, py - 12, 10, skin);

    // Occhi
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    int eyeOffsetX = lastDx * 3;
    SDL_Rect eye1 = {px - 5 + eyeOffsetX, py - 14, 3, 4};
    SDL_Rect eye2 = {px + 2 + eyeOffsetX, py - 14, 3, 4};
    SDL_RenderFillRect(renderer, &eye1);
    SDL_RenderFillRect(renderer, &eye2);

    // Cappello da esploratore largo
    SDL_SetRenderDrawColor(renderer, hat.r, hat.g, hat.b, 255);
    drawFilledCircle(renderer, px, py - 18, 8, hat);
    SDL_Rect brim = {px - 16, py - 18, 32, 5};
    SDL_RenderFillRect(renderer, &brim);

    // Disegna Arma in mano (più grande)
    currentWeapon.render(renderer, px - TILE_SIZE/2, py - TILE_SIZE/2);

    // Proiettili dettagliati e più grandi
    for (const auto& p : projectiles) {
        if (p.active) {
            if (p.type == WPN_PISTOL) {
                drawFilledCircle(renderer, (int)p.x, (int)p.y, 4, {255, 255, 100, 255});
            } else if (p.type == WPN_SHOTGUN) {
                drawFilledCircle(renderer, (int)p.x, (int)p.y, 6, {255, 150, 50, 255});
            } else if (p.type == WPN_ROCKET) {
                SDL_SetRenderDrawColor(renderer, 100, 200, 100, 255);
                SDL_Rect r = {(int)p.x - 6, (int)p.y - 4, 12, 8};
                SDL_RenderFillRect(renderer, &r);
                drawFilledCircle(renderer, (int)p.x, (int)p.y, 5, {200, 50, 50, 255});
            } else if (p.type == WPN_LASER) {
                SDL_SetRenderDrawColor(renderer, 50, 200, 255, 255);
                for(int i=0; i<8; i++) SDL_RenderDrawLine(renderer, (int)p.x - p.dx*i*2, (int)p.y - p.dy*i*2, (int)p.x, (int)p.y);
                drawFilledCircle(renderer, (int)p.x, (int)p.y, 5, {200, 255, 255, 255});
            }
        }
    }
}