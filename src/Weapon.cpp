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
    int cx = x + TILE_SIZE / 2;
    int cy = y + TILE_SIZE / 2;
    
    if (type == WPN_PISTOL) {
        // Impugnatura
        SDL_SetRenderDrawColor(renderer, 60, 40, 20, 255);
        SDL_Rect grip = {cx - 4, cy, 6, 10};
        SDL_RenderFillRect(renderer, &grip);
        // Corpo
        SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);
        SDL_Rect body = {cx - 4, cy - 4, 10, 6};
        SDL_RenderFillRect(renderer, &body);
        // Canna
        SDL_Rect barrel = {cx + 6, cy - 3, 8, 3};
        SDL_RenderFillRect(renderer, &barrel);
    } else if (type == WPN_SHOTGUN) {
        // Legno
        SDL_SetRenderDrawColor(renderer, 150, 100, 50, 255);
        SDL_Rect body = {cx - 8, cy, 12, 8};
        SDL_RenderFillRect(renderer, &body);
        // Metallo
        SDL_SetRenderDrawColor(renderer, 70, 70, 70, 255);
        SDL_Rect barrel = {cx - 6, cy - 4, 16, 6};
        SDL_RenderFillRect(renderer, &barrel);
        SDL_Rect pump = {cx + 2, cy + 4, 6, 4};
        SDL_RenderFillRect(renderer, &pump);
    } else if (type == WPN_ROCKET) {
        // Corpo
        SDL_SetRenderDrawColor(renderer, 80, 160, 80, 255);
        SDL_Rect body = {cx - 8, cy - 4, 14, 8};
        SDL_RenderFillRect(renderer, &body);
        // Punta
        SDL_SetRenderDrawColor(renderer, 200, 50, 50, 255);
        drawFilledCircle(renderer, cx + 6, cy, 4, {200, 50, 50, 255});
        // Alette
        SDL_SetRenderDrawColor(renderer, 60, 120, 60, 255);
        SDL_Rect fin1 = {cx - 10, cy - 6, 4, 4};
        SDL_Rect fin2 = {cx - 10, cy + 2, 4, 4};
        SDL_RenderFillRect(renderer, &fin1);
        SDL_RenderFillRect(renderer, &fin2);
    } else if (type == WPN_LASER) {
        // Impugnatura
        SDL_SetRenderDrawColor(renderer, 40, 40, 60, 255);
        SDL_Rect grip = {cx - 2, cy, 5, 9};
        SDL_RenderFillRect(renderer, &grip);
        // Corpo
        SDL_SetRenderDrawColor(renderer, 100, 100, 150, 255);
        SDL_Rect body = {cx - 4, cy - 4, 10, 6};
        SDL_RenderFillRect(renderer, &body);
        // Nucleo luminoso
        drawFilledCircle(renderer, cx, cy - 1, 3, {50, 200, 255, 255});
        // Canna
        SDL_SetRenderDrawColor(renderer, 150, 150, 200, 255);
        SDL_Rect barrel = {cx + 6, cy - 2, 8, 3};
        SDL_RenderFillRect(renderer, &barrel);
    }
}