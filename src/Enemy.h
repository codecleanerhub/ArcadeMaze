#ifndef ENEMY_H
#define ENEMY_H

// ===========================================================================
// Enemy.h - Nemici del labirinto.
//
// Esistono 28 tipi di nemici (15 originali + 13 aggiunti per allineamento
// con il bestiary fantasy horror generato da script Python). Tutti
// condividono la stessa classe `Enemy`: il comportamento speciale e'
// determinato da `type` in `update()`.
//
// AI di movimento:
//   * NEMICI "PENSANTI" (ROBOT, SLIME, DEMON, ORC, BONE_GOLEM, DAMNED_KNIGHT,
//     GARGOYLE): usano BFS per trovare il cammino minimo verso il giocatore.
//     Il path viene ricalcolato ogni ~250 ms per ridurre il carico CPU.
//   * ALTRI NEMICI: usano moveGreedy (scelgono la cella adiacente che
//     minimizza la distanza in linea d'aria, con penalita' per tornare
//     indietro).
//
// Sparo: alcuni tipi (SKELETON, CULTIST, DEMON, WRAITH, ROBOT, WITCH,
// MAD_WIZARD) possono sparare al giocatore se nel raggio di 500 px,
// con cooldown casuale.
//
// Rendering: ogni nemico ha uno sprite associato (vedi SPRITE_MAP in
// Enemy.cpp). Se il PNG esiste viene usato; altrimenti fallback al
// disegno a primitive SFML.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include "Maze.h"
#include "Weapon.h"
#include "SpriteSheet.h"
#include <queue>
#include <string>
#include <cstdint>
#include <map>

// Tipo di nemico. L'ordine NON e' arbitrario: Game::spawnEnemies usa un
// array di tutti i tipi per scegliere casualmente; modificarne l'ordine
// cambierebbe le statistiche dei nemici esistenti senza update esplicito.
//
// I primi 15 (ZOMBIE..CULTIST) sono i tipi originali del gioco.
// I 13 successivi (MIMIC..PREDATOR_FUNGUS) sono aggiunti per allinearsi
// alle 20 creature del file `prompt_game_reference.txt` (i 7 non ancora
// mappati - Mimic/Lupo/Strega/Golem/Serpente/Cavaliere/Mago/Corvo/
// Tentacolo/Gargoyle/Spirito/Cinghiale/Fungo - sono inclusi qui).
enum EnemyType {
    // --- Tipi originali (15) ---
    ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT,
    ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
    ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
    ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST,
    // --- Nuovi tipi dal bestiary fantasy horror (13) ---
    ENEMY_MIMIC,            // monster_005 - forziere vivente
    ENEMY_WOLF,             // monster_003 - lupo spettrale
    ENEMY_WITCH,            // monster_007 - strega delle paludi
    ENEMY_BONE_GOLEM,       // monster_010 - golem di ossa
    ENEMY_ASH_SERPENT,      // monster_011 - serpente di cenere
    ENEMY_DAMNED_KNIGHT,    // monster_012 - cavaliere dannato
    ENEMY_MAD_WIZARD,       // monster_013 - mago folle
    ENEMY_DEMONIC_CROW,     // monster_015 - corvo demoniaco
    ENEMY_TENTACLE,         // monster_016 - tentacolo sotterraneo
    ENEMY_GARGOYLE,         // monster_017 - gargoyle vegliante
    ENEMY_WELL_SPIRIT,      // monster_018 - spirito del pozzo
    ENEMY_CURSED_BOAR,      // monster_019 - cinghiale maledetto
    ENEMY_PREDATOR_FUNGUS   // monster_020 - fungo predatore
};

// Numero totale di tipi di nemico (usato da Game::spawnEnemies per il
// random range). Se si aggiungono nuovi tipi all'enum, aggiornare anche
// questo valore.
constexpr int ENEMY_TYPE_COUNT = 28;

class Enemy {
public:
    // Costruttore: imposta posizione iniziale e statistiche in base al tipo.
    Enemy(EnemyType type, int startCol, int startRow);

    // Aggiorna il nemico (movimento + eventuale sparo).
    void update(Maze& maze, const Vec2& playerGridPos, const sf::Vector2f& playerPixelPos, std::vector<Projectile>& enemyProjectiles);

    // Disegna il nemico. Usa lo sprite se disponibile, altrimenti primitive.
    void render(sf::RenderTarget& target) const;

    void takeDamage(int dmg);
    bool isDead() const { return health <= 0; }
    Vec2 getGridPos() const;
    sf::Vector2f getPixelPos() const { return pos; }
    EnemyType getType() const { return type; }

    // True se il nemico sta eseguendo l'animazione di morte (dyingTimer>0).
    // Il nemico e' considerato "morto" per la logica di gioco (isDead()==true)
    // quando health<=0, ma l'animazione di morte continua per dyingTimer ms.
    bool isDying() const { return dyingTimer > 0; }
    // True se l'animazione di morte e' conclusa (il nemico puo' essere rimosso).
    bool isDeathAnimDone() const { return health <= 0 && dyingTimer == 0; }

    // --- SpriteSheet management ---
    // Carica tutti gli sprite dei nemici dalla cartella data. Da chiamare
    // una volta in Game::init(). I file mancanti vengono saltati
    // silenziosamente (il render fara' fallback alle primitive).
    static bool loadAllSprites(const std::string& basePath);
    // Libera gli sprite (chiamato alla chiusura, anche se non strettamente
    // necessario per SFML che gestisce le risorse).
    static void unloadAllSprites();

private:
    sf::Vector2f pos;
    int dx, dy;
    int speed;
    int health, maxHealth;
    EnemyType type;
    uint32_t pathUpdateTimer;
    uint32_t shootCooldown;
    uint32_t attackingTimer;  // >0 = animazione attacco in corso (ms simulati)
    uint32_t dyingTimer;      // >0 = animazione morte in corso (ms simulati)

    bool bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep);
    void moveGreedy(Maze& maze, const Vec2& target);

    // --- Render fallback a primitive SFML ---
    // Disegna il nemico con rettangoli/cerchi (vecchio comportamento).
    // Chiamato da render() se lo sprite non e' disponibile.
    void renderPrimitives(sf::RenderTarget& target) const;

    // --- SpriteSheet statici condivisi fra tutte le istanze ---
    // Mappa EnemyType -> SpriteSheet. Caricata una volta in loadAllSprites.
    static std::map<EnemyType, SpriteSheet> sprites;
    static bool spritesLoaded;

    // Restituisce l'ID del file (es. "monster_001") associato al tipo,
    // o stringa vuota se il tipo non ha uno sprite nel bestiary.
    static std::string getSpriteId(EnemyType t);
    // True se il tipo usa BFS invece di greedy.
    static bool usesBFS(EnemyType t);
    // True se il tipo puo' sparare al giocatore.
    static bool canShoot(EnemyType t);
};

#endif
