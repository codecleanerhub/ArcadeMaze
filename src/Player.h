#ifndef PLAYER_H
#define PLAYER_H

// ===========================================================================
// Player.h - Il personaggio controllato dall'utente.
//
// Movimento: "grid-aligned" nel labirinto (si muove di cella in cella,
// allineandosi al centro prima di poter cambiare direzione), ma in modalita'
// `freeMovement` (scontro col boss) il movimento e' libero in pixel.
//
// Sistema vitale: il giocatore ha `lives` vite; ogni vita ha `maxEnergy`
// punti energia. Quando l'energia arriva a 0 si perde una vita e l'energia
// viene ripristinata. Il salto e un breve periodo di invulnerabilita'
// dopo essere stati colpiti proteggono da ulteriori danni.
//
// Armi: il giocatore possiede un'arma alla volta (currentWeapon). Sparare
// consuma munizioni; quando finite non si puo' piu' sparare finche' non si
// raccoglie un'altra arma.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include "Weapon.h"
#include "Maze.h"
#include "Utils.h"
#include "SpriteSheet.h"
#include <cstdint>

// ===========================================================================
// CharacterType - 8 personaggi giocabili selezionabili dal menu "Select Player".
//
// I primi 2 (HERO_M, HERO_F) sono i personaggi originali del gioco
// (eroe maschio + eroina femmina). Gli altri 6 sono nuovi personaggi
// fantasy ispirati a classi D&D / LOTR: mago, orco, elfo, cavaliere,
// golem, uomo drago, vampiro.
//
// Ogni personaggio ha:
//   * Sprite PNG dedicato (assets/sprites/char_<name>_sheet.png) se esiste,
//     altrimenti fallback a primitive SFML (rendering procedurale).
//   * Stessa meccanica di gioco (non cambiano le statistiche).
//   * Color tint per distinguere P1 da P2 se scelgono lo stesso personaggio.
// ===========================================================================
enum CharacterType {
    CHAR_HERO_M,       // Eroe maschio (originale player1)
    CHAR_HERO_F,       // Eroina femmina (originale player2)
    CHAR_MAGE,         // Mago/stregone (mantello, cappello appuntito, bastone)
    CHAR_ORC,          // Orco (verde, zanne, muscoloso)
    CHAR_ELF,          // Elfo (biondo, orecchie appuntite, arco)
    CHAR_KNIGHT,       // Cavaliere (armatura, elmo, spada)
    CHAR_GOLEM,       // Golem (roccia grigia, occhi glow)
    CHAR_DRAGON,      // Uomo drago (scaglie rosse, ali, coda)
    CHAR_VAMPIRE       // Vampiro (mantello nero, pallore, canini)
};

constexpr int CHARACTER_TYPE_COUNT = 8;  // numero totale di personaggi

// Restituisce il nome del personaggio (per UI e path sprite).
// I file sprite sono: assets/sprites/char_<name>_sheet.png
std::string getCharacterSpriteBase(CharacterType ct);
// Restituisce il nome descrittivo (per UI menu selezione).
std::string getCharacterName(CharacterType ct);
// Restituisce il color tint per distinguere P1 (no tint = bianco) da P2
// (tint bluastro) quando scelgono lo stesso personaggio.
// playerNum: 1 o 2.
sf::Color getPlayerTint(int playerNum);

// Restituisce true se lo sprite PNG di default del personaggio e' rivolto
// verso DESTRA. Serve per decidere la logica di flip nel rendering:
//   * default RIGHT: flipped = (lastDx < 0)  -> specchia quando muove a sinistra
//   * default LEFT:  flipped = (lastDx > 0)  -> specchia quando muove a destra
// I valori sono stati verificati tramite VLM (vision model) su confronti
// side-by-side originale vs specchiato, integrando anche il feedback utente
// per HERO_M (player1) che e' stato corretto da LEFT a RIGHT dopo test reali.
bool spriteDefaultFacesRight(CharacterType ct);

class Player {
public:
    Player();

    // Reset completo: posizione, vite, energia, punteggio, arma iniziale.
    // Usato all'inizio di una nuova partita.
    void reset();
    // Reset solo della posizione e dei timer (mantiene vite/punteggio/arma).
    // Usato quando si ricomincia un livello o si rinascie dopo aver perso
    // una vita.
    void resetPosition();
    // Imposta posizione assoluta (usato in modalita' boss per posizionare
    // il giocatore in fondo alla stanza).
    void setPosition(float newX, float newY);

    // Aggiorna stato del giocatore (movimento, salto, cooldown, proiettili).
    // `freeMovement` true = modalita' stanza boss (movimento libero).
    // `particles` e' il vettore globale delle particelle, a cui il giocatore
    // aggiunge gli effetti (es. scintille del tesoro raccolto).
    void update(Maze& maze, bool freeMovement, std::vector<Particle>& particles);

    // Disegna il personaggio (corpo, cappello, frusta, arma equipaggiata)
    // e i suoi proiettili.
    void render(sf::RenderTarget& target);

    // Infligge un danno al giocatore (1 punto energia). Rispetta invulnerabilita'
    // e salto: se si e' saltando o ancora invulnerabili, il danno e' ignorato.
    void takeDamage();

    // Sostituisce l'arma corrente con quella raccolta.
    void collectWeapon(Weapon w);

    // Posizione sulla griglia del labirinto (utile per l'AI dei nemici).
    Vec2 getGridPos() const;
    // Posizione in pixel (centro del personaggio).
    sf::Vector2f getPixelPos() const { return pos; }

