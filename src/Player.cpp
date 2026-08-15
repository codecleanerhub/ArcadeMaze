#include "Player.h"
#include <iostream>
#include <algorithm>
#include <cmath>

Player::Player() { reset(); }

void Player::reset() {
    resetPosition();
    lives = 3; maxEnergy = 5; energy = maxEnergy;
    score = 0; nextLifeThreshold = 100000;
    currentWeapon = Weapon::generate(WPN_PISTOL);
    projectiles.clear();
}

void Player::resetPosition() {
    pos.x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
    pos.y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0; nextDx = 0; nextDy = 0; lastDx = 1; lastDy = 0;
    speed = 2; jumpTimer = 0; maxJumpTime = 0; damageTimer = 0; shootCooldown = 0;
    jumpOffset = 0.0f;
}

void Player::setPosition(float newX, float newY) {
    pos.x = newX; pos.y = newY; dx = 0; dy = 0; nextDx = 0; nextDy = 0;
}

bool Player::tryMove(int tDx, int tDy, Maze& maze) {
    int col = (int)(pos.x / TILE_SIZE);
    int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
    if (!maze.isWall(col + tDx, row + tDy)) {
        dx = tDx; dy = tDy; lastDx = tDx; lastDy = tDy;
        return true;
    }
    return false;
}

void Player::update(Maze& maze, bool freeMovement, std::vector<Particle>& particles) {
    if (jumpTimer > 0) {
        jumpTimer--;
        float progress = 1.0f - (float)jumpTimer / (float)maxJumpTime;
        jumpOffset = sin(progress * M_PI) * 25.0f; // Altezza salto
    } else {
        jumpOffset = 0.0f;
    }
    
    if (damageTimer > 16) damageTimer -= 16; else damageTimer = 0;
    if (shootCooldown > 16) shootCooldown -= 16; else shootCooldown = 0;

    if (freeMovement) {
        if (nextDx != 0 || nextDy != 0) {
            dx = nextDx; dy = nextDy; lastDx = dx; lastDy = dy; nextDx = 0; nextDy = 0;
        }
        pos.x += dx * speed; pos.y += dy * speed;
        if (pos.x < 16) pos.x = 16;
        if (pos.x > WINDOW_WIDTH - 16) pos.x = WINDOW_WIDTH - 16;
        if (pos.y < UI_HEIGHT + 16) pos.y = UI_HEIGHT + 16;
        if (pos.y > WINDOW_HEIGHT - 16) pos.y = WINDOW_HEIGHT - 16;
    } else {
        int col = (int)(pos.x / TILE_SIZE);
        int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
        float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
        float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
        if (fabs(pos.x - centerX) < speed && fabs(pos.y - centerY) < speed) {
            pos.x = centerX; pos.y = centerY;
            if (nextDx != 0 || nextDy != 0) { tryMove(nextDx, nextDy, maze); nextDx = 0; nextDy = 0; }
            if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
        }
        pos.x += dx * speed; pos.y += dy * speed;
        if (maze.getCellType(col, row) == CELL_TREASURE) {
            maze.collectTreasure(col, row);
            addScore(10000);
            for(int i=0; i<15; i++) {
                particles.push_back({pos, {(float)(rand()%6-3), (float)(rand()%6-3)}, sf::Color(255, 215, 0), 40, 40});
            }
        } else if (maze.getCellType(col, row) == CELL_WEAPON) {
            Weapon w = maze.collectWeapon(col, row);
            collectWeapon(w);
        }
    }

    for (auto& p : projectiles) {
        if (!p.active) continue;
        if (!freeMovement) {
            int pCol = (int)(p.pos.x / TILE_SIZE);
            int pRow = (int)((p.pos.y - UI_HEIGHT) / TILE_SIZE);
            if (maze.isWall(pCol, pRow)) { p.active = false; continue; }
        }
        p.pos.x += p.dir.x * 8.f; p.pos.y += p.dir.y * 8.f;
        if (p.pos.x < 0 || p.pos.x > WINDOW_WIDTH || p.pos.y < UI_HEIGHT || p.pos.y > WINDOW_HEIGHT) p.active = false;
    }
    projectiles.erase(std::remove_if(projectiles.begin(), projectiles.end(), [](const Projectile& p) { return !p.active; }), projectiles.end());
}

void Player::shoot() {
    if (currentWeapon.ammo > 0) {
        int shootDx = (dx != 0) ? dx : lastDx;
        int shootDy = (dy != 0) ? dy : lastDy;
        
        if (shootDx == 0 && shootDy == 0) shootDx = 1; // Fallback se fermo
        
        projectiles.push_back({pos, sf::Vector2f((float)shootDx, (float)shootDy), currentWeapon.power, true, currentWeapon.type});
        currentWeapon.ammo--;
    }
}

