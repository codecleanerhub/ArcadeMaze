#ifndef GAME_H
#define GAME_H

// ===========================================================================
// Game.h - Classe centrale del gioco.
//
// Game possiede tutti i sottosistemi (finestra SFML, maze, player, UI,
// audio, nemici, boss) e implementa il ciclo principale (handleEvents ->
// update -> render). Lo stato del gioco e' gestito da un enum `GameState`
// che pilota sia il rendering sia la logica di update.
//
// Modalita' di gioco:
//   * MODE_STORY: STORY_LEVELS_COUNT (17) livelli con boss crescenti, poi vittoria.
//   * MODE_INFINITE: continua senza fine (il contatore currentLevel cresce).
// ===========================================================================

#include <SFML/Graphics.hpp>
#include <vector>
#include "Maze.h"
#include "Player.h"
#include "Enemy.h"
#include "MiniBoss.h"
#include "UI.h"
#include "Utils.h"
#include "AudioManager.h"
#include "Boss.h"

// Stati di gioco: l'ordine NON e' arbitrario per la logica, ma i valori
// sono simbolici (non usati come indici).
enum GameState {
    STATE_MENU,           // menu' principale (sceglie anche 1/2 giocatori)
    STATE_SELECT_PLAYER,  // selezione personaggio (ruota 8 personaggi)
    STATE_CONFIG_JOY,     // configurazione joystick giocatore 1 (2 step)
    STATE_CONFIG_JOY_2,   // configurazione joystick giocatore 2 (2 step)
    STATE_PLAYING,        // modalita' labirinto (raccolta tesori + nemici)
    STATE_BOSS,           // scontro con il boss
    STATE_CONTINUES,      // schermata continues (conto alla rovescia 10-0)
    STATE_LOSE,           // schermata game over
    STATE_WIN_STORY,      // vittoria modalita' story (con fuochi d'artificio)
    STATE_WIN_INFINITE,   // vittoria modalita' infinite (placeholder)
    STATE_DEMO            // modalita' demo automatica (AI controlla P1 e P2)
};

enum GameMode { MODE_STORY, MODE_INFINITE };

// Numero di livelli della modalita' STORY. Quando currentLevel supera
// questo valore (dopo aver sconfitto il boss dell'ultimo livello), si
// passa a STATE_WIN_STORY. Ci sono 17 tipi di boss distinti: ogni livello
// story ha un boss diverso (nessuna ripetizione). STORY_LEVELS_COUNT = 17
// coincide con BOSS_TYPE_COUNT, cosi' ogni tipo appare una sola volta.
// In modalita' infinite si continua oltre i 17 e i tipi ciclano.
constexpr int STORY_LEVELS_COUNT = 17;

// Arma casuale da posizionare nella stanza del boss: il giocatore puo'
// raccoglierla per rimpiazzare la sua (le munizioni del boss sono 5).
struct BossRoomWeapon {
    Weapon w;
    sf::Vector2f pos;
};

// Fuoco d'artificio per la schermata STATE_WIN_STORY.
struct Firework {
    sf::Vector2f pos;
    sf::Vector2f vel;     // velocita' per frame (la y accelera in basso)
    sf::Color color;
    int life;             // vita residua in frame
};

// Bonus scarpe alate: aumenta la velocità di movimento del giocatore
// per 5 secondi quando raccolto. Appare nella stanza del boss.
// In modalita' 2P ci sono DUE paia di scarpe (una per player1, una per
// player2), ognuna con il proprio owner (1 o 2) per evitare che un
// player raccogli due volte. owner=0 significa "libera" (1P mode).
struct SpeedBootsBonus {
    sf::Vector2f pos;
    bool active;
    float bobOffset;  // oscillazione verticale per effetto fluttuante
    int owner;        // 0=libera (1P), 1=player1 (2P), 2=player2 (2P)
};

// Porta di uscita dal labirinto: quando tutti i tesori sono raccolti,
// appare una porta nel labirinto con animazione di apertura. Il player
// deve raggiungerla e toccarla per passare alla stanza del boss.
struct ExitDoor {
    sf::Vector2f pos;
    bool active;
    int animTimer;
    float glowPulse;
};

