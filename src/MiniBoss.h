#ifndef MINIBOSS_H
#define MINIBOSS_H

// ===========================================================================
// MiniBoss.h - Mini-boss dei labirinti (1 per livello, generato al respawn).
//
// I mini-boss sono nemici PIU' FORTI dei nemici normali ma PIU' DEBOLI dei
// boss di fine livello. Appaiono 1 volta per labirinto, quando il portale
// magico fa respawn dei nemici (al 50% dei nemici uccisi).
//
// Caratteristiche:
//   * 17 tipi unici (1 per labirinto, ispirati a LOTR e D&D)
//   * HP: tra nemico normale (3-8) e boss (50-250). ~20-40 HP.
//   * Velocita': PIU' LENTA del player (permette di scappare)
//   * AI: INSEGUE il player (BFS pathfinding come i nemici "pensanti")
//   * Armi unique: asce, coltelli, mazze, catene (armi bianche contundenti
//     e taglienti, NON proiettili). Attacco MEELE a distanza ravvicinata.
//   * Drop: score alto (5000-10000) quando ucciso
//
// Grafica:
//   * Stile BOSS (sprite dettagliati, palette 16 colori, overlays animati)
//   * Dimensioni PICCOLE (32-40px, entra nel labirinto TILE_SIZE=48)
//   * Diversi visivamente sia dai nemici normali (piu' piccoli) sia dai
//     boss (piu' grandi)
//
// Ispirazione: mostri del Signore degli Anelli (Orchi di Moria, Uruk-hai,
// Troll delle caverne, Nazgul, Spettri) e Dungeon & Dragons (Ogre, Gnoll,
// Bugbear, Minotauro, Lich minore).
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include "Maze.h"
#include "SpriteSheet.h"
#include <cstdint>
#include <string>
#include <map>

// Tipo di mini-boss. 17 tipi (1 per labirinto). L'ordine corrisponde al
// livello (1->GOBLIN_CHIEFTAIN, 2->CAVE_TROLL, ...). In modalita' story
// ogni tipo appare una sola volta. In modalita' infinite i tipi ciclano.
//
// ISPIRAZIONI:
//   - LOTR: Orchi di Moria, Uruk-hai, Troll, Nazgul, Spettri del Crepuscolo
//   - D&D: Ogre, Gnoll, Bugbear, Minotauro, Lich minore, Occhio Beholder
enum MiniBossType {
    MB_GOBLIN_CHIEFTAIN,     // Livello 1: Capo Goblin (ascia)
    MB_CAVE_TROLL,           // Livello 2: Troll delle caverne (mazza)
    MB_ORC_BERSERKER,        // Livello 3: Orco berserker (scure)
    MB_WARG_RIDER,           // Livello 4: Cavaliere di Warg (lancia)
    MB_URUK_HAI,            // Livello 5: Uruk-hai (spada)
    MB_NAZGUL,              // Livello 6: Nazgul (pugnale avvelenato)
    MB_OGRE_BRUTE,          // Livello 7: Ogre (mazzafrusto)
    MB_GNOLL_PACKLORD,      // Livello 8: Signore dei Gnoll (ascia)
    MB_BUGBEAR_CHIEF,       // Livello 9: Capo Bugbear (catena)
    MB_MINOTAUR,            // Livello 10: Minotauro (ascia bipenne)
    MB_WIGHT_LORD,          // Livello 11: Signore dei Wight (spada spettrale)
    MB_CAVE_GIANT,          // Livello 12: Gigante delle caverne (mazza)
    MB_DEATH_KNIGHT,        // Livello 13: Cavaliere della morte (spada)
    MB_ILLITHID,            // Livello 14: Mind Flayer (tentacoli)
    MB_ETTIN,               // Livello 15: Ettin (due teste, due mazze)
    MB_FOMORIAN,            // Livello 16: Gigante deforme (mazza)
    MB_BALROG_CULTIST       // Livello 17: Cultista del Balrog (frusta di fuoco)
};

constexpr int MINIBOSS_TYPE_COUNT = 17;

// Tipo di arma del mini-boss (determina animazione attacco e danno).
enum MiniBossWeapon {
    MBW_AXE,        // ascia (tagliente, danno medio)
    MBW_MACE,       // mazza (contundente, danno alto)
    MBW_SWORD,      // spada (tagliente, danno medio-alto)
    MBW_DAGGER,     // pugnale (tagliente, danno basso ma veloce)
    MBW_CHAIN,      // catena (contundente, danno alto, raggio lungo)
    MBW_CLUB,       // mazzafrusto (contundente, danno molto alto)
    MBW_WHIP,       // frusta (tagliente, raggio lunghissimo)
    MBW_TENTACLES   // tentacoli (danno medio, effetto mente)
};

struct Projectile;  // forward declaration

class MiniBoss {
public:
    // Costruttore: imposta posizione e statistiche in base al tipo e livello.
    MiniBoss(MiniBossType t, int level, int startCol, int startRow);

    // Aggiorna il mini-boss: AI inseguitamento (BFS) + attacco meele.
    // `playerGridPos` e' la posizione del player in coordinate griglia.
    // `playerPixelPos` per il calcolo dell'attacco meele (distanza).
    // `particles` per effetti visivi dell'attacco (scintille, sangue).
    void update(Maze& maze, const Vec2& playerGridPos,
                const sf::Vector2f& playerPixelPos,
                std::vector<Particle>& particles);

    // Disegna il mini-boss (stile boss ma dimensioni piccole).
    void render(sf::RenderTarget& target) const;

    // Infligge danni al mini-boss.
    void takeDamage(int dmg) { health -= dmg; if (health < 0) health = 0; }

    bool isDead() const { return health <= 0; }
    sf::Vector2f getPixelPos() const { return pos; }
    MiniBossType getType() const { return type; }
    MiniBossWeapon getWeapon() const { return weapon; }
    int getHealth() const { return health; }
    int getMaxHealth() const { return maxHealth; }
    int getAttackDamage() const;
    float getAttackRange() const;  // raggio di attacco meele in pixel
    int getScoreReward() const;

    // True se il mini-boss sta attaccando in questo frame (per collisione danno).
    bool isAttacking() const { return attackingTimer > 0; }

private:
    sf::Vector2f pos;
    int dx, dy;
    int speed;
    int health, maxHealth;
    MiniBossType type;
    MiniBossWeapon weapon;
    uint32_t pathUpdateTimer;
    uint32_t attackCooldown;     // ms residui al prossimo attacco
    uint32_t attackingTimer;     // >0 = animazione attacco in corso
    uint32_t dyingTimer;         // >0 = animazione morte
    float animTime;
    int size;                    // dimensione sprite (32-40px)

    // SpriteSheet del mini-boss (caricato da assets/sprites/miniboss_XX)
    SpriteSheet sprite;
    bool spriteLoaded;

    // BFS pathfinding (come Enemy::bfsPath)
    bool bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep);
    void moveGreedy(Maze& maze, const Vec2& target);

    // Render a primitive SFML (fallback se sprite non disponibile)
    void renderPrimitives(sf::RenderTarget& target) const;

    // Mappa tipo -> ID file sprite (miniboss_01, miniboss_02, ecc.)
    static std::string getSpriteId(MiniBossType t);
    // Carica lo sprite per il tipo corrente
    void loadSprite();

    // Mappa tipo -> arma
    static MiniBossWeapon getWeaponForType(MiniBossType t);
    // Statistiche in base al tipo e livello
    static int getBaseHealth(MiniBossType t);
    static int getBaseSpeed(MiniBossType t);
    static int getBaseSize(MiniBossType t);
};

#endif
