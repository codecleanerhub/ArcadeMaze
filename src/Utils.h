#ifndef UTILS_H
#define UTILS_H

// ===========================================================================
// Utils.h - Utility di base condivise dall'intero progetto ArcadeMazeFantasy.
//
// Questo header definisce:
//   * Le costanti globali della finestra, della griglia del labirinto e
//     dell'area UI in alto (tutta la logica di gioco assume questi valori).
//   * Strutture dati leggere (Vec2, Config, Particle) usate in piu' moduli.
//   * Le funzioni di disegno del testo bitmap: il gioco NON usa font SFML,
//     ma un font 3x5 disegnato a mano tramite la tabella FONT in Utils.cpp.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include <string>
#include <vector>

// --- Dimensioni finestra e griglia di gioco -------------------------------
// La finestra logica e' quadrata 1024x1024; l'area di gioco e' posta sotto
// la barra UI di 80 px (UI_HEIGHT). Il labirinto occupa 21 colonne x 19 righe
// di celle da 48 px: 21*48 = 1008 px (<= 1024), 19*48 = 912 px (<= 1024-80).
const int WINDOW_WIDTH  = 1024;
const int WINDOW_HEIGHT = 1024;
const int TILE_SIZE     = 48;
const int MAZE_COLS     = 21;
const int MAZE_ROWS     = 19;
const int UI_HEIGHT     = 80;

// --- Vettore 2D intero (usato per coordinate di griglia del labirinto) ----
struct Vec2 { int x, y; };

// --- Configurazione comandi (tastiera + joystick) ------------------------
// I valori di default rispecchiano le frecce direzionali e i tasti Space/Alt.
// Vengono comunque sovrascritti da loadConfig() leggendo "config.ini".
//
// In modalita' 2 giocatori:
//   * Player 1 usa la tastiera (key_*) o il joystick 0 (joy_*).
//   * Player 2 usa una tastiera secondaria (key2_*) o il joystick 1 (joy2_*).
// I pulsanti del joystick 0/1 sono configurabili da menu' (STATE_CONFIG_JOY
// e STATE_CONFIG_JOY_2); la tastiera secondaria ha valori fissi (WASD + Q/E)
// definiti qui come default.
struct Config {
    // --- Player 1 (tastiera) ---
    int key_up    = sf::Keyboard::Up;
    int key_down  = sf::Keyboard::Down;
    int key_left  = sf::Keyboard::Left;
    int key_right = sf::Keyboard::Right;
    int key_jump  = sf::Keyboard::Space;
    int key_shoot = sf::Keyboard::LAlt;

    // --- Player 1 (joystick 0) ---
    int joy_axis_x = 0;   // asse orizzontale
    int joy_axis_y = 1;   // asse verticale
    int joy_jump   = 0;   // pulsante salto
    int joy_shoot  = 2;   // pulsante sparo

    // --- Player 2 (tastiera secondaria, fissa) ---
    // WASD per il movimento, Q per saltare, E per sparare.
    int key2_up    = sf::Keyboard::W;
    int key2_down  = sf::Keyboard::S;
    int key2_left  = sf::Keyboard::A;
    int key2_right = sf::Keyboard::D;
    int key2_jump  = sf::Keyboard::Q;
    int key2_shoot = sf::Keyboard::E;

    // --- Player 2 (joystick 1) ---
    // Assi solitamente identici al joystick 0; i pulsanti sono configurabili
    // da menu' (STATE_CONFIG_JOY_2) e quindi inizializzati a default comuni.
    int joy2_axis_x = 0;
    int joy2_axis_y = 1;
    int joy2_jump   = 0;
    int joy2_shoot  = 2;
};

// --- Particella generica --------------------------------------------------
// Usata per effetti: sangue dei nemici, scintille del tesoro, ecc.
// `life` e `maxLife` sono in frame (a 60 FPS), il colore e' sfumato in base
// al rapporto life/maxLife durante il rendering.
// `size` e' il raggio in pixel (default 4). `type` controlla la forma:
//   * 0 = cerchio (default, sangue/scintille)
//   * 1 = fiamma triangolare (per fuoco: punta verso l'alto, si restringe)
//   * 2 = quadrato (per detriti/cenere)
struct Particle {
    sf::Vector2f pos;
    sf::Vector2f vel;
    sf::Color color;
    int life = 0;       // vita residua (frame)
    int maxLife = 0;    // vita iniziale (per calcolare l'alpha)
    float size = 4.f;   // raggio in pixel (default 4)
    int type = 0;       // 0=cerchio, 1=fiamma triangolare, 2=quadrato
};

// Costruttori di comodo per Particle (per non dover specificare size/type
// ogni volta). Mantengono compatibilità col codice esistente che usa la
// sintassi {pos, vel, color, life, maxLife} (size=4, type=0 di default).
inline Particle makeParticle(sf::Vector2f pos, sf::Vector2f vel,
                              sf::Color color, int life, int maxLife,
                              float size = 4.f, int type = 0) {
    return {pos, vel, color, life, maxLife, size, type};
}

// Carica la configurazione dei comandi da un file INI semplice.
Config loadConfig(const std::string& filename);

// --- Funzioni di disegno testo (font bitmap 3x5) --------------------------
// Il font e' definito in Utils.cpp come array di 37 glifi (A-Z, 0-9, spazio).
// `scale` e' il fattore di ingrandimento di ogni pixel del glifo.
// Le varianti "Outlined" disegnano 4 copie nere sfalsate dietro al testo
// per creare un contorno che migliora la leggibiliita' su sfondi chiari.
void drawText(sf::RenderTarget& target, const std::string& text, float x, float y, int scale, sf::Color color);
void drawTextCentered(sf::RenderTarget& target, const std::string& text, float cx, float y, int scale, sf::Color color);
void drawTextOutlined(sf::RenderTarget& target, const std::string& text, float x, float y, int scale, sf::Color color);
void drawTextCenteredOutlined(sf::RenderTarget& target, const std::string& text, float cx, float y, int scale, sf::Color color);

#endif
