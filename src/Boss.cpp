#include "Boss.h"
#include "Weapon.h"
#include <cstdlib>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

Boss::Boss(int lvl, int w, int h) : shootTimer(0) {
    level = lvl; screenWidth = w; screenHeight = h;
    size = 180 + lvl * 20; // Molto più grande
    pos.x = w / 2.0f; pos.y = UI_HEIGHT + 150.0f + size;
    dx = (lvl % 2 == 0) ? 2 : -2; dy = (lvl % 3 == 0) ? 1 : -1;
    speed = 1 + lvl / 2;
    health = 50 + lvl * 20; maxHealth = health;
    switch(lvl % 4) {
        case 0: color = sf::Color(255, 50, 50); break;  // Rosso
        case 1: color = sf::Color(50, 255, 50); break;  // Verde
        case 2: color = sf::Color(50, 50, 255); break;  // Blu
        case 3: color = sf::Color(255, 255, 50); break; // Giallo
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
    float px = pos.x;
    float py = pos.y;
    sf::Color outline(10, 10, 10);

    // Ombra
    sf::CircleShape shadow(size/2.f);
    shadow.setFillColor(sf::Color(0, 0, 0, 150));
    shadow.setPosition(px - size/2.f, py + size/4.f); target.draw(shadow);

    // Tentacoli
    sf::Color tc(color.r/2, color.g/2, color.b/2);
    for(int i=0; i<10; i++) {
        float angle = i * (M_PI / 5) + (shootTimer/1000.0f); // Tentacoli ondeggianti
        sf::CircleShape tentacle(size/5.f);
        tentacle.setFillColor(tc); tentacle.setOutlineThickness(3.f); tentacle.setOutlineColor(outline);
        tentacle.setPosition(px + cos(angle) * size/2.f - size/5.f, py + sin(angle) * size/2.f - size/5.f);
        target.draw(tentacle);
    }

    // Corpo centrale
    sf::CircleShape body(size/2.f);
    body.setFillColor(color); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
    body.setPosition(px - size/2.f, py - size/2.f); target.draw(body);

    // Occhi multipli
    for(int i=0; i<3; i++) {
        for(int j=0; j<3; j++) {
            if((i+j)%2==0) {
                float ex = px - size/3.f + i * size/3.f;
                float ey = py - size/4.f + j * size/4.f;
                sf::CircleShape eye(size/10.f); eye.setFillColor(sf::Color::White);
                eye.setPosition(ex - size/10.f, ey - size/10.f); target.draw(eye);
                sf::CircleShape pupil(size/20.f); pupil.setFillColor(sf::Color::Black);
                pupil.setPosition(ex - size/20.f, ey - size/20.f); target.draw(pupil);
            }
        }
    }

    // Bocca dentata
    sf::RectangleShape mouth(sf::Vector2f(size*0.8f, size/4.f));
    mouth.setFillColor(sf::Color::Black);
    mouth.setPosition(px - size*0.4f, py + size/8.f);
    target.draw(mouth);
    
    // Denti
    for(int i=0; i<6; i++) {
        sf::ConvexShape tooth; tooth.setPointCount(3);
        tooth.setFillColor(sf::Color::White); tooth.setOutlineThickness(2.f); tooth.setOutlineColor(outline);
        tooth.setPoint(0, sf::Vector2f(px - size*0.4f + i * (size*0.8f)/6, py + size/8.f));
        tooth.setPoint(1, sf::Vector2f(px - size*0.4f + (i+1) * (size*0.8f)/6, py + size/8.f));
        tooth.setPoint(2, sf::Vector2f(px - size*0.4f + i * (size*0.8f)/6 + (size*0.8f)/12, py + size/4.f));
        target.draw(tooth);
    }

    // Barra vita
    sf::RectangleShape hbBg(sf::Vector2f(size, 15.f)); hbBg.setFillColor(sf::Color(50, 0, 0));
    hbBg.setPosition(px - size/2.f, py - size/2.f - 30.f); target.draw(hbBg);
    sf::RectangleShape hbFg(sf::Vector2f(size * health / maxHealth, 15.f)); hbFg.setFillColor(sf::Color(255, 50, 50));
    hbFg.setPosition(px - size/2.f, py - size/2.f - 30.f); target.draw(hbFg);
}