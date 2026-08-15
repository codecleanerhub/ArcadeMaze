#include "Weapon.h"
#include <cstdlib>
#include "Utils.h"

Weapon Weapon::generateRandom() { return generate(static_cast<WeaponType>(rand() % 4)); }

Weapon Weapon::generate(WeaponType t) {
    Weapon w; w.type = t;
    if (t == WPN_PISTOL) { w.power = 1; w.ammo = 15; }
    else if (t == WPN_SHOTGUN) { w.power = 2; w.ammo = 8; }
    else if (t == WPN_ROCKET) { w.power = 4; w.ammo = 3; }
    else if (t == WPN_LASER) { w.power = 3; w.ammo = 10; }
    return w;
}

std::string Weapon::getName() const {
    switch(type) {
        case WPN_PISTOL: return "PISTOL"; case WPN_SHOTGUN: return "SHOTGUN";
        case WPN_ROCKET: return "ROCKET"; case WPN_LASER: return "LASER";
    }
    return "";
}

sf::Color Weapon::getColor() const {
    switch(type) {
        case WPN_PISTOL: return sf::Color(200, 200, 200); case WPN_SHOTGUN: return sf::Color(200, 100, 50);
        case WPN_ROCKET: return sf::Color(100, 200, 50); case WPN_LASER: return sf::Color(50, 200, 255);
    }
    return sf::Color::White;
}

void Weapon::render(sf::RenderTarget& target, float x, float y) const {
    float cx = x + TILE_SIZE / 2.f;
    float cy = y + TILE_SIZE / 2.f; // <-- La variabile corretta è cy
    sf::Color outline(20, 20, 20, 255);

    // Ombra a terra
    sf::CircleShape shadow(20.f);
    shadow.setFillColor(sf::Color(0, 0, 0, 100));
    shadow.setPosition(cx - 20.f, cy + 8.f);
    target.draw(shadow);

    if (type == WPN_PISTOL) {
        sf::RectangleShape grip(sf::Vector2f(10.f, 16.f)); grip.setFillColor(sf::Color(40, 20, 10)); grip.setOutlineThickness(1.f); grip.setOutlineColor(outline);
        grip.setPosition(cx - 8.f, cy); target.draw(grip);
        sf::RectangleShape body(sf::Vector2f(20.f, 12.f)); body.setFillColor(sf::Color(70, 70, 70)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(cx - 10.f, cy - 10.f); target.draw(body);
        sf::RectangleShape barrel(sf::Vector2f(14.f, 8.f)); barrel.setFillColor(sf::Color(100, 100, 100));
        barrel.setPosition(cx + 8.f, cy - 8.f); target.draw(barrel);
    } 
    else if (type == WPN_SHOTGUN) {
        sf::RectangleShape body(sf::Vector2f(20.f, 14.f)); body.setFillColor(sf::Color(110, 70, 30)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(cx - 14.f, cy + 2.f); target.draw(body);
        sf::RectangleShape barrel(sf::Vector2f(28.f, 10.f)); barrel.setFillColor(sf::Color(60, 60, 60)); barrel.setOutlineThickness(1.f); barrel.setOutlineColor(outline);
        barrel.setPosition(cx - 10.f, cy - 10.f); target.draw(barrel);
        sf::RectangleShape pump(sf::Vector2f(12.f, 6.f)); pump.setFillColor(sf::Color(90, 90, 90));
        pump.setPosition(cx + 2.f, cy + 6.f); target.draw(pump);
    } 
    else if (type == WPN_ROCKET) {
        sf::RectangleShape body(sf::Vector2f(24.f, 18.f)); body.setFillColor(sf::Color(70, 140, 70)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(cx - 12.f, cy - 8.f); target.draw(body);
        sf::CircleShape tip(10.f); tip.setFillColor(sf::Color(180, 40, 40)); tip.setOutlineThickness(1.f); tip.setOutlineColor(outline);
        tip.setPosition(cx + 8.f, cy - 10.f); target.draw(tip);
        sf::RectangleShape fin1(sf::Vector2f(5.f, 10.f)); fin1.setFillColor(sf::Color(50, 100, 50));
        fin1.setPosition(cx - 14.f, cy - 12.f); target.draw(fin1);
    } 
    else if (type == WPN_LASER) {
        // Glow effect
        sf::CircleShape glow(14.f); glow.setFillColor(sf::Color(50, 200, 255, 50));
        glow.setPosition(cx - 14.f, cy - 14.f); target.draw(glow);
        
        sf::RectangleShape grip(sf::Vector2f(12.f, 14.f)); grip.setFillColor(sf::Color(20, 20, 40)); grip.setOutlineThickness(1.f); grip.setOutlineColor(outline);
        grip.setPosition(cx - 8.f, cy + 2.f); target.draw(grip);
        sf::RectangleShape body(sf::Vector2f(22.f, 12.f)); body.setFillColor(sf::Color(80, 80, 120)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(cx - 10.f, cy - 10.f); target.draw(body);
        sf::CircleShape core(6.f); core.setFillColor(sf::Color(150, 255, 255));
        core.setPosition(cx - 6.f, cy - 6.f); target.draw(core);
    }
}

void Weapon::renderEquipped(sf::RenderTarget& target, float x, float y) const {
    if (type == WPN_PISTOL) {
        sf::RectangleShape grip(sf::Vector2f(6.f, 10.f)); grip.setFillColor(sf::Color(40, 20, 10));
        grip.setPosition(x - 3.f, y + 2.f); target.draw(grip);
        sf::RectangleShape body(sf::Vector2f(12.f, 8.f)); body.setFillColor(sf::Color(70, 70, 70));
        body.setPosition(x - 4.f, y - 6.f); target.draw(body);
        sf::RectangleShape barrel(sf::Vector2f(10.f, 5.f)); barrel.setFillColor(sf::Color(100, 100, 100));
        barrel.setPosition(x + 6.f, y - 5.f); target.draw(barrel);
    } 
    else if (type == WPN_SHOTGUN) {
        sf::RectangleShape barrel(sf::Vector2f(20.f, 8.f)); barrel.setFillColor(sf::Color(60, 60, 60));
        barrel.setPosition(x - 6.f, y - 4.f); target.draw(barrel);
        sf::RectangleShape pump(sf::Vector2f(8.f, 5.f)); pump.setFillColor(sf::Color(110, 70, 30));
        pump.setPosition(x + 2.f, y + 4.f); target.draw(pump);
    } 
    else if (type == WPN_ROCKET) {
        sf::RectangleShape body(sf::Vector2f(16.f, 12.f)); body.setFillColor(sf::Color(70, 140, 70));
        body.setPosition(x - 6.f, y - 4.f); target.draw(body);
        sf::CircleShape tip(6.f); tip.setFillColor(sf::Color(180, 40, 40));
        tip.setPosition(x + 8.f, y - 6.f); target.draw(tip);
    } 
    else if (type == WPN_LASER) {
        sf::RectangleShape body(sf::Vector2f(14.f, 10.f)); body.setFillColor(sf::Color(80, 80, 120));
        body.setPosition(x - 5.f, y - 4.f); target.draw(body);
        sf::CircleShape core(4.f); core.setFillColor(sf::Color(150, 255, 255));
        core.setPosition(x - 4.f, y - 3.f); target.draw(core);
    }
}