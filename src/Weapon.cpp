#include "Weapon.h"
#include <cstdlib>
Weapon Weapon::generateRandom() {
    Weapon w;
    int r = rand() % 3;
    if (r == 0) { w.type = WPN_PISTOL; w.power = 1; w.ammo = 15; }
    else if (r == 1) { w.type = WPN_SHOTGUN; w.power = 2; w.ammo = 8; }
    else { w.type = WPN_ROCKET; w.power = 3; w.ammo = 3; }
    return w;
}
std::string Weapon::getName() const {
    switch(type) {
        case WPN_PISTOL: return "PISTOL";
        case WPN_SHOTGUN: return "SHOTGUN";
        case WPN_ROCKET: return "ROCKET";
    }
    return "UNKNOWN";
}
SDL_Color Weapon::getColor() const {
    switch(type) {
        case WPN_PISTOL: return {200, 200, 200, 255};
        case WPN_SHOTGUN: return {200, 100, 50, 255};
        case WPN_ROCKET: return {200, 50, 50, 255};
    }
    return {255, 255, 255, 255};
}