// Portale magico per respawn nemici: quando il 50% dei nemici viene ucciso,
// appare un portale magico al centro del labirinto. Si apre con un'animazione,
// fa uscire i nemici respawnati uno alla volta (4 secondi di intervallo),
// poi si chiude. Avviene una sola volta per livello.
struct MagicPortal {
    sf::Vector2f pos;
    bool active;
    int phase;              // 0=apertura, 1=spawn nemici (con intervalli), 2=chiusura, 3=inattivo
    int phaseTimer;         // ms residui della fase corrente
    float rotation;
    float glowPulse;
    int enemiesToSpawn;     // nemici ancora da spawnare
    int spawnTimer;         // ms residui al prossimo spawn (4000ms = 4 secondi)
    std::vector<int> deadEnemyIndices;  // indici dei nemici morti da respawnare
};

// Macchia di sangue temporanea sul pavimento dopo la morte di un nemico.
struct BloodStain {
    sf::Vector2f pos;
    int life;               // vita residua in frame (60 FPS)
    int maxLife;
    float radius;
    sf::Color color;
};

// Mucchio di cenere temporaneo sul pavimento dopo che un nemico e' stato
// BRUCIATO dal player invincibile (calice dell'immortalita'). Diverso dal
// BloodStain perche':
//   * Forma irregolare (mucchio, non macchia piatta)
//   * Colore grigio-beige chiaro (cenere) invece di rosso scuro (sangue)
//   * Particelle di cenere che si sollevano lentamente verso l'alto
//   * Piu' duraturo del sangue (i resti bruciati restano piu' a lungo)
struct AshPile {
    sf::Vector2f pos;
    int life;               // vita residua in frame (60 FPS)
    int maxLife;
    float radius;           // raggio del mucchio
    float animTime;         // tempo per animazione particelle cenere
};

// Effetto esplosione di fuoco che appare quando il player invincibile tocca
// un nemico. Sostituisce la vecchia logica "solo particelle triangolari" con
// uno spritesheet PNG animato (effect_fireburst) + glow radiale procedurale
// per dare un effetto fuoco realistico.
// Viene creato in updateInvincible() e renderizzato da drawFireBursts().
struct FireBurst {
    sf::Vector2f pos;       // centro dell'esplosione
    int life;               // vita residua in frame (60 frame = 1s)
    int maxLife;
    float animTime;          // tempo per animazione frame PNG
    float scale;            // scala dello sprite (1 = nativo 64x64)
};

// Mina: oggetto sul pavimento che, se calpestato dal player, si attiva
// e rimbalza. Se colpisce un nemico lo uccide e scompare.
// Una sola mina per livello. Appare nel labirinto E nella stanza del boss.
struct Mine {
    sf::Vector2f pos;
    bool active;
    bool bouncing;
    sf::Vector2f vel;
    int bounceTimer;
    float rotation;
    float pulse;
    bool inBossRoom;        // true = mina nella stanza del boss
};

// Calice d'oro: pozione magica che appare in posizione casuale nel labirinto.
struct GoldenChalice {
    sf::Vector2f pos;
    bool active;
    float pulse;
    float bobOffset;
};

// Scettro magico: bastone con gemma. Se raccolto, scatena 5 fulmini
// in posizioni casuali a 3 secondi di intervallo. I fulmini tolgono
// 50% HP ai nemici e 15% HP al boss. Appare 1 volta per livello (anche nel boss).
struct MagicScepter {
    sf::Vector2f pos;
    bool active;            // true = scettro presente sul pavimento
    float pulse;
    float bobOffset;
    int lightningsLeft;     // fulmini ancora da generare
    int lightningTimer;     // ms al prossimo fulmine (3000 = 3 secondi)
    bool triggered;         // true = scettro raccolto, fulmini in corso
};

// Fulmine: visualizzato brevemente quando colpisce. Il fulmine ATTRAVERSA
// TUTTO lo schermo: parte dal bordo superiore (o da un angolo) e scende fino
// al punto di impatto (dove fa danno). Questo garantisce che il fulmine
// attraversi tutto lo schermo e possa colpire nemici in qualsiasi posizione.
//
// La saetta e' composta da una lista di punti che formano un zigzag:
// parte da `startPos` (alto) e arriva a `pos` (punto di impatto).
// L'angolo puo' essere verticale, diagonale sinistra o diagonale destra.
struct Lightning {
    sf::Vector2f pos;       // posizione del fulmine (punto di impatto, basso)
    sf::Vector2f startPos;  // posizione di partenza (bordo superiore o angolo)
    int life;               // vita residua in frame
    int maxLife;
    bool hitEnemy;          // true se ha colpito un nemico
    bool hitBoss;           // true se ha colpito il boss
    // punti del zigzag (pre-calcolati per rendering stabile)
    std::vector<sf::Vector2f> zigzagPoints;
};

