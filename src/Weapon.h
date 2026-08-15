#ifndef WEAPON_H
#define WEAPON_H

#include <string>
#include <SDL2/SDL.h> // <-- AGGIUNTO PER SDL_Color

enum WeaponType {
    WPN_PISTOL,
    WPN_SHOTGUN,
    WPN_ROCKET
};

struct Weapon {
    WeaponType type;
    int power;      // Danno per colpo
    int ammo;       // Munizioni rimanenti
    
    // Genera un'arma casuale. Più è potente, meno munizioni ha.
    static Weapon generateRandom();
    
    std::string getName() const;
    SDL_Color getColor() const;
};

#endif