void Player::takeDamage() {
    if (!isJumping() && damageTimer == 0) {
        energy--;
        damageTimer = 1000;
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

Vec2 Player::getGridPos() const { return { (int)(pos.x / TILE_SIZE), (int)((pos.y - UI_HEIGHT) / TILE_SIZE) }; }

void Player::render(sf::RenderTarget& target) {
    float px = pos.x;
    float py = pos.y - jumpOffset; // Applica offset visivo del salto

    drawTextCentered(target, currentWeapon.getName(), px, pos.y - 45, 2, sf::Color(255, 255, 0));

    sf::Color skin(210, 180, 140);
    sf::Color shirt(200, 200, 200);
    sf::Color jacket(139, 69, 19);
    sf::Color pants(50, 50, 50);
    sf::Color hat(80, 50, 20);
    sf::Color outline(10, 10, 10);

    // Gambe (stile Super Mario se salta)
    if (isJumping()) {
        sf::RectangleShape leg1(sf::Vector2f(8.f, 16.f)); leg1.setFillColor(pants); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 12.f, py + 4.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(8.f, 16.f)); leg2.setFillColor(pants); leg2.setOutlineThickness(1.f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 4.f, py + 4.f); target.draw(leg2);
    } else {
        sf::RectangleShape leg1(sf::Vector2f(8.f, 20.f)); leg1.setFillColor(pants); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 4.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(8.f, 20.f)); leg2.setFillColor(pants); leg2.setOutlineThickness(1.f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 2.f, py + 4.f); target.draw(leg2);
    }

    // Corpo (Camicia)
    sf::RectangleShape body(sf::Vector2f(24.f, 20.f)); body.setFillColor(shirt); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
    body.setPosition(px - 12.f, py - 8.f); target.draw(body);
    // Giubbotto di pelle (ai lati)
    sf::RectangleShape jacket1(sf::Vector2f(6.f, 20.f)); jacket1.setFillColor(jacket); jacket1.setOutlineThickness(1.f); jacket1.setOutlineColor(outline);
    jacket1.setPosition(px - 12.f, py - 8.f); target.draw(jacket1);
    sf::RectangleShape jacket2(sf::Vector2f(6.f, 20.f)); jacket2.setFillColor(jacket); jacket2.setOutlineThickness(1.f); jacket2.setOutlineColor(outline);
    jacket2.setPosition(px + 6.f, py - 8.f); target.draw(jacket2);

    // Braccia
    sf::RectangleShape arm1(sf::Vector2f(6.f, 16.f)); arm1.setFillColor(shirt); arm1.setOutlineThickness(1.f); arm1.setOutlineColor(outline);
    arm1.setPosition(px - 14.f, py - 6.f); target.draw(arm1);
    sf::RectangleShape arm2(sf::Vector2f(6.f, 16.f)); arm2.setFillColor(shirt); arm2.setOutlineThickness(1.f); arm2.setOutlineColor(outline);
    arm2.setPosition(px + 8.f, py - 6.f); target.draw(arm2);

    // Testa
    sf::CircleShape head(8.f); head.setFillColor(skin); head.setOutlineThickness(1.f); head.setOutlineColor(outline);
    head.setPosition(px - 8.f, py - 22.f); target.draw(head);

    // Cappello Fedora
    sf::RectangleShape top(sf::Vector2f(14.f, 6.f)); top.setFillColor(hat); top.setOutlineThickness(1.f); top.setOutlineColor(outline);
    top.setPosition(px - 7.f, py - 28.f); target.draw(top);
    sf::RectangleShape brim(sf::Vector2f(24.f, 4.f)); brim.setFillColor(hat); brim.setOutlineThickness(1.f); brim.setOutlineColor(outline);
    brim.setPosition(px - 12.f, py - 24.f); target.draw(brim);

    // Frusta sul fianco
    sf::RectangleShape whip(sf::Vector2f(2.f, 12.f)); whip.setFillColor(sf::Color(100, 50, 10));
    whip.setPosition(px + 10.f, py - 4.f); target.draw(whip);

    // Arma in mano
    currentWeapon.renderEquipped(target, px + (lastDx * 16), py);

    // Proiettili
    for (const auto& p : projectiles) {
        if (p.active) {
            if (p.type == WPN_PISTOL) {
                sf::CircleShape proj(6.f); proj.setFillColor(sf::Color(255, 255, 100));
                proj.setPosition(p.pos.x - 6.f, p.pos.y - 6.f); target.draw(proj);
            } else if (p.type == WPN_LASER) {
                sf::RectangleShape beam(sf::Vector2f(24.f, 6.f)); beam.setFillColor(sf::Color(50, 200, 255));
                beam.setPosition(p.pos.x - 12.f, p.pos.y - 3.f); target.draw(beam);
            } else {
                sf::CircleShape proj(8.f); proj.setFillColor(sf::Color(200, 50, 50));
                proj.setPosition(p.pos.x - 8.f, p.pos.y - 8.f); target.draw(proj);
            }
        }
    }
}