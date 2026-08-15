#include "UI.h"
void UI::render(SDL_Renderer* renderer, Player& player, int remainingDots) {
    SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
    SDL_Rect uiBg = {0, 0, WINDOW_WIDTH, UI_HEIGHT};
    SDL_RenderFillRect(renderer, &uiBg);
    
    SDL_Color white = {255, 255, 255, 255};
    SDL_Color yellow = {255, 255, 0, 255};
    
    drawText(renderer, "SCORE", 10, 10, 2, white);
    drawText(renderer, std::to_string(player.getScore()), 10, 30, 2, yellow);
    
    drawText(renderer, "LIVES", 150, 10, 2, white);
    for(int i = 0; i < player.getLives(); ++i) {
        SDL_SetRenderDrawColor(renderer, 0, 255, 255, 255);
        SDL_Rect head = {160 + i * 20, 35, 8, 8}; SDL_RenderFillRect(renderer, &head);
        SDL_Rect body = {163 + i * 20, 44, 2, 8}; SDL_RenderFillRect(renderer, &body);
    }
    
    Weapon w = player.getCurrentWeapon();
    drawText(renderer, "WPN", 300, 10, 2, white);
    drawText(renderer, w.getName(), 300, 30, 2, w.getColor());
    
    drawText(renderer, "AMMO", 450, 10, 2, white);
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255);
    SDL_Rect ammoBg = {450, 35, 100, 10}; SDL_RenderFillRect(renderer, &ammoBg);
    SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255);
    int ammoWidth = (100 * w.ammo) / 15;
    SDL_Rect ammoFg = {450, 35, ammoWidth, 10}; SDL_RenderFillRect(renderer, &ammoFg);
    
    drawText(renderer, "DOTS", 600, 10, 2, white);
    drawText(renderer, std::to_string(remainingDots), 600, 30, 2, yellow);
}
