// ===========================================================================
// main.cpp - Entry point del gioco ArcadeMazeFantasy.
//
// Crea l'istanza di Game, la inizializza (finestra + configurazione) e
// avvia il ciclo principale. Tutto il lavoro e' delegato a Game.
// ===========================================================================

#include "Game.h"

int main() {
    Game game;
    if (game.init()) {
        game.run();
    }
    return 0;
}
