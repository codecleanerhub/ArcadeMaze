#ifndef UTILS_H
#define UTILS_H

#include <SFML/Graphics.hpp>
#include <string>
#include <vector>

const int WINDOW_WIDTH = 1024;
const int WINDOW_HEIGHT = 1024;
const int TILE_SIZE = 48;
const int MAZE_COLS = 21;
const int MAZE_ROWS = 19;
const int UI_HEIGHT = 80;

struct Vec2 { int x, y; };

struct Config {
    int key_up = sf::Keyboard::Up;
    int key_down = sf::Keyboard::Down;
    int key_left = sf::Keyboard::Left;
    int key_right = sf::Keyboard::Right;
    int key_jump = sf::Keyboard::Space;
    int key_shoot = sf::Keyboard::LAlt;
    
    // Joystick
    int joy_axis_x = 0;
    int joy_axis_y = 1;
    int joy_jump = 0;
    int joy_shoot = 2;
};

struct Particle {
    sf::Vector2f pos;
    sf::Vector2f vel;
    sf::Color color;
    int life;
    int maxLife;
};

Config loadConfig(const std::string& filename);
void drawText(sf::RenderTarget& target, const std::string& text, float x, float y, int scale, sf::Color color);
void drawTextCentered(sf::RenderTarget& target, const std::string& text, float cx, float y, int scale, sf::Color color);
void drawTextOutlined(sf::RenderTarget& target, const std::string& text, float x, float y, int scale, sf::Color color);
void drawTextCenteredOutlined(sf::RenderTarget& target, const std::string& text, float cx, float y, int scale, sf::Color color);

#endif