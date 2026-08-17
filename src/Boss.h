#ifndef BOSS_H
#define BOSS_H

// ===========================================================================
// Boss.h - Boss di fine livello.
//
// Esistono 17 tipi di boss (10 originali + 7 aggiunti per allineamento
// totale col bestiary fantasy horror). Il livello 1 corrisponde al tipo
// 0 (GOLEM), il livello 17 al tipo 16 (TWILIGHT_KNIGHT). In modalita'
// story i livelli sono 17 (STORY_LEVELS_COUNT = BOSS_TYPE_COUNT): ogni
// boss appare una sola volta, senza ripetizioni. In modalita' infinite
// si continua oltre i 17 e i tipi ciclano.
//
// Comportamento:
//   * Il boss si muove diagonalmente nella stanza rimbalzando sui bordi.
//   * Sparo a ventaglio (3 colpi) verso il giocatore, con probabilita'
//     di un colpo "bomba" piu' lento ma piu' potente.
//   * La velocita' e gli HP scalano col livello.
//   * L'animazione di attacco viene triggerata quando il boss spara
//     (attackingTimer > 0 per ~500 ms dopo ogni sparo).
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Utils.h"
#include "SpriteSheet.h"
#include <cstdint>
#include <map>
#include <string>

// Tipo di boss. L'ordine corrisponde al livello (1->GOLEM, 2->LICH, ...).
// I primi 10 sono i tipi originali; gli ultimi 7 sono aggiunti dal
// bestiary fantasy horror (allineamento totale col file di riferimento).
enum BossType {
    // --- 10 tipi originali ---
    BOSS_GOLEM, BOSS_LICH, BOSS_DEMON, BOSS_SPIDER,
    BOSS_ABOMINATION, BOSS_KRAKEN, BOSS_DRAGON,
    BOSS_WRAITH_LORD, BOSS_VAMPIRE, BOSS_BEHOLDER,
    // --- 7 nuovi tipi dal bestiary (boss_021, 023, 024, 025, 026, 027, 028) ---
    BOSS_GHOUL_LORD,         // boss_021 - Signore dei Ghoul
    BOSS_SPECTRAL_ALPHA,     // boss_023 - Lupo Alpha Spettrale
    BOSS_CULT_HERALD,        // boss_024 - Araldo del Culto
    BOSS_COLOSSAL_MIMIC,     // boss_025 - Mimic Colossale
    BOSS_RAT_KING,           // boss_026 - Re dei Topi
    BOSS_SUPREME_WITCH,      // boss_027 - Strega Suprema delle Paludi
    BOSS_TWILIGHT_KNIGHT     // boss_028 - Cavaliere del Crepuscolo
};

// Numero totale di tipi di boss (usato da Game per il ciclo sui livelli).
constexpr int BOSS_TYPE_COUNT = 17;

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
    BossType getType() const { return type; }

    // --- SpriteSheet management ---
    // Carica tutti gli sprite dei boss dalla cartella data. Da chiamare una
    // volta in Game::init(). I file mancanti vengono saltati: il render
    // fara' fallback alle primitive.
    static bool loadAllSprites(const std::string& basePath);
    static void unloadAllSprites();
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
    float animTime;       // tempo accumulato per le animazioni (in secondi)
    uint32_t attackingTimer;  // > 0 = animazione attacco in corso (ms simulati)

    // --- Render fallback a primitive SFML ---
    void renderPrimitives(sf::RenderTarget& target) const;

    // --- Overlays procedurali animati disegnati sopra lo sprite ---
    // Indipendenti dai frame dello sprite: arti, tentacoli, occhi, ali, ecc.
    // che si muovono in tempo reale secondo `animTime`. Danno al boss un
    // aspetto piu' "vivo" anche quando lo sprite ha pochi frame.
    void renderSpriteExtras(sf::RenderTarget& target) const;

    // --- SpriteSheet statici condivisi fra tutte le istanze ---
    static std::map<BossType, SpriteSheet> sprites;
    static bool spritesLoaded;
    // Mappa BossType -> ID del file bestiary. Tutti i 17 tipi hanno match
    // diretto col bestiary fantasy horror (10 originali mappati sui
    // corrispondenti boss_0xx del file + 7 nuovi).
    static std::string getSpriteId(BossType t);
};

#endif
