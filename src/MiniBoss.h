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

// Tipo di mini-boss. 51 tipi (1 per ogni livello labirinto della story mode).
// In modalita' story ogni tipo appare una sola volta. In modalita' infinite
// i tipi ciclano dopo il 51.
//
// ISPIRAZIONI:
//   - LOTR: Orchi di Moria, Uruk-hai, Troll, Nazgul, Spettri del Crepuscolo
//   - D&D: Ogre, Gnoll, Bugbear, Minotauro, Lich minore, Occhio Beholder
//   - Narnia: Lupo Fenris, Strega Bianca, Minotauro di Narnia, Nano guerriero
//   - The Witcher: Leshen, Bruxa, Katakan, Fiend, Werewolf, Golem di Witcher
//   - Doom: Imp, Pinky Demon, Revenant, Cacodemon, Hell Knight, Mancubus
enum MiniBossType {
    // --- LOTR + D&D (17 originali, livelli 1-17 labirinto) ---
    MB_GOBLIN_CHIEFTAIN,     // Capo Goblin (ascia)
    MB_CAVE_TROLL,           // Troll delle caverne (mazza)
    MB_ORC_BERSERKER,        // Orco berserker (scure)
    MB_WARG_RIDER,           // Cavaliere di Warg (lancia)
    MB_URUK_HAI,            // Uruk-hai (spada)
    MB_NAZGUL,              // Nazgul (pugnale avvelenato)
    MB_OGRE_BRUTE,          // Ogre (mazzafrusto)
    MB_GNOLL_PACKLORD,      // Signore dei Gnoll (ascia)
    MB_BUGBEAR_CHIEF,       // Capo Bugbear (catena)
    MB_MINOTAUR,            // Minotauro (ascia bipenne)
    MB_WIGHT_LORD,          // Signore dei Wight (spada spettrale)
    MB_CAVE_GIANT,          // Gigante delle caverne (mazza)
    MB_DEATH_KNIGHT,        // Cavaliere della morte (spada)
    MB_ILLITHID,            // Mind Flayer (tentacoli)
    MB_ETTIN,               // Ettin (due teste, due mazze)
    MB_FOMORIAN,            // Gigante deforme (mazza)
    MB_BALROG_CULTIST,      // Cultista del Balrog (frusta di fuoco)
    // --- Narnia (7, livelli 18-24 labirinto) ---
    MB_FENRIS_WOLF,         // Lupo Fenris di Narnia (zanne)
    MB_WHITE_WITCH_GUARD,   // Guardia della Strega Bianca (spada di ghiaccio)
    MB_NARNIA_MINOTAUR,     // Minotauro di Narnia (ascia)
    MB_DWARF_BERSERKER,     // Nano guerriero di Narnia (ascia)
    MB_WITCH_KNIGHT,       // Cavaliere della Strega Bianca (lancia di ghiaccio)
    MB_TALKING_BEAST,       // Bestia parlante corrotta (artigli)
    MB_ICE_GIANT_NARNIA,    // Gigante di ghiaccio (mazza)
    // --- The Witcher (10, livelli 25-34 labirinto) ---
    MB_LESHEN,             // Leshen (artigli + radici)
    MB_BRUXA,              // Bruxa (artigli vampireschi)
    MB_KATAKAN,            // Katakan (artigli)
    MB_FIEND,              // Fiend (corna)
    MB_WITCHER_GOLEM,      // Golem di Witcher (pugni)
    MB_NOONWRAITH,         // Noonwraith (lama spettrale)
    MB_FOGLET,             // Foglet (artigli)
    MB_GRAVE_HAG,           // Strega delle tombe (artigli)
    MB_MANTICORE_WITCHER,  // Manticore (coda aculeata)
    MB_CYCLOPS_WITCHER,    // Ciclope di Witcher (mazza)
    // --- Doom (10, livelli 35-44 labirinto) ---
    MB_DOOM_IMP,           // Imp di Doom (palle di fuoco)
    MB_PINKY_DEMON,        // Pinky Demon (zanne)
    MB_REVENANT,           // Revenant (missili)
    MB_CACODEMON,          // Cacodemon (plasma)
    MB_HELL_KNIGHT,       // Hell Knight (pugni)
    MB_MANCUBUS,           // Mancubus (fiamme)
    MB_ARCHVILE,          // Archvile (fuoco)
    MB_BARON_OF_HELL,     // Baron of Hell (artigli)
    MB_PAIN_ELEMENTAL,    // Pain Elemental (lost souls)
    MB_DOOM_CYBERDEMON,   // Cyberdemone minore (razzo)
    // --- Ibridi/Fantasy extra (7, livelli 45-51 labirinto) ---
    MB_SHADOW_ASSASSIN,    // Assassino ombra (pugnali)
    MB_CRYSTAL_GOLEM,     // Golem di cristallo (pugni cristallini)
    MB_VOID_WALKER,       // Camminatore del vuoto (artigli dimensionali)
    MB_BLOOD_ELEMENTAL,   // Elementale di sangue (lame di sangue)
    MB_STORM_TITAN,      // Titano della tempesta (fulmine)
    MB_PLAGUE_LORD,      // Signore della peste (bastone infetto)
    MB_VOID_SERPENT       // Serpente del vuoto (morsi velenosi)
};

