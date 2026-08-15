#include "Weapon.h"
#include <cstdlib>
#include "Utils.h"

Weapon Weapon::generateRandom() {
    int r = rand() % 4;
    return generate(static_cast<WeaponType>(r));
}

Weapon Weapon::generate(WeaponType t) {
    Weapon w;
    w.type = t;
    if (t == WPN_PISTOL) { w.power = 1; w.ammo = 15; }
    else if (t == WPN_SHOTGUN) { w.power = 2; w.ammo = 8; }
    else if (t == WPN_ROCKET) { w.power = 4; w.ammo = 3; }
    else if (t == WPN_LASER) { w.power = 3; w.ammo = 10; }
    return w;
}

std::string Weapon::getName() const {
    switch(type) {
        case WPN_PISTOL: return "PISTOL";
        case WPN_SHOTGUN: return "SHOTGUN";
        case WPN_ROCKET: return "ROCKET";
        case WPN_LASER: return "LASER";
    }
    return "UNKNOWN";
}

SDL_Color Weapon::getColor() const {
    switch(type) {
        case WPN_PISTOL: return {200, 200, 200, 255};
        case WPN_SHOTGUN: return {200, 100, 50, 255};
        case WPN_ROCKET: return {100, 200, 50, 255};
        case WPN_LASER: return {50, 200, 255, 255};
    }
    return {255, 255, 255, 255};
}

void Weapon::render(SDL_Renderer* renderer, int x, int y) const {
    // x, y è l'angolo in alto a sinistra del tile
    int cx = x + TILE_SIZE / 2;
    int cy = y + TILE_SIZE / 2;
    
    if (type == WPN_PISTOL) {
        SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);
        SDL_Rect body = {cx - 4, cy - 2, 8, 4};
        SDL_Rect barrel = {cx + 4, cy - 3, 6, 2};
        SDL_RenderFillRect(renderer, &body);
        SDL_RenderFillRect(renderer, &barrel);
    } else if (type == WPN_SHOTGUN) {
        SDL_SetRenderDrawColor(renderer, 150, 100, 50, 255);
        SDL_Rect body = {cx - 6, cy - 2, 10, 5};
        SDL_RenderFillRect(renderer, &body);
        SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);
        SDL_Rect barrel = {cx + 4, cy - 2, 8, 3};
        SDL_RenderFillRect(renderer, &barrel);
    } else if (type == WPN_ROCKET) {
        SDL_SetRenderDrawColor(renderer, 80, 160, 80, 255);
        SDL_Rect body = {cx - 6, cy - 3, 12, 6};
        SDL_RenderFillRect(renderer, &body);
        SDL_SetRenderDrawColor(renderer, 200, 50, 50, 255);
        SDL_Rect tip = {cx + 6, cy - 2, 3, 4};
        SDL_RenderFillRect(renderer, &tip);
    } else if (type == WPN_LASER) {
        SDL_SetRenderDrawColor(renderer, 150, 150, 200, 255);
        SDL_Rect body = {cx - 4, cy - 3, 8, 6};
        SDL_RenderFillRect(renderer, &body);
        drawFilledCircle(renderer, cx, cy, 3, {50, 200, 255, 255});
        SDL_SetRenderDrawColor(renderer, 100, 200, 255, 255);
        SDL_Rect barrel = {cx + 4, cy - 1, 8, 2};
        SDL_RenderFillRect(renderer, &barrel);
    }
}