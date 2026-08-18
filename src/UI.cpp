#include "UI.h"

// ===========================================================================
// UI.cpp - Rendering della barra HUD in alto.
//
// Tutte le scritte usano il font bitmap definito in Utils.cpp. La barra e'
// larga quanto la finestra (WINDOW_WIDTH) ed alta UI_HEIGHT (80 px).
// Layout (coordinate x fisse):
//   *  10: SCORE      + punteggio
//   * 150: LIVES      + cuori
//   * 280: ENERGY     + barra energia
//   * 420: WPN        + nome arma
//   * 570: AMMO       + barra munizioni
//   * 700: TRES       + tesori rimasti
// ===========================================================================

// ---------------------------------------------------------------------------
// drawDetailedHeart: disegna un cuore "stilizzato" composto da:
//   * Due semicerchi (sinistro e destro) per i lobi
//   * Un triangolo convesso per la punta in basso
//   * Un piccolo riflesso bianco in alto a sinistra per dare "lucentezza"
// Usato per le vite del giocatore. `size` e' il raggio dei semicerchi.
// ---------------------------------------------------------------------------
void drawDetailedHeart(sf::RenderTarget& target, float x, float y, float size, sf::Color fill, sf::Color outline) {
    // Lobo sinistro
    sf::CircleShape l1(size/2); l1.setFillColor(fill); l1.setOutlineThickness(1.5f); l1.setOutlineColor(outline);
    l1.setPosition(x - size/2, y - size/4);
    target.draw(l1);

    // Lobo destro
    sf::CircleShape l2(size/2); l2.setFillColor(fill); l2.setOutlineThickness(1.5f); l2.setOutlineColor(outline);
    l2.setPosition(x, y - size/4);
    target.draw(l2);

    // Punta triangolare
    sf::ConvexShape bottom; bottom.setPointCount(3);
    bottom.setFillColor(fill); bottom.setOutlineThickness(1.5f); bottom.setOutlineColor(outline);
    bottom.setPoint(0, sf::Vector2f(x - size, y));
    bottom.setPoint(1, sf::Vector2f(x + size, y));
    bottom.setPoint(2, sf::Vector2f(x, y + size));
    target.draw(bottom);

    // Riflesso bianco (effetto luce)
    sf::CircleShape hl(1.5f); hl.setFillColor(sf::Color(255, 255, 255, 200));
    hl.setPosition(x - size/3, y - size/4);
    target.draw(hl);
}

// ---------------------------------------------------------------------------
// UI::render: disegna tutta la barra HUD.
// Le barre di energia e munizioni usano un rettangolo di sfondo grigio e
// uno di primo piano colorato proporzionale al valore corrente.
//
// Nota: la barra AMMO e' normalizzata su 15 (il valore massimo possibile,
// corrispondente alla pistola). Per armi con munizioni massime diverse
// (es. razzo=3) la barra risultante sara' piu' corta del reale: e' un limite
// noto del rendering, da tenere a mente se si bilanciano le armi.
// ---------------------------------------------------------------------------
void UI::render(sf::RenderTarget& target, Player& player, int remainingTreasures) {
    // Sfondo della barra
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, UI_HEIGHT));
    bg.setFillColor(sf::Color(20, 20, 20));
    target.draw(bg);

    // SCORE
    drawTextOutlined(target, "SCORE", 10, 10, 2, sf::Color::White);
    drawTextOutlined(target, std::to_string(player.getScore()), 10, 30, 2, sf::Color::Yellow);

    // LIVES: un cuore per ogni vita
    drawTextOutlined(target, "LIVES", 150, 10, 2, sf::Color::White);
    for(int i = 0; i < player.getLives(); ++i) {
        drawDetailedHeart(target, 160 + i * 24, 35, 8.f, sf::Color(220, 20, 20), sf::Color(100, 0, 0));
    }

    // ENERGY: barra proporzionale (magenta su grigio)
    drawTextOutlined(target, "ENERGY", 280, 10, 2, sf::Color::White);
    sf::RectangleShape enBg(sf::Vector2f(100.f, 18.f)); enBg.setFillColor(sf::Color(100, 100, 100));
    enBg.setOutlineThickness(2.f); enBg.setOutlineColor(sf::Color(60, 60, 60));
    enBg.setPosition(280, 30); target.draw(enBg);
    sf::RectangleShape enFg(sf::Vector2f(100.f * player.getEnergy() / player.getMaxEnergy(), 18.f)); enFg.setFillColor(sf::Color(255, 0, 255));
    enFg.setPosition(280, 30); target.draw(enFg);

    // WPN: nome dell'arma nel colore associato
    Weapon w = player.getCurrentWeapon();
    drawTextOutlined(target, "WPN", 420, 10, 2, sf::Color::White);
    drawTextOutlined(target, w.getName(), 420, 30, 2, w.getColor());

    // AMMO: barra normalizzata a 15 (max della pistola)
    drawTextOutlined(target, "AMMO", 570, 10, 2, sf::Color::White);
    sf::RectangleShape ammoBg(sf::Vector2f(100.f, 18.f)); ammoBg.setFillColor(sf::Color(100, 100, 100));
    ammoBg.setOutlineThickness(2.f); ammoBg.setOutlineColor(sf::Color(60, 60, 60));
    ammoBg.setPosition(570, 30); target.draw(ammoBg);
    sf::RectangleShape ammoFg(sf::Vector2f(100.f * w.ammo / 15.f, 18.f)); ammoFg.setFillColor(sf::Color::Yellow);
    ammoFg.setPosition(570, 30); target.draw(ammoFg);

    // TRES: tesori ancora da raccogliere (quando arriva a 0 parte il boss)
    drawTextOutlined(target, "TRES", 700, 10, 2, sf::Color::White);
    drawTextOutlined(target, std::to_string(remainingTreasures), 700, 30, 2, sf::Color::Yellow);
}

