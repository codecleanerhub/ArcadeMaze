#ifndef BOSS_H
#define BOSS_H

// ===========================================================================
// Boss.h - Boss di fine livello.
//
// Esistono 10 tipi di boss (uno per livello, dal 1 al 10). Tutti
// condividono la stessa classe: il rendering specifico e' scelto in base
// al `type` (a sua volta derivato da `level`).
//
// Comportamento:
//   * Il boss si muove diagonalmente nella stanza rimbalzando sui bordi.
//   * Sparo a ventaglio (3 colpi) verso il giocatore, con probabilita'
//     di un colpo "bomba" piu' lento ma piu' potente.
//   * La velocita' e gli HP scalano col livello.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include <cstdint>

// Tipo di boss. L'ordine corrisponde al livello (1->GOLEM, 2->LICH, ...).
// Aggiungere/modificare tipi richiede aggiornare anche il rendering.
enum BossType {
    BOSS_GOLEM, BOSS_LICH, BOSS_DEMON, BOSS_SPIDER,
    BOSS_ABOMINATION, BOSS_KRAKEN, BOSS_DRAGON,
    BOSS_WRAITH_LORD, BOSS_VAMPIRE, BOSS_BEHOLDER
};

struct Projectile;  // forward declaration (definito in Weapon.h)

class Boss {
public:
    // Costruttore: dimensiona il boss in base al livello. `w` e `h` sono
    // le dimensioni della finestra (usati per i rimbalzi).
    Boss(int level, int w, int h);

    // Aggiorna posizione, animazione e sparo del boss.
    // `playerX/Y` servono per calcolare la direzione di fuoco.
    void update(float playerX, float playerY, std::vector<Projectile>& bossProjectiles);

    // Disegna il boss (sprite specifica per tipo + barra HP).
    void render(sf::RenderTarget& target) const;

    // Infligge danni al boss.
    void takeDamage(int dmg);

    bool isDead() const { return health <= 0; }
    sf::Vector2f getPos() const { return pos; }
    int getSize() const { return size; }
private:
    sf::Vector2f pos;
    int dx, dy;       // direzione di rimbalzo
    int size;         // dimensione del boss (px); usata anche come raggio per le collisioni
    int health, maxHealth;
    int speed;
    BossType type;
    uint32_t shootTimer;  // ms simulati: controllo frequenza di sparo
    int level;
    int screenWidth, screenHeight;
    float animTime;  // tempo accumulato per le animazioni (in secondi)
};

#endif
