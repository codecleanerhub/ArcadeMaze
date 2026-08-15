#include "Boss.h"
#include "Player.h" 
#include "Weapon.h"
#include <cstdlib>

Boss::Boss(int lvl, int w, int h) {
    level = lvl;
    screenWidth = w;
    screenHeight = h;
    
    size = 100 + lvl * 10; 
    x = w / 2.0f;
    y = UI_HEIGHT + 100.0f + size;
    dx = (lvl % 2 == 0) ? 2 : -2;
    dy = (lvl % 3 == 0) ? 1 : -1;
    speed = 1 + lvl / 2;
    
    health = 30 + lvl * 15;
    maxHealth = health;
    
    switch(lvl % 4) {
        case 0: color = {255, 50, 50, 255}; break;  
        case 1: color = {50, 255, 50, 255}; break;  
        case 2: color = {50, 50, 255, 255}; break;  
        case 3: color = {255, 255, 50, 255}; break; 
    }
    shootTimer = 0;
}

void Boss::update(int playerX, int playerY, std::vector<Projectile>& bossProjectiles) {
    x += dx * speed;
    y += dy * speed;
    
    if (x < size/2 || x > screenWidth - size/2) dx = -dx;
    if (y < UI_HEIGHT + size/2 || y > screenHeight - size/2) dy = -dy;
    
    shootTimer += 16;
    if (shootTimer > (1500 - level * 100)) {
        shootTimer = 0;
        float dxp = playerX - x;
        float dyp = playerY - y;
        float dist = sqrt(dxp*dxp + dyp*dyp);
        if (dist > 0) {
            bossProjectiles.push_back({x, y, (int)(dxp/dist * 4), (int)(dyp/dist * 4), 1, true, WPN_PISTOL});
        }
    }
}

void Boss::takeDamage(int dmg) {
    health -= dmg;
}

void Boss::render(SDL_Renderer* renderer) const {
    int px = (int)x;
    int py = (int)y;
    
    drawFilledCircle(renderer, px, py + size/3, size/2, {0, 0, 0, 100});
    
    drawFilledCircle(renderer, px, py, size/2, color);
    
    SDL_Color tentacleColor = {(Uint8)(color.r/2), (Uint8)(color.g/2), (Uint8)(color.b/2), 255};
    SDL_SetRenderDrawColor(renderer, tentacleColor.r, tentacleColor.g, tentacleColor.b, 255);
    for(int i=0; i<8; i++) {
        float angle = i * (M_PI / 4);
        int tx = px + (int)(cos(angle) * size/2);
        int ty = py + (int)(sin(angle) * size/2);
        drawFilledCircle(renderer, tx, ty, size/6, tentacleColor);
    }
    
    drawFilledCircle(renderer, px - size/4, py - size/6, size/8, {255, 255, 255, 255});
    drawFilledCircle(renderer, px + size/4, py - size/6, size/8, {255, 255, 255, 255});
    drawFilledCircle(renderer, px - size/4, py - size/6, size/16, {0, 0, 0, 255});
    drawFilledCircle(renderer, px + size/4, py - size/6, size/16, {0, 0, 0, 255});
    
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_Rect mouth = {px - size/3, py + size/8, size*2/3, size/4};
    SDL_RenderFillRect(renderer, &mouth);
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    for(int i=0; i<5; i++) {
        SDL_Rect tooth = {px - size/3 + i * (size*2/3)/5, py + size/8, (size*2/3)/5 - 2, size/8};
        SDL_RenderFillRect(renderer, &tooth);
    }
    
    SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
    SDL_Rect hbBg = {px - size/2, py - size/2 - 20, size, 10};
    SDL_RenderFillRect(renderer, &hbBg);
    SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
    SDL_Rect hbFg = {px - size/2, py - size/2 - 20, (size * health) / maxHealth, 10};
    SDL_RenderFillRect(renderer, &hbFg);
}