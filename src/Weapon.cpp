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
        SDL_SetRenderDrawColor(renderer, 50, 30, 10, 255); // Impugnatura scura
        SDL_Rect grip = {cx - 6, cy, 8, 14};
        SDL_RenderFillRect(renderer, &grip);
        SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255); // Corpo
        SDL_Rect body = {cx - 6, cy - 6, 14, 8};
        SDL_RenderFillRect(renderer, &body);
        SDL_SetRenderDrawColor(renderer, 120, 120, 120, 255); // Canna
        SDL_Rect barrel = {cx + 8, cy - 4, 10, 4};
        SDL_RenderFillRect(renderer, &barrel);
    } else if (type == WPN_SHOTGUN) {
        SDL_SetRenderDrawColor(renderer, 120, 80, 40, 255); // Legno
        SDL_Rect body = {cx - 12, cy + 2, 16, 12};
        SDL_RenderFillRect(renderer, &body);
        SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255); // Metallo
        SDL_Rect barrel = {cx - 8, cy - 6, 20, 8};
        SDL_RenderFillRect(renderer, &barrel);
        SDL_Rect pump = {cx + 2, cy + 6, 8, 6};
        SDL_RenderFillRect(renderer, &pump);
    } else if (type == WPN_ROCKET) {
        SDL_SetRenderDrawColor(renderer, 80, 160, 80, 255); // Corpo
        SDL_Rect body = {cx - 10, cy - 6, 18, 12};
        SDL_RenderFillRect(renderer, &body);
        drawFilledCircle(renderer, cx + 8, cy, 6, {200, 50, 50, 255}); // Punta
        SDL_SetRenderDrawColor(renderer, 60, 120, 60, 255); // Alette
        SDL_Rect fin1 = {cx - 12, cy - 10, 4, 6};
        SDL_Rect fin2 = {cx - 12, cy + 4, 4, 6};
        SDL_RenderFillRect(renderer, &fin1);
        SDL_RenderFillRect(renderer, &fin2);
    } else if (type == WPN_LASER) {
        SDL_SetRenderDrawColor(renderer, 30, 30, 50, 255); // Impugnatura
        SDL_Rect grip = {cx - 4, cy + 2, 8, 12};
        SDL_RenderFillRect(renderer, &grip);
        SDL_SetRenderDrawColor(renderer, 100, 100, 150, 255); // Corpo
        SDL_Rect body = {cx - 6, cy - 6, 14, 8};
        SDL_RenderFillRect(renderer, &body);
        drawFilledCircle(renderer, cx, cy - 2, 4, {50, 200, 255, 255}); // Nucleo
        SDL_SetRenderDrawColor(renderer, 150, 150, 200, 255); // Canna
        SDL_Rect barrel = {cx + 8, cy - 4, 10, 4};
        SDL_RenderFillRect(renderer, &barrel);
    }
}