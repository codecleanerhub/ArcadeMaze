#ifndef UI_H
#define UI_H

// ===========================================================================
// UI.h - Barra HUD in alto (altezza UI_HEIGHT = 80 px).
//
// Mostra in modo sintetico: punteggio, vite (cuori), energia, arma
// corrente, munizioni, tesori rimanenti.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Player.h"

class UI {
public:
    UI();
    // Carica lo sprite del cuore da assets/sprites/ui_heart.png.
    // Da chiamare una volta in Game::init(). Se il file manca, il render
    // fa fallback a drawDetailedHeart (procedurale).
    bool loadHeartSprite(const std::string& path);
    // Disegna l'intera barra HUD. `remainingTreasures` viene passato dal
    // Game perche' e' lui a tenere il riferimento al labirinto.
    void render(sf::RenderTarget& target, Player& player, int remainingTreasures);
    // Overload per 2 giocatori: mostra anche le stats del player2.
    void render(sf::RenderTarget& target, Player& player1, Player& player2, int remainingTreasures);
private:
    // Sprite del cuore per le vite. Se non caricato, fallback a drawDetailedHeart.
    sf::Texture heartTexture;
    sf::Sprite heartSprite;
    bool heartLoaded;
    // Disegna un cuore singolo alla posizione (x, y) con dimensione `size`.
    // Usa lo sprite heartSprite se caricato, altrimenti fallback procedurale.
    void drawHeart(sf::RenderTarget& target, float x, float y, float size);
};

#endif
