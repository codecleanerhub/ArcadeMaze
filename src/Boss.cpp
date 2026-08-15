#include "Boss.h"
#include "Weapon.h"
#include <cstdlib>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

Boss::Boss(int lvl, int w, int h) : shootTimer(0), animTime(0.0f) {
    level = lvl; screenWidth = w; screenHeight = h;
    size = 160 + lvl * 10; 
    pos.x = w / 2.0f; pos.y = UI_HEIGHT + 120.0f + size;
    dx = (lvl % 2 == 0) ? 2 : -2; dy = (lvl % 3 == 0) ? 1 : -1;
    speed = 1 + lvl / 2;
    health = 50 + lvl * 20; maxHealth = health;
    type = static_cast<BossType>((lvl - 1) % 10);
}

void Boss::update(float playerX, float playerY, std::vector<Projectile>& bossProjectiles) {
    animTime += 0.016f;
    pos.x += dx * speed; pos.y += dy * speed;
    if (pos.x < size/2 || pos.x > screenWidth - size/2) dx = -dx;
    if (pos.y < UI_HEIGHT + size/2 || pos.y > screenHeight - size/2) dy = -dy;
    shootTimer += 16;
    
    if (shootTimer > (1500 - level * 100)) {
        shootTimer = 0;
        float dxp = playerX - pos.x, dyp = playerY - pos.y;
        float dist = sqrt(dxp*dxp + dyp*dyp);
        if (dist > 0) {
            float baseAngle = atan2(dyp, dxp);
            for(int i = -1; i <= 1; i++) {
                float angle = baseAngle + i * 0.3f;
                bossProjectiles.push_back({pos, sf::Vector2f(cos(angle)*5.0f, sin(angle)*5.0f), 1, true, WPN_PISTOL});
            }
            if (rand() % 3 == 0) {
                float bombAngle = baseAngle + (rand()%60 - 30) * (M_PI/180.0f);
                bossProjectiles.push_back({pos, sf::Vector2f(cos(bombAngle)*2.0f, sin(bombAngle)*2.0f), 2, true, WPN_ROCKET});
            }
        }
    }
}

void Boss::takeDamage(int dmg) { health -= dmg; }

