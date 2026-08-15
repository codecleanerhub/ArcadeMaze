#include "Boss.h"
#include "Weapon.h"
#include <cstdlib>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

Boss::Boss(int lvl, int w, int h) : shootTimer(0) {
    level = lvl; screenWidth = w; screenHeight = h;
    size = 160 + lvl * 10; 
    pos.x = w / 2.0f; pos.y = UI_HEIGHT + 120.0f + size;
    dx = (lvl % 2 == 0) ? 2 : -2; dy = (lvl % 3 == 0) ? 1 : -1;
    speed = 1 + lvl / 2;
    health = 50 + lvl * 20; maxHealth = health;
    type = static_cast<BossType>((lvl - 1) % 10); // 10 tipi di boss
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

    if (type == BOSS_GOLEM) {
        sf::Color rock(100, 100, 110);
        sf::RectangleShape body(sf::Vector2f(size, size*0.8f)); body.setFillColor(rock); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.f, py - size*0.4f); target.draw(body);
        sf::RectangleShape arm1(sf::Vector2f(size*0.3f, size*0.6f)); arm1.setFillColor(sf::Color(60, 60, 70)); arm1.setOutlineThickness(3.f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*0.8f, py - size*0.2f); target.draw(arm1);
        arm1.setPosition(px + size*0.5f, py - size*0.2f); target.draw(arm1);
        sf::RectangleShape head(sf::Vector2f(size*0.5f, size*0.5f)); head.setFillColor(rock); head.setOutlineThickness(3.f); head.setOutlineColor(outline);
        head.setPosition(px - size*0.25f, py - size*0.8f); target.draw(head);
        sf::CircleShape eye(size/12.f); eye.setFillColor(sf::Color(0, 255, 50));
        eye.setPosition(px - size/4.f - size/12.f, py - size*0.6f); target.draw(eye);
        eye.setPosition(px + size/4.f - size/12.f, py - size*0.6f); target.draw(eye);
    } 
    else if (type == BOSS_LICH) {
        sf::ConvexShape robe; robe.setPointCount(5);
        robe.setFillColor(sf::Color(40, 20, 60)); robe.setOutlineThickness(4.f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py - size/2.f)); robe.setPoint(1, sf::Vector2f(px + size/2.f, py));
        robe.setPoint(2, sf::Vector2f(px + size/3.f, py + size/2.f)); robe.setPoint(3, sf::Vector2f(px - size/3.f, py + size/2.f));
        robe.setPoint(4, sf::Vector2f(px - size/2.f, py));
        target.draw(robe);
        sf::CircleShape skull(size/3.f); skull.setFillColor(sf::Color(220, 220, 200)); skull.setOutlineThickness(3.f); skull.setOutlineColor(outline);
        skull.setPosition(px - size/3.f, py - size/2.f); target.draw(skull);
        sf::CircleShape eye(size/14.f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px - size/5.f, py - size/3.f); target.draw(eye);
        eye.setPosition(px + size/10.f, py - size/3.f); target.draw(eye);
    } 
    else if (type == BOSS_DEMON) {
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(80, 10, 10)); wing.setOutlineThickness(3.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px - size/3.f, py - size/4.f)); wing.setPoint(1, sf::Vector2f(px - size*1.2f, py - size/2.f));
        wing.setPoint(2, sf::Vector2f(px - size*1.1f, py + size/4.f)); wing.setPoint(3, sf::Vector2f(px - size/3.f, py + size/6.f));
        target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px + size/3.f, py - size/4.f); target.draw(wing);
        sf::CircleShape body(size/2.f); body.setFillColor(sf::Color(150, 30, 30)); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.f, py - size/2.f); target.draw(body);
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(outline);
        horn.setPoint(0, sf::Vector2f(px - size/3.f, py - size/2.f)); horn.setPoint(1, sf::Vector2f(px - size/2.f, py - size*0.8f)); horn.setPoint(2, sf::Vector2f(px - size/4.f, py - size*0.7f));
        target.draw(horn);
        horn.setPoint(0, sf::Vector2f(px + size/3.f, py - size/2.f)); horn.setPoint(1, sf::Vector2f(px + size/2.f, py - size*0.8f)); horn.setPoint(2, sf::Vector2f(px + size/4.f, py - size*0.7f));
        target.draw(horn);
        sf::CircleShape eye(size/10.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - size/4.f - size/10.f, py - size/6.f); target.draw(eye);
        eye.setPosition(px + size/4.f - size/10.f, py - size/6.f); target.draw(eye);
    } 
    else if (type == BOSS_SPIDER) {
        sf::Color carapace(40, 0, 50);
        for(int i=0; i<4; i++) {
            float angle1 = (45 + i*20) * M_PI / 180.0;
            float angle2 = (-45 - i*20) * M_PI / 180.0;
            sf::RectangleShape leg1(sf::Vector2f(size/2.f, size/16.f)); leg1.setFillColor(carapace); leg1.setOutlineThickness(2.f); leg1.setOutlineColor(outline);
            leg1.rotate(angle1 * 180 / M_PI); leg1.setPosition(px - size/4.f, py); target.draw(leg1);
            sf::RectangleShape leg2(sf::Vector2f(size/2.f, size/16.f)); leg2.setFillColor(carapace); leg2.setOutlineThickness(2.f); leg2.setOutlineColor(outline);
            leg2.rotate(angle2 * 180 / M_PI); leg2.setPosition(px + size/4.f, py); target.draw(leg2);
        }
        sf::CircleShape abdomen(size/2.f); abdomen.setFillColor(carapace); abdomen.setOutlineThickness(4.f); abdomen.setOutlineColor(outline);
        abdomen.setPosition(px - size/2.f, py - size/4.f); target.draw(abdomen);
        sf::CircleShape head(size/4.f); head.setFillColor(sf::Color(60, 0, 70)); head.setOutlineThickness(3.f); head.setOutlineColor(outline);
        head.setPosition(px - size/8.f, py - size/1.5f); target.draw(head);
        sf::CircleShape eye(size/20.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - size/6.f, py - size/1.6f); target.draw(eye);
        eye.setPosition(px + size/12.f, py - size/1.6f); target.draw(eye);
    }
    else if (type == BOSS_ABOMINATION) {
        // Abominio di carne (Frankenstein)
        sf::Color flesh(140, 160, 120);
        sf::RectangleShape body(sf::Vector2f(size*0.8f, size)); body.setFillColor(flesh); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
        body.setPosition(px - size*0.4f, py - size/2.f); target.draw(body);
        // Cuciture
        sf::RectangleShape s1(sf::Vector2f(size*0.8f, 2.f)); s1.setFillColor(sf::Color(80, 0, 0));
        s1.setPosition(px - size*0.4f, py - size/4.f); target.draw(s1);
        s1.setPosition(px - size*0.4f, py + size/4.f); target.draw(s1);
        // Braccia enormi
        sf::RectangleShape arm1(sf::Vector2f(size*0.3f, size*0.7f)); arm1.setFillColor(flesh); arm1.setOutlineThickness(3.f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*0.7f, py - size/3.f); target.draw(arm1);
        arm1.setPosition(px + size*0.4f, py - size/3.f); target.draw(arm1);
        // Testa con bulloni
        sf::RectangleShape head(sf::Vector2f(size*0.4f, size*0.4f)); head.setFillColor(flesh); head.setOutlineThickness(3.f); head.setOutlineColor(outline);
        head.setPosition(px - size*0.2f, py - size*0.9f); target.draw(head);
        sf::RectangleShape bolt1(sf::Vector2f(size*0.1f, size*0.1f)); bolt1.setFillColor(sf::Color(180, 180, 180));
        bolt1.setPosition(px - size*0.3f, py - size*0.8f); target.draw(bolt1);
        bolt1.setPosition(px + size*0.2f, py - size*0.8f); target.draw(bolt1);
        // Occhi spenti
        sf::CircleShape eye(size/14.f); eye.setFillColor(sf::Color(50, 50, 50));
        eye.setPosition(px - size/5.f, py - size*0.75f); target.draw(eye);
        eye.setPosition(px + size/10.f, py - size*0.75f); target.draw(eye);
    }
    else if (type == BOSS_KRAKEN) {
        // Kraken/Cthulhu
        sf::Color skin(0, 100, 100);
        sf::CircleShape body(size/2.f); body.setFillColor(skin); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.f, py - size/2.f); target.draw(body);
        // Tentacoli
        for(int i=0; i<8; i++) {
            float angle = i * (M_PI / 4);
            sf::ConvexShape tent; tent.setPointCount(4); tent.setFillColor(skin); tent.setOutlineThickness(2.f); tent.setOutlineColor(outline);
            tent.setPoint(0, sf::Vector2f(px, py));
            tent.setPoint(1, sf::Vector2f(px + cos(angle)*size/3.f, py + sin(angle)*size/3.f));
            tent.setPoint(2, sf::Vector2f(px + cos(angle)*size/2.f + 10, py + sin(angle)*size/2.f + 10));
            tent.setPoint(3, sf::Vector2f(px + cos(angle)*size/2.f - 10, py + sin(angle)*size/2.f - 10));
            target.draw(tent);
        }
        // Occhi maligni
        sf::CircleShape eye(size/10.f); eye.setFillColor(sf::Color(255, 255, 0));
        eye.setPosition(px - size/4.f - size/10.f, py - size/4.f); target.draw(eye);
        eye.setPosition(px + size/4.f - size/10.f, py - size/4.f); target.draw(eye);
        // Ventose sul corpo
        sf::CircleShape vent(size/30.f); vent.setFillColor(sf::Color(0, 130, 130));
        for(int i=0; i<5; i++) {
            vent.setPosition(px - size/3.f + i*10, py); target.draw(vent);
        }
    }
    else if (type == BOSS_DRAGON) {
        // Drago scheletrico
        sf::Color bone(200, 200, 180);
        // Ali scheletriche
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(50, 50, 50)); wing.setOutlineThickness(3.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px - size/4.f, py - size/3.f)); wing.setPoint(1, sf::Vector2f(px - size, py - size/2.f));
        wing.setPoint(2, sf::Vector2f(px - size*0.9f, py + size/6.f)); wing.setPoint(3, sf::Vector2f(px - size/4.f, py));
        target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px + size/4.f, py - size/3.f); target.draw(wing);
        // Collo lungo
        sf::RectangleShape neck(sf::Vector2f(size*0.2f, size*0.8f)); neck.setFillColor(bone); neck.rotate(-30); neck.setOutlineThickness(3.f); neck.setOutlineColor(outline);
        neck.setPosition(px - size*0.1f, py - size*0.1f); target.draw(neck);
        // Testa
        sf::ConvexShape head; head.setPointCount(4); head.setFillColor(bone); head.setOutlineThickness(3.f); head.setOutlineColor(outline);
        head.setPoint(0, sf::Vector2f(px - size/2.f, py - size)); head.setPoint(1, sf::Vector2f(px - size/4.f, py - size*1.1f));
        head.setPoint(2, sf::Vector2f(px - size/4.f, py - size*0.9f)); head.setPoint(3, sf::Vector2f(px - size/2.f, py - size*0.9f));
        target.draw(head);
        // Occhio rosso
        sf::CircleShape eye(size/20.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - size/2.f + size/20.f, py - size + size/20.f); target.draw(eye);
        // Corpo
        sf::RectangleShape body(sf::Vector2f(size*0.6f, size*0.6f)); body.setFillColor(bone); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
        body.setPosition(px - size*0.3f, py - size*0.2f); target.draw(body);
    }
    else if (type == BOSS_WRAITH_LORD) {
        // Signore dei Wraith (armatura spettrale)
        sf::Color armor(100, 100, 150);
        // Mantella strappata
        sf::ConvexShape cloak; cloak.setPointCount(6); cloak.setFillColor(sf::Color(20, 20, 40, 220)); cloak.setOutlineThickness(4.f); cloak.setOutlineColor(outline);
        cloak.setPoint(0, sf::Vector2f(px - size/2.f, py - size/3.f)); cloak.setPoint(1, sf::Vector2f(px + size/2.f, py - size/3.f));
        cloak.setPoint(2, sf::Vector2f(px + size/3.f, py + size/2.f)); cloak.setPoint(3, sf::Vector2f(px + size/6.f, py + size/3.f));
        cloak.setPoint(4, sf::Vector2f(px - size/6.f, py + size/2.f)); cloak.setPoint(5, sf::Vector2f(px - size/3.f, py + size/3.f));
        target.draw(cloak);
        // Elmo
        sf::RectangleShape helm(sf::Vector2f(size*0.4f, size*0.5f)); helm.setFillColor(armor); helm.setOutlineThickness(3.f); helm.setOutlineColor(outline);
        helm.setPosition(px - size*0.2f, py - size*0.6f); target.draw(helm);
        // Corna dell'elmo
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(armor);
        horn.setPoint(0, sf::Vector2f(px - size*0.2f, py - size*0.6f)); horn.setPoint(1, sf::Vector2f(px - size*0.4f, py - size*0.8f)); horn.setPoint(2, sf::Vector2f(px - size*0.2f, py - size*0.5f));
        target.draw(horn);
        horn.setPoint(0, sf::Vector2f(px + size*0.2f, py - size*0.6f)); horn.setPoint(1, sf::Vector2f(px + size*0.4f, py - size*0.8f)); horn.setPoint(2, sf::Vector2f(px + size*0.2f, py - size*0.5f));
        target.draw(horn);
        // Occhi blu spettrali
        sf::CircleShape eye(size/14.f); eye.setFillColor(sf::Color(0, 255, 255, 200));
        eye.setPosition(px - size/5.f, py - size*0.45f); target.draw(eye);
        eye.setPosition(px + size/10.f, py - size*0.45f); target.draw(eye);
    }
    else if (type == BOSS_VAMPIRE) {
        // Signore dei Vampiri
        sf::Color skin(230, 230, 250);
        // Mantello
        sf::ConvexShape cloak; cloak.setPointCount(4); cloak.setFillColor(sf::Color(120, 0, 0)); cloak.setOutlineThickness(4.f); cloak.setOutlineColor(outline);
        cloak.setPoint(0, sf::Vector2f(px - size/2.f, py - size/4.f)); cloak.setPoint(1, sf::Vector2f(px + size/2.f, py - size/4.f));
        cloak.setPoint(2, sf::Vector2f(px + size/3.f, py + size/2.f)); cloak.setPoint(3, sf::Vector2f(px - size/3.f, py + size/2.f));
        target.draw(cloak);
        // Colletto bianco
        sf::RectangleShape collar(sf::Vector2f(size*0.3f, size*0.1f)); collar.setFillColor(sf::Color(255, 255, 255)); collar.setOutlineThickness(2.f); collar.setOutlineColor(outline);
        collar.setPosition(px - size*0.15f, py - size*0.3f); target.draw(collar);
        // Testa pallida
        sf::CircleShape head(size/3.f); head.setFillColor(skin); head.setOutlineThickness(3.f); head.setOutlineColor(outline);
        head.setPosition(px - size/3.f, py - size/2.f); target.draw(head);
        // Capelli neri
        sf::RectangleShape hair(sf::Vector2f(size*0.6f, size*0.2f)); hair.setFillColor(sf::Color::Black);
        hair.setPosition(px - size*0.3f, py - size*0.5f); target.draw(hair);
        // Occhi rossi
        sf::CircleShape eye(size/14.f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px - size/5.f, py - size/3.f); target.draw(eye);
        eye.setPosition(px + size/10.f, py - size/3.f); target.draw(eye);
        // Zanne
        sf::ConvexShape fang; fang.setPointCount(3); fang.setFillColor(sf::Color::White);
        fang.setPoint(0, sf::Vector2f(px - size/6.f, py - size/12.f)); fang.setPoint(1, sf::Vector2f(px - size/10.f, py - size/12.f)); fang.setPoint(2, sf::Vector2f(px - size/8.f, py));
        target.draw(fang);
        fang.setPoint(0, sf::Vector2f(px + size/10.f, py - size/12.f)); fang.setPoint(1, sf::Vector2f(px + size/6.f, py - size/12.f)); fang.setPoint(2, sf::Vector2f(px + size/8.f, py));
        target.draw(fang);
    }
    else if (type == BOSS_BEHOLDER) {
        // Beholder (Occhio tiranno)
        sf::Color bodyCol(100, 50, 50);
        // Corpo centrale (globo)
        sf::CircleShape body(size/2.f); body.setFillColor(bodyCol); body.setOutlineThickness(4.f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.f, py - size/2.f); target.draw(body);
        // Occhio centrale enorme
        sf::CircleShape eye(size/4.f); eye.setFillColor(sf::Color::White); eye.setOutlineThickness(2.f); eye.setOutlineColor(outline);
        eye.setPosition(px - size/4.f, py - size/4.f); target.draw(eye);
        sf::CircleShape pupil(size/8.f); pupil.setFillColor(sf::Color::Black);
        pupil.setPosition(px - size/8.f, py - size/8.f); target.draw(pupil);
        sf::CircleShape iris(size/16.f); iris.setFillColor(sf::Color(255, 0, 0));
        iris.setPosition(px - size/16.f, py - size/16.f); target.draw(iris);
        // Stalks (piccoli occhi su tentacoli)
        for(int i=0; i<8; i++) {
            float angle = i * (M_PI / 4);
            float tx = px + cos(angle) * size/2.f;
            float ty = py + sin(angle) * size/2.f;
            // Gambo
            sf::RectangleShape stalk(sf::Vector2f(size/8.f, size/3.f)); stalk.setFillColor(bodyCol); stalk.setOutlineThickness(2.f); stalk.setOutlineColor(outline);
            stalk.rotate(angle * 180 / M_PI + 90); stalk.setPosition(tx, ty); target.draw(stalk);
            // Occhio
            sf::CircleShape sEye(size/12.f); sEye.setFillColor(sf::Color::White); sEye.setOutlineThickness(1.f); sEye.setOutlineColor(outline);
            sEye.setPosition(tx - size/12.f, ty - size/12.f); target.draw(sEye);
            sf::CircleShape sPupil(size/24.f); sPupil.setFillColor(sf::Color::Black);
            sPupil.setPosition(tx - size/24.f, ty - size/24.f); target.draw(sPupil);
        }
    }

    // Bocca/Denti generici (tranne beholder)
    if(type != BOSS_BEHOLDER) {
        sf::RectangleShape mouth(sf::Vector2f(size*0.6f, size/6.f));
        mouth.setFillColor(sf::Color::Black);
        mouth.setPosition(px - size*0.3f, py + size/6.f);
        target.draw(mouth);
    }

    // Barra vita
    sf::RectangleShape hbBg(sf::Vector2f(size, 15.f)); hbBg.setFillColor(sf::Color(50, 0, 0));
    hbBg.setPosition(px - size/2.f, py - size/2.f - 30.f); target.draw(hbBg);
    sf::RectangleShape hbFg(sf::Vector2f(size * health / maxHealth, 15.f)); hbFg.setFillColor(sf::Color(255, 50, 50));
    hbFg.setPosition(px - size/2.f, py - size/2.f - 30.f); target.draw(hbFg);
}