#include "UI.h"

void UI::render(SDL_Renderer* renderer, Player& player, int remainingDots) {
    SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
    SDL_Rect uiBg = {0, 0, WINDOW_WIDTH, UI_HEIGHT};
    SDL_RenderFillRect(renderer, &uiBg);
    
    SDL_Color white = {255, 255, 255, 255};
    SDL_Color yellow = {255, 255, 0, 255};
    SDL_Color magenta = {255, 0, 255, 255};
    
    // Score
    drawText(renderer, "SCORE", 10, 10, 2, white);
    drawText(renderer, std::to_string(player.getScore()), 10, 30, 2, yellow);
    
    // Vite
    drawText(renderer, "LIVES", 150, 10, 2, white);
    for(int i = 0; i < player.getLives(); ++i) {
        SDL_SetRenderDrawColor(renderer, 0, 255, 255, 255);
        SDL_Rect head = {160 + i * 20, 35, 8, 8}; SDL_RenderFillRect(renderer, &head);
        SDL_Rect body = {163 + i * 20, 44, 2, 8}; SDL_RenderFillRect(renderer, &body);
    }
    
    // Energia (Scudo)
    drawText(renderer, "ENERGY", 280, 10, 2, white);
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255);
    SDL_Rect enBg = {280, 35, 100, 10}; SDL_RenderFillRect(renderer, &enBg);
    int enWidth = (100 * player.getEnergy()) / player.getMaxEnergy();
    SDL_SetRenderDrawColor(renderer, magenta.r, magenta.g, magenta.b, 255);
    SDL_Rect enFg = {280, 35, enWidth, 10}; SDL_RenderFillRect(renderer, &enFg);
    
    // Arma e munizioni
    Weapon w = player.getCurrentWeapon();
    drawText(renderer, "WPN", 420, 10, 2, white);
    drawText(renderer, w.getName(), 420, 30, 2, w.getColor());
    
    drawText(renderer, "AMMO", 570, 10, 2, white);
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255);
    SDL_Rect ammoBg = {570, 35, 100, 10}; SDL_RenderFillRect(renderer, &ammoBg);
    SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255);
    int ammoWidth = (100 * w.ammo) / 15;
    SDL_Rect ammoFg = {570, 35, ammoWidth, 10}; SDL_RenderFillRect(renderer, &ammoFg);
    
    // Dots rimanenti
    drawText(renderer, "DOTS", 700, 10, 2, white);
    drawText(renderer, std::to_string(remainingDots), 700, 30, 2, yellow);
}