constexpr int MINIBOSS_TYPE_COUNT = 51;

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

    // --- STATO BURNING (bruciatura da player invincibile) ---
    // Come per Enemy: quando il player invincibile (calice) tocca il mini-boss,
    // questo NON muore istantaneamente: entra in stato "burning" per
    // `burningTimer` frame. Durante questo stato:
    //   * Il mini-boss e' fermo (non si muove, non attacca)
    //   * Sopra di esso viene disegnato un overlay di fiamme (sprite PNG
    //     effect_fireaura + glow radiale multistrato + poche fiamme procedurali)
    // A fine burning, il mini-boss muore (cenere + FireBurst finale).
    // Poiche' il mini-boss e' piu' resistente dei nemici normali (18-35 HP),
    // una singola "bruciatura" non lo uccide: gli toglie ~40% HP. Servono
    // 2-3 contatti ravvicinati col player invincibile per bruciarlo del tutto.
    bool isBurning() const { return burningTimer > 0; }
    void startBurning(int frames = 50);  // accende per `frames` frame
    // True se e' appena uscito dallo stato burning (burningTimer scaduto ma
    // non ancora morto). Usato da Game per finalizzare la morte (cenere).
    bool wasBurned() const { return burnedFlag; }
    void clearBurnedFlag() { burnedFlag = false; }
    // True se il mini-boss sta morendo (animazione morte in corso).
    bool isDying() const { return dyingTimer > 0; }

    // --- FLEE MODE (calice dell'immortalita') ---
    // Quando fleeMode e' true, il mini-boss si allontana dal player invece
    // di inseguirlo. Attivato da Game quando il player e' invincibile.
    void setFleeMode(bool flee) { fleeMode = flee; }
    bool isFleeing() const { return fleeMode; }

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
    uint32_t burningTimer;       // >0 = mini-boss che brucia (player invincibile)
    uint32_t burnAnimTime;       // tempo accumulato per animazione fiamme overlay
    bool burnedFlag;             // true se e' stato in burning (per finalizzazione morte)
    float animTime;
    int size;                    // dimensione sprite (32-40px)

    // --- FIX: target di movimento persistente tra un pathfinding BFS e il
    // successivo. In precedenza il movimento era INSIDE il blocco BFS che
    // gira ogni ~300ms, quindi il mini-boss si muoveva solo 1 volta ogni
    // 18 frame -> sembrava congelato. Ora il BFS calcola solo il target
    // (centro della prossima cella) e il movimento viene applicato OGNI
    // frame verso targetPos, dando movimento fluido.
    sf::Vector2f targetPos;      // centro della cella verso cui muovere
    bool hasTarget;              // true se targetPos e' valido

    bool fleeMode;  // true = il mini-boss fugge dal player (calice attivo)

    // SpriteSheet del mini-boss (caricato da assets/sprites/miniboss_XX)
    SpriteSheet sprite;
    bool spriteLoaded;

    // BFS pathfinding (come Enemy::bfsPath)
    bool bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep);
    void moveGreedy(Maze& maze, const Vec2& target);
    // fleeGreedy: euristica di FUGA per il mini-boss. Sceglie la cella
    // adiacente che MASSIMIZZA la distanza dal target (player).
    void fleeGreedy(Maze& maze, const Vec2& target);

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
