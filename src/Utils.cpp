#include "Utils.h"
#include <fstream>
#include <iostream>

Config loadConfig(const std::string& filename) {
    Config config;
    std::ifstream file(filename);
    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#' || line[0] == '[') continue;
        size_t delimiterPos = line.find('=');
        if (delimiterPos != std::string::npos) {
            std::string key = line.substr(0, delimiterPos);
            int value = std::stoi(line.substr(delimiterPos + 1));
            if (key == "KEY_UP") config.key_up = value;
            else if (key == "KEY_DOWN") config.key_down = value;
            else if (key == "KEY_LEFT") config.key_left = value;
            else if (key == "KEY_RIGHT") config.key_right = value;
            else if (key == "KEY_JUMP") config.key_jump = value;
            else if (key == "KEY_SHOOT") config.key_shoot = value;
        }
    }
    return config;
}

const uint8_t FONT[37][5] = {
    {0b111, 0b101, 0b111, 0b101, 0b101}, {0b110, 0b101, 0b110, 0b101, 0b110},
    {0b111, 0b100, 0b100, 0b100, 0b111}, {0b110, 0b101, 0b101, 0b101, 0b110},
    {0b111, 0b100, 0b111, 0b100, 0b111}, {0b111, 0b100, 0b111, 0b100, 0b100},
    {0b111, 0b100, 0b101, 0b101, 0b111}, {0b101, 0b101, 0b111, 0b101, 0b101},
    {0b111, 0b010, 0b010, 0b010, 0b111}, {0b001, 0b001, 0b001, 0b101, 0b111},
    {0b101, 0b110, 0b100, 0b110, 0b101}, {0b100, 0b100, 0b100, 0b100, 0b111},
    {0b101, 0b111, 0b111, 0b101, 0b101}, {0b101, 0b111, 0b111, 0b111, 0b101},
    {0b111, 0b101, 0b101, 0b101, 0b111}, {0b111, 0b101, 0b111, 0b100, 0b100},
    {0b111, 0b101, 0b101, 0b111, 0b011}, {0b111, 0b101, 0b110, 0b101, 0b101},
    {0b111, 0b100, 0b111, 0b001, 0b111}, {0b111, 0b010, 0b010, 0b010, 0b010},
    {0b101, 0b101, 0b101, 0b101, 0b111}, {0b101, 0b101, 0b101, 0b101, 0b010},
    {0b101, 0b101, 0b111, 0b111, 0b101}, {0b101, 0b101, 0b010, 0b101, 0b101},
    {0b101, 0b101, 0b010, 0b010, 0b010}, {0b111, 0b001, 0b010, 0b100, 0b111},
    {0b111, 0b101, 0b101, 0b101, 0b111}, {0b010, 0b110, 0b010, 0b010, 0b111},
    {0b111, 0b001, 0b111, 0b100, 0b111}, {0b111, 0b001, 0b111, 0b001, 0b111},
    {0b101, 0b101, 0b111, 0b001, 0b001}, {0b111, 0b100, 0b111, 0b001, 0b111},
    {0b111, 0b100, 0b111, 0b101, 0b111}, {0b111, 0b001, 0b010, 0b010, 0b010},
    {0b111, 0b101, 0b111, 0b101, 0b111}, {0b111, 0b101, 0b111, 0b001, 0b111},
    {0b000, 0b000, 0b000, 0b000, 0b000}
};

void drawText(sf::RenderTarget& target, const std::string& text, float x, float y, int scale, sf::Color color) {
    float currentX = x;
    for (char c : text) {
        int charIndex = 36;
        if (c >= 'A' && c <= 'Z') charIndex = c - 'A';
        else if (c >= 'a' && c <= 'z') charIndex = c - 'a';
        else if (c >= '0' && c <= '9') charIndex = 26 + (c - '0');
        const uint8_t* charData = FONT[charIndex];
        for (int row = 0; row < 5; ++row) {
            for (int col = 0; col < 3; ++col) {
                if (charData[row] & (1 << (2 - col))) {
                    sf::RectangleShape pixel(sf::Vector2f(scale, scale));
                    pixel.setPosition(currentX + col * scale, y + row * scale);
                    pixel.setFillColor(color);
                    target.draw(pixel);
                }
            }
        }
        currentX += 4 * scale;
    }
}

void drawTextCentered(sf::RenderTarget& target, const std::string& text, float cx, float y, int scale, sf::Color color) {
    float width = text.length() * 4 * scale;
    drawText(target, text, cx - width / 2.f, y, scale, color);
}