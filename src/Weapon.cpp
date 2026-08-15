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
    
    // Piattaforma ombra per non confonderle col resto
    drawFilledCircle(renderer, cx, cy + 8, 12, {0, 0, 0, 100});

    if (type == WPN_PISTOL) {
        // Impugnatura
        SDL_SetRenderDrawColor(renderer, 40, 20, 10, 255);
        SDL_Rect grip = {cx - 8, cy, 10, 16};
        SDL_RenderFillRect(renderer, &grip);
        // Corpo
        SDL_SetRenderDrawColor(renderer, 70, 70, 70, 255);
        SDL_Rect body = {cx - 8, cy - 8, 16, 10};
        SDL_RenderFillRect(renderer, &body);
        // Canna
        SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255);
        SDL_Rect barrel = {cx + 8, cy - 6, 12, 6};
        SDL_RenderFillRect(renderer, &barrel);
        // Mirino
        SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
        SDL_Rect sight = {cx + 10, cy - 9, 2, 3};
        SDL_RenderFillRect(renderer, &sight);
    } 
    else if (type == WPN_SHOTGUN) {
        // Legno
        SDL_SetRenderDrawColor(renderer, 110, 70, 30, 255);
        SDL_Rect body = {cx - 14, cy + 2, 18, 14};
        SDL_RenderFillRect(renderer, &body);
        // Metallo
        SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255);
        SDL_Rect barrel = {cx - 10, cy - 8, 24, 10};
        SDL_RenderFillRect(renderer, &barrel);
        // Canna doppia
        SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255);
        SDL_Rect b1 = {cx - 8, cy - 7, 20, 2};
        SDL_Rect b2 = {cx - 8, cy - 3, 20, 2};
        SDL_RenderFillRect(renderer, &b1);
        SDL_RenderFillRect(renderer, &b2);
        // Pompa
        SDL_SetRenderDrawColor(renderer, 90, 90, 90, 255);
        SDL_Rect pump = {cx + 2, cy + 6, 10, 6};
        SDL_RenderFillRect(renderer, &pump);
    } 
    else if (type == WPN_ROCKET) {
        // Corpo
        SDL_SetRenderDrawColor(renderer, 70, 140, 70, 255);
        SDL_Rect body = {cx - 12, cy - 8, 22, 16};
        SDL_RenderFillRect(renderer, &body);
        // Punta
        drawFilledCircle(renderer, cx + 10, cy, 8, {180, 40, 40, 255});
        // Alette
        SDL_SetRenderDrawColor(renderer, 50, 100, 50, 255);
        SDL_Rect fin1 = {cx - 14, cy - 12, 4, 8};
        SDL_Rect fin2 = {cx - 14, cy + 4, 4, 8};
        SDL_RenderFillRect(renderer, &fin1);
        SDL_RenderFillRect(renderer, &fin2);
        // Dettagli lineari
        SDL_SetRenderDrawColor(renderer, 30, 60, 30, 255);
        SDL_RenderDrawLine(renderer, cx-12, cy, cx+10, cy);
    } 
    else if (type == WPN_LASER) {
        // Impugnatura
        SDL_SetRenderDrawColor(renderer, 20, 20, 40, 255);
        SDL_Rect grip = {cx - 6, cy + 2, 10, 14};
        SDL_RenderFillRect(renderer, &grip);
        // Corpo
        SDL_SetRenderDrawColor(renderer, 80, 80, 120, 255);
        SDL_Rect body = {cx - 8, cy - 8, 18, 10};
        SDL_RenderFillRect(renderer, &body);
        // Nucleo luminoso grande
        drawFilledCircle(renderer, cx, cy - 3, 5, {50, 200, 255, 255});
        drawFilledCircle(renderer, cx, cy - 3, 2, {255, 255, 255, 255});
        // Canna
        SDL_SetRenderDrawColor(renderer, 120, 120, 160, 255);
        SDL_Rect barrel = {cx + 10, cy - 6, 12, 6};
        SDL_RenderFillRect(renderer, &barrel);
        // Bobine energia
        SDL_SetRenderDrawColor(renderer, 150, 255, 255, 255);
        SDL_Rect coil1 = {cx-6, cy-7, 2, 2};
        SDL_Rect coil2 = {cx-3, cy-7, 2, 2};
        SDL_RenderFillRect(renderer, &coil1);
        SDL_RenderFillRect(renderer, &coil2);
    }
}