#include "Player.h"
#include <iostream>
#include <algorithm>

Player::Player() {
    reset();
}

void Player::reset() {
    x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
    y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;
    nextDx = 0; nextDy = 0;
    lastDx = 1; lastDy = 0;
    speed = 2;
    lives = 3;
    maxEnergy = 5;
    energy = maxEnergy;
    score = 0;
    nextLifeThreshold = 100000;
    currentWeapon = { WPN_PISTOL, 1, 15 };
    projectiles.clear();
    jumpTimer = 0;
    damageTimer = 0;
}

void Player::handleInput(SDL_Scancode key, const Config& config, Maze& maze) {
    if (key == config.key_up) { nextDx = 0; nextDy = -1; }
    else if (key == config.key_down) { nextDx = 0; nextDy = 1; }
    else if (key == config.key_left) { nextDx = -1; nextDy = 0; }
    else if (key == config.key_right) { nextDx = 1; nextDy = 0; }
    else if (key == config.key_jump) {
        if (jumpTimer == 0) jumpTimer = 500;
    }
    else if (key == config.key_shoot) {
        shoot();
    }
}

bool Player::tryMove(int tDx, int tDy, Maze& maze) {
    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    
    if (!maze.isWall(col + tDx, row + tDy)) {
        dx = tDx;
        dy = tDy;
        lastDx = tDx;
        lastDy = tDy;
        return true;
    }
    return false;
}

void Player::update(Maze& maze) {
    if (jumpTimer > 0) jumpTimer -= 16;
    if (damageTimer > 0) damageTimer -= 16;

    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    
    float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
    float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;

    if (fabs(x - centerX) < speed && fabs(y - centerY) < speed) {
        x = centerX;
        y = centerY;
        
        if (nextDx != 0 || nextDy != 0) {
            tryMove(nextDx, nextDy, maze);
            nextDx = 0; nextDy = 0;
        }
        
        if (maze.isWall(col + dx, row + dy)) {
            dx = 0; dy = 0;
        }
    }

    x += dx * speed;
    y += dy * speed;

    if (maze.getCellType(col, row) == CELL_DOT) {
        maze.collectDot(col, row);
        addScore(1000);
    } else if (maze.getCellType(col, row) == CELL_WEAPON) {
        Weapon w = maze.collectWeapon(col, row);
        collectWeapon(w);
    }

    for (auto& p : projectiles) {
        if (!p.active) continue;
        
        int pCol = (int)(p.x / TILE_SIZE);
        int pRow = (int)((p.y - UI_HEIGHT) / TILE_SIZE);
        
        if (maze.isWall(pCol, pRow)) {
            p.active = false;
        } else {
            p.x += p.dx * 6;
            p.y += p.dy * 6;
        }
    }
    
    projectiles.erase(std::remove_if(projectiles.begin(), projectiles.end(), [](const Projectile& p) { return !p.active; }), projectiles.end());
}

void Player::shoot() {
    if (currentWeapon.ammo > 0) {
        int shootDx = dx;
        int shootDy = dy;
        
        if (shootDx == 0 && shootDy == 0) {
            shootDx = lastDx;
            shootDy = lastDy;
        }
        
        if (shootDx != 0 || shootDy != 0) {
            projectiles.push_back({x, y, shootDx, shootDy, currentWeapon.power, true});
            currentWeapon.ammo--;
        }
    }
}

void Player::takeDamage() {
    if (!isJumping() && damageTimer == 0) {
        energy--;
        damageTimer = 1500;
        
        if (energy <= 0) {
            lives--;
            energy = maxEnergy;
            x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
            y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
            dx = 0; dy = 0;
        }
    }
}

void Player::collectWeapon(Weapon w) {
    currentWeapon = w;
}

void Player::addScore(int points) {
    score += points;
    if (score >= nextLifeThreshold) {
        lives++;
        nextLifeThreshold += 100000;
    }
}

Vec2 Player::getGridPos() const {
    return { (int)(x / TILE_SIZE), (int)((y - UI_HEIGHT) / TILE_SIZE) };
}

Vec2 Player::getPixelPos() const {
    return { (int)x, (int)y };
}

void Player::render(SDL_Renderer* renderer) {
    int px = (int)x;
    int py = (int)y;

    // Ombra
    drawFilledCircle(renderer, px, py + 12, 8, {0, 0, 0, 100});

    // Stato (colore base)
    SDL_Color skin = {255, 220, 177, 255};
    SDL_Color clothes = isInvulnerable() ? SDL_Color{100, 100, 255, 255} : (isJumping() ? SDL_Color{255, 255, 0, 255} : SDL_Color{70, 130, 180, 255}); // Blu (Esploratore)
    SDL_Color pants = {50, 50, 150, 255};
    SDL_Color hat = {90, 60, 30, 255}; // Marrone cappello
    SDL_Color backpack = {30, 80, 30, 255};

    // Disegna Gambe
    SDL_SetRenderDrawColor(renderer, pants.r, pants.g, pants.b, 255);
    SDL_Rect leg1 = {px - 5, py + 2, 4, 10};
    SDL_Rect leg2 = {px + 1, py + 2, 4, 10};
    SDL_RenderFillRect(renderer, &leg1);
    SDL_RenderFillRect(renderer, &leg2);

    // Disegna Zaino (dietro)
    SDL_SetRenderDrawColor(renderer, backpack.r, backpack.g, backpack.b, 255);
    SDL_Rect bpk = {px - 7, py - 3, 4, 9};
    SDL_RenderFillRect(renderer, &bpk);

    // Disegna Corpo
    SDL_SetRenderDrawColor(renderer, clothes.r, clothes.g, clothes.b, 255);
    SDL_Rect body = {px - 6, py - 4, 12, 8};
    SDL_RenderFillRect(renderer, &body);

    // Disegna Braccia
    SDL_Rect arm1 = {px - 8, py - 3, 3, 7};
    SDL_Rect arm2 = {px + 5, py - 3, 3, 7};
    SDL_RenderFillRect(renderer, &arm1);
    SDL_RenderFillRect(renderer, &arm2);

    // Disegna Testa
    drawFilledCircle(renderer, px, py - 8, 5, skin);

    // Disegna Cappello
    SDL_SetRenderDrawColor(renderer, hat.r, hat.g, hat.b, 255);
    SDL_Rect hat_base = {px - 7, py - 11, 14, 2};
    SDL_Rect hat_top = {px - 3, py - 15, 6, 4};
    SDL_RenderFillRect(renderer, &hat_base);
    SDL_RenderFillRect(renderer, &hat_top);

    // Disegna Arma
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);
    if (lastDx == 1) { // Destra
        SDL_Rect gun = {px + 7, py - 1, 6, 3};
        SDL_RenderFillRect(renderer, &gun);
    } else if (lastDx == -1) { // Sinistra
        SDL_Rect gun = {px - 13, py - 1, 6, 3};
        SDL_RenderFillRect(renderer, &gun);
    } else if (lastDy == 1) { // Giù
        SDL_Rect gun = {px - 1, py + 7, 3, 6};
        SDL_RenderFillRect(renderer, &gun);
    } else if (lastDy == -1) { // Su
        SDL_Rect gun = {px - 1, py - 13, 3, 6};
        SDL_RenderFillRect(renderer, &gun);
    }

    // Disegna Proiettili
    SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255);
    for (const auto& p : projectiles) {
        if (p.active) {
            drawFilledCircle(renderer, (int)p.x, (int)p.y, 3, {255, 200, 0, 255});
        }
    }
}