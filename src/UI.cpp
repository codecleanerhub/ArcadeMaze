#include "UI.h"

void drawHeart(sf::RenderTarget& target, float x, float y, float size, sf::Color color) {
    sf::CircleShape l1(size/2); l1.setFillColor(color);
    l1.setPosition(x - size/2, y - size/4);
    target.draw(l1);
    
    sf::CircleShape l2(size/2); l2.setFillColor(color);
    l2.setPosition(x, y - size/4);
    target.draw(l2);
    
    sf::ConvexShape bottom; bottom.setPointCount(3);
    bottom.setFillColor(color);
    bottom.setPoint(0, sf::Vector2f(x - size, y));
    bottom.setPoint(1, sf::Vector2f(x + size, y));
    bottom.setPoint(2, sf::Vector2f(x, y + size));
    target.draw(bottom);
}

void UI::render(sf::RenderTarget& target, Player& player, int remainingTreasures) {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, UI_HEIGHT));
    bg.setFillColor(sf::Color(20, 20, 20));
    target.draw(bg);

    drawText(target, "SCORE", 10, 10, 2, sf::Color::White);
    drawText(target, std::to_string(player.getScore()), 10, 30, 2, sf::Color::Yellow);
    
    drawText(target, "LIVES", 150, 10, 2, sf::Color::White);
    for(int i = 0; i < player.getLives(); ++i) {
        drawHeart(target, 160 + i * 24, 35, 8.f, sf::Color::Red);
    }
    
    drawText(target, "ENERGY", 280, 10, 2, sf::Color::White);
    sf::RectangleShape enBg(sf::Vector2f(100.f, 10.f)); enBg.setFillColor(sf::Color(100, 100, 100));
    enBg.setPosition(280, 35); target.draw(enBg);
    sf::RectangleShape enFg(sf::Vector2f(100.f * player.getEnergy() / player.getMaxEnergy(), 10.f)); enFg.setFillColor(sf::Color(255, 0, 255));
    enFg.setPosition(280, 35); target.draw(enFg);

    Weapon w = player.getCurrentWeapon();
    drawText(target, "WPN", 420, 10, 2, sf::Color::White);
    drawText(target, w.getName(), 420, 30, 2, w.getColor());
    
    drawText(target, "AMMO", 570, 10, 2, sf::Color::White);
    sf::RectangleShape ammoBg(sf::Vector2f(100.f, 10.f)); ammoBg.setFillColor(sf::Color(100, 100, 100));
    ammoBg.setPosition(570, 35); target.draw(ammoBg);
    sf::RectangleShape ammoFg(sf::Vector2f(100.f * w.ammo / 15.f, 10.f)); ammoFg.setFillColor(sf::Color::Yellow);
    ammoFg.setPosition(570, 35); target.draw(ammoFg);
    
    drawText(target, "TRES", 700, 10, 2, sf::Color::White);
    drawText(target, std::to_string(remainingTreasures), 700, 30, 2, sf::Color::Yellow);
}