void Boss::render(sf::RenderTarget& target) const {
    float px = pos.x;
    float py = pos.y;
    sf::Color outline(10, 10, 10);

    sf::CircleShape shadow(size/2.0f);
    shadow.setFillColor(sf::Color(0, 0, 0, 150));
    shadow.setPosition(px - size/2.0f, py + size/4.0f); 
    target.draw(shadow);

    float mouthOpen = (sin(animTime * 4.0f) + 1.0f) / 2.0f;
    float mouthHeight = size/6.0f + mouthOpen * size/6.0f;

    if (type == BOSS_GOLEM) {
        sf::Color rock(100, 100, 110);
        sf::RectangleShape body(sf::Vector2f(size, size*4/5)); 
        body.setFillColor(rock); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.0f, py - size*2/5); target.draw(body);
        
        float armOffset = sin(animTime * 3.0f) * 10.0f;
        sf::RectangleShape arm1(sf::Vector2f(size*3/10, size*3/5)); 
        arm1.setFillColor(sf::Color(60, 60, 70)); arm1.setOutlineThickness(3.0f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*4/5, py - size/5 + armOffset); target.draw(arm1);
        arm1.setPosition(px + size/2, py - size/5 - armOffset); target.draw(arm1);
        
        sf::RectangleShape head(sf::Vector2f(size/2, size/2)); 
        head.setFillColor(rock); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/4, py - size*4/5); target.draw(head);
        
        sf::Uint8 eyeBright = 150 + sin(animTime * 10.0f) * 105;
        sf::CircleShape eye(size/12.0f); eye.setFillColor(sf::Color(0, eyeBright, 50));
        eye.setPosition(px - size/4 - size/12, py - size*3/5); target.draw(eye);
        eye.setPosition(px + size/4 - size/12, py - size*3/5); target.draw(eye);
    } 
    else if (type == BOSS_LICH) {
        sf::ConvexShape robe; robe.setPointCount(5);
        robe.setFillColor(sf::Color(40, 20, 60)); robe.setOutlineThickness(4.0f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py - size/2.0f));
        float wave1 = sin(animTime * 3.0f) * 10.0f;
        robe.setPoint(1, sf::Vector2f(px + size/2.0f + wave1, py));
        robe.setPoint(2, sf::Vector2f(px + size/3.0f, py + size/2.0f));
        robe.setPoint(3, sf::Vector2f(px - size/3.0f, py + size/2.0f));
        robe.setPoint(4, sf::Vector2f(px - size/2.0f - wave1, py));
        target.draw(robe);
        
        sf::CircleShape skull(size/3.0f); skull.setFillColor(sf::Color(220, 220, 200)); skull.setOutlineThickness(3.0f); skull.setOutlineColor(outline);
        skull.setPosition(px - size/3.0f, py - size/2.0f); target.draw(skull);
        
        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px - size/5, py - size/3); target.draw(eye);
        eye.setPosition(px + size/10, py - size/3); target.draw(eye);
        
        sf::RectangleShape mouth(sf::Vector2f(size*2/5, mouthHeight/2));
        mouth.setFillColor(sf::Color::Black);
        mouth.setPosition(px - size/5, py + size/8); target.draw(mouth);
    } 
    else if (type == BOSS_DEMON) {
        float wingFlap = sin(animTime * 8.0f) * 0.4f + 0.8f;
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(80, 10, 10)); wing.setOutlineThickness(3.0f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px - size/3, py - size/4));
        wing.setPoint(1, sf::Vector2f(px - size*6/5, py - size/2 * wingFlap));
        wing.setPoint(2, sf::Vector2f(px - size*11/10, py + size/4 * wingFlap));
        wing.setPoint(3, sf::Vector2f(px - size/3, py + size/6));
        target.draw(wing);
        wing.scale(-1.0f, 1.0f); wing.setPosition(px + size/3, py - size/4); target.draw(wing);
        
        sf::CircleShape body(size/2.0f); body.setFillColor(sf::Color(150, 30, 30)); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.0f, py - size/2.0f); target.draw(body);
        
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(outline);
        horn.setPoint(0, sf::Vector2f(px - size/3, py - size/2)); 
        horn.setPoint(1, sf::Vector2f(px - size/2, py - size*4/5)); 
        horn.setPoint(2, sf::Vector2f(px - size/4, py - size*7/10));
        target.draw(horn);
        
        horn.setPoint(0, sf::Vector2f(px + size/3, py - size/2)); 
        horn.setPoint(1, sf::Vector2f(px + size/2, py - size*4/5)); 
        horn.setPoint(2, sf::Vector2f(px + size/4, py - size*7/10));
        target.draw(horn);
        
        sf::CircleShape eye(size/10.0f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - size/4 - size/10, py - size/6); target.draw(eye);
        eye.setPosition(px + size/4 - size/10, py - size/6); target.draw(eye);
    } 
    else if (type == BOSS_SPIDER) {
        sf::Color carapace(40, 0, 50);
        for(int i=0; i<4; i++) {
            float angle1 = (45 + i*20) * M_PI / 180.0f;
            float angle2 = (-45 - i*20) * M_PI / 180.0f;
            float legMove = sin(animTime * 6.0f + i) * 10.0f;
            
            sf::RectangleShape leg1(sf::Vector2f(size/2.0f, size/16.0f)); 
            leg1.setFillColor(carapace); leg1.setOutlineThickness(2.0f); leg1.setOutlineColor(outline);
            leg1.rotate(angle1 * 180 / M_PI); leg1.setPosition(px - size/4, py + legMove); target.draw(leg1);
            
            sf::RectangleShape leg2(sf::Vector2f(size/2.0f, size/16.0f)); 
            leg2.setFillColor(carapace); leg2.setOutlineThickness(2.0f); leg2.setOutlineColor(outline);
            leg2.rotate(angle2 * 180 / M_PI); leg2.setPosition(px + size/4, py - legMove); target.draw(leg2);
        }
        sf::CircleShape abdomen(size/2.0f); abdomen.setFillColor(carapace); abdomen.setOutlineThickness(4.0f); abdomen.setOutlineColor(outline);
        abdomen.setPosition(px - size/2.0f, py - size/4); target.draw(abdomen);
        sf::CircleShape head(size/4.0f); head.setFillColor(sf::Color(60, 0, 70)); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/8, py - size*2/3); target.draw(head);
        
        sf::Uint8 eyeBright = 150 + sin(animTime * 8.0f) * 105;
        sf::CircleShape eye(size/20.0f); eye.setFillColor(sf::Color(eyeBright, 0, 0));
        eye.setPosition(px - size/6, py - size*5/8); target.draw(eye);
        eye.setPosition(px + size/12, py - size*5/8); target.draw(eye);
    }
    else if (type == BOSS_ABOMINATION) {
        sf::Color flesh(140, 160, 120);
        sf::RectangleShape body(sf::Vector2f(size*4/5, size)); 
        body.setFillColor(flesh); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size*2/5, py - size/2.0f); target.draw(body);
        
        float armWave = sin(animTime * 2.0f) * 15.0f;
        sf::RectangleShape arm1(sf::Vector2f(size*3/10, size*7/10)); 
        arm1.setFillColor(flesh); arm1.setOutlineThickness(3.0f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*7/10, py - size/3 + armWave); target.draw(arm1);
        arm1.setPosition(px + size*2/5, py - size/3 - armWave); target.draw(arm1);
        
        sf::RectangleShape head(sf::Vector2f(size*2/5, size*2/5)); 
        head.setFillColor(flesh); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/5, py - size*9/10); target.draw(head);
        
        sf::RectangleShape bolt1(sf::Vector2f(size/10, size/10)); bolt1.setFillColor(sf::Color(180, 180, 180));
        bolt1.setPosition(px - size*3/10, py - size*4/5); target.draw(bolt1);
        bolt1.setPosition(px + size/5, py - size*4/5); target.draw(bolt1);
        
        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(50, 50, 50));
        eye.setPosition(px - size/5, py - size*3/4); target.draw(eye);
        eye.setPosition(px + size/10, py - size*3/4); target.draw(eye);
    }
    else if (type == BOSS_KRAKEN) {
        sf::Color skin(0, 100, 100);
        for(int i=0; i<8; i++) {
            float angle = i * (M_PI / 4) + sin(animTime * 2.0f + i) * 0.2f;
            sf::ConvexShape tent; tent.setPointCount(4); 
            tent.setFillColor(skin); tent.setOutlineThickness(2.0f); tent.setOutlineColor(outline);
            tent.setPoint(0, sf::Vector2f(px, py));
            tent.setPoint(1, sf::Vector2f(px + cos(angle)*size/3, py + sin(angle)*size/3));
            tent.setPoint(2, sf::Vector2f(px + cos(angle)*size/2 + 10, py + sin(angle)*size/2 + 10));
            tent.setPoint(3, sf::Vector2f(px + cos(angle)*size/2 - 10, py + sin(angle)*size/2 - 10));
            target.draw(tent);
        }
        sf::CircleShape body(size/2.0f); body.setFillColor(skin); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.0f, py - size/2.0f); target.draw(body);
        sf::CircleShape eye(size/10.0f); eye.setFillColor(sf::Color(255, 255, 0));
        eye.setPosition(px - size/4 - size/10, py - size/4); target.draw(eye);
        eye.setPosition(px + size/4 - size/10, py - size/4); target.draw(eye);
    }
    else if (type == BOSS_DRAGON) {
        sf::Color bone(200, 200, 180);
        float wingFlap = sin(animTime * 6.0f) * 0.3f + 0.8f;
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(50, 50, 50)); wing.setOutlineThickness(3.0f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px - size/4, py - size/3));
        wing.setPoint(1, sf::Vector2f(px - size, py - size/2 * wingFlap));
        wing.setPoint(2, sf::Vector2f(px - size*9/10, py + size/6 * wingFlap));
        wing.setPoint(3, sf::Vector2f(px - size/4, py));
        target.draw(wing);
        wing.scale(-1.0f, 1.0f); wing.setPosition(px + size/4, py - size/3); target.draw(wing);
        
        float neckWave = sin(animTime * 2.0f) * 20.0f;
        sf::RectangleShape neck(sf::Vector2f(size/5, size*4/5)); 
        neck.setFillColor(bone); neck.rotate(-30 + neckWave); neck.setOutlineThickness(3.0f); neck.setOutlineColor(outline);
        neck.setPosition(px - size/10, py - size/10); target.draw(neck);
        
        sf::ConvexShape head; head.setPointCount(4); 
        head.setFillColor(bone); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPoint(0, sf::Vector2f(px - size/2, py - size)); 
        head.setPoint(1, sf::Vector2f(px - size/4, py - size*11/10));
        head.setPoint(2, sf::Vector2f(px - size/4, py - size*9/10)); 
        head.setPoint(3, sf::Vector2f(px - size/2, py - size*9/10));
        target.draw(head);
        
        sf::CircleShape eye(size/20.0f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - size/2 + size/20, py - size + size/20); target.draw(eye);
        
        sf::RectangleShape body(sf::Vector2f(size*3/5, size*3/5)); 
        body.setFillColor(bone); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size*3/10, py - size/5); target.draw(body);
    }
    else if (type == BOSS_WRAITH_LORD) {
        sf::Color armor(100, 100, 150);
        sf::ConvexShape cloak; cloak.setPointCount(6); 
        cloak.setFillColor(sf::Color(20, 20, 40, 220)); cloak.setOutlineThickness(4.0f); cloak.setOutlineColor(outline);
        float wave1 = sin(animTime * 4.0f) * 15.0f;
        cloak.setPoint(0, sf::Vector2f(px - size/2, py - size/3)); 
        cloak.setPoint(1, sf::Vector2f(px + size/2, py - size/3));
        cloak.setPoint(2, sf::Vector2f(px + size/3 + wave1, py + size/2)); 
        cloak.setPoint(3, sf::Vector2f(px + size/6, py + size/3 - wave1/2));
        cloak.setPoint(4, sf::Vector2f(px - size/6, py + size/2)); 
        cloak.setPoint(5, sf::Vector2f(px - size/3 - wave1, py + size/3 + wave1/2));
        target.draw(cloak);
        
        sf::RectangleShape helm(sf::Vector2f(size*2/5, size/2)); 
        helm.setFillColor(armor); helm.setOutlineThickness(3.0f); helm.setOutlineColor(outline);
        helm.setPosition(px - size/5, py - size*3/5); target.draw(helm);
        
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(armor);
        horn.setPoint(0, sf::Vector2f(px - size/5, py - size*3/5)); 
        horn.setPoint(1, sf::Vector2f(px - size*2/5, py - size*4/5)); 
        horn.setPoint(2, sf::Vector2f(px - size/5, py - size/2));
        target.draw(horn);
        
        horn.setPoint(0, sf::Vector2f(px + size/5, py - size*3/5)); 
        horn.setPoint(1, sf::Vector2f(px + size*2/5, py - size*4/5)); 
        horn.setPoint(2, sf::Vector2f(px + size/5, py - size/2));
        target.draw(horn);
        
        sf::Uint8 eyeBright = 150 + sin(animTime * 5.0f) * 105;
        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(0, eyeBright, eyeBright, 200));
        eye.setPosition(px - size/5, py - size*9/20); target.draw(eye);
        eye.setPosition(px + size/10, py - size*9/20); target.draw(eye);
    }
    else if (type == BOSS_VAMPIRE) {
        sf::Color skin(230, 230, 250);
        sf::ConvexShape cloak; cloak.setPointCount(4); 
        cloak.setFillColor(sf::Color(120, 0, 0)); cloak.setOutlineThickness(4.0f); cloak.setOutlineColor(outline);
        float wave1 = sin(animTime * 3.0f) * 10.0f;
        cloak.setPoint(0, sf::Vector2f(px - size/2, py - size/4)); 
        cloak.setPoint(1, sf::Vector2f(px + size/2, py - size/4));
        cloak.setPoint(2, sf::Vector2f(px + size/3 + wave1, py + size/2)); 
        cloak.setPoint(3, sf::Vector2f(px - size/3 - wave1, py + size/2));
        target.draw(cloak);
        
        sf::RectangleShape collar(sf::Vector2f(size*3/10, size/10)); 
        collar.setFillColor(sf::Color(255, 255, 255)); collar.setOutlineThickness(2.0f); collar.setOutlineColor(outline);
        collar.setPosition(px - size*3/20, py - size*3/10); target.draw(collar);
        
        sf::CircleShape head(size/3.0f); head.setFillColor(skin); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/3, py - size/2); target.draw(head);
        
        sf::RectangleShape hair(sf::Vector2f(size*3/5, size/5)); hair.setFillColor(sf::Color::Black);
        hair.setPosition(px - size*3/10, py - size/2); target.draw(hair);
        
        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px - size/5, py - size/3); target.draw(eye);
        eye.setPosition(px + size/10, py - size/3); target.draw(eye);
    }
    else if (type == BOSS_BEHOLDER) {
        sf::Color bodyCol(100, 50, 50);
        float pulse = 1.0f + sin(animTime * 4.0f) * 0.1f;
        sf::CircleShape body(size/2.0f * pulse); 
        body.setFillColor(bodyCol); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - (size/2.0f * pulse), py - (size/2.0f * pulse)); target.draw(body);
        
        sf::CircleShape eye(size/4.0f); eye.setFillColor(sf::Color::White); eye.setOutlineThickness(2.0f); eye.setOutlineColor(outline);
        eye.setPosition(px - size/4, py - size/4); target.draw(eye);
        
        float pupilX = px - size/8 + cos(animTime * 2.0f) * (size/20);
        float pupilY = py - size/8 + sin(animTime * 2.0f) * (size/20);
        sf::CircleShape pupil(size/8.0f); pupil.setFillColor(sf::Color::Black);
        pupil.setPosition(pupilX - size/8, pupilY - size/8); target.draw(pupil);
        
        sf::CircleShape iris(size/16.0f); iris.setFillColor(sf::Color(255, 0, 0));
        iris.setPosition(pupilX - size/16, pupilY - size/16); target.draw(iris);
        
        for(int i=0; i<8; i++) {
            float angle = i * (M_PI / 4) + sin(animTime * 3.0f + i) * 0.3f;
            float tx = px + cos(angle) * size/2;
            float ty = py + sin(angle) * size/2;
            sf::RectangleShape stalk(sf::Vector2f(size/8, size/3)); 
            stalk.setFillColor(bodyCol); stalk.setOutlineThickness(2.0f); stalk.setOutlineColor(outline);
            stalk.rotate(angle * 180 / M_PI + 90); stalk.setPosition(tx, ty); target.draw(stalk);
            
            sf::CircleShape sEye(size/12.0f); sEye.setFillColor(sf::Color::White); sEye.setOutlineThickness(1.0f); sEye.setOutlineColor(outline);
            sEye.setPosition(tx - size/12, ty - size/12); target.draw(sEye);
            
            sf::CircleShape sPupil(size/24.0f); sPupil.setFillColor(sf::Color::Black);
            sPupil.setPosition(tx - size/24, ty - size/24); target.draw(sPupil);
        }
    }

    if(type != BOSS_BEHOLDER && type != BOSS_LICH) {
        sf::RectangleShape mouth(sf::Vector2f(size*3/5, mouthHeight));
        mouth.setFillColor(sf::Color::Black);
        mouth.setPosition(px - size*3/10, py + size/6);
        target.draw(mouth);
        
        int numTeeth = 6;
        for(int i=0; i<numTeeth; i++) {
            float toothW = (size*3/5) / numTeeth;
            sf::ConvexShape tooth; tooth.setPointCount(3);
            tooth.setFillColor(sf::Color::White); tooth.setOutlineThickness(1.5f); tooth.setOutlineColor(outline);
            tooth.setPoint(0, sf::Vector2f(px - size*3/10 + i * toothW, py + size/6));
            tooth.setPoint(1, sf::Vector2f(px - size*3/10 + (i+1) * toothW, py + size/6));
            tooth.setPoint(2, sf::Vector2f(px - size*3/10 + i * toothW + toothW/2, py + size/6 + mouthHeight * 4/5));
            target.draw(tooth);
        }
    }

    sf::RectangleShape hbBg(sf::Vector2f(size, 15.0f)); hbBg.setFillColor(sf::Color(50, 0, 0));
    hbBg.setPosition(px - size/2, py - size/2 - 30); target.draw(hbBg);
    sf::RectangleShape hbFg(sf::Vector2f(size * health / maxHealth, 15.0f)); hbFg.setFillColor(sf::Color(255, 50, 50));
    hbFg.setPosition(px - size/2, py - size/2 - 30); target.draw(hbFg);
}