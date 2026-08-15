#ifndef WEAPON_H
#define WEAPON_H

#include <SFML/Graphics.hpp>
#include <string>

enum WeaponType { WPN_PISTOL, WPN_SHOTGUN, WPN_ROCKET, WPN_LASER };

struct Projectile {
    sf::Vector2f pos;
    sf::Vector2f dir;
    int power;
    bool active;
    WeaponType type;
};

struct Weapon {
    WeaponType type;
    int power;      
    int ammo;       
    
    static Weapon generateRandom();
    static Weapon generate(WeaponType t);
    
    std::string getName() const;
    sf::Color getColor() const;
    void render(sf::RenderTarget& target, float x, float y) const; // A terra
    void renderEquipped(sf::RenderTarget& target, float x, float y) const; // In mano (più piccola)
};

#endif