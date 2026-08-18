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
#include "UI.h"
#include "Utils.h"
#include "AudioManager.h"
#include "Boss.h"

// Stati di gioco: l'ordine NON e' arbitrario per la logica, ma i valori
// sono simbolici (non usati come indici).
enum GameState {
    STATE_MENU,           // menu' principale (sceglie anche 1/2 giocatori)
    STATE_CONFIG_JOY,     // configurazione joystick giocatore 1 (2 step)
    STATE_CONFIG_JOY_2,   // configurazione joystick giocatore 2 (2 step)
    STATE_PLAYING,        // modalita' labirinto (raccolta tesori + nemici)
    STATE_BOSS,           // scontro con il boss
    STATE_CONTINUES,      // schermata continues (conto alla rovescia 10-0)
    STATE_LOSE,           // schermata game over
    STATE_WIN_STORY,      // vittoria modalita' story (con fuochi d'artificio)
    STATE_WIN_INFINITE    // vittoria modalita' infinite (placeholder)
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
struct SpeedBootsBonus {
    sf::Vector2f pos;
    bool active;
    float bobOffset;  // oscillazione verticale per effetto fluttuante
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

// Mina: oggetto sul pavimento del labirinto che, se calpestato dal player,
// si attiva e rimbalza per 8 secondi. Se colpisce un nemico lo uccide
// e scompare. Se non colpisce nessuno, scompare dopo 8 secondi.
// Una sola mina per livello, in posizione casuale.
// Puo' comparire anche nella stanza del boss.
struct Mine {
    sf::Vector2f pos;
    bool active;            // true = mina presente sul pavimento
    bool bouncing;          // true = mina attivata e in movimento
    sf::Vector2f vel;       // velocita' di rimbalzo (px/frame)
    int bounceTimer;        // ms residui di rimbalzo (8000 = 8 secondi)
    float rotation;         // rotazione per animazione
    float pulse;            // pulsazione visiva
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
    // dinamicamente ad ogni scontro.
    std::vector<Enemy> enemies;
    Boss* boss;
    std::vector<Projectile> bossProjectiles;     // proiettili sparati dal boss
    std::vector<Projectile> enemyProjectiles;    // proiettili sparati dai nemici
    std::vector<BossRoomWeapon> bossRoomWeapons; // armi a terra nella stanza del boss
    SpeedBootsBonus speedBoots;                 // bonus scarpe alate (1 per boss fight)
    ExitDoor exitDoor;                          // porta di uscita dal labirinto (post-tesori)
    MagicPortal magicPortal;                    // portale magico per respawn nemici
    bool portalUsed;                            // true = portale gia' usato questo livello
    int initialEnemyCount;                      // numero nemici iniziali (per calcolo 50%)
    std::vector<BloodStain> bloodStains;        // macchie di sangue temporanee
    Mine mine;                                   // mina sul pavimento (1 per livello)
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
    int configJoyStep;                         // step configurazione joystick (0/1)
    int continuesLeft;                         // crediti continues rimanenti (max 3)
    int continuesTimer;                        // conto alla rovescia 10-0 (secondi)
    int continuesTimerMs;                      // ms residui del secondo corrente
    bool continuesChoice;                      // true = YES, false = NO
    bool diedInBoss;                           // true se morto durante il boss

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
    // Genera un fuoco d'artificio esploso in posizione casuale.
    void spawnFirework();
};

#endif

