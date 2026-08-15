#include "UI.h"

void drawDetailedHeart(sf::RenderTarget& target, float x, float y, float size, sf::Color fill, sf::Color outline) {
    // Metà sinistra
    sf::CircleShape l1(size/2); l1.setFillColor(fill); l1.setOutlineThickness(1.5f); l1.setOutlineColor(outline);
    l1.setPosition(x - size/2, y - size/4);
    target.draw(l1);
    
    // Metà destra
    sf::CircleShape l2(size/2); l2.setFillColor(fill); l2.setOutlineThickness(1.5f); l2.setOutlineColor(outline);
    l2.setPosition(x, y - size/4);
    target.draw(l2);
    
    // Punta
    sf::ConvexShape bottom; bottom.setPointCount(3);
    bottom.setFillColor(fill); bottom.setOutlineThickness(1.5f); bottom.setOutlineColor(outline);
    bottom.setPoint(0, sf::Vector2f(x - size, y));
    bottom.setPoint(1, sf::Vector2f(x + size, y));
    bottom.setPoint(2, sf::Vector2f(x, y + size));
    target.draw(bottom);
    
    // Riflesso bianco
    sf::CircleShape hl(1.5f); hl.setFillColor(sf::Color(255, 255, 255, 200));
    hl.setPosition(x - size/3, y - size/4);
    target.draw(hl);
}

void UI::render(sf::RenderTarget& target, Player& player, int remainingTreasures) {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, UI_HEIGHT));
    bg.setFillColor(sf::Color(20, 20, 20));
    target.draw(bg);

    drawTextOutlined(target, "SCORE", 10, 10, 2, sf::Color::White);
    drawTextOutlined(target, std::to_string(player.getScore()), 10, 30, 2, sf::Color::Yellow);
    
    drawTextOutlined(target, "LIVES", 150, 10, 2, sf::Color::White);
    for(int i = 0; i < player.getLives(); ++i) {
        drawDetailedHeart(target, 160 + i * 24, 35, 8.f, sf::Color(220, 20, 20), sf::Color(100, 0, 0));
    }
    
    drawTextOutlined(target, "ENERGY", 280, 10, 2, sf::Color::White);
    sf::RectangleShape enBg(sf::Vector2f(100.f, 10.f)); enBg.setFillColor(sf::Color(100, 100, 100));
    enBg.setPosition(280, 35); target.draw(enBg);
    sf::RectangleShape enFg(sf::Vector2f(100.f * player.getEnergy() / player.getMaxEnergy(), 10.f)); enFg.setFillColor(sf::Color(255, 0, 255));
    enFg.setPosition(280, 35); target.draw(enFg);

    Weapon w = player.getCurrentWeapon();
    drawTextOutlined(target, "WPN", 420, 10, 2, sf::Color::White);
    drawTextOutlined(target, w.getName(), 420, 30, 2, w.getColor());
    
    drawTextOutlined(target, "AMMO", 570, 10, 2, sf::Color::White);
    sf::RectangleShape ammoBg(sf::Vector2f(100.f, 10.f)); ammoBg.setFillColor(sf::Color(100, 100, 100));
    ammoBg.setPosition(570, 35); target.draw(ammoBg);
    sf::RectangleShape ammoFg(sf::Vector2f(100.f * w.ammo / 15.f, 10.f)); ammoFg.setFillColor(sf::Color::Yellow);
    ammoFg.setPosition(570, 35); target.draw(ammoFg);
    
    drawTextOutlined(target, "TRES", 700, 10, 2, sf::Color::White);
    drawTextOutlined(target, std::to_string(remainingTreasures), 700, 30, 2, sf::Color::Yellow);
}