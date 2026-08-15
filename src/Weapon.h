#ifndef WEAPON_H
#define WEAPON_H

#include <string>
#include <SDL2/SDL.h>

enum WeaponType {
    WPN_PISTOL,
    WPN_SHOTGUN,
    WPN_ROCKET,
    WPN_LASER
};

struct Projectile {
    float x, y;
    int dx, dy;
    int power;
    bool active;
    WeaponType type; // Aggiunto per disegnare il proiettile corretto
};

struct Weapon {
    WeaponType type;
    int power;      
    int ammo;       
    
    static Weapon generateRandom();
    static Weapon generate(WeaponType t);
    
    std::string getName() const;
    SDL_Color getColor() const;
    void render(SDL_Renderer* renderer, int x, int y) const;
};

#endif