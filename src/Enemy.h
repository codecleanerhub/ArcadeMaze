#ifndef ENEMY_H
#define ENEMY_H

// ===========================================================================
// Enemy.h - Nemici del labirinto.
//
// Esistono 15 tipi di nemici con statistiche (velocita'/salute) diverse.
// Tutti condividono la stessa classe `Enemy`: il comportamento speciale
// e' determinato da `type` in `update()`.
//
// AI di movimento:
//   * NEMICI "PENSANTI" (ROBOT, SLIME, DEMON, ORC): usano BFS per trovare
//     il cammino minimo verso il giocatore. Il path viene ricalcolato ogni
//     ~250 ms per ridurre il carico CPU.
//   * ALTRI NEMICI: usano moveGreedy (scelgono la cella adiacente che
//     minimizza la distanza in linea d'aria, con penalita' per tornare
//     indietro).
//
// Sparo: alcuni tipi (SKELETON, CULTIST, DEMON, WRAITH, ROBOT) possono
// sparare al giocatore se nel raggio di 500 px, con cooldown casuale.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include "Maze.h"
#include "Weapon.h"
#include <queue>
#include <string>
#include <cstdint>

// Tipo di nemico. L'ordine NON e' arbitrario: Game::spawnEnemies usa un
// array di 15 elementi per scegliere casualmente; modificarne l'ordine
// cambierebbe le statistiche dei nemici esistenti senza update esplicito.
enum EnemyType {
    ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT,
    ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
    ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
    ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST
};

class Enemy {
public:
    // Costruttore: imposta posizione iniziale e statistiche in base al tipo.
    Enemy(EnemyType type, int startCol, int startRow);

    // Aggiorna il nemico (movimento + eventuale sparo).
    // `playerGridPos` serve per l'AI di movimento; `playerPixelPos` e'
    // usata per calcolare la traiettoria di eventuali proiettili.
    // `enemyProjectiles` e' il vettore condiviso in cui il nemico aggiunge
    // i propri colpi (gestito/aggiornato da Game).
    void update(Maze& maze, const Vec2& playerGridPos, const sf::Vector2f& playerPixelPos, std::vector<Projectile>& enemyProjectiles);

    // Disegna il nemico (sprite specifica per tipo).
    void render(sf::RenderTarget& target) const;

    // Infligge `dmg` punti danno. La morte e' gestita esternamente tramite
    // isDead() (non c'e' animazione di morte qui).
    void takeDamage(int dmg);

    bool isDead() const { return health <= 0; }
    Vec2 getGridPos() const;
    sf::Vector2f getPixelPos() const { return pos; }
    EnemyType getType() const { return type; }

private:
    sf::Vector2f pos;
    int dx, dy;     // direzione corrente
    int speed;      // pixel per frame
    int health, maxHealth;
    EnemyType type;
    uint32_t pathUpdateTimer;  // ms simulati: ricalcola BFS ogni ~250ms
    uint32_t shootCooldown;    // ms simulati: cooldown fra spari

    // BFS sul labirinto per trovare il prossimo passo verso `target`.
    // Restituisce true se `target` e' raggiungibile e riempie `nextStep`
    // con la prima cella del percorso. Complessita' O(cols*rows).
    bool bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep);

    // Movimento greedy: sceglie la direzione che minimizza la distanza
    // quadrata al target, con una piccola penalita' per invertire la
    // direzione corrente (evita oscillazioni "avanti/indietro").
    void moveGreedy(Maze& maze, const Vec2& target);
};

#endif
