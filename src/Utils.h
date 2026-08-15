#ifndef UTILS_H
#define UTILS_H

#include <SDL2/SDL.h>
#include <string>
#include <map>

// Dimensioni logiche del gioco
const int WINDOW_WIDTH = 800;
const int WINDOW_HEIGHT = 800;
const int TILE_SIZE = 32;
const int MAZE_COLS = 19;
const int MAZE_ROWS = 19;
const int UI_HEIGHT = 64;

// Strutture di base
struct Vec2 {
    int x, y;
};

struct Config {
    int key_up = SDL_SCANCODE_UP;
    int key_down = SDL_SCANCODE_DOWN;
    int key_left = SDL_SCANCODE_LEFT;
    int key_right = SDL_SCANCODE_RIGHT;
    int key_jump = SDL_SCANCODE_SPACE;
    int key_shoot = SDL_SCANCODE_RETURN;
};

// Funzioni di utilità
Config loadConfig(const std::string& filename);
void drawText(SDL_Renderer* renderer, const std::string& text, int x, int y, int scale, SDL_Color color);
void drawFilledCircle(SDL_Renderer* renderer, int cx, int cy, int radius, SDL_Color color); // NUOVA FUNZIONE

#endif