class Game {
public:
    Game();
    // Inizializza la finestra (framerate, view, config). Restituisce false
    // solo in caso di errore irreversibile (mai nel caso corrente).
    bool init();
    // Ciclo principale: handleEvents -> update -> render finche' isRunning.
    void run();
private:
    sf::RenderWindow window;
    Maze maze;
    Player player;
    Player player2;      // Secondo giocatore (usato solo se numPlayers == 2)
    UI ui;
    AudioManager audio;
    int numPlayers;      // 1 o 2 giocatori (impostato nel menu)

    // Entita' di gioco. `enemies` e' un vettore perche' ogni livello ne
    // genera 5. `boss` e' un puntatore perche' viene creato/destroyato
    // dinamicamente ad ogni scontro. `miniBoss` e' un puntatore perche'
    // appare SOLO quando il portale magico fa respawn (1 per labirinto).
    std::vector<Enemy> enemies;
    Boss* boss;
    MiniBoss* miniBoss;            // mini-boss del labirinto (1 per livello, al respawn)
    bool miniBossSpawned;          // true = mini-boss gia' generato questo livello
    std::vector<Projectile> bossProjectiles;     // proiettili sparati dal boss
    std::vector<Projectile> enemyProjectiles;    // proiettili sparati dai nemici
    std::vector<BossRoomWeapon> bossRoomWeapons; // armi a terra nella stanza del boss
    SpeedBootsBonus speedBoots;                 // bonus scarpe alate player1
    SpeedBootsBonus speedBoots2;                // bonus scarpe alate player2 (2P)
    ExitDoor exitDoor;                          // porta di uscita dal labirinto (post-tesori)
    MagicPortal magicPortal;                    // portale magico per respawn nemici
    bool portalUsed;                            // true = portale gia' usato questo livello
    int initialEnemyCount;                      // numero nemici iniziali (per calcolo 50%)
    std::vector<BloodStain> bloodStains;        // macchie di sangue temporanee
    std::vector<AshPile> ashPiles;              // mucchi di cenere (nemici bruciati)
    std::vector<FireBurst> fireBursts;          // esplosioni di fuoco (nemici bruciati)
    Mine mine;                                   // mina sul pavimento (1 per livello)
    GoldenChalice chalice;                       // calice d'oro pozione magica (1 per livello)
    bool chaliceUsed;                            // true = calice gia' raccolto questo livello
    int playerInvincibleTimer;                   // >0 = player1 immortale (ms residui)
    int player2InvincibleTimer;                  // >0 = player2 immortale (ms residui)
    MagicScepter scepter;                        // scettro magico fulmini (1 per livello)
    bool scepterUsed;                            // true = scettro gia' raccolto questo livello
    std::vector<Lightning> lightnings;           // fulmini attivi (visualizzazione)
    std::vector<Particle> particles;             // particelle generiche (sangue, scintille)
    std::vector<Firework> fireworks;             // fuochi d'artificio (solo in WIN_STORY)

    Config config;
    GameState state;
    GameMode gameMode;
    bool isRunning;
    int currentLevel;                          // 1..STORY_LEVELS_COUNT (story) o illimitato (infinite)
    int menuItemIndex;                         // voce menu' selezionata (0..5)
    bool musicEnabled;
    int lightningTimer;                        // durata residua del fulmine nel menu'
    int screenFlashTimer;                      // ms residui del flash bianco schermo (fulmini)
    int configJoyStep;                         // step configurazione joystick (0/1)
    int continuesLeft;                         // crediti continues rimanenti (max 3)
    int continuesTimer;                        // conto alla rovescia 10-0 (secondi)
    int continuesTimerMs;                      // ms residui del secondo corrente
    bool continuesChoice;                      // true = YES, false = NO
    bool diedInBoss;                           // true se morto durante il boss

