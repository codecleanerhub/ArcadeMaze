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
    // Disegna l'intera barra HUD. `remainingTreasures` viene passato dal
    // Game perche' e' lui a tenere il riferimento al labirinto.
    void render(sf::RenderTarget& target, Player& player, int remainingTreasures);
};
#endif
