#ifndef UI_H
#define UI_H
#include <SDL2/SDL.h>
#include "Player.h"
class UI {
public:
    void render(SDL_Renderer* renderer, Player& player, int remainingDots);
};
#endif