    // --- Select Player (selezione personaggio) ---
    // 8 personaggi giocabili (CHAR_HERO_M, CHAR_HERO_F, CHAR_MAGE, ecc.).
    // P1 e P2 scelgono indipendentemente il proprio personaggio.
    // Se scelgono lo stesso, P2 ha un tint bluastro per distinguerlo.
    CharacterType player1Character;            // personaggio scelto da P1
    CharacterType player2Character;            // personaggio scelto da P2
    int selectPlayerStep;                      // 0 = P1 sceglie, 1 = P2 sceglie (solo 2P)
    int wheelIndex;                            // indice personaggio corrente nella ruota (0..7)
    float wheelRotation;                       // animazione rotazione ruota (per transizione fluida)
    int wheelTargetIndex;                      // indice target (per animazione smooth)

    // --- TEST MODE (feature temporanea, facilmente disabilitabile) ---
    // Per disabilitare completamente la voce di menu "Test Mode" e la
    // scorciatoia da tastiera (barra spaziatrice per saltare il livello),
    // basta commentare la riga #define seguente. Tutto il codice collegato
    // e' racchiuso tra #ifdef TEST_MODE_FEATURE / #endif.
#define TEST_MODE_FEATURE
#ifdef TEST_MODE_FEATURE
    bool testModeEnabled;                      // true = salto livello con Space attivo
    bool testSkipKeyPressed;                   // debounce: true finche' Space resta premuto
#endif

    // --- DEMO MODE (modalita' demo automatica) ---
    // Quando l'utente non interagisce col menu per 30 secondi, il gioco si
    // avvia automaticamente in modalita' Demo: 2 giocatori controllati dal
    // computer, personaggi casuali, livello casuale (labirinto o boss).
    // La demo dura 2 minuti, poi torna al menu. Se l'utente preme un tasto
    // o muove il joystick durante la demo, questa si interrompe.
    int demoInactivityTimer;     // ms residui di inattivita' prima della demo (30000 = 30s)
    int demoDurationTimer;       // ms residui di durata demo (120000 = 2min)
    bool demoIsBoss;             // true = demo nella stanza del boss, false = labirinto
    int demoAiTimerP1;           // timer per cambio direzione AI P1
    int demoAiTimerP2;           // timer per cambio direzione AI P2
    int demoAiDirP1;             // direzione corrente AI P1 (0=fermo,1=su,2=giu,3=sx,4=dx)
    int demoAiDirP2;             // direzione corrente AI P2 (0=fermo,1=su,2=giu,3=sx,4=dx)
    int demoAiShootTimerP1;      // timer per sparo AI P1
    int demoAiShootTimerP2;      // timer per sparo AI P2

    // Sottometodi del ciclo principale
    void handleEvents();
    void update();
    void render();

    // Genera 5 nemici in posizioni casuali del labirinto.
    void spawnEnemies();
    // Spawna un nemico dal portale magico (1 alla volta).
    void spawnEnemyFromPortal();
    // Inizia un nuovo livello: rigenera maze, resetta posizione giocatore,
    // spawn nemici, riproduce musica.
    void startLevel(int lvl);
    // Passa alla stanza del boss: crea il boss, posiziona il giocatore in
    // fondo, spawn delle armi casuali sul pavimento.
    // Se `keepBossState` e' true (continue dopo morte nel boss), NON ricrea
    // il boss: mantiene HP/posizione/animazione esatti del boss in vita al
    // momento della morte del player. Resetta solo player, proiettili e armi.
    void startBossFight(bool keepBossState = false);
    // Genera 3 armi casuali nella stanza del boss (raccoglibili).
    void spawnBossRoomWeapons();
    // Mappa WeaponType -> SoundType per riprodurre il suono corretto.
    SoundType getWeaponSound(WeaponType wt);

