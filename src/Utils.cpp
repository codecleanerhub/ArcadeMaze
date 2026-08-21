#include "Utils.h"
#include <fstream>
#include <iostream>
#include <cmath>

// ===========================================================================
// Utils.cpp - Implementazione utility di base.
//
// Contiene:
//   * loadConfig(): parser minimale di file INI con sintassi CHIAVE=VALORE.
//   * Font bitmap 3x5 a 37 caratteri e relative funzioni di disegno.
//   * Nessuna dipendenza esterna oltre a SFML e libreria standard.
// ===========================================================================

// ---------------------------------------------------------------------------
// loadConfig: legge un file INI nel formato "CHIAVE=VALORE".
//
// Regole:
//   * Le righe vuote, quelle che iniziano con '#' e quelle che iniziano con
//     '[' vengono ignorate (commenti / sezioni stile Windows INI).
//   * Il valore viene interpretato come intero (std::stoi).
//   * Le chiavi non riconosciute vengono silenziosamente ignorate.
//   * Se il file non esiste, si mantiene la configurazione di default
//     impostata nel costruttore di Config (vedi Utils.h).
// ---------------------------------------------------------------------------
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
            if (key == "KEY_UP")         config.key_up = value;
            else if (key == "KEY_DOWN")  config.key_down = value;
            else if (key == "KEY_LEFT")  config.key_left = value;
            else if (key == "KEY_RIGHT") config.key_right = value;
            else if (key == "KEY_JUMP")  config.key_jump = value;
            else if (key == "KEY_SHOOT") config.key_shoot = value;
            else if (key == "JOY_AXIS_X") config.joy_axis_x = value;
            else if (key == "JOY_AXIS_Y") config.joy_axis_y = value;
            else if (key == "JOY_JUMP")   config.joy_jump = value;
            else if (key == "JOY_SHOOT")  config.joy_shoot = value;
        }
    }
    return config;
}

// ---------------------------------------------------------------------------
// FONT: tabella di 37 glifi 3x5 codificati come 5 byte per carattere.
// Ogni byte rappresenta una riga; i 3 bit meno significativi indicano quali
// pixel della riga sono accesi (bit 2 = colonna sinistra, bit 0 = destra).
//
// Indici:
//   0..25  -> 'A'..'Z'
//   26..35 -> '0'..'9'
//   36     -> spazio (tutti zeri)
//
// Questa tabella e' l'unico "font" usato dal gioco: evita di caricare file
// TTF esterni e mantiene l'estetica "arcade" retro.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// drawText: disegna `text` partendo dal pixel (x, y).
// Per ogni carattere:
//   * Ne mappa il codice ASCII all'indice della tabella FONT.
//   * Disegna un RectangleShape per ogni bit acceso del glifo.
//   * Avanza di 4*scale in orizzontale (3 pixel di glifo + 1 di spazio).
// ---------------------------------------------------------------------------
void drawText(sf::RenderTarget& target, const std::string& text, int x, int y, int scale, sf::Color color) {
    float currentX = (float)x;
    float fy = (float)y;
    for (char c : text) {
        int charIndex = 36;  // default: spazio
        if (c >= 'A' && c <= 'Z')      charIndex = c - 'A';
        else if (c >= 'a' && c <= 'z') charIndex = c - 'a';   // case-insensitive
        else if (c >= '0' && c <= '9') charIndex = 26 + (c - '0');
        const uint8_t* charData = FONT[charIndex];
        for (int row = 0; row < 5; ++row) {
            for (int col = 0; col < 3; ++col) {
                if (charData[row] & (1 << (2 - col))) {
                    sf::RectangleShape pixel(sf::Vector2f((float)scale, (float)scale));
                    pixel.setPosition(currentX + col * scale, fy + row * scale);
                    pixel.setFillColor(color);
                    target.draw(pixel);
                }
            }
        }
        currentX += 4 * scale;
    }
}

// drawTextCentered: centra orizzontalmente il testo rispetto a `cx`.
// Larghezza stimata = lunghezza stringa * 4 * scale (3 px glifo + 1 px spazio).
void drawTextCentered(sf::RenderTarget& target, const std::string& text, int cx, int y, int scale, sf::Color color) {
    float width = (float)text.length() * 4.f * (float)scale;
    drawText(target, text, (int)(cx - width / 2.f), y, scale, color);
}

// drawTextOutlined: disegna il testo con un contorno nero di 1 px su 4 lati.
// Serve per mantenere la leggibiliita' su sfondi chiari o animati.
void drawTextOutlined(sf::RenderTarget& target, const std::string& text, int x, int y, int scale, sf::Color color) {
    drawText(target, text, x - scale, y, scale, sf::Color::Black);
    drawText(target, text, x + scale, y, scale, sf::Color::Black);
    drawText(target, text, x, y - scale, scale, sf::Color::Black);
    drawText(target, text, x, y + scale, scale, sf::Color::Black);
    drawText(target, text, x, y, scale, color);
}

// drawTextCenteredOutlined: combinazione di centered + outlined.
void drawTextCenteredOutlined(sf::RenderTarget& target, const std::string& text, int cx, int y, int scale, sf::Color color) {
    float width = (float)text.length() * 4.f * (float)scale;
    drawTextOutlined(target, text, (int)(cx - width / 2.f), y, scale, color);
}