// ---------------------------------------------------------------------------
// render (2 giocatori): disegna la barra HUD con stats di entrambi i player.
// Player1 a sinistra, player2 a destra, tesori al centro.
// ---------------------------------------------------------------------------
void UI::render(sf::RenderTarget& target, Player& player1, Player& player2, int remainingTreasures) {
    // Sfondo della barra
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, UI_HEIGHT));
    bg.setFillColor(sf::Color(20, 20, 20));
    target.draw(bg);

    // === PLAYER 1 (sinistra) ===
    // P1 SCORE
    drawTextOutlined(target, "P1", 10, 10, 2, sf::Color(100, 200, 255));
    drawTextOutlined(target, std::to_string(player1.getScore()), 10, 30, 2, sf::Color::Yellow);
    // P1 LIVES
    drawTextOutlined(target, "LIFE", 80, 10, 2, sf::Color::White);
    for(int i = 0; i < player1.getLives(); ++i) {
        drawDetailedHeart(target, 90 + i * 16, 35, 6.f, sf::Color(220, 20, 20), sf::Color(100, 0, 0));
    }
    // P1 ENERGY
    drawTextOutlined(target, "EN", 180, 10, 2, sf::Color::White);
    sf::RectangleShape en1Bg(sf::Vector2f(60.f, 14.f)); en1Bg.setFillColor(sf::Color(100, 100, 100));
    en1Bg.setOutlineThickness(1.5f); en1Bg.setOutlineColor(sf::Color(60, 60, 60));
    en1Bg.setPosition(180, 32); target.draw(en1Bg);
    sf::RectangleShape en1Fg(sf::Vector2f(60.f * player1.getEnergy() / player1.getMaxEnergy(), 14.f));
    en1Fg.setFillColor(sf::Color(255, 0, 255));
    en1Fg.setPosition(180, 32); target.draw(en1Fg);
    // P1 WPN + AMMO
    Weapon w1 = player1.getCurrentWeapon();
    drawTextOutlined(target, w1.getName(), 250, 10, 2, w1.getColor());
    drawTextOutlined(target, std::to_string(w1.ammo), 250, 30, 2, sf::Color::Yellow);

    // === TESORI (centro) ===
    drawTextOutlined(target, "TRES", 470, 10, 2, sf::Color::White);
    drawTextOutlined(target, std::to_string(remainingTreasures), 470, 30, 2, sf::Color::Yellow);

    // === PLAYER 2 (destra) ===
    // P2 SCORE
    drawTextOutlined(target, "P2", 560, 10, 2, sf::Color(255, 150, 100));
    drawTextOutlined(target, std::to_string(player2.getScore()), 560, 30, 2, sf::Color::Yellow);
    // P2 LIVES
    drawTextOutlined(target, "LIFE", 640, 10, 2, sf::Color::White);
    for(int i = 0; i < player2.getLives(); ++i) {
        drawDetailedHeart(target, 650 + i * 16, 35, 6.f, sf::Color(220, 20, 20), sf::Color(100, 0, 0));
    }
    // P2 ENERGY
    drawTextOutlined(target, "EN", 740, 10, 2, sf::Color::White);
    sf::RectangleShape en2Bg(sf::Vector2f(60.f, 14.f)); en2Bg.setFillColor(sf::Color(100, 100, 100));
    en2Bg.setOutlineThickness(1.5f); en2Bg.setOutlineColor(sf::Color(60, 60, 60));
    en2Bg.setPosition(740, 32); target.draw(en2Bg);
    sf::RectangleShape en2Fg(sf::Vector2f(60.f * player2.getEnergy() / player2.getMaxEnergy(), 14.f));
    en2Fg.setFillColor(sf::Color(255, 0, 255));
    en2Fg.setPosition(740, 32); target.draw(en2Fg);
    // P2 WPN + AMMO
    Weapon w2 = player2.getCurrentWeapon();
    drawTextOutlined(target, w2.getName(), 820, 10, 2, w2.getColor());
    drawTextOutlined(target, std::to_string(w2.ammo), 820, 30, 2, sf::Color::Yellow);
}