    int getLives() const { return lives; }
    int getEnergy() const { return energy; }
    int getMaxEnergy() const { return maxEnergy; }

    // Aggiunge punti al punteggio; ogni 100000 punti si guadagna una vita.
    void addScore(int points);
    int getScore() const { return score; }
    int getNextLifeThreshold() const { return nextLifeThreshold; }

    Weapon getCurrentWeapon() const { return currentWeapon; }
    // Riferimento ai proiettili sparati dal giocatore (usato da Game per
    // gestire le collisioni con nemici e boss).
    std::vector<Projectile>& getProjectiles() { return projectiles; }

    // Salto: quando e' > 0 il personaggio e' in aria (immune ai danni).
    bool isJumping() const { return jumpTimer > 0; }
    // Invulnerabilita' temporanea dopo essere stato colpito.
    bool isInvulnerable() const { return damageTimer > 0; }

    // Spara un proiettile nella direzione corrente (consuma 1 munizione).
    void shoot();
    // Attiva il salto (ha effetto solo se non si sta gia' saltando).
    void activateJump() { if (jumpTimer == 0) { maxJumpTime = 40; jumpTimer = maxJumpTime; } }

    // Cooldown fra un colpo e il successivo (in ms simulati: decrementato
    // di 16 per frame, quindi ~9 frame a 60 FPS).
    uint32_t getShootCooldown() const { return shootCooldown; }
    // Flag: true se il player ha appena raccolto un'arma nel labirinto.
    // Game::update lo controlla per riprodurre il suono di caricamento.
    bool pickedWeaponThisFrame;
    bool consumePickedWeapon() { bool v = pickedWeaponThisFrame; pickedWeaponThisFrame = false; return v; }
    void setShootCooldown(uint32_t cd) { shootCooldown = cd; }

    // Imposta la direzione desiderata (l'effettivo cambio avviene quando
    // il personaggio raggiunge il centro di una cella).
    void setDirection(int tDx, int tDy) {
        nextDx = tDx;
        nextDy = tDy;
    }

    // Aggiunge una vita (premio dopo aver sconfitto un boss).
    void addLife() { lives++; }

    // --- SpriteSheet management ---
    // Carica sprite principale + 4 frame camminata + 1 salto.
    bool loadSprite(const std::string& basePath);
    bool isSpriteLoaded() const { return sprite.isLoaded(); }

    // --- Character selection (Select Player menu) ---
    // Imposta il tipo di personaggio (eroe, mago, orco, ecc.) e il numero
    // giocatore (1 o 2). Carica lo sprite associato al personaggio.
    // Se playerNum=2 e il personaggio e' uguale a P1, viene applicato un
    // color tint bluastro per distinguere i due giocatori.
    void setCharacter(CharacterType ct, int playerNum);
    CharacterType getCharacter() const { return characterType; }
    int getPlayerNum() const { return playerNum; }
    // Carica lo sprite del personaggio corrente (basato su characterType).
    void loadCharacterSprite();

    // --- Speed boost (da bonus scarpe alate) ---
    void activateSpeedBoost() { speedBoostTimer = 5000; }  // 5 secondi
    bool hasSpeedBoost() const { return speedBoostTimer > 0; }

private:
    sf::Vector2f pos;       // posizione in pixel (centro personaggio)
    // dx,dy: direzione di movimento corrente; nextDx,nextDy: direzione
    // richiesta da input (applicata al prossimo centro cella);
    // lastDx,lastDy: ultima direzione non nulla (usata per orientare
    // l'arma quando il giocatore e' fermo).
    int dx, dy, nextDx, nextDy, lastDx, lastDy;
    int speed, lives, energy, maxEnergy, score, nextLifeThreshold;
    Weapon currentWeapon;
    std::vector<Projectile> projectiles;

    // Timer in "ms simulati": il gioco decrementa di 16 ogni frame a 60 FPS.
    uint32_t jumpTimer, maxJumpTime, damageTimer, shootCooldown;
    uint32_t shootAnimTimer;  // >0 = animazione attacco in corso
    uint32_t animTime;        // tempo accumulato per animazioni idle/walk
    uint32_t speedBoostTimer; // >0 = speed boost attivo (ms simulati)
    float jumpOffset;       // altezza visiva del salto (pixel)

    // SpriteSheet del giocatore: sprite principale (idle/stand)
    SpriteSheet sprite;
    // 4 frame di camminata alternati (walk0..walk3)
    SpriteSheet walkSprites[4];
    // Sprite salto
    SpriteSheet jumpSprite;

    // --- Character selection ---
    CharacterType characterType;  // personaggio scelto (eroe, mago, orco, ...)
    int playerNum;                // 1 o 2 (per tint color se stesso personaggio)
    sf::Color tint;               // tint applicato allo sprite (bianco = nessuno)

    // Tenta di muoversi nella direzione (tDx, tDy). Restituisce true se il
    // movimento e' possibile (la cella destinazione non e' muro).
    bool tryMove(int tDx, int tDy, Maze& maze);

    // Disegna solo i proiettili del giocatore (forma diversa per tipo).
    // Separato da render() perche' viene chiamato anche quando si usa lo
    // sprite PNG (i proiettili non sono parte dello spritesheet).
    void drawProjectiles(sf::RenderTarget& target);

    // Rendering procedurale (fallback) per i personaggi senza sprite PNG.
    // Disegna il personaggio con primitive SFML in base a characterType.
    // Usato anche per l'anteprima nel menu "Select Player".
    void renderCharacterFallback(sf::RenderTarget& target, float x, float y,
                                  bool flipped, bool walking, float bobY) const;
};

#endif
