#include "Player.h"
#include <iostream>
#include <algorithm>

Player::Player() {
    reset();
}

void Player::reset() {
    // Posizione iniziale del giocatore (aggiunto offset UI_HEIGHT)
    x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
    y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;
    nextDx = 0; nextDy = 0;
    lastDx = 1; lastDy = 0; // Inizia guardando verso destra
    speed = 2;
    lives = 3;
    score = 0;
    nextLifeThreshold = 100000;
    currentWeapon = { WPN_PISTOL, 1, 15 }; // Arma iniziale
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
        if (jumpTimer == 0) jumpTimer = 500; // Salto di 500ms
    }
    else if (key == config.key_shoot) {
        shoot();
    }
}

bool Player::tryMove(int tDx, int tDy, Maze& maze) {
    // Controlla se può cambiare direzione o se sta sbattendo contro un muro
    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    
    if (!maze.isWall(col + tDx, row + tDy)) {
        dx = tDx;
        dy = tDy;
        lastDx = tDx; // Aggiorna l'ultima direzione
        lastDy = tDy;
        return true;
    }
    return false;
}

void Player::update(Maze& maze) {
    // Aggiorna i timer
    if (jumpTimer > 0) jumpTimer -= 16; // Approssimazione 60fps
    if (damageTimer > 0) damageTimer -= 16;

    // Calcola posizione griglia corrente (tenendo conto dell'offset UI)
    int col = (int)(x / TILE_SIZE);
    int row = (int)((y - UI_HEIGHT) / TILE_SIZE);
    
    // Centro della cella (con offset UI)
    float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
    float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;

    // Logica di svolta agli incroci: permette di cambiare direzione solo se centrati nella cella
    if (fabs(x - centerX) < speed && fabs(y - centerY) < speed) {
        x = centerX;
        y = centerY;
        
        if (nextDx != 0 || nextDy != 0) {
            tryMove(nextDx, nextDy, maze);
            nextDx = 0; nextDy = 0; // Resetta il buffer
        }
        
        // Si ferma se sbatte contro un muro
        if (maze.isWall(col + dx, row + dy)) {
            dx = 0; dy = 0;
        }
    }

    x += dx * speed;
    y += dy * speed;

    // Raccogli puntini o armi
    if (maze.getCellType(col, row) == CELL_DOT) {
        maze.collectDot(col, row);
        addScore(1000);
    } else if (maze.getCellType(col, row) == CELL_WEAPON) {
        Weapon w = maze.collectWeapon(col, row);
        collectWeapon(w);
    }

    // Aggiorna i proiettili
    for (auto& p : projectiles) {
        if (!p.active) continue;
        
        int pCol = (int)(p.x / TILE_SIZE);
        int pRow = (int)((p.y - UI_HEIGHT) / TILE_SIZE);
        
        if (maze.isWall(pCol, pRow)) {
            p.active = false;
        } else {
            p.x += p.dx * 6; // Velocità proiettile
            p.y += p.dy * 6;
        }
    }
    
    // Pulisci proiettili inattivi
    projectiles.erase(std::remove_if(projectiles.begin(), projectiles.end(), [](const Projectile& p) { return !p.active; }), projectiles.end());
}

void Player::shoot() {
    if (currentWeapon.ammo > 0) {
        int shootDx = dx;
        int shootDy = dy;
        
        // Se fermo, spara nella direzione in cui era rivolto
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
        lives--;
        damageTimer = 1500; // 1.5 secondi di invulnerabilità dopo essere stati colpiti
        // Respawn
        x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
        y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
        dx = 0; dy = 0;
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
    // Disegna l'omino stilizzato (Stickman)
    SDL_Color bodyColor = isInvulnerable() ? SDL_Color{100, 100, 255, 255} : (isJumping() ? SDL_Color{255, 255, 0, 255} : SDL_Color{0, 255, 255, 255});
    SDL_SetRenderDrawColor(renderer, bodyColor.r, bodyColor.g, bodyColor.b, 255);
    
    // Testa
    SDL_Rect head = {(int)x - 6, (int)y - 10, 12, 12};
    SDL_RenderFillRect(renderer, &head);
    
    // Corpo
    SDL_Rect body = {(int)x - 2, (int)y + 2, 4, 8};
    SDL_RenderFillRect(renderer, &body);
    
    // Braccia
    SDL_Rect arm1 = {(int)x - 8, (int)y + 4, 6, 2};
    SDL_Rect arm2 = {(int)x + 2, (int)y + 4, 6, 2};
    SDL_RenderFillRect(renderer, &arm1);
    SDL_RenderFillRect(renderer, &arm2);
    
    // Gambe
    SDL_Rect leg1 = {(int)x - 4, (int)y + 10, 3, 6};
    SDL_Rect leg2 = {(int)x + 1, (int)y + 10, 3, 6};
    SDL_RenderFillRect(renderer, &leg1);
    SDL_RenderFillRect(renderer, &leg2);

    // Disegna proiettili
    SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255);
    for (const auto& p : projectiles) {
        if (p.active) {
            SDL_Rect proj = {(int)p.x - 3, (int)p.y - 3, 6, 6};
            SDL_RenderFillRect(renderer, &proj);
        }
    }
}