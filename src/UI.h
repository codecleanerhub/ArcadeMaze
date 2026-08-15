#ifndef UI_H
#define UI_H
#include <SFML/Graphics.hpp>
#include "Player.h"
class UI {
public:
    void render(sf::RenderTarget& target, Player& player, int remainingTreasures);
};
#endif