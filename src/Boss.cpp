#include "Boss.h"
#include "Weapon.h"
#include <cstdlib>
#include <cmath> // <-- AGGIUNTO PER sqrt, sin, cos, M_PI

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

Boss::Boss(int lvl, int w, int h) : shootTimer(0) {
    level = lvl; screenWidth = w; screenHeight = h;
    size = 100 + lvl * 10; 
    pos.x = w / 2.0f; pos.y = UI_HEIGHT + 100.0f + size;
    dx = (lvl % 2 == 0) ? 2 : -2; dy = (lvl % 3 == 0) ? 1 : -1;
    speed = 1 + lvl / 2;
    health = 30 + lvl * 15; maxHealth = health;
    switch(lvl % 4) {
        case 0: color = sf::Color(255, 50, 50); break;
        case 1: color = sf::Color(50, 255, 50); break;
        case 2: color = sf::Color(50, 50, 255); break;
        case 3: color = sf::Color(255, 255, 50); break;
    }
}

void Boss::update(float playerX, float playerY, std::vector<Projectile>& bossProjectiles) {
    pos.x += dx * speed; pos.y += dy * speed;
    if (pos.x < size/2 || pos.x > screenWidth - size/2) dx = -dx;
    if (pos.y < UI_HEIGHT + size/2 || pos.y > screenHeight - size/2) dy = -dy;
    shootTimer += 16;
    if (shootTimer > (1500 - level * 100)) {
        shootTimer = 0;
        float dxp = playerX - pos.x, dyp = playerY - pos.y;
        float dist = sqrt(dxp*dxp + dyp*dyp);
        if (dist > 0) bossProjectiles.push_back({pos, sf::Vector2f(dxp/dist * 4.f, dyp/dist * 4.f), 1, true, WPN_PISTOL});
    }
}

void Boss::takeDamage(int dmg) { health -= dmg; }

void Boss::render(sf::RenderTarget& target) const {
    sf::CircleShape shadow(size/2.f);
    shadow.setFillColor(sf::Color(0, 0, 0, 100));
    shadow.setPosition(pos.x - size/2.f, pos.y + size/3.f); target.draw(shadow);

    sf::CircleShape body(size/2.f);
    body.setFillColor(color);
    body.setPosition(pos.x - size/2.f, pos.y - size/2.f); target.draw(body);

    sf::Color tc(color.r/2, color.g/2, color.b/2);
    for(int i=0; i<8; i++) {
        float angle = i * (M_PI / 4);
        sf::CircleShape tentacle(size/6.f);
        tentacle.setFillColor(tc);
        tentacle.setPosition(pos.x + cos(angle) * size/2.f - size/6.f, pos.y + sin(angle) * size/2.f - size/6.f);
        target.draw(tentacle);
    }

    sf::CircleShape eye1(size/8.f); eye1.setFillColor(sf::Color::White);
    eye1.setPosition(pos.x - size/4.f - size/8.f, pos.y - size/6.f - size/8.f); target.draw(eye1);
    sf::CircleShape eye2(size/8.f); eye2.setFillColor(sf::Color::White);
    eye2.setPosition(pos.x + size/4.f - size/8.f, pos.y - size/6.f - size/8.f); target.draw(eye2);
    sf::CircleShape p1(size/16.f); p1.setFillColor(sf::Color::Black);
    p1.setPosition(pos.x - size/4.f - size/16.f, pos.y - size/6.f - size/16.f); target.draw(p1);
    sf::CircleShape p2(size/16.f); p2.setFillColor(sf::Color::Black);
    p2.setPosition(pos.x + size/4.f - size/16.f, pos.y - size/6.f - size/16.f); target.draw(p2);

    sf::RectangleShape hbBg(sf::Vector2f(size, 10.f)); hbBg.setFillColor(sf::Color::Red);
    hbBg.setPosition(pos.x - size/2.f, pos.y - size/2.f - 20.f); target.draw(hbBg);
    sf::RectangleShape hbFg(sf::Vector2f(size * health / maxHealth, 10.f)); hbFg.setFillColor(sf::Color::Green);
    hbFg.setPosition(pos.x - size/2.f, pos.y - size/2.f - 20.f); target.draw(hbFg);
}