    // Disegna il menu' principale (sfondo stellato + luna + fulmini + opzioni).
    void drawMenu();
    // Disegna la schermata di configurazione joystick.
    void drawConfigJoy();
    // Disegna la schermata continues (conto alla rovescia, Yes/No).
    void drawContinues();
    // Disegna la schermata di configurazione joystick per il giocatore 2.
    void drawConfigJoy2();
    // Disegna la schermata di selezione personaggio (ruota 8 personaggi).
    // Mostra il personaggio corrente al centro (frontale) e i vicini ai lati
    // (in scala ridotta per effetto "carosello"). Joystick/tastiera ruota
    // la selezione, Enter conferma. In 2P: P1 sceglie prima, poi P2.
    void drawSelectPlayer();
    // Disegna un'anteprima del personaggio (sprite PNG o fallback primitive).
    // Usato da drawSelectPlayer per ogni personaggio nella ruota.
    void drawCharacterPreview(sf::RenderTarget& target, CharacterType ct,
                              float x, float y, float scale,
                              const sf::Color& tint, sf::Uint8 alpha);
    // Genera un fuoco d'artificio esploso in posizione casuale.
    void spawnFirework();
    // Disegna lo scettro magico in stile "Gandalf" (bastone di Gandalf
    // grigio con gemma cristallina luminosa sulla cima). e' chiamato da
    // STATE_PLAYING, STATE_BOSS e dalla minimappa. Centralizza il rendering
    // per evitare duplicazione di codice tra i 3 stati. (sx, sy) e' il
    // centro del bastone (la gemma e' sopra, l'impugnatura sotto).
    // sPulse e' il fattore di pulsazione (>1 = piu' grande, effetto aura).
    void drawMagicScepter(sf::RenderTarget& target, float sx, float sy, float sPulse);
    // Genera i punti zigzag di un fulmine che parte da startPos (alto) e
    // arriva a endPos (punto di impatto, basso). Il fulmine ha `numSegs`
    // segmenti con oscillazione orizzontale casuale di ampiezza `jitter`.
    // I punti sono pre-calcolati una tantum per rendering stabile.
    std::vector<sf::Vector2f> generateLightningPath(sf::Vector2f startPos,
                                                    sf::Vector2f endPos,
                                                    int numSegs, float jitter);
    // Crea un fulmine completo (Lightning) con path zigzag che attraversa
    // tutto lo schermo. Sceglie casualmente un angolo di partenza:
    // verticale, diagonale sinistra o diagonale destra. Imposta life,
    // maxLife, hitEnemy=false, hitBoss=false, e pre-calcola zigzagPoints.
    // endPoint e' il punto di impatto (dove il fulmine fa danno).
    Lightning createFullScreenLightning(sf::Vector2f endPoint);
    // Disegna un fulmine (con path zigzag gia' calcolato) sul target.
    // Usa primitve SFML: segmenti larghi 4px con outline bianca, halo,
    // glow, flash, ramificazioni e scintille. Stile 8-bit/16-bit.
    void drawLightning(sf::RenderTarget& target, const Lightning& lt);
    // Disegna l'aura di FUOCO attorno al giocatore quando e' invincibile
    // (calice dell'immortalita'). Sostituisce la vecchia aura gialla con:
    //   * Fiamme animate che salgono dal basso verso l'alto (8 fiamme)
    //   * Bagliore arancione pulsante attorno al player
    //   * Particelle di scintille che fluttuano
    // Colori palette 16: (220,160,40) oro, (200,80,80) rosso, (240,240,240)
    // cenere bianca. (pos) e' il centro del player, invTimer per pulsazione.
    void drawFireAura(sf::RenderTarget& target, sf::Vector2f pos, int invTimer);
    // Disegna le esplosioni di fuoco create quando il player invincibile
    // brucia un nemico. Usa spritesheet PNG (effect_fireburst) + glow radiale.
    void drawFireBursts(sf::RenderTarget& target);
    // Disegna i mucchi di cenere. Usa spritesheet PNG (effect_ashpile) +
    // braci incandescenti + fumo procedurale.
    void drawAshPiles(sf::RenderTarget& target);

    // --- DEMO MODE ---
    // Avvia la modalita' demo: sceglie personaggi casuali, modalita' 2P,
    // livello casuale (labirinto o boss), resetta timer durata a 2 minuti.
    void startDemoMode();
    // Aggiorna la logica demo: AI per P1 e P2 (movimento + sparo casuale),
    // gestione timer durata, interruzione se l'utente preme un tasto.
    void updateDemoMode();
    // Disegna l'overlay "DEMO MODE" in alto (rosso intermittente stile fantasy).
    void drawDemoOverlay(sf::RenderTarget& target);
    // Ferma la demo e torna al menu principale, resettando il timer di
    // inattivita' a 30 secondi.
    void stopDemoMode();

    // --- FLUSSO PARTITA ---
    // Chiamato dopo che P1 (1P) o P2 (2P) hanno finito la selezione personaggio.
    // Controlla se i tasti sono configurati: se lo sono, avvia il livello;
    // altrimenti, va a STATE_CONFIG_JOY (che poi portera' a STATE_CONFIG_JOY_2
    // in 2P, e infine al livello).
    void startGameAfterSelectPlayer();
};

#endif

