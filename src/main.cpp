#include "Game.h"
int main(int argc, char* argv[]) {
    Game game;
    if (game.init()) {
        game.run();
    }
    game.cleanup();
    return 0;
}
