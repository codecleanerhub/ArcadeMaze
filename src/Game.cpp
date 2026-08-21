#include "Game.h"
#include "XInputJoystick.h"
#include <iostream>
#include <cstdlib>
#include <algorithm>
#include <cmath>

// ===========================================================================
// Game.cpp - Implementazione del ciclo di gioco centrale.
//
// Flusso di una partita tipica:
//   1. Menu: scelta modalita'/musica, configurazione joystick, avvio partita.
//   2. Per ogni livello (1..STORY_LEVELS_COUNT):
//      a. STATE_PLAYING: esplorazione labirinto, raccolta tesori, scontro
//         con i nemici. Quando `maze.getRemainingTreasures()==0` si passa
//         al boss.
//      b. STATE_BOSS: scontro nella stanza del boss. Quando il boss muore
//         si guadagna una vita e si passa al livello successivo; dopo il
//         livello STORY_LEVELS_COUNT (17, un boss per tipo senza ripetizioni)
//         in modalita' story si vince.
//   3. STATE_LOSE: game over (Enter torna al menu').
//   4. STATE_WIN_STORY: vittoria (con fuochi d'artificio).
//
// Tutti i tempi sono gestiti come "ms simulati" decrementati di 16 ogni
// frame a 60 FPS.
// ===========================================================================

// ---------------------------------------------------------------------------
// Costruttore: crea la finestra in fullscreen alla risoluzione desktop e
// inizializza tutti i membri ai valori di default. La view SFML e' impostata
// a una risoluzione logica fissa WINDOW_WIDTH x WINDOW_HEIGHT (1024x1024):
// il viewport viene poi riadattato in handleEvents (evento Resized) per
// mantenere l'aspect ratio e centrare l'immagine (letterboxing).
//
// Nota: l'ordine della initializer list deve rispettare l'ordine di
// dichiarazione dei membri in Game.h, altrimenti g++ emette -Wreorder.
// Ordine dichiarazione in Game.h: window, maze, player, player2, ui, audio,
// numPlayers, enemies, boss, ..., config, state, gameMode, isRunning,
// currentLevel, menuItemIndex, musicEnabled, lightningTimer, configJoyStep.
// Qui inizializziamo solo i membri non di default; gli altri (vettori, maze,
// player) sono costruiti di default.
// ---------------------------------------------------------------------------
Game::Game() : window(sf::VideoMode::getDesktopMode(), "Arcade Maze Fantasy", sf::Style::Fullscreen), numPlayers(1), boss(nullptr), miniBoss(nullptr), miniBossSpawned(false), state(STATE_MENU), gameMode(MODE_STORY), isRunning(true), currentLevel(1), menuItemIndex(0), musicEnabled(false), lightningTimer(0), screenFlashTimer(0), configJoyStep(0), continuesLeft(3), continuesTimer(10), continuesTimerMs(0), continuesChoice(true), diedInBoss(false), player1Character(CHAR_HERO_M), player2Character(CHAR_HERO_F), selectPlayerStep(0), wheelIndex(0), wheelRotation(0.f), wheelTargetIndex(0)
#ifdef TEST_MODE_FEATURE
    , testModeEnabled(false), testSkipKeyPressed(false)
#endif
{
    exitDoor.active = false;
    exitDoor.animTimer = 0;
    exitDoor.glowPulse = 0.f;
    magicPortal.active = false;
    magicPortal.phase = 3;
    magicPortal.phaseTimer = 0;
    magicPortal.rotation = 0.f;
    magicPortal.glowPulse = 0.f;
    magicPortal.enemiesToSpawn = 0;
    magicPortal.spawnTimer = 0;
    portalUsed = false;
    initialEnemyCount = 0;
    mine.active = false;
    mine.bouncing = false;
    mine.bounceTimer = 0;
    mine.rotation = 0.f;
    mine.pulse = 0.f;
    mine.inBossRoom = false;
    chalice.active = false;
    chalice.pulse = 0.f;
    chalice.bobOffset = 0.f;
    chaliceUsed = false;
    playerInvincibleTimer = 0;
    player2InvincibleTimer = 0;
    scepter.active = false;
    scepter.triggered = false;
    scepter.lightningsLeft = 0;
    scepter.lightningTimer = 0;
    scepterUsed = false;
    lightnings.clear();
}

// init: imposta framerate, view iniziale e carica la configurazione comandi.
// Inoltre tenta di caricare gli sprite PNG dei nemici e dei boss dalla
// cartella "assets/sprites". Se i file non esistono (primo avvio o asset
// non ancora generati), il gioco resta giocabile con i disegni a primitive.
bool Game::init() {
    window.setFramerateLimit(60);
    sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
    window.setView(view);
    config = loadConfig("config.ini");
    // Carica gli sprite dei nemici e dei boss (bestiary fantasy horror).
    // I file mancanti vengono saltati: il render fara' fallback alle primitive.
    Enemy::loadAllSprites("assets/sprites");
    Boss::loadAllSprites("assets/sprites");
    // Carica gli sprite dei giocatori in base al personaggio selezionato.
    // I personaggi di default sono CHAR_HERO_M (P1) e CHAR_HERO_F (P2),
    // ma l'utente puo' cambiarli dal menu "SELECT PLAYER".
    // Se il file sprite non esiste, resta unloaded e il render fa fallback
    // alle primitive (renderCharacterFallback).
    player.setCharacter(player1Character, 1);
    player2.setCharacter(player2Character, 2);
    // Inizializza XInput (Windows) o SFML (Linux/macOS) joystick
    Joy::init();
    return true;
}

// ---------------------------------------------------------------------------
// startLevel: (ri)avvia un livello di esplorazione.
// Rigenera il labirinto, riposiziona il giocatore all'angolo (1,1), spawn
// 5 nemici in posizioni casuali, pulisce i proiettili e attiva la musica
// del livello corrente.
// ---------------------------------------------------------------------------
void Game::startLevel(int lvl) {
    currentLevel = lvl;
    // Passa il livello a maze.generate() per selezionare la palette
    // cromatica tematica del livello (8 palette che ciclano).
    maze.generate(currentLevel);
    // Se il livello e' 1 (nuova partita), resetta completamente vite/energia/
    // punteggio del giocatore. Altrimenti (livello successivo) mantieni i
    // progressi e resetta solo la posizione.
    if (lvl == 1) {
        player.reset();
        if (numPlayers == 2) player2.reset();
    } else {
        player.resetPosition();
        if (numPlayers == 2) player2.resetPosition();
    }
    if (numPlayers == 2) {
        // Posiziona il secondo giocatore a una cella di distanza dal primo
        player2.setPosition(player.getPixelPos().x + TILE_SIZE,
                             player.getPixelPos().y);
    }
    spawnEnemies();
    enemyProjectiles.clear();
    exitDoor.active = false;
    exitDoor.animTimer = 0;
    magicPortal.active = false;
    magicPortal.phase = 3;
    portalUsed = false;
    initialEnemyCount = (int)enemies.size();
    bloodStains.clear();
    ashPiles.clear();
    fireBursts.clear();  // pulisce anche le esplosioni di fuoco residue
    // Reset del mini-boss (verra' generato al respawn del portale magico)
    if (miniBoss) { delete miniBoss; miniBoss = nullptr; }
    miniBossSpawned = false;
    // Spawna la mina in una cella vuota casuale del labirinto
    mine.active = false;
    mine.bouncing = false;
    mine.bounceTimer = 0;
    mine.rotation = 0.f;
    mine.pulse = 0.f;
    mine.inBossRoom = false;
    chaliceUsed = false;
    chalice.active = false;
    playerInvincibleTimer = 0;
    player2InvincibleTimer = 0;
    scepter.active = false;
    scepter.triggered = false;
    scepter.lightningsLeft = 0;
    scepter.lightningTimer = 0;
    scepterUsed = false;
    lightnings.clear();
    {
        std::vector<Vec2> mineCells;
        for (int c = 1; c < MAZE_COLS - 1; c++) {
            for (int r = 1; r < MAZE_ROWS - 1; r++) {
                if (maze.getCellType(c, r) == CELL_EMPTY) {
                    sf::Vector2f ppos = player.getPixelPos();
                    int pc = (int)(ppos.x / TILE_SIZE);
                    int pr = (int)((ppos.y - UI_HEIGHT) / TILE_SIZE);
                    if (abs(c - pc) + abs(r - pr) >= 5) {
                        mineCells.push_back({c, r});
                    }
                }
            }
        }
        if (!mineCells.empty()) {
            Vec2 chosen = mineCells[rand() % mineCells.size()];
            mine.pos.x = chosen.x * TILE_SIZE + TILE_SIZE / 2.f;
            mine.pos.y = chosen.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            mine.active = true;
        }
    }
    // Spawna il calice d'oro in una cella vuota casuale (diversa dalla mina)
    {
        std::vector<Vec2> chaliceCells;
        for (int c = 1; c < MAZE_COLS - 1; c++) {
            for (int r = 1; r < MAZE_ROWS - 1; r++) {
                if (maze.getCellType(c, r) == CELL_EMPTY) {
                    sf::Vector2f ppos = player.getPixelPos();
                    int pc = (int)(ppos.x / TILE_SIZE);
                    int pr = (int)((ppos.y - UI_HEIGHT) / TILE_SIZE);
                    if (abs(c - pc) + abs(r - pr) >= 5) {
                        // Non troppo vicino alla mina
                        int mc = (int)(mine.pos.x / TILE_SIZE);
                        int mr = (int)((mine.pos.y - UI_HEIGHT) / TILE_SIZE);
                        if (abs(c - mc) + abs(r - mr) >= 4) {
                            chaliceCells.push_back({c, r});
                        }
                    }
                }
            }
        }
        if (!chaliceCells.empty()) {
            Vec2 chosen = chaliceCells[rand() % chaliceCells.size()];
            chalice.pos.x = chosen.x * TILE_SIZE + TILE_SIZE / 2.f;
            chalice.pos.y = chosen.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            chalice.active = true;
            chalice.pulse = 0.f;
            chalice.bobOffset = 0.f;
        }
    }
    // Spawna lo scettro magico in una cella vuota casuale (diverso da mina e calice)
    {
        std::vector<Vec2> scepterCells;
        int mineC = (int)(mine.pos.x / TILE_SIZE);
        int mineR = (int)((mine.pos.y - UI_HEIGHT) / TILE_SIZE);
        int chalC = chalice.active ? (int)(chalice.pos.x / TILE_SIZE) : -1;
        int chalR = chalice.active ? (int)((chalice.pos.y - UI_HEIGHT) / TILE_SIZE) : -1;
        for (int c = 1; c < MAZE_COLS - 1; c++) {
            for (int r = 1; r < MAZE_ROWS - 1; r++) {
                if (maze.getCellType(c, r) == CELL_EMPTY) {
                    if (abs(c - mineC) + abs(r - mineR) >= 4 &&
                        abs(c - chalC) + abs(r - chalR) >= 4) {
                        sf::Vector2f ppos = player.getPixelPos();
                        int pc = (int)(ppos.x / TILE_SIZE);
                        int pr = (int)((ppos.y - UI_HEIGHT) / TILE_SIZE);
                        if (abs(c - pc) + abs(r - pr) >= 5)
                            scepterCells.push_back({c, r});
                    }
                }
            }
        }
        if (!scepterCells.empty()) {
            Vec2 chosen = scepterCells[rand() % scepterCells.size()];
            scepter.pos.x = chosen.x * TILE_SIZE + TILE_SIZE / 2.f;
            scepter.pos.y = chosen.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            scepter.active = true;
            scepter.pulse = 0.f;
            scepter.bobOffset = 0.f;
            scepter.triggered = false;
            scepter.lightningsLeft = 0;
            scepter.lightningTimer = 0;
        }
    }
    state = STATE_PLAYING;
    if (musicEnabled) audio.playLevelMusic(currentLevel, false);
}

// ---------------------------------------------------------------------------
// spawnEnemies: genera 5 nemici in posizioni casuali del labirinto.
//
// Logica:
//   * Il tipo di ogni nemico e' scelto casualmente fra i 15 disponibili.
//   * La posizione e' random finche' non si trova una cella non muro e non
//     troppo vicina al giocatore (zona (c<5, r<5) esclusa per dare respiro
//     iniziale al giocatore).
//   * I nemici precedenti vengono sostituiti (clear).
// ---------------------------------------------------------------------------
void Game::spawnEnemies() {
    enemies.clear();
    // Tutti i 28 tipi disponibili (15 originali + 13 nuovi del bestiary).
    // ENEMY_TYPE_COUNT e' definito in Enemy.h.
    EnemyType allTypes[] = {
        // 15 tipi originali
        ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT,
        ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
        ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
        ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST,
        // 13 nuovi tipi dal bestiary fantasy horror
        ENEMY_MIMIC, ENEMY_WOLF, ENEMY_WITCH, ENEMY_BONE_GOLEM,
        ENEMY_ASH_SERPENT, ENEMY_DAMNED_KNIGHT, ENEMY_MAD_WIZARD,
        ENEMY_DEMONIC_CROW, ENEMY_TENTACLE, ENEMY_GARGOYLE,
        ENEMY_WELL_SPIRIT, ENEMY_CURSED_BOAR, ENEMY_PREDATOR_FUNGUS
    };

    for (int i = 0; i < 5; ++i) {
        EnemyType t = allTypes[rand() % ENEMY_TYPE_COUNT];
        int c, r;
        // Cerca posizione valida (non muro e non nell'angolo iniziale 5x5)
        do {
            c = 1 + rand() % (MAZE_COLS - 2);
            r = 1 + rand() % (MAZE_ROWS - 2);
        } while (maze.isWall(c, r) || (c < 5 && r < 5));
        enemies.push_back(Enemy(t, c, r));
    }
}

// ---------------------------------------------------------------------------
// spawnEnemyFromPortal: spawna un nemico dal portale magico. Prende il
// primo nemico morto dalla lista deadEnemyIndices, lo respawn vicino al
// portale in una cella vuota, e riproduce il suono di uscita.
// ---------------------------------------------------------------------------
void Game::spawnEnemyFromPortal() {
    if (magicPortal.enemiesToSpawn <= 0 || magicPortal.deadEnemyIndices.empty()) {
        magicPortal.enemiesToSpawn = 0;
        return;
    }
    // Prendi il primo nemico morto dalla lista
    int idx = magicPortal.deadEnemyIndices.back();
    magicPortal.deadEnemyIndices.pop_back();

    if (idx < 0 || idx >= (int)enemies.size()) {
        magicPortal.enemiesToSpawn--;
        return;
    }

    EnemyType et = enemies[idx].getType();
    int pc = (int)(magicPortal.pos.x / TILE_SIZE);
    int pr = (int)((magicPortal.pos.y - UI_HEIGHT) / TILE_SIZE);

    // Cerca una cella vuota in raggio crescente dal portale
    bool placed = false;
    for (int radius = 1; radius <= 5 && !placed; radius++) {
        for (int dc = -radius; dc <= radius && !placed; dc++) {
            for (int dr = -radius; dr <= radius && !placed; dr++) {
                int nc = pc + dc, nr = pr + dr;
                if (nc > 0 && nc < MAZE_COLS - 1 && nr > 0 && nr < MAZE_ROWS - 1
                    && !maze.isWall(nc, nr)
                    && maze.getCellType(nc, nr) == CELL_EMPTY) {
                    enemies[idx] = Enemy(et, nc, nr);
                    placed = true;
                    // Effetto particellare di uscita dal portale
                    for (int i = 0; i < 10; i++) {
                        particles.push_back({magicPortal.pos,
                            {(float)(rand()%6-3), (float)(rand()%6-3)},
                            sf::Color(200, 100, 255), 25, 25});
                    }
                }
            }
        }
    }
    magicPortal.enemiesToSpawn--;
}
// Crea il boss (allocato dinamicamente: il precedente viene deallocato),
// posiziona il giocatore in fondo alla stanza, pulisce proiettili e fa
// spawn di 3 armi casuali a terra (cosi' il giocatore ha munizioni fresche).
//
// Se `keepBossState` e' true (chiamato dopo morte del player nel boss con
// continue credit), NON ricrea il boss: mantiene HP, posizione, animazione e
// tipo di attacco esattamente come erano al momento della morte del player.
// In questo modo il player non puo' "farmare" il boss ricominciando da capo
// con la barra energia piena ad ogni continue. Vengono comunque ripuliti i
// proiettili in volo e re-spawnate le armi a terra, cosi' il player ha
// munizioni fresche per continuare la fight.
// ---------------------------------------------------------------------------
void Game::startBossFight(bool keepBossState) {
    state = STATE_BOSS;
    if (keepBossState && boss != nullptr && !boss->isDead()) {
        // --- CONTINUE CREDIT: mantieni lo stato del boss fight ---
        // Il boss resta invariato (HP, posizione, animazione, tipo attacco).
        // Inoltre NON vengono rigenerati:
        //   * mine (se gia' usata o in rimbalzo, resta cosi')
        //   * scettro (se gia' raccolto/triggered, resta cosi')
        //   * armi a terra (bossRoomWeapons resta invariato)
        //   * scarpe alate (speedBoots/speedBoots2 restano come sono)
        // Vengono solo riposizionati i giocatori e puliti i proiettili in
        // volo. Questo rispetta la regola: "lo stato del gioco deve rimanere
        // identico, solo la vita del giocatore viene ricaricata".
        player.resetPosition();
        player.setPosition(WINDOW_WIDTH / 2.0f, WINDOW_HEIGHT - 100.0f);
        if (numPlayers == 2) {
            player2.resetPosition();
            player2.setPosition(WINDOW_WIDTH / 2.0f + 120.0f, WINDOW_HEIGHT - 100.0f);
        }
        bossProjectiles.clear();
        enemyProjectiles.clear();
        // NESSUNA rigenerazione di mine/scettro/armi/scarpe: lo stato resta.
        if (musicEnabled) audio.playLevelMusic(currentLevel, true);
        return;
    }
    // --- NUOVA BOSS FIGHT (keepBossState=false) ---
    // Creazione boss nuova o reset completo.
    if (boss) delete boss;
    boss = new Boss(currentLevel, WINDOW_WIDTH, WINDOW_HEIGHT);
    player.resetPosition();
    // Posiziona il giocatore in fondo alla stanza (centro orizzontale)
    player.setPosition(WINDOW_WIDTH / 2.0f, WINDOW_HEIGHT - 100.0f);
    if (numPlayers == 2) {
        player2.resetPosition();
        // Posiziona player2 a 120 px dal player (abbastanza da non scattare
        // subito il friendly fire, soglia 800 ~= 28 px).
        player2.setPosition(WINDOW_WIDTH / 2.0f + 120.0f, WINDOW_HEIGHT - 100.0f);
    }
    bossProjectiles.clear();
    enemyProjectiles.clear();
    spawnBossRoomWeapons();
    // --- Spawn scarpe alate ---
    // In 1P: 1 paio (per player1). In 2P: 2 paia (uno per player1, uno per
    // player2), posizionati in punti diversi della stanza. owner indica
    // quale player puo' raccogliere le scarpe (0=libera/1P, 1=p1, 2=p2).
    speedBoots.active = true;
    speedBoots.pos = sf::Vector2f(150.0f, 200.0f);
    speedBoots.bobOffset = 0.f;
    speedBoots.owner = 0;  // 1P: libera
    if (numPlayers == 2) {
        // 2P: una paia per player1 (owner=1) e una per player2 (owner=2)
        speedBoots.owner = 1;
        speedBoots2.active = true;
        speedBoots2.pos = sf::Vector2f(WINDOW_WIDTH - 150.0f, 200.0f);
        speedBoots2.bobOffset = 0.f;
        speedBoots2.owner = 2;
    } else {
        speedBoots2.active = false;
        speedBoots2.owner = 0;
    }
    // --- Spawn mina nella stanza del boss ---
    // IMPORTANTE: se la mina era attiva nel labirinto ma NON e' stata
    // raccolta (mine.active=true, mine.inBossRoom=false), la rimuoviamo
    // dal labirinto e ne spawniamo una NUOVA nella stanza del boss.
    // Questo previene il bug in cui la mina del labirinto rimaneva
    // "congelata" (non raccoglibile) nella stanza del boss perche'
    // mine.inBossRoom era false e il blocco STATE_BOSS la ignorava.
    if (mine.active && !mine.inBossRoom) {
        // Mina del labirinto non raccolta: rimuovila
        mine.active = false;
        mine.bouncing = false;
    }
    if (!mine.active) {
        // Spawna mina nella stanza del boss (posizione casuale, non al centro)
        mine.pos.x = 200.f + (rand() % 600);
        mine.pos.y = UI_HEIGHT + 150.f + (rand() % 400);
        mine.active = true;
        mine.bouncing = false;
        mine.bounceTimer = 0;
        mine.rotation = 0.f;
        mine.pulse = 0.f;
        mine.inBossRoom = true;
    }
    // Se la mina era gia' stata attivata nel labirinto ed e' in fase di
    // rimbalzo (mine.bouncing=true), la lasciamo continuare ma la
    // marchiamo come inBossRoom perche' ora e' nella stanza del boss.
    if (mine.bouncing) {
        mine.inBossRoom = true;
    }
    // Il calice NON appare nella stanza del boss
    chalice.active = false;
    // --- Scettro magico nella stanza del boss ---
    // Lo scettro DEVE apparire nella stanza del boss SEMPRE, anche se e'
    // stato gia' raccolto nel labirinto. Questo dava al giocatore 2 occasioni
    // di usare i fulmini per livello (una nel labirinto, una nel boss).
    //
    // Logica:
    //   * Se lo scettro NON e' stato raccolto nel labirinto (scepter.active
    //     e' ancora true, posizione valida): lo lasciamo dove e' (verra'
    //     visualizzato e raccoglibile nella stanza del boss).
    //   * Se lo scettro e' stato raccolto nel labirinto (scepter.triggered
    //     e' true, i fulmini sono gia' partiti o in corso): RESET completo
    //     dello stato e spawn di un NUOVO scettro in posizione casuale nella
    //     stanza del boss. I fulmini residui del labirinto continuano fino
    //     a esaurirsi (non vengono cancellati), ma il nuovo scettro dara'
    //     altri 5 fulmini quando raccolto.
    //   * Se lo scettro non e' ancora apparso (nessuna delle due): spawn
    //     normale in posizione casuale.
    if (scepter.active && !scepter.triggered) {
        // Scettro ancora a terra nel labirinto: riposizionalo casualmente
        // nella stanza del boss (perche' la posizione del labirinto non e'
        // valida nella stanza del boss).
        scepter.pos.x = 200.f + (rand() % 600);
        scepter.pos.y = UI_HEIGHT + 150.f + (rand() % 400);
        // Mantieni active=true, pulse, bobOffset. Reset triggered/lightnings.
        scepter.triggered = false;
        scepter.lightningsLeft = 0;
        scepter.lightningTimer = 0;
    } else {
        // Scettro gia' raccolto nel labirinto (triggered=true) OPPURE mai
        // apparso: spawn di un NUOVO scettro nella stanza del boss.
        // Reset completo dello stato per permettere il pickup e 5 nuovi
        // fulmini anche se ce n'erano già altri in corso.
        scepter.pos.x = 200.f + (rand() % 600);
        scepter.pos.y = UI_HEIGHT + 150.f + (rand() % 400);
        scepter.active = true;
        scepter.pulse = 0.f;
        scepter.bobOffset = 0.f;
        scepter.triggered = false;
        scepter.lightningsLeft = 0;
        scepter.lightningTimer = 0;
        // NOTA: NON resettiamo scepterUsed qui, perche' serve a tracciare
        // se lo scettro e' stato usato ALMENO una volta nel livello corrente
        // (per la minimappa e altre logiche). Verra' resettato in startLevel.
    }
    if (musicEnabled) audio.playLevelMusic(currentLevel, true);
}

// ---------------------------------------------------------------------------
// spawnBossRoomWeapons: posiziona 3 armi casuali a terra nella stanza del
// boss. Le armi sono distribuite orizzontalmente (a 300 px di distanza).
// Ogni arma ha 5 colpi (bilanciamento: abbastanza per danneggiare il boss
// ma non per ucciderlo con una sola arma).
// ---------------------------------------------------------------------------
void Game::spawnBossRoomWeapons() {
    bossRoomWeapons.clear();
    for(int i=0; i<3; i++) {
        Weapon w = Weapon::generateRandom();
        w.ammo = 5;
        bossRoomWeapons.push_back({w, sf::Vector2f(200.0f + i * 300.0f, 200.0f)});
    }
}

// Mappa WeaponType -> SoundType: serve per riprodurre il suono corretto
// quando il giocatore spara. Default: SOUND_PISTOL (per sicurezza).
SoundType Game::getWeaponSound(WeaponType wt) {
    switch(wt) {
        case WPN_PISTOL:  return SOUND_PISTOL;
        case WPN_SHOTGUN: return SOUND_SHOTGUN;
        case WPN_ROCKET:  return SOUND_ROCKET;
        case WPN_LASER:   return SOUND_LASER;
    }
    return SOUND_PISTOL;
}

// ---------------------------------------------------------------------------
// handleEvents: processa tutti gli eventi SFML in coda. Include:
//   * Chiusura finestra / ridimensionamento (con letterboxing per aspect)
//   * Tastiera: ESC (uscire/tornare al menu'), frecce (menu'), Return (conferma)
//   * Joystick: pulsanti per navigazione menu' e configurazione comandi
//
// Logica di Resize: viene calcolato il viewport SFML per mantenere
// l'aspect ratio 1:1 della finestra logica (1024x1024) centrando l'immagine
// con bande nere (letterbox) se lo schermo non e' quadrato.
// ---------------------------------------------------------------------------
void Game::handleEvents() {
    sf::Event event;
    while (window.pollEvent(event)) {
        if (event.type == sf::Event::Closed) isRunning = false;
        else if (event.type == sf::Event::Resized) {
            // Calcolo del viewport con letterboxing
            float windowRatio = (float)event.size.width / (float)event.size.height;
            float viewRatio = (float)WINDOW_WIDTH / (float)WINDOW_HEIGHT;
            sf::FloatRect viewport(0.f, 0.f, 1.f, 1.f);
            if (windowRatio > viewRatio) {
                // Finestra piu' larga del dovuto: bande laterali
                viewport.width = viewRatio / windowRatio;
                viewport.left = (1.f - viewport.width) / 2.f;
            } else {
                // Finestra piu' alta del dovuto: bande sopra/sotto
                viewport.height = windowRatio / viewRatio;
                viewport.top = (1.f - viewport.height) / 2.f;
            }
            sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
            view.setViewport(viewport);
            window.setView(view);
        }
        else if (event.type == sf::Event::KeyPressed) {
            int key = event.key.code;
            // ESC: comportamento dipendente dallo stato
            if (key == sf::Keyboard::Escape) {
                if (state == STATE_CONFIG_JOY || state == STATE_CONFIG_JOY_2) state = STATE_MENU;
                else if (state == STATE_MENU) isRunning = false;
                else {
                    // Torna al menu': ferma la musica di gioco e (se l'opzione
                    // musica e' attiva) riprende la traccia DEDICATA del menu'
                    // (corale fantasy, diversa dalle musiche di gioco).
                    state = STATE_MENU;
                    currentLevel = 1;
                    audio.stopEpicMusic();  // ferma eventuali jingle epici
                    if (musicEnabled) audio.playMenuMusic();
                    else audio.stopMusic();
                }
            }

            // Navigazione menu'
            if (state == STATE_MENU) {
                // Su/Giu: cambio voce selezionata (7 voci totali, wrap con +7 %7)
                if (key == sf::Keyboard::Up) { menuItemIndex = (menuItemIndex - 1 + 7) % 7; audio.playSound(SOUND_MENU_SELECT); }
                else if (key == sf::Keyboard::Down) { menuItemIndex = (menuItemIndex + 1) % 7; audio.playSound(SOUND_MENU_SELECT); }
                // Sinistra/Destra: modifica dell'opzione selezionata
                else if (key == sf::Keyboard::Left) {
                    if (menuItemIndex == 0) numPlayers = (numPlayers == 1) ? 2 : 1;
                    if (menuItemIndex == 1) gameMode = (gameMode == MODE_STORY) ? MODE_INFINITE : MODE_STORY;
                    if (menuItemIndex == 2) {
                        musicEnabled = !musicEnabled;
                        // Nel menu' principale: usa la traccia DEDICATA del menu'
                        // (corale fantasy drammatica), DISTINTA dalle musiche
                        // di gioco. Suona sul canale principale in loop.
                        if (musicEnabled) audio.playMenuMusic();
                        else audio.stopMusic();
                    }
#ifdef TEST_MODE_FEATURE
                    if (menuItemIndex == 4) testModeEnabled = !testModeEnabled;
#endif
                }
                else if (key == sf::Keyboard::Right) {
                    if (menuItemIndex == 0) numPlayers = (numPlayers == 1) ? 2 : 1;
                    if (menuItemIndex == 1) gameMode = (gameMode == MODE_STORY) ? MODE_INFINITE : MODE_STORY;
                    if (menuItemIndex == 2) {
                        musicEnabled = !musicEnabled;
                        if (musicEnabled) audio.playMenuMusic();
                        else audio.stopMusic();
                    }
#ifdef TEST_MODE_FEATURE
                    if (menuItemIndex == 4) testModeEnabled = !testModeEnabled;
#endif
                }
                // Return: conferma (3 = select player, 5 = config joystick, 6 = avvia partita)
                else if (key == sf::Keyboard::Return) {
                    audio.playSound(SOUND_MENU_CONFIRM);
                    if (menuItemIndex == 3) {
                        // SELECT PLAYER: apre la schermata di selezione personaggio
                        state = STATE_SELECT_PLAYER;
                        selectPlayerStep = 0;  // P1 sceglie per primo
                        wheelIndex = (int)player1Character;
                        wheelTargetIndex = wheelIndex;
                        wheelRotation = 0.f;
                    }
                    else if (menuItemIndex == 5) { state = STATE_CONFIG_JOY; configJoyStep = 0; }
                    else if (menuItemIndex == 6) {
                        // Avvia il livello 1. La finestra resta in fullscreen
                        // alla risoluzione nativa gia' impostata nel costruttore.
                        window.setFramerateLimit(60);
                        sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
                        window.setView(view);
                        currentLevel = 1;
                        // Applica i personaggi scelti ai player prima di iniziare
                        player.setCharacter(player1Character, 1);
                        if (numPlayers == 2) player2.setCharacter(player2Character, 2);
                        startLevel(1);
                    }
                }
            } else if (state == STATE_SELECT_PLAYER) {
                // --- Schermata selezione personaggio ---
                // Left/Right (o joystick): ruota la ruota dei personaggi
                // Enter: conferma il personaggio corrente
                if (key == sf::Keyboard::Left) {
                    wheelTargetIndex = (wheelTargetIndex - 1 + CHARACTER_TYPE_COUNT) % CHARACTER_TYPE_COUNT;
                    audio.playSound(SOUND_MENU_SELECT);
                }
                else if (key == sf::Keyboard::Right) {
                    wheelTargetIndex = (wheelTargetIndex + 1) % CHARACTER_TYPE_COUNT;
                    audio.playSound(SOUND_MENU_SELECT);
                }
                else if (key == sf::Keyboard::Return) {
                    audio.playSound(SOUND_MENU_CONFIRM);
                    if (selectPlayerStep == 0) {
                        // P1 ha scelto
                        player1Character = (CharacterType)wheelIndex;
                        if (numPlayers == 2) {
                            // In 2P: P2 sceglie ora
                            selectPlayerStep = 1;
                            wheelIndex = (int)player2Character;
                            wheelTargetIndex = wheelIndex;
                        } else {
                            // In 1P: torna al menu
                            state = STATE_MENU;
                        }
                    } else {
                        // P2 ha scelto
                        player2Character = (CharacterType)wheelIndex;
                        state = STATE_MENU;
                    }
                }
                else if (key == sf::Keyboard::Escape) {
                    // ESC: torna al menu senza confermare
                    state = STATE_MENU;
                }
            } else if (state == STATE_CONTINUES) {
                // Schermata continues: Left/Right scegli Yes/No, Enter conferma
                if (key == sf::Keyboard::Left || key == sf::Keyboard::Right) {
                    continuesChoice = !continuesChoice;
                    audio.playSound(SOUND_MENU_SELECT);
                }
                else if (key == sf::Keyboard::Return) {
                    audio.playSound(SOUND_MENU_CONFIRM);
                    if (continuesChoice) {
                        // YES: continua con 3 vite, consuma 1 credito
                        // Se morto nel boss, riparte dal boss; altrimenti dal livello
                        continuesLeft--;
                        player.reset();
                        if (numPlayers == 2) player2.reset();
                        if (diedInBoss) startBossFight(true);
                        else startLevel(currentLevel);
                    } else {
                        // NO: game over
                        state = STATE_LOSE;
                    }
                }
                else if (key == sf::Keyboard::Escape) {
                    state = STATE_LOSE;
                }
            } else if (state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) {
                // Schermate finali: Enter torna al menu'
                if (key == sf::Keyboard::Return) {
                    state = STATE_MENU;
                    currentLevel = 1;
                    continuesLeft = 3;  // reset crediti per nuova partita
                    // Ferma eventuali musiche/jingle e riprende la traccia
                    // DEDICATA del menu' se l'opzione musica e' attiva.
                    audio.stopEpicMusic();
                    if (musicEnabled) audio.playMenuMusic();
                    else audio.stopMusic();
                }
            }
        }
        // FIX: joystick buttons gestiti in update() con polling Joy::
        // (non qui con eventi SFML, perche' Joy:: usa XInput/DirectInput
        // nativo che ha numerazione pulsanti diversa da SFML)
        else if (event.type == sf::Event::JoystickButtonPressed) {
            // Tutti gli stati joystick sono migrati a polling Joy:: in update()
        }
    }
}

// ---------------------------------------------------------------------------
// update: aggiorna la logica di gioco in base allo stato corrente.
//
// Stati gestiti:
//   * STATE_MENU: navigazione menu con joystick (asse Y), fulmini casuali
//   * STATE_PLAYING/STATE_BOSS: input del giocatore, aggiornamento entita',
//     collisioni, suoni, transizioni di stato
//   * STATE_WIN_STORY: spawn e aggiornamento dei fuochi d'artificio
//
// Nota: gli input di movimento/sparo sono gestiti qui (non in handleEvents)
// perche' sono input "continui" (isKeyPressed) che vanno controllati ad
// ogni frame, non eventi discreti.
// ---------------------------------------------------------------------------
void Game::update() {
    // FIX CRITICO: Joy::update() deve essere chiamato qui.
    // Su Windows, alcuni gamepad (specialmente XInput) richiedono che
    // update() sia chiamato IL PIU' TARDI POSSIBILE prima della lettura
    // degli assi. Chiamandolo qui (dopo handleEvents) dovrebbe funzionare.
    Joy::update();

    // --- Stato MENU: navigazione joystick + fulmini casuali ---
    if (state == STATE_MENU) {
        unsigned joystickId = 0;  // FIX: usa joystick ID diretto (non cache)
        if (joystickId < sf::Joystick::Count) {
            float y = Joy::getAxisPosition(joystickId, (sf::Joystick::Axis)config.joy_axis_y);
            // joyMoved e' static: serve da "debounce" per evitare che un
            // solo movimento dell'analogico faccia scorrere tutte le voci.
            static bool joyMoved = false;
            if (fabs(y) > 50 && !joyMoved) {
                joyMoved = true;
                if (y < 0) { menuItemIndex = (menuItemIndex - 1 + 7) % 7; audio.playSound(SOUND_MENU_SELECT); }
                else { menuItemIndex = (menuItemIndex + 1) % 7; audio.playSound(SOUND_MENU_SELECT); }
            } else if (fabs(y) < 20) joyMoved = false;  // isteresi per il ritorno
        }

        // Fulmine casuale: ~5/600 di probabilita' per frame, durata 10 frame
        if (rand() % 600 < 5) lightningTimer = 10;
        if (lightningTimer > 0) lightningTimer--;
        // Polling pulsante jump = conferma menu (con debounce)
        if (Joy::isConnected(0) && config.joy_jump >= 0) {
            static bool menuJoyBtn = false;
            bool pressed = Joy::isButtonPressed(0, (unsigned)config.joy_jump);
            if (pressed && !menuJoyBtn) {
                menuJoyBtn = true;
                audio.playSound(SOUND_MENU_CONFIRM);
                if (menuItemIndex == 3) {
                    state = STATE_SELECT_PLAYER;
                    selectPlayerStep = 0;
                    wheelIndex = (int)player1Character;
                    wheelTargetIndex = wheelIndex;
                    wheelRotation = 0.f;
                }
                else if (menuItemIndex == 5) { state = STATE_CONFIG_JOY; configJoyStep = 0; }
                else if (menuItemIndex == 6) {
                    window.setFramerateLimit(60);
                    sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
                    window.setView(view);
                    currentLevel = 1;
                    player.setCharacter(player1Character, 1);
                    if (numPlayers == 2) player2.setCharacter(player2Character, 2);
                    startLevel(1);
                }
            } else if (!pressed) menuJoyBtn = false;
        }
    }
    // --- Stato SELECT_PLAYER: navigazione ruota personaggi con joystick ---
    else if (state == STATE_SELECT_PLAYER) {
        // FIX: usa il joystick corretto in base allo step (P1=0, P2=1 o fallback 0)
        // e se Joy:: non trova il joystick 1, prova SFML direttamente
        unsigned int wheelJoyId = (selectPlayerStep == 0) ? 0 : 1;
        bool wheelJoyConnected = Joy::isConnected(wheelJoyId);
        if (!wheelJoyConnected && wheelJoyId == 1) {
            sf::Joystick::update();
            wheelJoyConnected = sf::Joystick::isConnected(1);
            if (!wheelJoyConnected) {
                wheelJoyId = 0;  // gamepad condiviso
                wheelJoyConnected = Joy::isConnected(0);
            }
        }
        if (wheelJoyConnected) {
            int axisX = (selectPlayerStep == 0) ? config.joy_axis_x : config.joy2_axis_x;
            float x = Joy::getAxisPosition(wheelJoyId, (sf::Joystick::Axis)axisX);
            // Se Joy:: non ha funzionato, prova SFML direttamente
            if (wheelJoyId == 1 && fabs(x) < 0.1f) {
                x = sf::Joystick::getAxisPosition(wheelJoyId, (sf::Joystick::Axis)axisX);
            }
            static bool joyMovedWheel = false;
            if (fabs(x) > 50 && !joyMovedWheel) {
                joyMovedWheel = true;
                if (x < 0) {
                    wheelTargetIndex = (wheelTargetIndex - 1 + CHARACTER_TYPE_COUNT) % CHARACTER_TYPE_COUNT;
                } else {
                    wheelTargetIndex = (wheelTargetIndex + 1) % CHARACTER_TYPE_COUNT;
                }
                audio.playSound(SOUND_MENU_SELECT);
            } else if (fabs(x) < 20) joyMovedWheel = false;
        }
        // Animazione ruota: interpolazione smooth verso wheelTargetIndex
        if (wheelIndex != wheelTargetIndex) {
            wheelRotation += 0.15f;  // velocita' rotazione
            if (wheelRotation >= 1.f) {
                wheelRotation = 0.f;
                // Avanza di 1 verso il target (gestendo wrap-around)
                int diff = wheelTargetIndex - wheelIndex;
                if (diff > CHARACTER_TYPE_COUNT / 2) diff -= CHARACTER_TYPE_COUNT;
                else if (diff < -CHARACTER_TYPE_COUNT / 2) diff += CHARACTER_TYPE_COUNT;
                if (diff > 0) wheelIndex = (wheelIndex + 1) % CHARACTER_TYPE_COUNT;
                else if (diff < 0) wheelIndex = (wheelIndex - 1 + CHARACTER_TYPE_COUNT) % CHARACTER_TYPE_COUNT;
            }
        }
        // Polling pulsante jump = conferma personaggio (con debounce)
        // Usa lo stesso wheelJoyId della navigazione ruota
        if (wheelJoyConnected) {
            static bool selJoyBtn = false;
            int jumpBtn = (selectPlayerStep == 0) ? config.joy_jump : config.joy2_jump;
            if (jumpBtn < 0) jumpBtn = 0;
            bool pressed = Joy::isButtonPressed(wheelJoyId, (unsigned)jumpBtn);
            // Se Joy:: non trova il pulsante, prova SFML
            if (!pressed && wheelJoyId == 1) {
                pressed = sf::Joystick::isButtonPressed(wheelJoyId, (unsigned)jumpBtn);
            }
            if (pressed && !selJoyBtn) {
                selJoyBtn = true;
                audio.playSound(SOUND_MENU_CONFIRM);
                if (selectPlayerStep == 0) {
                    player1Character = (CharacterType)wheelIndex;
                    if (numPlayers == 2) {
                        selectPlayerStep = 1;
                        wheelIndex = (int)player2Character;
                        wheelTargetIndex = wheelIndex;
                    } else {
                        state = STATE_MENU;
                    }
                } else {
                    player2Character = (CharacterType)wheelIndex;
                    state = STATE_MENU;
                }
            } else if (!pressed) selJoyBtn = false;
        }
    }

    // --- STATO CONFIG_JOY: configurazione joystick player 1 via polling ---
    // Usa Joy::isButtonPressed (XInput/DirectInput nativo) invece di eventi
    // SFML, perche' la numerazione dei pulsanti e' diversa tra SFML (DirectInput)
    // e Joy:: (XInput).
    //
    // FIX: dopo aver catturato un pulsante (step 0 o 1), aspetta che TUTTI
    // i pulsanti siano rilasciati prima di accettare il prossimo input.
    // Questo evita che lo stesso pulsante ancora premuto venga registrato
    // automaticamente per lo step successivo.
    if (state == STATE_CONFIG_JOY && Joy::isConnected(0)) {
        static bool waitForRelease = false;  // true = aspetta che tutti i pulsanti siano rilasciati

        // Se stiamo aspettando il rilascio, controlla se tutti i pulsanti sono su
        if (waitForRelease) {
            unsigned int maxBtns = Joy::getButtonCount(0);
            if (maxBtns > 128) maxBtns = 128;
            bool anyPressed = false;
            for (unsigned int b = 0; b < maxBtns; b++) {
                if (Joy::isButtonPressed(0, b)) { anyPressed = true; break; }
            }
            if (!anyPressed) waitForRelease = false;  // tutti rilasciati, pronto per prossimo input
            return;  // salta il resto di update() finche' non sono rilasciati
        }

        // Scansiona tutti i pulsanti
        unsigned int maxButtons = Joy::getButtonCount(0);
        if (maxButtons > 128) maxButtons = 128;
        for (unsigned int b = 0; b < maxButtons; b++) {
            if (Joy::isButtonPressed(0, b)) {
                if (configJoyStep == 0) {
                    config.joy_jump = (int)b;
                    configJoyStep = 1;
                    audio.playSound(SOUND_MENU_CONFIRM);
                    waitForRelease = true;  // aspetta rilascio prima di step 1
                } else if (configJoyStep == 1) {
                    config.joy_shoot = (int)b;
                    if (numPlayers == 2) { state = STATE_CONFIG_JOY_2; configJoyStep = 0; }
                    else state = STATE_MENU;
                    audio.playSound(SOUND_MENU_CONFIRM);
                    waitForRelease = true;
                }
                break;
            }
        }
    }

    // --- STATO CONFIG_JOY_2: configurazione joystick player 2 via polling ---
    if (state == STATE_CONFIG_JOY_2 && Joy::isConnected(1)) {
        static bool waitForRelease2 = false;

        if (waitForRelease2) {
            unsigned int maxBtns = Joy::getButtonCount(1);
            if (maxBtns > 128) maxBtns = 128;
            bool anyPressed = false;
            for (unsigned int b = 0; b < maxBtns; b++) {
                if (Joy::isButtonPressed(1, b)) { anyPressed = true; break; }
            }
            if (!anyPressed) waitForRelease2 = false;
            return;
        }

        unsigned int maxButtons = Joy::getButtonCount(1);
        if (maxButtons > 128) maxButtons = 128;
        for (unsigned int b = 0; b < maxButtons; b++) {
            if (Joy::isButtonPressed(1, b)) {
                if (configJoyStep == 0) {
                    config.joy2_jump = (int)b;
                    configJoyStep = 1;
                    audio.playSound(SOUND_MENU_CONFIRM);
                    waitForRelease2 = true;
                } else if (configJoyStep == 1) {
                    config.joy2_shoot = (int)b;
                    state = STATE_MENU;
                    audio.playSound(SOUND_MENU_CONFIRM);
                    waitForRelease2 = true;
                }
                break;
            }
        }
    }

    // --- Polling joystick per stati menu/continues/win/lose ---
    // CONTINUES: pulsante jump = conferma, pulsante shoot = toggle
    if (state == STATE_CONTINUES && Joy::isConnected(0) && config.joy_jump >= 0) {
        static bool contJoyBtn = false;
        static bool contShootBtn = false;
        bool jumpPressed = Joy::isButtonPressed(0, (unsigned)config.joy_jump);
        bool shootPressed = (config.joy_shoot >= 0) ? Joy::isButtonPressed(0, (unsigned)config.joy_shoot) : false;
        if (jumpPressed && !contJoyBtn) {
            contJoyBtn = true;
            audio.playSound(SOUND_MENU_CONFIRM);
            if (continuesChoice) {
                continuesLeft--;
                player.reset();
                if (numPlayers == 2) player2.reset();
                if (diedInBoss) startBossFight(true);
                else startLevel(currentLevel);
            } else {
                state = STATE_LOSE;
            }
        } else if (!jumpPressed) contJoyBtn = false;
        if (shootPressed && !contShootBtn) {
            contShootBtn = true;
            continuesChoice = !continuesChoice;
            audio.playSound(SOUND_MENU_SELECT);
        } else if (!shootPressed) contShootBtn = false;
    }
    // WIN/LOSE: pulsante jump = torna al menu
    if ((state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) &&
        Joy::isConnected(0) && config.joy_jump >= 0) {
        static bool winJoyBtn = false;
        bool pressed = Joy::isButtonPressed(0, (unsigned)config.joy_jump);
        if (pressed && !winJoyBtn) {
            winJoyBtn = true;
            state = STATE_MENU;
            currentLevel = 1;
            continuesLeft = 3;
        } else if (!pressed) winJoyBtn = false;
    }
    if (state == STATE_PLAYING || state == STATE_BOSS) {
        // Tastiera: direzioni (mutuamente esclusive con else-if)
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_up))    { player.setDirection(0, -1); }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_down))  { player.setDirection(0, 1);  }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_left))  { player.setDirection(-1, 0); }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_right)) { player.setDirection(1, 0);  }

        // Joystick: prevale sulla tastiera se fuori dalla deadzone (30%)
        if (Joy::isConnected(0)) {
            float x = Joy::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_x);
            float y = Joy::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_y);
            if (fabs(x) > 30 || fabs(y) > 30) {
                // Determina l'asse dominante per evitare movimenti diagonali
                // non intenzionali (utile per labirinto "snap-to-grid").
                if (fabs(x) > fabs(y)) {
                    if (x > 30) { player.setDirection(1, 0); }
                    else if (x < -30) { player.setDirection(-1, 0); }
                } else {
                    if (y > 30) { player.setDirection(0, 1); }
                    else if (y < -30) { player.setDirection(0, -1); }
                }
            }
            // Sparo joystick: cooldown 150 ms (~9 frame)
            // Non sparare se il pulsante non e' stato configurato (-1)
            if (config.joy_shoot >= 0 && Joy::isButtonPressed(0, (unsigned)config.joy_shoot)) {
                if (player.getShootCooldown() == 0) {
                    int ammoBefore = player.getCurrentWeapon().ammo;
                    player.shoot();
                    // Suono solo se effettivamente sparato (munizioni calate)
                    if (player.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                    player.setShootCooldown(150);
                }
            }
            if (config.joy_jump >= 0 && Joy::isButtonPressed(0, (unsigned)config.joy_jump)) {
                bool wasJumping = player.isJumping();
                player.activateJump();
                if (!wasJumping && player.isJumping()) audio.playSound(SOUND_JUMP);
            }
        }
        // Sparo tastiera (stessa logica del joystick)
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_shoot)) {
            if (player.getShootCooldown() == 0) {
                int ammoBefore = player.getCurrentWeapon().ammo;
                player.shoot();
                if (player.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                player.setShootCooldown(150);
            }
        }
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_jump)) {
            bool wasJumping = player.isJumping();
            player.activateJump();
            if (!wasJumping && player.isJumping()) audio.playSound(SOUND_JUMP);
        }
    }

    // --- Input secondo giocatore (solo in modalita' 2 giocatori) ---
    // Player 2 puo' usare sia il joystick 1 sia una tastiera secondaria
    // (default WASD + Q salto + E sparo). I due input coesistono.
    if ((state == STATE_PLAYING || state == STATE_BOSS) && numPlayers == 2) {
        // Tastiera secondaria (default WASD + Q/E)
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key2_up))    { player2.setDirection(0, -1); }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key2_down))  { player2.setDirection(0, 1);  }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key2_left))  { player2.setDirection(-1, 0); }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key2_right)) { player2.setDirection(1, 0);  }

        // Joystick P2: usa la STESSA logica di P1 (Joy:: con Joy::update).
        // FIX DEFINITIVO: il problema e' che isConnected(1) ricalcola
        // xinputCount ogni volta (chiama g_xinputGetState per 4 slot).
        // Se il secondo arcade stick e' DirectInput, isConnected(1) ritorna
        // true solo se diIndex=1-xinputCount e' < g_dinputDeviceCount.
        // Con 1 XInput + 2 DirectInput: xinputCount=1, diIndex=0 -> OK.
        // MA getAxisPosition ricalcola xinputCount INDEPENDENTEMENTE.
        // Se tra le due chiamate lo stato XInput cambia (es. P1 muove lo
        // stick), xinputCount potrebbe essere diverso -> diIndex diverso ->
        // legge il device sbagliato.
        //
        // FIX: usa SEMPRE p2JoyId=1, e lascia che Joy:: gestisca il
        // fallback internamente. Joy::isConnected(1) ricalcola ogni volta,
        // ma getAxisPosition usa la stessa logica, quindi e' consistente.
        // Se isConnected(1) ritorna false, il codice sotto non esegue,
        // ma almeno non c'e' mismatch tra isConnected e getAxisPosition.
        //
        // Inoltre: se Joy::isConnected(1) e' false, usa SFML fallback
        // (sf::Joystick) che su Windows e' separato da XInput/DirectInput.
        unsigned int p2JoyId = 1;
        // Controlla se il joystick 1 e' disponibile con qualsiasi metodo
        bool p2Connected = Joy::isConnected(1);
        if (!p2Connected) {
            // Prova SFML direttamente per joystick 1
            sf::Joystick::update();
            p2Connected = sf::Joystick::isConnected(1);
            if (p2Connected) {
                // SFML vede il joystick 1, usiamo SFML tramite Joy::
                // (Joy:: fallback a SFML quando XInput/DirectInput non trova)
                p2JoyId = 1;
            } else {
                // Nessun joystick 1: usa il joystick 0 (condiviso con P1)
                p2JoyId = 0;
            }
        }
        // Leggi assi sempre (anche se p2JoyId=0, per gamepad condiviso)
        float x = Joy::getAxisPosition(p2JoyId, (sf::Joystick::Axis)config.joy2_axis_x);
        float y = Joy::getAxisPosition(p2JoyId, (sf::Joystick::Axis)config.joy2_axis_y);
        // Se Joy:: non ha funzionato (valori 0), prova SFML direttamente
        if (p2JoyId == 1 && fabs(x) < 0.1f && fabs(y) < 0.1f) {
            x = sf::Joystick::getAxisPosition(p2JoyId, (sf::Joystick::Axis)config.joy2_axis_x);
            y = sf::Joystick::getAxisPosition(p2JoyId, (sf::Joystick::Axis)config.joy2_axis_y);
        }
        if (fabs(x) > 25 || fabs(y) > 25) {
            if (fabs(x) > fabs(y)) {
                if (x > 25) { player2.setDirection(1, 0); }
                else if (x < -25) { player2.setDirection(-1, 0); }
            } else {
                if (y > 25) { player2.setDirection(0, 1); }
                else if (y < -25) { player2.setDirection(0, -1); }
            }
        }
        // Sparo joystick
        if (config.joy2_shoot >= 0) {
            bool shootPressed = Joy::isButtonPressed(p2JoyId, (unsigned)config.joy2_shoot);
            if (!shootPressed && p2JoyId == 1) {
                shootPressed = sf::Joystick::isButtonPressed(p2JoyId, (unsigned)config.joy2_shoot);
            }
            if (shootPressed && player2.getShootCooldown() == 0) {
                int ammoBefore = player2.getCurrentWeapon().ammo;
                player2.shoot();
                if (player2.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player2.getCurrentWeapon().type));
                player2.setShootCooldown(150);
            }
        }
        // Salto joystick
        if (config.joy2_jump >= 0) {
            bool jumpPressed = Joy::isButtonPressed(p2JoyId, (unsigned)config.joy2_jump);
            if (!jumpPressed && p2JoyId == 1) {
                jumpPressed = sf::Joystick::isButtonPressed(p2JoyId, (unsigned)config.joy2_jump);
            }
            if (jumpPressed) {
                bool wasJumping = player2.isJumping();
                player2.activateJump();
                if (!wasJumping && player2.isJumping()) audio.playSound(SOUND_JUMP);
            }
        }

        // Sparo tastiera (tasto E di default)
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key2_shoot)) {
            if (player2.getShootCooldown() == 0) {
                int ammoBefore = player2.getCurrentWeapon().ammo;
                player2.shoot();
                if (player2.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player2.getCurrentWeapon().type));
                player2.setShootCooldown(150);
            }
        }
        // Salto tastiera (tasto Q di default)
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key2_jump)) {
            bool wasJumping = player2.isJumping();
            player2.activateJump();
            if (!wasJumping && player2.isJumping()) audio.playSound(SOUND_JUMP);
        }
    }

    // --- Logica STATE_PLAYING: labirinto ---
    if (state == STATE_PLAYING) {
        // Tesori: rileva raccolta confrontando il conteggio prima/dopo update
        int treasuresBefore = maze.getRemainingTreasures();
        player.update(maze, false, particles);
        if (player.consumePickedWeapon()) audio.playSound(SOUND_WEAPON_PICKUP);
        if (numPlayers == 2) {
            player2.update(maze, false, particles);
            if (player2.consumePickedWeapon()) audio.playSound(SOUND_WEAPON_PICKUP);
        }
        if (maze.getRemainingTreasures() < treasuresBefore) audio.playSound(SOUND_TREASURE);

        // Aggiornamento nemici (passa pos giocatore per AI + sparo)
        sf::Vector2f pPos = player.getPixelPos();
        for (auto& enemy : enemies) {
            if (!enemy.isDeathAnimDone()) enemy.update(maze, player.getGridPos(), pPos, enemyProjectiles);
        }

        // --- Aggiornamento mini-boss (se presente) ---
        // Il mini-boss insegue il player con BFS e attacca meele.
        if (miniBoss && !miniBoss->isDead()) {
            miniBoss->update(maze, player.getGridPos(), pPos, particles);
            // --- Collisione mini-boss vs player (danno meele quando attacca) ---
            // takeDamage() del player toglie 1 HP fisso (con invulnerabilita'
            // post-colpo). Per simulare il danno alto del mini-boss, chiamiamo
            // takeDamage() piu' volte in base al danno dell'arma.
            if (miniBoss->isAttacking()) {
                float dx = pPos.x - miniBoss->getPixelPos().x;
                float dy = pPos.y - miniBoss->getPixelPos().y;
                float dist = sqrtf(dx*dx + dy*dy);
                if (dist < miniBoss->getAttackRange() + 10.f) {
                    // Danno al player (solo se non invincibile)
                    if (playerInvincibleTimer <= 0) {
                        // takeDamage() toglie 1 HP per chiamata. Il mini-boss
                        // fa 12-25 danno, quindi chiamiamo takeDamage() per
                        // ogni punto (ma takeDamage rispetta invulnerabilita'
                        // post-colpo, quindi solo 1 sara' effettivo).
                        // Per semplicita', chiamiamo takeDamage() una volta
                        // per ogni 5 punti danno (arrotondato).
                        int numHits = miniBoss->getAttackDamage() / 5;
                        if (numHits < 1) numHits = 1;
                        for (int h = 0; h < numHits; h++) {
                            player.takeDamage();
                        }
                    }
                }
            }
        }
        // Pulizia mini-boss morto (dopo animazione morte)
        if (miniBoss && miniBoss->isDead()) {
            // Lascia il mini-boss renderizzato per l'animazione di morte
            // (dyingTimer gestito in update). Quando e' 0, eliminiamo.
            // Per semplicita', eliminiamo subito dopo la morte.
            player.addScore(miniBoss->getScoreReward());
            audio.playSound(SOUND_ENEMY_DEATH);
            audio.playSound(SOUND_ENEMY_EXPLODE);
            // Particelle di morte (oro per distinguerlo dai nemici normali)
            for (int i = 0; i < 30; i++) {
                float ang = (rand() % 360) * (float)M_PI / 180.f;
                float spd = 2.f + (rand() % 6);
                particles.push_back(makeParticle(
                    miniBoss->getPixelPos(),
                    sf::Vector2f(cosf(ang) * spd, sinf(ang) * spd - 2.f),
                    sf::Color(220, 160, 40),  // oro
                    50, 50, 6.f, 1));  // fiamma triangolare
            }
            delete miniBoss;
            miniBoss = nullptr;
        }

        // --- Aggiornamento proiettili nemici ---
        // Vanno mossi qui perche' Enemy non ha accesso al loop di gioco.
        for (auto& proj : enemyProjectiles) {
            if (!proj.active) continue;
            proj.pos += proj.dir; // Muove il proiettile nemico
            // Disattiva se fuori dall'area di gioco (sotto la UI)
            if (proj.pos.x < 0 || proj.pos.x > WINDOW_WIDTH || proj.pos.y < UI_HEIGHT || proj.pos.y > WINDOW_HEIGHT) {
                proj.active = false;
            }
        }

        // --- Collisioni: proiettili giocatore vs nemici ---
        // La soglia 600 (sqrt ~24.5 px) e' una distanza al quadrato: e' piu'
        // veloce di sqrt ed e' sufficiente per hit detection approssimata.
        for (auto& proj : player.getProjectiles()) {
            if (!proj.active) continue;
            for (auto& enemy : enemies) {
                if (enemy.isDead()) continue;
                float dx = proj.pos.x - enemy.getPixelPos().x;
                float dy = proj.pos.y - enemy.getPixelPos().y;
                if (dx*dx + dy*dy < 600) {
                    enemy.takeDamage(proj.power);
                    proj.active = false;
                    if (enemy.isDead()) {
                        player.addScore(5000);
                        audio.playSound(SOUND_ENEMY_DEATH);
                        audio.playSound(SOUND_ENEMY_EXPLODE);
                        audio.playSound(SOUND_BLOOD_SPLAT);
                        // Esplosione: 25 particelle rosse + 10 scintille
                        for(int i=0; i<25; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%10-5), (float)(rand()%10-5)}, sf::Color(150+rand()%50, 0, 0), 35, 35});
                        for(int i=0; i<10; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%12-6), (float)(rand()%12-6)}, sf::Color(200, 100, 50), 25, 25});
                        // Macchia di sangue temporanea (5 secondi = 300 frame)
                        bloodStains.push_back({enemy.getPixelPos(), 300, 300, 8.f + (rand()%6), sf::Color(120, 0, 0, 200)});
                    }
                    break;
                }
            }
        }

        // --- Collisioni: proiettili player vs mini-boss ---
        // Il mini-boss ha HP piu' alti (18-35), quindi serve piu' di 1 colpo.
        // Hit box piu' grande dei nemici normali (size 32-40px).
        if (miniBoss && !miniBoss->isDead()) {
            float mbHalfSize = (float)miniBoss->getMaxHealth() * 0.f + 16.f;  // raggio ~16px
            for (auto& proj : player.getProjectiles()) {
                if (!proj.active) continue;
                float dx = proj.pos.x - miniBoss->getPixelPos().x;
                float dy = proj.pos.y - miniBoss->getPixelPos().y;
                if (dx*dx + dy*dy < mbHalfSize * mbHalfSize) {
                    miniBoss->takeDamage(proj.power);
                    proj.active = false;
                    audio.playSound(SOUND_BOSS_HIT);  // suono clank metallico
                    // Particelle di impatto (oro)
                    for (int i = 0; i < 8; i++) {
                        float ang = (rand() % 360) * (float)M_PI / 180.f;
                        particles.push_back(makeParticle(
                            miniBoss->getPixelPos(),
                            sf::Vector2f(cosf(ang) * 3.f, sinf(ang) * 3.f - 1.f),
                            sf::Color(220, 160, 40),  // oro
                            20, 20, 3.f, 0));
                    }
                }
            }
        }

        // --- Collisioni: proiettili nemici vs giocatore ---
        // Ignorate se il giocatore e' invulnerabile o sta saltando (dodge).
        if (!player.isInvulnerable() && !player.isJumping()) {
            for (auto& proj : enemyProjectiles) {
                if (!proj.active) continue;
                float dx = proj.pos.x - player.getPixelPos().x;
                float dy = proj.pos.y - player.getPixelPos().y;
                if (dx*dx + dy*dy < 600) {
                    proj.active = false;
                    int livesBefore = player.getLives();
                    player.takeDamage();
                    // Suono solo se e' stato effettivamente preso un danno
                    if (player.getLives() < livesBefore || player.getEnergy() < player.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                    break;
                }
            }
            // Rimuove i proiettili inattivi (erase-remove idiom)
            enemyProjectiles.erase(std::remove_if(enemyProjectiles.begin(), enemyProjectiles.end(), [](const Projectile& p) { return !p.active; }), enemyProjectiles.end());
        }

        // --- Collisioni corpo a corpo ---
        // Soglia 800 (sqrt ~28 px): piu' generosa dei proiettili perche' il
        // contatto fisico e' piu' "tollerante" dal punto di vista gameplay.
        if (!player.isInvulnerable() && !player.isJumping()) {
            for (auto& enemy : enemies) {
                if (enemy.isDead()) continue;
                float dx = pPos.x - enemy.getPixelPos().x;
                float dy = pPos.y - enemy.getPixelPos().y;
                if (dx*dx + dy*dy < 800) {
                    int livesBefore = player.getLives();
                    player.takeDamage();
                    if (player.getLives() < livesBefore || player.getEnergy() < player.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                    break;
                }
            }
        }

        // --- Collisioni player2: proiettili vs nemici (solo se 2 giocatori) ---
        if (numPlayers == 2) {
            for (auto& proj : player2.getProjectiles()) {
                if (!proj.active) continue;
                for (auto& enemy : enemies) {
                    if (enemy.isDead()) continue;
                    float dx = proj.pos.x - enemy.getPixelPos().x;
                    float dy = proj.pos.y - enemy.getPixelPos().y;
                    if (dx*dx + dy*dy < 600) {
                        enemy.takeDamage(proj.power);
                        proj.active = false;
                        if (enemy.isDead()) {
                            player2.addScore(5000);
                            audio.playSound(SOUND_ENEMY_DEATH);
                            audio.playSound(SOUND_ENEMY_EXPLODE);
                            audio.playSound(SOUND_BLOOD_SPLAT);
                            for(int i=0; i<25; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%10-5), (float)(rand()%10-5)}, sf::Color(150+rand()%50, 0, 0), 35, 35});
                            for(int i=0; i<10; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%12-6), (float)(rand()%12-6)}, sf::Color(200, 100, 50), 25, 25});
                            bloodStains.push_back({enemy.getPixelPos(), 300, 300, 8.f + (rand()%6), sf::Color(120, 0, 0, 200)});
                        }
                        break;
                    }
                }
            }

            // --- Collisioni player2: proiettili nemici vs player2 ---
            if (!player2.isInvulnerable() && !player2.isJumping()) {
                for (auto& proj : enemyProjectiles) {
                    if (!proj.active) continue;
                    float dx = proj.pos.x - player2.getPixelPos().x;
                    float dy = proj.pos.y - player2.getPixelPos().y;
                    if (dx*dx + dy*dy < 600) {
                        proj.active = false;
                        int livesBefore = player2.getLives();
                        player2.takeDamage();
                        if (player2.getLives() < livesBefore || player2.getEnergy() < player2.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                    }
                }
            }

            // --- Collisioni corpo a corpo player2 vs nemici ---
            if (!player2.isInvulnerable() && !player2.isJumping()) {
                for (auto& enemy : enemies) {
                    if (enemy.isDead()) continue;
                    sf::Vector2f pPos2 = player2.getPixelPos();
                    float dx = pPos2.x - enemy.getPixelPos().x;
                    float dy = pPos2.y - enemy.getPixelPos().y;
                    if (dx*dx + dy*dy < 800) {
                        int livesBefore = player2.getLives();
                        player2.takeDamage();
                        if (player2.getLives() < livesBefore || player2.getEnergy() < player2.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                        break;
                    }
                }
            }

            // --- Collisioni tra i due giocatori (friendly fire) ---
            // Quando i due giocatori si sovrappongono si danneggiano a vicenda.
            // La precedente versione assegnava +1000 punti al danno: era una
            // meccanica illogica (premia il danneggiare l'alleato). Ora e'
            // una penalita' pura: entrambi prendono danno e ricevono invulnerabilita'
            // temporanea (gestita da Player::takeDamage) per evitare che si
            // scateni una catena di hit nello stesso frame.
            if (!player.isInvulnerable() && !player2.isInvulnerable()
                && !player.isJumping() && !player2.isJumping()) {
                float dx = pPos.x - player2.getPixelPos().x;
                float dy = pPos.y - player2.getPixelPos().y;
                if (dx*dx + dy*dy < 800) {  // Soglia di contatto (sqrt ~28 px)
                    int livesBefore1 = player.getLives();
                    int livesBefore2 = player2.getLives();
                    player.takeDamage();
                    player2.takeDamage();
                    if (player.getLives() < livesBefore1
                        || player.getEnergy() < player.getMaxEnergy()
                        || player2.getLives() < livesBefore2
                        || player2.getEnergy() < player2.getMaxEnergy()) {
                        audio.playSound(SOUND_LOSE_LIFE);
                    }
                }
            }
        }

        // Transizioni di stato: morte -> continues (se crediti) o lose
        if (numPlayers == 1 && player.getLives() <= 0) {
            if (continuesLeft > 0) {
                state = STATE_CONTINUES; diedInBoss = false;
                continuesTimer = 10; continuesTimerMs = 0; continuesChoice = true;
            } else state = STATE_LOSE;
        }
        if (numPlayers == 2 && player.getLives() <= 0 && player2.getLives() <= 0) {
            if (continuesLeft > 0) {
                state = STATE_CONTINUES; diedInBoss = false;
                continuesTimer = 10; continuesTimerMs = 0; continuesChoice = true;
            } else state = STATE_LOSE;
        }
        // Quando tutti i tesori sono raccolti, appare una porta di uscita
        // nel labirinto. Il player deve raggiungerla per passare al boss.
        // La porta viene posizionata in una cella vuota lontana dal player
        // (massima distanza Manhattan possibile).
        if (maze.getRemainingTreasures() == 0 && !exitDoor.active) {
            // Trova una cella vuota CASUALE raggiungibile dal player
            std::vector<Vec2> emptyCells;
            for (int c = 1; c < MAZE_COLS - 1; c++) {
                for (int r = 1; r < MAZE_ROWS - 1; r++) {
                    if (maze.getCellType(c, r) == CELL_EMPTY) {
                        emptyCells.push_back({c, r});
                    }
                }
            }
            if (!emptyCells.empty()) {
                Vec2 chosen = emptyCells[rand() % emptyCells.size()];
                exitDoor.pos.x = chosen.x * TILE_SIZE + TILE_SIZE / 2.f;
                exitDoor.pos.y = chosen.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
                exitDoor.active = true;
                exitDoor.animTimer = 800;
                exitDoor.glowPulse = 0.f;
                audio.playSound(SOUND_TREASURE);
            }
        }

        // Aggiornamento della porta di uscita
        if (exitDoor.active) {
            if (exitDoor.animTimer > 16) exitDoor.animTimer -= 16;
            else exitDoor.animTimer = 0;
            exitDoor.glowPulse += 0.016f;
            if (exitDoor.animTimer == 0) {
                // Player1 o player2 possono attivare la scala
                bool p1Hit = false, p2Hit = false;
                float dx1 = player.getPixelPos().x - exitDoor.pos.x;
                float dy1 = player.getPixelPos().y - exitDoor.pos.y;
                if (dx1 * dx1 + dy1 * dy1 < 600) p1Hit = true;
                if (numPlayers == 2) {
                    float dx2 = player2.getPixelPos().x - exitDoor.pos.x;
                    float dy2 = player2.getPixelPos().y - exitDoor.pos.y;
                    if (dx2 * dx2 + dy2 * dy2 < 600) p2Hit = true;
                }
                if (p1Hit || p2Hit) {
                    exitDoor.active = false;
                    startBossFight();
                }
            }
        }

        // --- Respawn nemici al 50% tramite portale magico ---
        // Quando il 50% dei nemici iniziali e' stato ucciso e il portale
        // non e' ancora stato usato, appare un portale magico al centro
        // del labirinto. Il portale si apre (fase 0, 1000ms), fa uscire
        // i nemici respawnati (fase 1, 500ms), poi si chiude (fase 2,
        // 800ms). Una sola volta per livello.
        if (!portalUsed && initialEnemyCount > 0) {
            int aliveCount = 0;
            for (const auto& e : enemies) if (!e.isDead()) aliveCount++;
            if (aliveCount <= initialEnemyCount / 2 && aliveCount > 0) {
                // Attiva il portale: cerca la cella vuota piu' vicina al
                // centro del labirinto (il centro esatto potrebbe essere un muro)
                int targetC = MAZE_COLS / 2;
                int targetR = MAZE_ROWS / 2;
                int bestC = -1, bestR = -1, bestDist = 999;
                for (int c = 1; c < MAZE_COLS - 1; c++) {
                    for (int r = 1; r < MAZE_ROWS - 1; r++) {
                        if (maze.getCellType(c, r) == CELL_EMPTY) {
                            int d = abs(c - targetC) + abs(r - targetR);
                            if (d < bestDist) {
                                bestDist = d; bestC = c; bestR = r;
                            }
                        }
                    }
                }
                if (bestC >= 0) {
                    magicPortal.pos.x = bestC * TILE_SIZE + TILE_SIZE / 2.f;
                    magicPortal.pos.y = bestR * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
                    magicPortal.active = true;
                    magicPortal.phase = 0;
                    magicPortal.phaseTimer = 1000;
                    magicPortal.rotation = 0.f;
                    magicPortal.glowPulse = 0.f;
                    magicPortal.enemiesToSpawn = 3;
                    if (magicPortal.enemiesToSpawn > initialEnemyCount)
                        magicPortal.enemiesToSpawn = initialEnemyCount;
                    magicPortal.spawnTimer = 0;
                    magicPortal.deadEnemyIndices.clear();
                    // Raccogli gli indici dei nemici morti da respawnare
                    for (int i = 0; i < (int)enemies.size(); i++) {
                        if (enemies[i].isDead() && enemies[i].isDeathAnimDone()) {
                            magicPortal.deadEnemyIndices.push_back(i);
                        }
                    }
                    portalUsed = true;
                    audio.playSound(SOUND_PORTAL_OPEN);

                    // --- Spawn del mini-boss (1 per labirinto, al respawn) ---
                    // Il mini-boss appare SOLO quando il portale magico si
                    // attiva (50% nemici uccisi). 1 per livello, tipo unico
                    // basato sul livello corrente (17 tipi che ciclano).
                    //
                    // FIX: in precedenza lo spawn cercava la cella PIU'
                    // LONTANA dal player (che essendo partito da (1,1) ->
                    // angolo in alto a sinistra -> il mini-boss spuntava
                    // nell'angolo IN BASSO A DESTRA, opposto allo schermo).
                    // Inoltre il mini-boss sembrava "sbucato dal nulla" in
                    // un punto scollegato dal portale.
                    //
                    // Ora cerchiamo una cella vuota VICINO al portale (raggio
                    // 1-4), cosi' il mini-boss appare DRAMMATICAMENTE dal
                    // portale insieme ai nemici respawnati. Se il portale non
                    // ha celle libere vicine, facciamo fallback alla cella
                    // piu' lontana dal player (comportamento precedente).
                    if (!miniBossSpawned && !miniBoss) {
                        int portalC = (int)(magicPortal.pos.x / TILE_SIZE);
                        int portalR = (int)((magicPortal.pos.y - UI_HEIGHT) / TILE_SIZE);
                        int mbC = -1, mbR = -1;

                        // Cerca cella vuota in raggio crescente dal portale
                        // (raggio 1 = adiacente al portale, 4 = ~2 celle distanza)
                        for (int radius = 1; radius <= 4 && mbC < 0; radius++) {
                            for (int dc = -radius; dc <= radius && mbC < 0; dc++) {
                                for (int dr = -radius; dr <= radius && mbC < 0; dr++) {
                                    int nc = portalC + dc;
                                    int nr = portalR + dr;
                                    if (nc <= 0 || nc >= MAZE_COLS - 1) continue;
                                    if (nr <= 0 || nr >= MAZE_ROWS - 1) continue;
                                    if (maze.isWall(nc, nr)) continue;
                                    if (maze.getCellType(nc, nr) != CELL_EMPTY) continue;
                                    // Non spawnare esattamente sopra il portale
                                    if (nc == portalC && nr == portalR) continue;
                                    mbC = nc;
                                    mbR = nr;
                                }
                            }
                        }

                        // Fallback: se non trova cella vicino al portale,
                        // usa la vecchia logica "cella piu' lontana dal player"
                        if (mbC < 0) {
                            sf::Vector2f ppos = player.getPixelPos();
                            int pc = (int)(ppos.x / TILE_SIZE);
                            int pr = (int)((ppos.y - UI_HEIGHT) / TILE_SIZE);
                            int fallbackBestDist = -1;  // FIX -Wshadow
                            for (int c = 1; c < MAZE_COLS - 1; c++) {
                                for (int r = 1; r < MAZE_ROWS - 1; r++) {
                                    if (maze.getCellType(c, r) == CELL_EMPTY &&
                                        !maze.isWall(c, r)) {
                                        int dist = abs(c - pc) + abs(r - pr);
                                        if (dist >= 6 && dist > fallbackBestDist) {
                                            fallbackBestDist = dist;
                                            mbC = c;
                                            mbR = r;
                                        }
                                    }
                                }
                            }
                        }

                        if (mbC >= 0) {
                            // Tipo basato sul livello (17 tipi che ciclano)
                            MiniBossType mbType = (MiniBossType)(
                                (currentLevel - 1) % MINIBOSS_TYPE_COUNT);
                            miniBoss = new MiniBoss(mbType, currentLevel, mbC, mbR);
                            miniBossSpawned = true;
                            // Effetto particellare di "esplosione" all'uscita
                            // del mini-boss dal portale (molto piu' intenso dei
                            // nemici normali: 25 particelle dorate invece di 10
                            // viola).
                            for (int i = 0; i < 25; i++) {
                                float ang = (rand() % 360) * (float)M_PI / 180.f;
                                float speed = 3.f + (rand() % 30) / 10.f;
                                particles.push_back(makeParticle(
                                    sf::Vector2f(miniBoss->getPixelPos().x,
                                                 miniBoss->getPixelPos().y),
                                    sf::Vector2f(cosf(ang) * speed, sinf(ang) * speed - 1.f),
                                    sf::Color(220, 160, 40),  // oro
                                    35, 35, 4.f, 0));
                            }
                        }
                    }

                    // Avvia musica evocativa fantasy per la durata del portale.
                    // Questa traccia e' un jingle evento (non musica di sottofondo):
                    // suona SEMPRE, anche se l'opzione "musica" del menu e' OFF.
                    audio.playLevelMusic(0, false);  // traccia speciale
                }
            }
        }

        // Aggiornamento del portale magico
        if (magicPortal.active) {
            magicPortal.rotation += 0.03f;
            magicPortal.glowPulse += 0.016f;
            if (magicPortal.phaseTimer > 16) magicPortal.phaseTimer -= 16;
            else magicPortal.phaseTimer = 0;

            if (magicPortal.phaseTimer == 0) {
                if (magicPortal.phase == 0) {
                    // Fase apertura completata -> inizio fase spawn (con intervalli)
                    magicPortal.phase = 1;
                    magicPortal.spawnTimer = 500;  // primo spawn dopo 500ms
                    // Spawna il primo nemico subito
                    spawnEnemyFromPortal();
                } else if (magicPortal.phase == 2) {
                    // Fase chiusura completata -> inattivo
                    magicPortal.phase = 3;
                    magicPortal.active = false;
                    // Ripristina lo stato sonoro precedente al portale:
                    // - se la musica di sottofondo era attiva, riprendi la traccia del livello
                    // - se era disattivata, ferma tutto (silenzio come prima del portale)
                    if (musicEnabled) audio.playLevelMusic(currentLevel, false);
                    else audio.stopMusic();
                }
            }

            // Fase 1: spawn nemici con intervallo di 4 secondi
            if (magicPortal.phase == 1) {
                if (magicPortal.spawnTimer > 16) magicPortal.spawnTimer -= 16;
                else magicPortal.spawnTimer = 0;
                if (magicPortal.spawnTimer == 0 && magicPortal.enemiesToSpawn > 0) {
                    spawnEnemyFromPortal();
                    magicPortal.spawnTimer = 4000;  // 4 secondi al prossimo
                }
                // Se tutti i nemici sono spawnati, passa alla chiusura
                if (magicPortal.enemiesToSpawn == 0) {
                    magicPortal.phase = 2;
                    magicPortal.phaseTimer = 800;
                    audio.playSound(SOUND_PORTAL_CLOSE);
                }
            }
        }

        // --- Aggiornamento macchie di sangue ---
        for (auto& bs : bloodStains) {
            bs.life--;
        }
        bloodStains.erase(std::remove_if(bloodStains.begin(), bloodStains.end(),
            [](const BloodStain& bs) { return bs.life <= 0; }), bloodStains.end());

        // --- Aggiornamento mucchi di cenere ---
        // I mucchi di cenere (nemici bruciati dal player invincibile) durano
        // piu' a lungo del sangue e hanno un'animazione di particelle che
        // si sollevano lentamente.
        for (auto& ap : ashPiles) {
            ap.life--;
            ap.animTime += 0.04f;
        }
        ashPiles.erase(std::remove_if(ashPiles.begin(), ashPiles.end(),
            [](const AshPile& ap) { return ap.life <= 0; }), ashPiles.end());

        // --- Aggiornamento delle esplosioni di fuoco (FireBurst) ---
        // Ogni FireBurst vive ~60 frame (1s) e viene rimosso quando scade.
        for (auto& fb : fireBursts) {
            fb.life--;
            fb.animTime += 0.1f;
        }
        fireBursts.erase(std::remove_if(fireBursts.begin(), fireBursts.end(),
            [](const FireBurst& fb) { return fb.life <= 0; }), fireBursts.end());

        // --- Aggiornamento del calice d'oro (pozione magica) ---
        if (chalice.active) {
            chalice.pulse += 0.016f;
            chalice.bobOffset = sinf(chalice.pulse * 3.f) * 4.f;
            // Collisione con player1 o player2
            float dx1 = player.getPixelPos().x - chalice.pos.x;
            float dy1 = player.getPixelPos().y - chalice.pos.y;
            bool p1Hit = (dx1 * dx1 + dy1 * dy1 < 500);
            bool p2Hit = false;
            if (numPlayers == 2) {
                float dx2 = player2.getPixelPos().x - chalice.pos.x;
                float dy2 = player2.getPixelPos().y - chalice.pos.y;
                p2Hit = (dx2 * dx2 + dy2 * dy2 < 500);
            }
            if (p1Hit || p2Hit) {
                chalice.active = false;
                chaliceUsed = true;
                // Durata invincibilita': 10000 ms = 10 secondi (valore originale).
                // FIX: aumentata del 50% -> 15000 ms = 15 secondi (richiesta utente).
                // Questo da' piu' tempo al player per bruciare nemici dopo aver
                // bevuto il calice.
                if (p1Hit) playerInvincibleTimer = 15000;
                if (p2Hit) player2InvincibleTimer = 15000;
                audio.playSound(SOUND_POTION_DRINK);
                // Avvia il jingle epico DEDICATO del calice (fanfara eroica
                // dorata, ~6s). Suona su un canale SEPARATO (epicSound), NON
                // interrompe la musica di gioco di sottofondo. DISTINTA dal
                // jingle dello scettro (che e' mistico/arcano) e dalle musiche
                // di gioco.
                audio.playEpicMusic(TRACK_EPIC_CHALICE);
                for (int i = 0; i < 20; i++)
                    particles.push_back({chalice.pos, {(float)(rand()%8-4), (float)(rand()%8-4)},
                        sf::Color(255, 215, 0), 40, 40});
            }
        }

        // --- Aggiornamento invincibilità (pozione) per entrambi i player ---
        // Quando il giocatore e' invincibile (calice dell'immortalita'), i
        // nemici che tocca BRUCIANO: non c'e' sangue, ma fiammate + cenere.
        // Lambda per evitare duplicazione.
        //
        // FIX: il nemico NON muore istantaneamente. Ora entra in stato
        // "burning" (enemy.startBurning(50)) per 50 frame (~0.8s). Durante
        // questo stato, sopra il nemico viene disegnato un overlay di fiamme
        // (vedi Enemy::render). Quando burningTimer arriva a 0, il nemico
        // muore davvero (gestito sotto: takeDamage(999) + cenere + FireBurst).
        auto updateInvincible = [this](Player& p, int& timer) {
            if (timer > 0) {
                if (timer > 16) timer -= 16;
                else timer = 0;
                if (timer > 0) {
                    for (auto& enemy : enemies) {
                        // Skip se gia' morto, gia' morente, o gia' bruciando
                        if (enemy.isDead() || enemy.isDying() || enemy.isBurning()) continue;
                        float dx = p.getPixelPos().x - enemy.getPixelPos().x;
                        float dy = p.getPixelPos().y - enemy.getPixelPos().y;
                        if (dx * dx + dy * dy < 600) {
                            // Accende il nemico: entra in stato burning per 50 frame.
                            // Il nemico sara' visualmente coperto da fiamme.
                            enemy.startBurning(50);
                            // Punteggio subito (percezione immediata del danno)
                            p.addScore(5000);
                            // Suono di accensione (fuoco che prende)
                            audio.playSound(SOUND_ENEMY_EXPLODE);
                        }
                    }
                    // --- FIX: brucia anche il mini-boss se presente e vicino ---
                    // In precedenza il mini-boss era IGNORATO dal calice: il player
                    // invincibile poteva toccarlo senza subire danno ne' ferirlo.
                    // Ora il mini-boss viene bruciato come i nemici normali, ma
                    // con due differenze:
                    //   1. Raggio collisione piu' grande (1200 invece di 600)
                    //      perche' il mini-boss e' piu' grande
                    //   2. Una singola "bruciatura" di 50 frame NON lo uccide:
                    //      gli toglie ~40% HP. Servono 2-3 contatti per bruciarlo
                    //      del tutto. La morte da bruciatura (quando HP <= 0)
                    //      viene gestita sotto (come i nemici normali).
                    if (miniBoss && !miniBoss->isDead() &&
                        !miniBoss->isDying() && !miniBoss->isBurning()) {
                        float dx = p.getPixelPos().x - miniBoss->getPixelPos().x;
                        float dy = p.getPixelPos().y - miniBoss->getPixelPos().y;
                        // Raggio piu' grande per il mini-boss (e' piu' grosso)
                        if (dx * dx + dy * dy < 1200) {
                            miniBoss->startBurning(50);
                            // Score per il contatto (non per l'uccisione)
                            p.addScore(2000);
                            audio.playSound(SOUND_ENEMY_EXPLODE);
                        }
                    }
                }
            }
        };
        updateInvincible(player, playerInvincibleTimer);
        if (numPlayers == 2) updateInvincible(player2, player2InvincibleTimer);

        // --- Gestione morte nemici bruciati (burning -> ash) ---
        // Quando un nemico in stato burning arriva a burningTimer == 0, muore:
        // takeDamage(999), suono di morte, creazione mucchio di cenere e
        // piccolo FireBurst finale (lampo di transizione). Nessuna esplosione
        // di triangoli gialli/rossi: la vecchia nuvola di 40+15 particelle
        // triangolari e' stata eliminata. Ora si vede solo:
        //   1. Il nemico AVVOLTO da fiamme per 50 frame (overlay in Enemy::render)
        //   2. Un lampo finale breve (FireBurst scale 0.9, vita 30 frame = 0.5s)
        //   3. Il mucchio di cenere che resta sul pavimento
        for (auto& enemy : enemies) {
            // Rileva la transizione: era burning (burnAnimTime > 0) ma ora
            // burningTimer == 0 e non e' ancora morto (health > 0).
            // In questo caso, finalizziamo la morte da bruciatura.
            if (enemy.isBurning() == false && enemy.isDead() == false &&
                enemy.isDying() == false && enemy.wasBurned()) {
                // Il nemico muore: takeDamage(999) triggera dyingTimer
                enemy.takeDamage(999);
                enemy.clearBurnedFlag();  // resetta wasBurned per evitare re-trigger
                audio.playSound(SOUND_ENEMY_DEATH);
                // Mucchio di cenere sul pavimento (dove era il nemico)
                ashPiles.push_back({enemy.getPixelPos(), 500, 500,
                    12.f + (rand()%6), 0.f});  // raggio 12-17, durata ~8.3s
                // Piccolo FireBurst finale (lampo di transizione, non esplosione)
                // Scale 0.9 (piu' piccolo del FireBurst normale che era 1.5),
                // vita 30 frame (0.5s, piu' breve del normale che era 60).
                fireBursts.push_back({enemy.getPixelPos(), 30, 30,
                    0.f, 0.9f});  // pos, life=30, maxLife=30, animTime=0, scale=0.9
            }
        }

        // --- FIX: Gestione morte mini-boss bruciato (burning -> ash) ---
        // Come i nemici normali, il mini-boss che ha finito lo stato burning
        // viene finalizzato qui. Tuttavia, una singola bruciatura NON lo
        // uccide: gli toglie ~40% HP. Quando l'HP arriva a 0 (dopo 2-3
        // bruciature), il mini-boss muore e diventa cenere + FireBurst.
        if (miniBoss && !miniBoss->isDead() && !miniBoss->isDying() &&
            !miniBoss->isBurning() && miniBoss->wasBurned()) {
            // La fase burning e' finita. Infliggi il danno da bruciatura:
            // ~40% HP del mini-boss (maxHealth / 2.5 ~= 40%).
            int burnDmg = miniBoss->getMaxHealth() * 40 / 100;
            if (burnDmg < 5) burnDmg = 5;  // minimo 5 danni
            miniBoss->takeDamage(burnDmg);
            miniBoss->clearBurnedFlag();
            // Suono: fuoco che si spegne / danno subito
            audio.playSound(SOUND_BLOOD_SPLAT);
            // Piccolo FireBurst come feedback del danno subito
            fireBursts.push_back({miniBoss->getPixelPos(), 25, 25,
                0.f, 0.7f});
            // Se il mini-boss e' morto per la bruciatura (HP <= 0):
            // takeDamage ha impostato health = 0, ma il mini-boss non triggera
            // automaticamente dyingTimer come Enemy. Impostiamolo a mano.
            if (miniBoss->isDead()) {
                // Crea cenere + FireBurst grande per la morte del mini-boss
                ashPiles.push_back({miniBoss->getPixelPos(), 600, 600,
                    18.f + (rand()%6), 0.f});  // raggio piu' grande dei nemici
                // FireBurst piu' grande per il mini-boss (scale 1.2, vita 50)
                fireBursts.push_back({miniBoss->getPixelPos(), 50, 50,
                    0.f, 1.2f});
                audio.playSound(SOUND_ENEMY_DEATH);
            }
        }

        // --- Aggiornamento dello scettro magico ---
        if (scepter.active && !scepter.triggered) {
            scepter.pulse += 0.016f;
            scepter.bobOffset = sinf(scepter.pulse * 3.f) * 4.f;
            // Collisione con player1 o player2
            float dx1 = player.getPixelPos().x - scepter.pos.x;
            float dy1 = player.getPixelPos().y - scepter.pos.y;
            bool p1Hit = (dx1 * dx1 + dy1 * dy1 < 500);
            bool p2Hit = false;
            if (numPlayers == 2) {
                float dx2 = player2.getPixelPos().x - scepter.pos.x;
                float dy2 = player2.getPixelPos().y - scepter.pos.y;
                p2Hit = (dx2 * dx2 + dy2 * dy2 < 500);
            }
            if (p1Hit || p2Hit) {
                scepter.active = false;
                scepter.triggered = true;
                scepterUsed = true;
                scepter.lightningsLeft = 5;
                scepter.lightningTimer = 200;  // primo fulmine tra 200ms
                audio.playSound(SOUND_SCEPTER_PICKUP);  // "oh-oh-oh" magico evocativo
                // Avvia il jingle epico DEDICATO dello scettro (arcano, mistico,
                // ~7s, tritono sospeso). Suona su un canale SEPARATO (epicSound),
                // NON interrompe la musica di gioco. DISTINTA dal jingle del
                // calice (che e' eroico/dorato) e dalle musiche di gioco.
                audio.playEpicMusic(TRACK_EPIC_SCEPTER);
                for (int i = 0; i < 15; i++)
                    particles.push_back({scepter.pos, {(float)(rand()%8-4), (float)(rand()%8-4)},
                        sf::Color(180, 200, 255), 35, 35});
            }
        }

        // --- Update fulmini (scettro magico) ---
        // Lo scettro genera 5 fulmini totali (scepter.lightningsLeft=5),
        // ognuno a 3 secondi di distanza. Ogni fulmine ATTRAVERSA TUTTO lo
        // schermo (dall'alto al punto di impatto) usando verticali e
        // diagonali. Il danno viene calcolato lungo TUTTO il percorso del
        // fulmine, cosi' i nemici vengono colpiti anche se il fulmine li
        // attraversa in volo (non solo al punto di impatto).
        if (scepter.triggered && scepter.lightningsLeft > 0) {
            if (scepter.lightningTimer > 16) scepter.lightningTimer -= 16;
            else scepter.lightningTimer = 0;
            if (scepter.lightningTimer == 0) {
                // Genera un fulmine in posizione casuale (punto di impatto)
                float lx, ly;
                if (state == STATE_BOSS) {
                    lx = 100.f + (rand() % (WINDOW_WIDTH - 200));
                    ly = UI_HEIGHT + 100.f + (rand() % (WINDOW_HEIGHT - UI_HEIGHT - 200));
                } else {
                    // Nel labirinto: posizione casuale
                    lx = (1 + rand() % (MAZE_COLS - 2)) * TILE_SIZE + TILE_SIZE / 2.f;
                    ly = UI_HEIGHT + (1 + rand() % (MAZE_ROWS - 2)) * TILE_SIZE + TILE_SIZE / 2.f;
                }
                // Crea il fulmine che ATTRAVERSA TUTTO lo schermo (verticale
                // o diagonale) con zigzag pre-calcolato. La saetta parte
                // dal bordo superiore (o angolo) e arriva a (lx, ly).
                lightnings.push_back(createFullScreenLightning(sf::Vector2f(lx, ly)));
                audio.playSound(SOUND_LIGHTNING);
                // Flash bianco su tutto lo schermo per simulare il lampo
                // del fulmine (effetto "illumination flash"). Ridotto a
                // 120ms (era 250ms) per non affaticare gli occhi.
                screenFlashTimer = 120;
                scepter.lightningsLeft--;
                if (scepter.lightningsLeft > 0) {
                    scepter.lightningTimer = 3000;  // 3 secondi al prossimo
                }
                // --- Danni ai nemici lungo TUTTO il percorso del fulmine ---
                // Per ogni nemico, controlla se uno dei segmenti del
                // zigzag lo attraversa (distanza < 30px). Se si', il nemico
                // prende 999 danni (morte istantanea). Questo garantisce
                // che il fulmine possa colpire nemici in qualsiasi posizione
                // dello schermo, anche lontani dal punto di impatto.
                const std::vector<sf::Vector2f>& pts =
                    lightnings.back().zigzagPoints;
                for (auto& enemy : enemies) {
                    if (enemy.isDead()) continue;
                    sf::Vector2f epos = enemy.getPixelPos();
                    bool hit = false;
                    // Controlla distanza da ogni segmento del zigzag
                    for (size_t i = 0; i + 1 < pts.size() && !hit; i++) {
                        sf::Vector2f p0 = pts[i];
                        sf::Vector2f p1 = pts[i + 1];
                        // Distanza punto-segmento
                        float segDx = p1.x - p0.x;
                        float segDy = p1.y - p0.y;
                        float segLen2 = segDx * segDx + segDy * segDy;
                        if (segLen2 < 0.001f) continue;
                        float t = ((epos.x - p0.x) * segDx +
                                   (epos.y - p0.y) * segDy) / segLen2;
                        if (t < 0.f) t = 0.f;
                        if (t > 1.f) t = 1.f;
                        float projX = p0.x + segDx * t;
                        float projY = p0.y + segDy * t;
                        float ddx = epos.x - projX;
                        float ddy = epos.y - projY;
                        if (ddx * ddx + ddy * ddy < 900.f) {  // raggio 30px
                            hit = true;
                        }
                    }
                    // Controlla anche distanza dal punto di impatto (50px)
                    if (!hit) {
                        float dx = epos.x - lx;
                        float dy = epos.y - ly;
                        if (dx * dx + dy * dy < 2500.f) hit = true;  // raggio 50px
                    }
                    if (hit) {
                        // FIX: folgora il nemico prima di ucciderlo. L'effetto
                        // electrified (overlay scarica elettrica) accompagna
                        // la morte per dare feedback visivo che e' stato il
                        // fulmine a ucciderlo, non una pallottola normale.
                        enemy.startElectrified(30);  // 0.5s di scarica elettrica
                        enemy.takeDamage(999);
                        player.addScore(3000);
                        audio.playSound(SOUND_ENEMY_DEATH);
                        audio.playSound(SOUND_BLOOD_SPLAT);
                        // Particelle elettriche ciano/bianco (NON sangue rosso)
                        // per distinguere la morte da fulmine da quella da proiettile
                        for (int i = 0; i < 20; i++)
                            particles.push_back({enemy.getPixelPos(), {(float)(rand()%10-5), (float)(rand()%10-5)},
                                sf::Color(120, 200, 200), 30, 30});  // ciano elettrico
                        for (int i = 0; i < 10; i++)
                            particles.push_back({enemy.getPixelPos(), {(float)(rand()%12-6), (float)(rand()%12-6)},
                                sf::Color(240, 240, 240), 25, 25});  // bianco scintille
                        bloodStains.push_back({enemy.getPixelPos(), 300, 300, 8.f + (rand()%6), sf::Color(120, 0, 0, 200)});
                        lightnings.back().hitEnemy = true;
                    }
                }
                // --- FIX: Danno fulmine al mini-boss ---
                // Il fulmine attraversa tutto lo schermo, quindi puo' colpire
                // il mini-boss ovunque si trovi. Stessa logica dei nemici:
                // controlla distanza da ogni segmento del zigzag + dal punto
                // di impatto. Danno: 35% HP del mini-boss (maxHealth * 35/100).
                // Non 999 come i nemici normali (il mini-boss ha 18-35 HP,
                // 999 lo ucciderebbe con un solo fulmine). Servono 2-3 fulmini
                // per ucciderlo (bilanciato con i 5 fulmini totali dello
                // scettro).
                if (miniBoss && !miniBoss->isDead() && !miniBoss->isDying()) {
                    sf::Vector2f mbPos = miniBoss->getPixelPos();
                    bool mbHit = false;
                    for (size_t i = 0; i + 1 < pts.size() && !mbHit; i++) {
                        sf::Vector2f p0 = pts[i];
                        sf::Vector2f p1 = pts[i + 1];
                        float segDx = p1.x - p0.x;
                        float segDy = p1.y - p0.y;
                        float segLen2 = segDx * segDx + segDy * segDy;
                        if (segLen2 < 0.001f) continue;
                        float t = ((mbPos.x - p0.x) * segDx +
                                   (mbPos.y - p0.y) * segDy) / segLen2;
                        if (t < 0.f) t = 0.f;
                        if (t > 1.f) t = 1.f;
                        float projX = p0.x + segDx * t;
                        float projY = p0.y + segDy * t;
                        float ddx = mbPos.x - projX;
                        float ddy = mbPos.y - projY;
                        // Raggio piu' grande del nemico normale (40px invece
                        // di 30) perche' il mini-boss e' piu' grosso
                        if (ddx * ddx + ddy * ddy < 1600.f) {
                            mbHit = true;
                        }
                    }
                    // Check anche distanza dal punto di impatto (70px)
                    if (!mbHit) {
                        float dx = mbPos.x - lx;
                        float dy = mbPos.y - ly;
                        if (dx * dx + dy * dy < 4900.f) mbHit = true;
                    }
                    if (mbHit) {
                        // Danno: 35% HP massimo (min 8)
                        int mbDmg = miniBoss->getMaxHealth() * 35 / 100;
                        if (mbDmg < 8) mbDmg = 8;
                        miniBoss->takeDamage(mbDmg);
                        player.addScore(1500);
                        audio.playSound(SOUND_ENEMY_EXPLODE);
                        // Particelle dorate per il colpo del fulmine
                        for (int i = 0; i < 25; i++)
                            particles.push_back({mbPos,
                                {(float)(rand()%12-6), (float)(rand()%12-6)},
                                sf::Color(220, 160, 40), 30, 30});  // oro
                        for (int i = 0; i < 15; i++)
                            particles.push_back({mbPos,
                                {(float)(rand()%14-7), (float)(rand()%14-7)},
                                sf::Color(120, 200, 200), 25, 25});  // ciano
                    }
                }
            }
        }
        // Update fulmini attivi (visualizzazione)
        for (auto& lt : lightnings) lt.life--;
        lightnings.erase(std::remove_if(lightnings.begin(), lightnings.end(),
            [](const Lightning& lt) { return lt.life <= 0; }), lightnings.end());

        // --- Aggiornamento della mina ---
        if (mine.active && !mine.bouncing) {
            // Mina ferma: controlla collisione con player1 o player2
            mine.pulse += 0.016f;
            float dx1 = player.getPixelPos().x - mine.pos.x;
            float dy1 = player.getPixelPos().y - mine.pos.y;
            bool p1Hit = (dx1 * dx1 + dy1 * dy1 < 400);
            bool p2Hit = false;
            if (numPlayers == 2) {
                float dx2 = player2.getPixelPos().x - mine.pos.x;
                float dy2 = player2.getPixelPos().y - mine.pos.y;
                p2Hit = (dx2 * dx2 + dy2 * dy2 < 400);
            }
            if (p1Hit || p2Hit) {
                mine.bouncing = true;
                mine.bounceTimer = 30000;
                float angle = (rand() % 360) * (float)M_PI / 180.f;
                mine.vel.x = cosf(angle) * 6.f;
                mine.vel.y = sinf(angle) * 6.f;
                audio.playSound(SOUND_MINE_BOUNCE);
            }
        }
        if (mine.bouncing) {
            // Mina in movimento: aggiorna posizione
            mine.rotation += 0.08f;
            mine.pulse += 0.03f;
            mine.pos += mine.vel;
            // Rimbalzo sui muri del labirinto
            int mc = (int)(mine.pos.x / TILE_SIZE);
            int mr = (int)((mine.pos.y - UI_HEIGHT) / TILE_SIZE);
            if (maze.isWall(mc, mr)) {
                // Determina direzione di rimbalzo in base al muro.
                // Calcola la colonna precedente (prima del movimento) per
                // capire se il muro e' verticale (inversione X) o
                // orizzontale (inversione Y).
                int prevC = (int)((mine.pos.x - mine.vel.x) / TILE_SIZE);
                if (maze.isWall(prevC, mr)) {
                    // Muro orizzontale: inverti Y
                    mine.vel.y = -mine.vel.y;
                } else {
                    // Muro verticale: inverti X
                    mine.vel.x = -mine.vel.x;
                }
                // Sposta fuori dal muro
                mine.pos += mine.vel;
                audio.playSound(SOUND_MINE_BOUNCE);
            }
            // Rimbalzo sui bordi della finestra
            if (mine.pos.x < 16) { mine.pos.x = 16; mine.vel.x = -mine.vel.x; audio.playSound(SOUND_MINE_BOUNCE); }
            if (mine.pos.x > WINDOW_WIDTH - 16) { mine.pos.x = WINDOW_WIDTH - 16; mine.vel.x = -mine.vel.x; audio.playSound(SOUND_MINE_BOUNCE); }
            if (mine.pos.y < UI_HEIGHT + 16) { mine.pos.y = UI_HEIGHT + 16; mine.vel.y = -mine.vel.y; audio.playSound(SOUND_MINE_BOUNCE); }
            if (mine.pos.y > WINDOW_HEIGHT - 16) { mine.pos.y = WINDOW_HEIGHT - 16; mine.vel.y = -mine.vel.y; audio.playSound(SOUND_MINE_BOUNCE); }

            // Controlla collisione con nemici
            for (auto& enemy : enemies) {
                if (enemy.isDead()) continue;
                float dx = mine.pos.x - enemy.getPixelPos().x;
                float dy = mine.pos.y - enemy.getPixelPos().y;
                if (dx * dx + dy * dy < 500) {
                    // Uccide il nemico!
                    enemy.takeDamage(999);
                    player.addScore(5000);
                    audio.playSound(SOUND_ENEMY_DEATH);
                    audio.playSound(SOUND_ENEMY_EXPLODE);
                    audio.playSound(SOUND_BLOOD_SPLAT);
                    // Esplosione + sangue
                    for (int i = 0; i < 25; i++)
                        particles.push_back({enemy.getPixelPos(), {(float)(rand()%10-5), (float)(rand()%10-5)}, sf::Color(150+rand()%50, 0, 0), 35, 35});
                    for (int i = 0; i < 10; i++)
                        particles.push_back({enemy.getPixelPos(), {(float)(rand()%12-6), (float)(rand()%12-6)}, sf::Color(200, 100, 50), 25, 25});
                    bloodStains.push_back({enemy.getPixelPos(), 300, 300, 8.f + (rand()%6), sf::Color(120, 0, 0, 200)});
                    // Esplosione mina
                    for (int i = 0; i < 20; i++)
                        particles.push_back({mine.pos, {(float)(rand()%12-6), (float)(rand()%12-6)}, sf::Color(255, 200, 50), 30, 30});
                    mine.active = false;
                    mine.bouncing = false;
                    break;
                }
            }
            // FIX: controlla collisione anche con il mini-boss (se presente e vivo)
            // Prima la mina non collideva col mini-boss, ora sì. La mina fa
            // 25 danni al mini-boss (non 999 come i nemici normali, altrimenti
            // lo uccide con un solo colpo). Il mini-boss ha 18-35 HP, quindi
            // servono 1-2 mine per ucciderlo (bilanciato).
            if (mine.active && mine.bouncing && miniBoss && !miniBoss->isDead()) {
                float dx = mine.pos.x - miniBoss->getPixelPos().x;
                float dy = mine.pos.y - miniBoss->getPixelPos().y;
                // Raggio collisione piu' largo del mini-boss (e' piu' grande)
                if (dx * dx + dy * dy < 800) {
                    // Danno al mini-boss (25 HP per mina)
                    miniBoss->takeDamage(25);
                    player.addScore(1000);
                    audio.playSound(SOUND_ENEMY_EXPLODE);
                    audio.playSound(SOUND_BLOOD_SPLAT);
                    // Esplosione + scintille dorate (mini-boss e' piu' resistente)
                    for (int i = 0; i < 30; i++)
                        particles.push_back({miniBoss->getPixelPos(),
                            {(float)(rand()%12-6), (float)(rand()%12-6)},
                            sf::Color(220, 160, 40), 35, 35});  // oro
                    for (int i = 0; i < 15; i++)
                        particles.push_back({miniBoss->getPixelPos(),
                            {(float)(rand()%14-7), (float)(rand()%14-7)},
                            sf::Color(200, 80, 80), 30, 30});  // rosso
                    // Esplosione mina
                    for (int i = 0; i < 20; i++)
                        particles.push_back({mine.pos, {(float)(rand()%12-6), (float)(rand()%12-6)}, sf::Color(255, 200, 50), 30, 30});
                    mine.active = false;
                    mine.bouncing = false;
                }
            }

            // Timer: dopo 8 secondi senza colpire nemici, scompare
            if (mine.bouncing) {
                if (mine.bounceTimer > 16) mine.bounceTimer -= 16;
                else mine.bounceTimer = 0;
                if (mine.bounceTimer == 0) {
                    // Scompare con piccola esplosione
                    for (int i = 0; i < 10; i++)
                        particles.push_back({mine.pos, {(float)(rand()%6-3), (float)(rand()%6-3)}, sf::Color(180, 150, 50), 20, 20});
                    mine.active = false;
                    mine.bouncing = false;
                }
            }
        }

#ifdef TEST_MODE_FEATURE
        // --- TEST MODE: salta direttamente al boss premendo barra spaziatrice ---
        // Se testModeEnabled e' true e il player preme Space, salta tutta la
        // fase di esplorazione del labirinto e va dritto al boss del livello
        // corrente. Debounce: salta solo alla pressione (non ogni frame).
        if (testModeEnabled) {
            bool spaceNow = sf::Keyboard::isKeyPressed(sf::Keyboard::Space);
            if (spaceNow && !testSkipKeyPressed) {
                // Salta al boss: same behaviour as raccogliere tutti i tesori.
                // Inoltre dà un po' di munizioni al player per essere sicuro
                // che possa combattere (5 colpi come le armi del boss room).
                startBossFight();
            }
            testSkipKeyPressed = spaceNow;
        }
#endif
    }
    // --- Logica STATE_BOSS: stanza del boss ---
    else if (state == STATE_BOSS) {
        // freeMovement=true: il giocatore si muove liberamente (non snap-to-grid)
        player.update(maze, true, particles);
        if (numPlayers == 2) player2.update(maze, true, particles);
        boss->update(player.getPixelPos().x, player.getPixelPos().y, bossProjectiles);

        // --- Update mina nella stanza del boss ---
        if (mine.active && mine.inBossRoom) {
            mine.pulse += 0.016f;
            if (!mine.bouncing) {
                // Collisione con player1 OR player2 (entrambi possono
                // raccogliere la mina nella stanza del boss). Prima il
                // pickup controllava solo player1, causando il bug in cui
                // in 2P il player2 non riusciva a raccogliere la mina.
                float dx1 = player.getPixelPos().x - mine.pos.x;
                float dy1 = player.getPixelPos().y - mine.pos.y;
                bool p1Hit = (dx1 * dx1 + dy1 * dy1 < 400);
                bool p2Hit = false;
                if (numPlayers == 2) {
                    float dx2 = player2.getPixelPos().x - mine.pos.x;
                    float dy2 = player2.getPixelPos().y - mine.pos.y;
                    p2Hit = (dx2 * dx2 + dy2 * dy2 < 400);
                }
                if (p1Hit || p2Hit) {
                    mine.bouncing = true;
                    mine.bounceTimer = 30000;
                    float angle = (rand() % 360) * (float)M_PI / 180.f;
                    mine.vel.x = cosf(angle) * 6.f;
                    mine.vel.y = sinf(angle) * 6.f;
                    audio.playSound(SOUND_MINE_BOUNCE);
                }
            } else {
                mine.rotation += 0.08f;
                mine.pos += mine.vel;
                // Rimbalzo sui bordi della stanza del boss
                if (mine.pos.x < 30) { mine.pos.x = 30; mine.vel.x = -mine.vel.x; audio.playSound(SOUND_MINE_BOUNCE); }
                if (mine.pos.x > WINDOW_WIDTH - 30) { mine.pos.x = WINDOW_WIDTH - 30; mine.vel.x = -mine.vel.x; audio.playSound(SOUND_MINE_BOUNCE); }
                if (mine.pos.y < UI_HEIGHT + 30) { mine.pos.y = UI_HEIGHT + 30; mine.vel.y = -mine.vel.y; audio.playSound(SOUND_MINE_BOUNCE); }
                if (mine.pos.y > WINDOW_HEIGHT - 30) { mine.pos.y = WINDOW_HEIGHT - 30; mine.vel.y = -mine.vel.y; audio.playSound(SOUND_MINE_BOUNCE); }
                // Collisione con il boss
                float dx = mine.pos.x - boss->getPos().x;
                float dy = mine.pos.y - boss->getPos().y;
                if (dx * dx + dy * dy < (boss->getSize() / 2) * (boss->getSize() / 2)) {
                    int dmg = boss->getMaxHealth() * 30 / 100;  // 30% HP massimo
                    if (dmg < 1) dmg = 1;
                    boss->takeDamage(dmg);
                    audio.playSound(SOUND_BOSS_HIT);
                    audio.playSound(SOUND_ENEMY_EXPLODE);
                    for (int i = 0; i < 20; i++)
                        particles.push_back({mine.pos, {(float)(rand()%12-6), (float)(rand()%12-6)}, sf::Color(255, 200, 50), 30, 30});
                    mine.active = false;
                    mine.bouncing = false;
                }
                // FIX: controlla collisione anche con i nemici normali residui
                // (nella stanza del boss potrebbero esserci nemici provenienti
                // dal portale o residui). Prima la mina li ignorava.
                if (mine.active && mine.bouncing) {
                    for (auto& enemy : enemies) {
                        if (enemy.isDead()) continue;
                        float edx = mine.pos.x - enemy.getPixelPos().x;
                        float edy = mine.pos.y - enemy.getPixelPos().y;
                        if (edx * edx + edy * edy < 500) {
                            enemy.takeDamage(999);
                            player.addScore(5000);
                            audio.playSound(SOUND_ENEMY_DEATH);
                            audio.playSound(SOUND_ENEMY_EXPLODE);
                            audio.playSound(SOUND_BLOOD_SPLAT);
                            for (int i = 0; i < 25; i++)
                                particles.push_back({enemy.getPixelPos(),
                                    {(float)(rand()%10-5), (float)(rand()%10-5)},
                                    sf::Color(150+rand()%50, 0, 0), 35, 35});
                            bloodStains.push_back({enemy.getPixelPos(), 300, 300,
                                8.f + (rand()%6), sf::Color(120, 0, 0, 200)});
                            for (int i = 0; i < 20; i++)
                                particles.push_back({mine.pos,
                                    {(float)(rand()%12-6), (float)(rand()%12-6)},
                                    sf::Color(255, 200, 50), 30, 30});
                            mine.active = false;
                            mine.bouncing = false;
                            break;
                        }
                    }
                }
                // FIX: controlla collisione anche con il mini-boss (se presente)
                // nella stanza del boss. Il mini-boss ha 18-35 HP, la mina fa
                // 25 danni (1-2 mine per ucciderlo).
                if (mine.active && mine.bouncing && miniBoss && !miniBoss->isDead()) {
                    float mdx = mine.pos.x - miniBoss->getPixelPos().x;
                    float mdy = mine.pos.y - miniBoss->getPixelPos().y;
                    if (mdx * mdx + mdy * mdy < 800) {
                        miniBoss->takeDamage(25);
                        player.addScore(1000);
                        audio.playSound(SOUND_ENEMY_EXPLODE);
                        audio.playSound(SOUND_BLOOD_SPLAT);
                        for (int i = 0; i < 30; i++)
                            particles.push_back({miniBoss->getPixelPos(),
                                {(float)(rand()%12-6), (float)(rand()%12-6)},
                                sf::Color(220, 160, 40), 35, 35});
                        for (int i = 0; i < 15; i++)
                            particles.push_back({miniBoss->getPixelPos(),
                                {(float)(rand()%14-7), (float)(rand()%14-7)},
                                sf::Color(200, 80, 80), 30, 30});
                        for (int i = 0; i < 20; i++)
                            particles.push_back({mine.pos,
                                {(float)(rand()%12-6), (float)(rand()%12-6)},
                                sf::Color(255, 200, 50), 30, 30});
                        mine.active = false;
                        mine.bouncing = false;
                    }
                }
                // Timer
                if (mine.bouncing) {
                    if (mine.bounceTimer > 16) mine.bounceTimer -= 16;
                    else mine.bounceTimer = 0;
                    if (mine.bounceTimer == 0) {
                        for (int i = 0; i < 10; i++)
                            particles.push_back({mine.pos, {(float)(rand()%6-3), (float)(rand()%6-3)}, sf::Color(180, 150, 50), 20, 20});
                        mine.active = false;
                        mine.bouncing = false;
                    }
                }
            }
        }

        // --- Update invincibilità player1 nella stanza del boss ---
        if (playerInvincibleTimer > 0) {
            if (playerInvincibleTimer > 16) playerInvincibleTimer -= 16;
            else playerInvincibleTimer = 0;
            if (playerInvincibleTimer > 0) {
                float dx = player.getPixelPos().x - boss->getPos().x;
                float dy = player.getPixelPos().y - boss->getPos().y;
                if (dx * dx + dy * dy < (boss->getSize() / 2) * (boss->getSize() / 2)) {
                    boss->takeDamage(1);
                    audio.playSound(SOUND_BOSS_HIT);
                }
            }
        }
        // --- Update invincibilità player2 nella stanza del boss ---
        if (player2InvincibleTimer > 0) {
            if (player2InvincibleTimer > 16) player2InvincibleTimer -= 16;
            else player2InvincibleTimer = 0;
            if (player2InvincibleTimer > 0) {
                float dx = player2.getPixelPos().x - boss->getPos().x;
                float dy = player2.getPixelPos().y - boss->getPos().y;
                if (dx * dx + dy * dy < (boss->getSize() / 2) * (boss->getSize() / 2)) {
                    boss->takeDamage(1);
                    audio.playSound(SOUND_BOSS_HIT);
                }
            }
        }

        // --- Update scettro/fulmini nella stanza del boss ---
        if (scepter.active && !scepter.triggered) {
            scepter.pulse += 0.016f;
            scepter.bobOffset = sinf(scepter.pulse * 3.f) * 4.f;
            float dx1 = player.getPixelPos().x - scepter.pos.x;
            float dy1 = player.getPixelPos().y - scepter.pos.y;
            bool p1Hit = (dx1 * dx1 + dy1 * dy1 < 500);
            bool p2Hit = false;
            if (numPlayers == 2) {
                float dx2 = player2.getPixelPos().x - scepter.pos.x;
                float dy2 = player2.getPixelPos().y - scepter.pos.y;
                p2Hit = (dx2 * dx2 + dy2 * dy2 < 500);
            }
            if (p1Hit || p2Hit) {
                scepter.active = false;
                scepter.triggered = true;
                scepterUsed = true;
                scepter.lightningsLeft = 5;
                scepter.lightningTimer = 200;
                audio.playSound(SOUND_SCEPTER_PICKUP);  // "oh-oh-oh" magico evocativo
                // Avvia il jingle epico DEDICATO dello scettro (arcano, ~7s).
                // Su un canale SEPARATO, non interrompe la musica di gioco.
                audio.playEpicMusic(TRACK_EPIC_SCEPTER);
                for (int i = 0; i < 15; i++)
                    particles.push_back({scepter.pos, {(float)(rand()%8-4), (float)(rand()%8-4)},
                        sf::Color(180, 200, 255), 35, 35});
            }
        }
        if (scepter.triggered && scepter.lightningsLeft > 0) {
            if (scepter.lightningTimer > 16) scepter.lightningTimer -= 16;
            else scepter.lightningTimer = 0;
            if (scepter.lightningTimer == 0) {
                float lx = 100.f + (float)(rand() % (WINDOW_WIDTH - 200));
                float ly = UI_HEIGHT + 100.f + (rand() % (WINDOW_HEIGHT - UI_HEIGHT - 200));
                // Crea fulmine che attraversa tutto lo schermo (verticale
                // o diagonale) con zigzag pre-calcolato.
                lightnings.push_back(createFullScreenLightning(sf::Vector2f(lx, ly)));
                audio.playSound(SOUND_LIGHTNING);
                // Flash ridotto a 120ms per non affaticare gli occhi.
                screenFlashTimer = 120;
                scepter.lightningsLeft--;
                if (scepter.lightningsLeft > 0) scepter.lightningTimer = 3000;
                // --- Danno al boss lungo TUTTO il percorso del fulmine ---
                // Controlla se uno dei segmenti del zigzag attraversa il
                // boss. Se si', infligge 15% HP massimo. Inoltre controlla
                // anche il punto di impatto (boss->getSize()/2 raggio).
                const std::vector<sf::Vector2f>& pts =
                    lightnings.back().zigzagPoints;
                sf::Vector2f bpos = boss->getPos();
                float bossR = boss->getSize() / 2.f;
                bool bossHit = false;
                for (size_t i = 0; i + 1 < pts.size() && !bossHit; i++) {
                    sf::Vector2f p0 = pts[i];
                    sf::Vector2f p1 = pts[i + 1];
                    float segDx = p1.x - p0.x;
                    float segDy = p1.y - p0.y;
                    float segLen2 = segDx * segDx + segDy * segDy;
                    if (segLen2 < 0.001f) continue;
                    float t = ((bpos.x - p0.x) * segDx +
                               (bpos.y - p0.y) * segDy) / segLen2;
                    if (t < 0.f) t = 0.f;
                    if (t > 1.f) t = 1.f;
                    float projX = p0.x + segDx * t;
                    float projY = p0.y + segDy * t;
                    float ddx = bpos.x - projX;
                    float ddy = bpos.y - projY;
                    if (ddx * ddx + ddy * ddy < bossR * bossR) {
                        bossHit = true;
                    }
                }
                // Controlla anche il punto di impatto
                if (!bossHit) {
                    float dx = lx - bpos.x;
                    float dy = ly - bpos.y;
                    if (dx * dx + dy * dy < bossR * bossR) bossHit = true;
                }
                if (bossHit) {
                    // Danno al boss ridotto a 5% HP massimo (era 15%).
                    // Con 5 fulmini che attraversano tutto lo schermo e
                    // possono colpire il boss, 5% * 5 = 25% HP massimo totale.
                    // Prima era 15% * 5 = 75%, troppo alto (uccideva il boss
                    // quasi da solo solo con i fulmini). Ora e' bilanciato:
                    // il fulmine e' un supporto, non l'arma principale.
                    int dmg = boss->getMaxHealth() * 5 / 100;
                    if (dmg < 1) dmg = 1;
                    boss->takeDamage(dmg);
                    audio.playSound(SOUND_BOSS_HIT);
                    lightnings.back().hitBoss = true;
                }
                // --- Danno ai nemici (se ci sono) lungo il percorso ---
                // Anche nella stanza del boss potrebbero esserci nemici
                // residuali (es. se provenienti da portale). Il fulmine li
                // colpisce come in STATE_PLAYING.
                for (auto& enemy : enemies) {
                    if (enemy.isDead()) continue;
                    sf::Vector2f epos = enemy.getPixelPos();
                    bool hit = false;
                    for (size_t i = 0; i + 1 < pts.size() && !hit; i++) {
                        sf::Vector2f p0 = pts[i];
                        sf::Vector2f p1 = pts[i + 1];
                        float segDx = p1.x - p0.x;
                        float segDy = p1.y - p0.y;
                        float segLen2 = segDx * segDx + segDy * segDy;
                        if (segLen2 < 0.001f) continue;
                        float t = ((epos.x - p0.x) * segDx +
                                   (epos.y - p0.y) * segDy) / segLen2;
                        if (t < 0.f) t = 0.f;
                        if (t > 1.f) t = 1.f;
                        float projX = p0.x + segDx * t;
                        float projY = p0.y + segDy * t;
                        float ddx = epos.x - projX;
                        float ddy = epos.y - projY;
                        if (ddx * ddx + ddy * ddy < 900.f) hit = true;
                    }
                    if (!hit) {
                        float dx = epos.x - lx;
                        float dy = epos.y - ly;
                        if (dx * dx + dy * dy < 2500.f) hit = true;
                    }
                    if (hit) {
                        enemy.takeDamage(999);
                        player.addScore(3000);
                        audio.playSound(SOUND_ENEMY_DEATH);
                        audio.playSound(SOUND_BLOOD_SPLAT);
                        for (int i = 0; i < 20; i++)
                            particles.push_back({enemy.getPixelPos(), {(float)(rand()%10-5), (float)(rand()%10-5)},
                                sf::Color(150+rand()%50, 0, 0), 30, 30});
                        bloodStains.push_back({enemy.getPixelPos(), 300, 300, 8.f + (rand()%6), sf::Color(120, 0, 0, 200)});
                    }
                }
            }
        }
        for (auto& lt : lightnings) lt.life--;
        lightnings.erase(std::remove_if(lightnings.begin(), lightnings.end(),
            [](const Lightning& lt) { return lt.life <= 0; }), lightnings.end());

        // --- Aggiornamento proiettili boss ---
        // Gestione comportamenti speciali:
        //   * homingTimer > 0: il proiettile insegue il player ruotando
        //     gradualmente la direzione verso di lui. Quando il timer scende
        //     a 0 il proiettile continua dritto (perde l'effetto).
        //   * age: incrementato di 16 ms per frame, usato per animazioni
        //     (es. pulsazione fuoco).
        sf::Vector2f playerPos = player.getPixelPos();
        for (auto& proj : bossProjectiles) {
            if (!proj.active) continue;
            proj.age += 16;
            // --- Homing: ruota gradualmente verso il player ---
            if (proj.homingTimer > 0) {
                proj.homingTimer -= 16;
                if (proj.homingTimer < 0) proj.homingTimer = 0;
                float speed = sqrt(proj.dir.x * proj.dir.x + proj.dir.y * proj.dir.y);
                if (speed > 0.001f) {
                    // Vettore verso il player
                    float tx = playerPos.x - proj.pos.x;
                    float ty = playerPos.y - proj.pos.y;
                    float tlen = sqrt(tx*tx + ty*ty);
                    if (tlen > 0.001f) {
                        // Direzione corrente normalizzata
                        float cx = proj.dir.x / speed;
                        float cy = proj.dir.y / speed;
                        // Direzione target normalizzata
                        float txn = tx / tlen;
                        float tyn = ty / tlen;
                        // Interpolazione lineare verso il target (lerp factor 0.08)
                        // => curvatura morbida, non snap immediato
                        float lerp = 0.08f;
                        float nx = cx + (txn - cx) * lerp;
                        float ny = cy + (tyn - cy) * lerp;
                        // Rinormalizza e applica speed originaria
                        float nlen = sqrt(nx*nx + ny*ny);
                        if (nlen > 0.001f) {
                            proj.dir.x = (nx / nlen) * speed;
                            proj.dir.y = (ny / nlen) * speed;
                        }
                    }
                }
            }
            // --- Movimento standard ---
            proj.pos += proj.dir;
            if (proj.pos.x < 0 || proj.pos.x > WINDOW_WIDTH || proj.pos.y < UI_HEIGHT || proj.pos.y > WINDOW_HEIGHT) {
                proj.active = false;
            }
        }

        // --- Collisioni: proiettili giocatore vs boss ---
        // Hit box circolare: raggio = size/2 (il centro del boss)
        for (auto& proj : player.getProjectiles()) {
            if (!proj.active) continue;
            float dx = proj.pos.x - boss->getPos().x;
            float dy = proj.pos.y - boss->getPos().y;
            if (dx*dx + dy*dy < (boss->getSize()/2)*(boss->getSize()/2)) {
                boss->takeDamage(proj.power);
                proj.active = false;
                audio.playSound(SOUND_BOSS_HIT);
            }
        }

        // --- Collisioni: proiettili boss vs giocatore ---
        if (!player.isInvulnerable() && !player.isJumping()) {
            for (auto& proj : bossProjectiles) {
                if (!proj.active) continue;
                float dx = proj.pos.x - player.getPixelPos().x;
                float dy = proj.pos.y - player.getPixelPos().y;
                if (dx*dx + dy*dy < 600) {
                    proj.active = false;
                    int livesBefore = player.getLives();
                    player.takeDamage();
                    if (player.getLives() < livesBefore || player.getEnergy() < player.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                }
            }
            bossProjectiles.erase(std::remove_if(bossProjectiles.begin(), bossProjectiles.end(), [](const Projectile& p) { return !p.active; }), bossProjectiles.end());
        }

        // --- Raccolta armi della stanza boss ---
        // Soglia 1000 (sqrt ~31.6 px): distanza di "pickup".
        for (auto it = bossRoomWeapons.begin(); it != bossRoomWeapons.end(); ) {
            float dx = it->pos.x - player.getPixelPos().x;
            float dy = it->pos.y - player.getPixelPos().y;
            if (dx*dx + dy*dy < 1000) { player.collectWeapon(it->w); audio.playSound(SOUND_WEAPON_PICKUP); it = bossRoomWeapons.erase(it); } else ++it;
        }

        // --- Raccolta bonus scarpe alate (speed boost) ---
        // In 2P ci sono 2 paia di scarpe (speedBoots owner=1 per player1,
        // speedBoots2 owner=2 per player2). Ogni player puo' raccogliere
        // solo le proprie scarpe (owner corrispondente). In 1P c'e' solo
        // speedBoots con owner=0 (libera, raccoglibile da player1).
        static float bootsAnimTime = 0.f;
        bootsAnimTime += 16.f;
        // --- SpeedBoots (player1 o 1P) ---
        if (speedBoots.active) {
            speedBoots.bobOffset = sinf(bootsAnimTime * 0.005f) * 5.f;
            // Player1 raccoglie se owner==0 (1P) o owner==1 (2P)
            if (speedBoots.owner == 0 || speedBoots.owner == 1) {
                float dx = speedBoots.pos.x - player.getPixelPos().x;
                float dy = speedBoots.pos.y - player.getPixelPos().y;
                if (dx*dx + dy*dy < 1000) {
                    player.activateSpeedBoost();
                    speedBoots.active = false;
                    audio.playSound(SOUND_TREASURE);
                }
            }
        }
        // --- SpeedBoots2 (player2 in 2P) ---
        if (numPlayers == 2 && speedBoots2.active) {
            speedBoots2.bobOffset = sinf(bootsAnimTime * 0.005f + 1.f) * 5.f;
            // Solo player2 con owner==2 raccoglie
            if (speedBoots2.owner == 2) {
                float dx2 = speedBoots2.pos.x - player2.getPixelPos().x;
                float dy2 = speedBoots2.pos.y - player2.getPixelPos().y;
                if (dx2*dx2 + dy2*dy2 < 1000) {
                    player2.activateSpeedBoost();
                    speedBoots2.active = false;
                    audio.playSound(SOUND_TREASURE);
                }
            }
        }

        // --- Raccolta armi player2 (solo se 2 giocatori) ---
        if (numPlayers == 2) {
            for (auto it = bossRoomWeapons.begin(); it != bossRoomWeapons.end(); ) {
                float dx = it->pos.x - player2.getPixelPos().x;
                float dy = it->pos.y - player2.getPixelPos().y;
                if (dx*dx + dy*dy < 1000) { player2.collectWeapon(it->w); audio.playSound(SOUND_WEAPON_PICKUP); it = bossRoomWeapons.erase(it); } else ++it;
            }

            // --- Collisioni player2 vs boss ---
            for (auto& proj : player2.getProjectiles()) {
                if (!proj.active) continue;
                float dx = proj.pos.x - boss->getPos().x;
                float dy = proj.pos.y - boss->getPos().y;
                if (dx*dx + dy*dy < (boss->getSize()/2)*(boss->getSize()/2)) {
                    boss->takeDamage(proj.power);
                    proj.active = false;
                    audio.playSound(SOUND_BOSS_HIT);
                }
            }

            // --- Collisioni proiettili boss vs player2 ---
            if (!player2.isInvulnerable() && !player2.isJumping()) {
                for (auto& proj : bossProjectiles) {
                    if (!proj.active) continue;
                    float dx = proj.pos.x - player2.getPixelPos().x;
                    float dy = proj.pos.y - player2.getPixelPos().y;
                    if (dx*dx + dy*dy < 600) {
                        proj.active = false;
                        int livesBefore = player2.getLives();
                        player2.takeDamage();
                        if (player2.getLives() < livesBefore || player2.getEnergy() < player2.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                    }
                }
            }
        }

        // Se ANCHE SOLO UN giocatore ha finito le munizioni e non ci sono armi
        // a terra, ne spawniamo altre 3 (evita soft-lock).
        bool p1Empty = player.getCurrentWeapon().ammo <= 0;
        bool p2Empty = (numPlayers == 2) ? (player2.getCurrentWeapon().ammo <= 0) : false;
        if ((p1Empty || p2Empty) && bossRoomWeapons.empty()) {
            spawnBossRoomWeapons();
        }
        // In 1P: GAME OVER quando il player 1 muore.
        // In 2P: GAME OVER quando ENTRAMBI i giocatori sono morti (uno dei due
        // puo' continuare a giocare da solo finche' ha vite).
        if (player.getLives() <= 0
            && (numPlayers == 1 || player2.getLives() <= 0)) {
            if (continuesLeft > 0) {
                state = STATE_CONTINUES; diedInBoss = true;
                continuesTimer = 10; continuesTimerMs = 0; continuesChoice = true;
            } else state = STATE_LOSE;
        }
#ifdef TEST_MODE_FEATURE
        // --- TEST MODE: salta al livello successivo premendo barra spaziatrice ---
        // Se testModeEnabled e' true e il player preme Space, il boss muore
        // istantaneamente. Verra' poi il normale flusso boss->isDead() a far
        // avanzare il livello. Debounce: salta solo alla pressione.
        if (testModeEnabled) {
            bool spaceNow = sf::Keyboard::isKeyPressed(sf::Keyboard::Space);
            if (spaceNow && !testSkipKeyPressed) {
                // Uccidi il boss istantaneamente: takeDamage con un valore
                // molto alto (> maxHealth di qualsiasi boss). maxHealth del
                // boss piu' grosso (livello 10) e' 50+10*20=250, usiamo 9999.
                boss->takeDamage(9999);
            }
            testSkipKeyPressed = spaceNow;
        }
#endif
        if (boss->isDead()) {
            audio.playSound(SOUND_BOSS_DEATH);
            player.addLife(); // Guadagni una vita dopo aver sconfitto il boss
            currentLevel++;

            // Modalita' story: vittoria dopo STORY_LEVELS_COUNT livelli
            // (boss dell'ultimo livello morto -> currentLevel superiore al max)
            if (gameMode == MODE_STORY && currentLevel > STORY_LEVELS_COUNT) {
                state = STATE_WIN_STORY;
                audio.stopMusic();
            } else {
                startLevel(currentLevel);
            }
        }
    } else if (state == STATE_WIN_STORY) {
        // --- Schermata vittoria: fuochi d'artificio ---
        // Ogni ~10 frame (1/6 di secondo) genera un fuoco d'artificio nuovo
        if (rand() % 10 == 0) spawnFirework();
        // Aggiorna fuochi: gravita' (y += 0.1) e decremento vita
        for (auto& fw : fireworks) {
            fw.pos += fw.vel;
            fw.vel.y += 0.1f;
            fw.life--;
        }
        // Rimuove i fuochi esauriti
        fireworks.erase(std::remove_if(fireworks.begin(), fireworks.end(), [](const Firework& fw) { return fw.life <= 0; }), fireworks.end());
    }
    // --- Logica STATE_CONTINUES: conto alla rovescia ---
    else if (state == STATE_CONTINUES) {
        continuesTimerMs += 16;
        if (continuesTimerMs >= 1000) {
            continuesTimerMs = 0;
            continuesTimer--;
            if (continuesTimer <= 0) {
                // Tempo scaduto: game over
                state = STATE_LOSE;
            }
        }
    }

    // --- Aggiornamento particelle (comune a tutti gli stati) ---
    for (auto& p : particles) {
        p.pos += p.vel;
        p.life--;
    }
    particles.erase(std::remove_if(particles.begin(), particles.end(), [](const Particle& p) { return p.life <= 0; }), particles.end());
}

// ---------------------------------------------------------------------------
// spawnFirework: genera un fuoco d'artificio esploso.
// Crea 30 particelle disposte a cerchio (angoli a 12° l'una) con velocita'
// radiale 4 px/frame, colore casuale fra 6 opzioni. La vita e' di 60 frame
// (1 sec a 60 FPS).
// ---------------------------------------------------------------------------
void Game::spawnFirework() {
    float x = (float)(100 + rand() % (WINDOW_WIDTH - 200));
    float y = (float)(100 + rand() % (WINDOW_HEIGHT / 2));  // solo meta' alta dello schermo
    sf::Color colors[] = {sf::Color::Red, sf::Color::Green, sf::Color::Blue, sf::Color::Yellow, sf::Color::Magenta, sf::Color::Cyan};
    sf::Color col = colors[rand() % 6];
    for(int i=0; i<30; i++) {
        float angle = i * ((float)M_PI * 2.f / 30.f);  // 30 particelle uniformi su 360°
        fireworks.push_back({sf::Vector2f(x, y), sf::Vector2f(cosf(angle)*4, sinf(angle)*4), col, 60});
    }
}

// ---------------------------------------------------------------------------
// drawMagicScepter: disegna lo scettro magico in stile "Gandalf il Grigio"
// (dal Signore degli Anelli).
//
// Caratteristiche del bastone di Gandalf:
//   * Bastone LUNGO di legno intagliato (grigio-marrone scuro, ruvido)
//   * Gemma cristallina in cima tenuta da FBI/raffiche metalliche
//   * La gemma brilla di luce bianco-azzurra (luce magica)
//   * Impugnatura lavorata con nodi del legno (grip texturizzato)
//   * Lunghezza totale ~36px (gemma inclusa), molto piu' imponente
//     del vecchio bastoncino 18px che sembrava un fiammifero.
//
// Il rendering e' sviluppato con primitive SFML:
//   1. Aura magica pulsante (azzurro chiaro) attorno alla gemma
//   2. Bastone: rettangolo verticale lungo con texture "legno grezzo"
//      ottenuta con piu' rettangoli sfalsati di toni di grigio-marrone
//   3. Nodi del legno: piccoli cerchi scuri lungo il bastone (effetto legno)
//   4. FBI/gabbia metallica che trattiene la gemma: 4 piccoli raggi
//      dorati che partono dalla cima del bastone verso la gemma
//   5. Gemma cristallina: cerchio grande azzurro-bianco brillante con
//      outline dorata (cornice metallica), nucleo bianco luminoso
//   6. Impugnatura: fascia dorata (anello metallico) + cuoio scuro
//      avvolto attorno al bastone (rettangoli sfalsati)
//   7. Glow raggio di luce dalla gemma (cone di luce verso il basso)
//
// (sx, sy) e' il centro del bastone (gemma ~sy-18, impugnatura ~sy+12).
// sPulse e' il fattore di pulsazione (>1 = piu' grande per l'aura).
// ---------------------------------------------------------------------------
void Game::drawMagicScepter(sf::RenderTarget& target, float sx, float sy, float sPulse) {
    // Palette 16 colori OBBLIGATORIA (dal prompt originale del gioco):
    // (12,12,12) (48,40,36) (96,80,72) (160,128,112)
    // (200,180,160) (120,140,160) (80,120,100) (40,80,60)
    // (160,40,40) (200,80,80) (220,160,40) (200,200,80)
    // (120,200,200) (80,160,220) (160,120,200) (240,240,240)
    // Lo scettro usa ESATTAMENTE questi colori per coerenza visiva con
    // gli sprite PNG generati con la stessa palette.
    const sf::Color COL_BLACK    (12, 12, 12);        // outline profondo
    const sf::Color COL_DARK_WOOD(48, 40, 36);        // legno molto scuro
    const sf::Color COL_MID_WOOD (96, 80, 72);        // legno medio
    const sf::Color COL_LIT_WOOD (160, 128, 112);     // legno illuminato
    const sf::Color COL_PALE     (200, 180, 160);     // venatura chiara
    const sf::Color COL_GOLD     (220, 160, 40);      // oro (incastonatura)
    const sf::Color COL_GEM       (80, 160, 220);      // gemma azzurra
    const sf::Color COL_WHITE    (240, 240, 240);     // nucleo bianco
    const sf::Color COL_SPARK    (200, 200, 80);      // scintille gialle
    const sf::Color COL_PURPLE   (160, 120, 200);     // aura magica (variante)

    // --- Aura magica pulsante attorno alla gemma ---
    // Aura esterna grande: gemma azzurra semitrasparente
    float auraR = 22.f * sPulse;
    sf::CircleShape scepterAura(auraR);
    scepterAura.setFillColor(sf::Color(COL_GEM.r, COL_GEM.g, COL_GEM.b, 55));
    scepterAura.setPosition(sx - auraR, sy - 18.f - auraR);
    target.draw(scepterAura);
    // Aura interna piu' intensa (bianca-azzurra)
    float auraR2 = 12.f * sPulse;
    sf::CircleShape scepterAura2(auraR2);
    scepterAura2.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 80));
    scepterAura2.setPosition(sx - auraR2, sy - 18.f - auraR2);
    target.draw(scepterAura2);

    // --- Bastone lungo (legno grezzo) ---
    // 3 strati per texture legno: base medio, venatura chiara, ombra scura.
    // Tutti i colori sono della palette 16 colori.
    // Strato base: legno medio (96,80,72)
    sf::RectangleShape staffBase(sf::Vector2f(4.f, 32.f));
    staffBase.setFillColor(COL_MID_WOOD);
    staffBase.setOutlineThickness(0.5f);
    staffBase.setOutlineColor(COL_BLACK);
    staffBase.setPosition(sx - 2.f, sy - 4.f);
    target.draw(staffBase);
    // Strato chiaro (venatura del legno) - 160,128,112
    sf::RectangleShape staffVein(sf::Vector2f(1.2f, 32.f));
    staffVein.setFillColor(COL_LIT_WOOD);
    staffVein.setPosition(sx - 1.5f, sy - 4.f);
    target.draw(staffVein);
    // Strato scuro (ombra venatura) - 48,40,36
    sf::RectangleShape staffShade(sf::Vector2f(0.8f, 32.f));
    staffShade.setFillColor(COL_DARK_WOOD);
    staffShade.setPosition(sx + 0.8f, sy - 4.f);
    target.draw(staffShade);

    // --- Nodi del legno (effetto texture ruvida) ---
    // 3 nodi scuri lungo il bastone per dare "carattere" di legno grezzo
    for (int n = 0; n < 3; n++) {
        float ny = sy - 2.f + n * 11.f;
        sf::CircleShape knot(1.2f);
        knot.setFillColor(COL_DARK_WOOD);
        knot.setPosition(sx - 1.2f, ny);
        target.draw(knot);
        // Highlight del nodo (effetto 3D) - legno illuminato
        sf::CircleShape knotHigh(0.5f);
        knotHigh.setFillColor(COL_PALE);
        knotHigh.setPosition(sx - 0.8f, ny - 0.3f);
        target.draw(knotHigh);
    }

    // --- FBI/gabbia metallica che trattiene la gemma ---
    // 4 raggi dorati che partono dalla cima del bastone verso la gemma,
    // simulando le "rifle" metalliche che tengono il cristallo (come nel
    // bastone di Gandalf nei film di Peter Jackson).
    for (int i = 0; i < 4; i++) {
        float angle = i * ((float)M_PI / 2.f) + ((float)M_PI / 4.f);  // 45, 135, 225, 315°
        // Posizione di partenza: cima del bastone (sx, sy-4)
        // Posizione di arrivo: lati della gemma (sx+/-5, sy-18+/-5)
        // Disegna il raggio come piccolo rettangolo inclinato
        sf::RectangleShape prong(sf::Vector2f(1.2f, 16.f));
        prong.setFillColor(COL_GOLD);
        prong.setOutlineThickness(0.3f);
        prong.setOutlineColor(COL_DARK_WOOD);
        prong.setPosition(sx - 0.6f, (sy - 4.f) - 16.f);
        float rotDeg = (angle - (float)M_PI / 2.f) * 180.f / (float)M_PI;
        prong.rotate(rotDeg);
        target.draw(prong);
    }

    // --- Cornice metallica dorata attorno alla gemma (anello) ---
    // Un anello dorato alla base della gemma (dove il cristallo si inserisce
    // nel bastone). Da' il senso di "gemma incastonata" come negli anelli.
    sf::CircleShape gemBase(5.5f);
    gemBase.setFillColor(COL_GOLD);
    gemBase.setOutlineThickness(1.f);
    gemBase.setOutlineColor(COL_DARK_WOOD);
    gemBase.setPosition(sx - 5.5f, sy - 18.f - 5.5f);
    target.draw(gemBase);

    // --- Gemma cristallina luminosa (centro del bastone di Gandalf) ---
    // Gemma grande (6px di raggio, era 4) per renderla visibile e "magica".
    // Colore gemma azzurra della palette (80,160,220).
    float gemR = 6.f * sPulse;
    sf::CircleShape gem(gemR);
    gem.setFillColor(COL_GEM);
    gem.setOutlineThickness(1.2f);
    gem.setOutlineColor(COL_GOLD);
    gem.setPosition(sx - gemR, sy - 18.f - gemR);
    target.draw(gem);

    // --- Nucleo bianco luminoso della gemma (centro) ---
    // Piccolo nucleo bianco pulsante: da' il senso di "luce interna"
    // come la gemma di Gandalf che brilla nel buio.
    float coreR = 2.5f * sPulse;
    sf::CircleShape gemCore(coreR);
    gemCore.setFillColor(COL_WHITE);
    gemCore.setPosition(sx - coreR, sy - 18.f - coreR);
    target.draw(gemCore);
    // Riflesso "specchiato" (piccolo puntino bianco in alto a sinistra)
    sf::CircleShape gemSpec(0.8f);
    gemSpec.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 220));
    gemSpec.setPosition(sx - 2.f, sy - 18.f - 3.f);
    target.draw(gemSpec);

    // --- Raggi di luce dalla gemma (4 raggi verso l'esterno) ---
    // Simula la luce magica che emana dal cristallo. Colore bianco-azzurro.
    for (int i = 0; i < 4; i++) {
        float angle = i * ((float)M_PI / 2.f) + sPulse * 0.3f;  // rotazione lenta
        float rayLen = 10.f * sPulse;
        sf::RectangleShape ray(sf::Vector2f(1.f, rayLen));
        ray.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 120));
        ray.setOrigin(0.5f, rayLen);
        ray.setPosition(sx, sy - 18.f);
        ray.setRotation(angle * 180.f / (float)M_PI - 90.f);
        target.draw(ray);
    }

    // --- Impugnatura (grip) ---
    // Fascia dorata (anello metallico) + cuoio scuro avvolto.
    // Posizione: parte bassa del bastone (sy + 18.f).
    // 1. Anello metallico superiore (oro)
    sf::RectangleShape gripTop(sf::Vector2f(6.f, 1.5f));
    gripTop.setFillColor(COL_GOLD);
    gripTop.setOutlineThickness(0.4f);
    gripTop.setOutlineColor(COL_DARK_WOOD);
    gripTop.setPosition(sx - 3.f, sy + 16.f);
    target.draw(gripTop);
    // 2. Cuoio avvolto (3 strisce) - legno scuro
    for (int i = 0; i < 3; i++) {
        sf::RectangleShape leather(sf::Vector2f(5.5f, 1.5f));
        leather.setFillColor(COL_DARK_WOOD);
        leather.setOutlineThickness(0.2f);
        leather.setOutlineColor(COL_BLACK);
        leather.setPosition(sx - 2.75f, sy + 18.f + i * 1.8f);
        target.draw(leather);
    }
    // 3. Anello metallico inferiore (oro)
    sf::RectangleShape gripBot(sf::Vector2f(6.f, 1.5f));
    gripBot.setFillColor(COL_GOLD);
    gripBot.setOutlineThickness(0.4f);
    gripBot.setOutlineColor(COL_DARK_WOOD);
    gripBot.setPosition(sx - 3.f, sy + 24.f);
    target.draw(gripBot);

    // --- Ombra del bastone sul pavimento ---
    // Da' profondita' e ancoraggio visivo al bastone.
    sf::CircleShape shadow(4.f);
    shadow.setFillColor(sf::Color(COL_BLACK.r, COL_BLACK.g, COL_BLACK.b, 80));
    shadow.setScale(1.5f, 0.5f);
    shadow.setPosition(sx - 4.f, sy + 28.f);
    target.draw(shadow);
}

// ---------------------------------------------------------------------------
// generateLightningPath: genera i punti zigzag di un fulmine che parte da
// startPos (alto) e arriva a endPos (punto di impatto, basso).
//
// Il fulmine e' composto da `numSegs` segmenti. Tra un segmento e l'altro
// c'e' un'oscillazione casuale (jitter) per dare l'effetto "saetta zigzag".
// I punti sono pre-calcolati una tantum e memorizzati in `zigzagPoints`
// perche' il rendering sia stabile (non fluttua ad ogni frame).
//
// Il primo punto e' startPos, l'ultimo e' endPos. Quindi numSegs segmenti
// corrispondono a numSegs+1 punti.
// ---------------------------------------------------------------------------
std::vector<sf::Vector2f> Game::generateLightningPath(sf::Vector2f startPos,
                                                      sf::Vector2f endPos,
                                                      int numSegs, float jitter) {
    std::vector<sf::Vector2f> points;
    points.push_back(startPos);
    float dx = endPos.x - startPos.x;
    float dy = endPos.y - startPos.y;
    for (int i = 1; i < numSegs; i++) {
        float t = (float)i / (float)numSegs;
        // Posizione interpolata linearmente tra start ed end
        float px = startPos.x + dx * t;
        float py = startPos.y + dy * t;
        // Aggiungi jitter perpendicolare alla direzione principale
        // Per un fulmine prevalentemente verticale, il jitter e' su X.
        // Per un fulmine diagonale, il jitter e' perpendicolare alla direzione.
        float dirLen = sqrtf(dx * dx + dy * dy);
        if (dirLen > 0.001f) {
            // Vettore perpendicolare: (-dy/dirLen, dx/dirLen)
            float perpX = -dy / dirLen;
            float perpY =  dx / dirLen;
            // Jitter casuale: ridotto agli estremi (inizio e fine) per
            // mantenere il fulmine ancorato a start/end
            float edgeFade = sinf(t * (float)M_PI);  // 0 agli estremi, 1 al centro
            float jit = ((rand() % 200) - 100) / 100.f * jitter * edgeFade;
            px += perpX * jit;
            py += perpY * jit;
        }
        points.push_back(sf::Vector2f(px, py));
    }
    points.push_back(endPos);
    return points;
}

// ---------------------------------------------------------------------------
// createFullScreenLightning: crea un fulmine che ATTRAVERSA TUTTO lo schermo.
//
// Sceglie casualmente 3 modalita' di partenza:
//   * 0 (verticale): parte dal bordo superiore sopra al punto di impatto
//   * 1 (diagonale sx): parte dall'angolo in alto a sinistra
//   * 2 (diagonale dx): parte dall'angolo in alto a destra
//
// In tutti i casi, il fulmine arriva al `endPoint` (dove fa danno).
// Pre-calcola zigzagPoints con 18 segmenti e jitter 35px per zigzag visibile.
//
// 5 fulmini totali vengono generati dallo scettro (scepter.lightningsLeft=5),
// ognuno a 3 secondi di distanza. Ogni fulmine attraversa tutto lo schermo
// e puo' colpire nemici in qualsiasi posizione.
// ---------------------------------------------------------------------------
Lightning Game::createFullScreenLightning(sf::Vector2f endPoint) {
    Lightning lt;
    lt.pos = endPoint;
    lt.life = 30;        // ~0.5s a 60 FPS
    lt.maxLife = 30;
    lt.hitEnemy = false;
    lt.hitBoss = false;

    // Scegli modalita' di partenza: 0=verticale, 1=diag sx, 2=diag dx
    int mode = rand() % 3;
    if (mode == 0) {
        // Verticale: parte dal bordo superiore sopra al punto di impatto
        lt.startPos = sf::Vector2f(endPoint.x, (float)UI_HEIGHT);
    } else if (mode == 1) {
        // Diagonale sinistra: parte dall'angolo in alto a sinistra
        lt.startPos = sf::Vector2f(20.f, (float)UI_HEIGHT);
    } else {
        // Diagonale destra: parte dall'angolo in alto a destra
        lt.startPos = sf::Vector2f((float)(WINDOW_WIDTH - 20), (float)UI_HEIGHT);
    }

    // Genera zigzag con 18 segmenti e jitter 35px
    lt.zigzagPoints = generateLightningPath(lt.startPos, endPoint, 18, 35.f);
    return lt;
}

// ---------------------------------------------------------------------------
// drawLightning: disegna un fulmine con path zigzag gia' calcolato.
//
// Elementi renderizzati (in ordine dal piu' lontano al piu' vicino):
//   1. Halo esterno grande (60px) - bagliore attorno al punto di impatto
//   2. Glow medio (30px) - bagliore elettrico
//   3. Saetta zigzag: 18 segmenti che attraversano tutto lo schermo,
//      larghezza 4px con outline bianca, colore azzurro-bianco
//   4. Glow attorno ad ogni segmento (effetto "elettrico")
//   5. Flash centrale (14px) al punto di impatto
//   6. 3 ramificazioni laterali casuali
//   7. 8 scintille radiali attorno al punto di impatto
//   8. Onda d'urto circolare (shockwave) che si espande
//
// Tutti gli elementi sfumano con alpha proporzionale a life/maxLife.
// ---------------------------------------------------------------------------
void Game::drawLightning(sf::RenderTarget& target, const Lightning& lt) {
    float lx = lt.pos.x;
    float ly = lt.pos.y;
    float alpha = 255.f * (float)lt.life / (float)lt.maxLife;

    // Palette 16 colori OBBLIGATORIA (dal prompt originale del gioco):
    //  (12,12,12) (48,40,36) (96,80,72) (160,128,112)
    //  (200,180,160) (120,140,160) (80,120,100) (40,80,60)
    //  (160,40,40) (200,80,80) (220,160,40) (200,200,80)
    //  (120,200,200) (80,160,220) (160,120,200) (240,240,240)
    // Il fulmine usa: gemma azzurra (80,160,220) per il bagliore,
    // bianco (240,240,240) per la saetta e il flash, giallo (200,200,80)
    // per le scintille. Tutti colori della palette.
    const sf::Color COL_GEM_BLUE(80, 160, 220);   // halo/glow
    const sf::Color COL_CYAN    (120, 200, 200);  // glow elettrico
    const sf::Color COL_WHITE    (240, 240, 240); // saetta + flash
    const sf::Color COL_YELLOW   (200, 200, 80);  // scintille

    // FIX: fulmine piu' realistico e sottile.
    // Prima: saetta 4px + glow 8px (troppo spessa, sembrava un tubo)
    // Ora: 3 strati sovrapposti per effetto "elettrico" realistico:
    //   1. Glow esterno largo (azzurro, alpha basso) - 6px
    //   2. Glow medio (ciano, alpha medio) - 3px
    //   3. Nucleo centrale bianco sottile - 1.5px (molto sottile)

    // --- 1. Halo esterno (bagliore grande attorno al punto di impatto) ---
    float haloR = 55.f;
    sf::CircleShape halo(haloR);
    halo.setFillColor(sf::Color(COL_GEM_BLUE.r, COL_GEM_BLUE.g, COL_GEM_BLUE.b,
                                (sf::Uint8)(alpha * 0.15f)));
    halo.setPosition(lx - haloR, ly - haloR);
    target.draw(halo);

    // --- 2. Glow medio (piu' piccolo, piu' intenso) ---
    sf::CircleShape glow(28.f);
    glow.setFillColor(sf::Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b,
                                (sf::Uint8)(alpha * 0.35f)));
    glow.setPosition(lx - 28.f, ly - 28.f);
    target.draw(glow);

    // --- 3. Glow interno (piccolo, bianco-ciano) ---
    sf::CircleShape glowInner(14.f);
    glowInner.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                      (sf::Uint8)(alpha * 0.5f)));
    glowInner.setPosition(lx - 14.f, ly - 14.f);
    target.draw(glowInner);

    // --- 4. Saetta zigzag (attraversa tutto lo schermo) ---
    // FIX: 3 strati per ogni segmento (glow esterno + glow medio + nucleo)
    // per un effetto "elettrico" realistico con nucleo sottile bianco.
    const std::vector<sf::Vector2f>& pts = lt.zigzagPoints;
    for (size_t i = 0; i + 1 < pts.size(); i++) {
        sf::Vector2f p0 = pts[i];
        sf::Vector2f p1 = pts[i + 1];
        float segDx = p1.x - p0.x;
        float segDy = p1.y - p0.y;
        float segLen = sqrtf(segDx * segDx + segDy * segDy);
        if (segLen < 0.001f) continue;
        float angle = atan2f(segDx, segDy) * 180.f / (float)M_PI;

        // Strato 1: glow esterno largo azzurro (6px)
        sf::RectangleShape boltGlow(sf::Vector2f(6.f, segLen));
        boltGlow.setFillColor(sf::Color(COL_GEM_BLUE.r, COL_GEM_BLUE.g,
                                         COL_GEM_BLUE.b,
                                         (sf::Uint8)(alpha * 0.2f)));
        boltGlow.setOrigin(3.f, 0.f);
        boltGlow.setPosition(p0.x, p0.y);
        boltGlow.rotate(angle);
        target.draw(boltGlow);

        // Strato 2: glow medio ciano (3px)
        sf::RectangleShape boltMid(sf::Vector2f(3.f, segLen));
        boltMid.setFillColor(sf::Color(COL_CYAN.r, COL_CYAN.g,
                                        COL_CYAN.b,
                                        (sf::Uint8)(alpha * 0.5f)));
        boltMid.setOrigin(1.5f, 0.f);
        boltMid.setPosition(p0.x, p0.y);
        boltMid.rotate(angle);
        target.draw(boltMid);

        // Strato 3: nucleo centrale bianco MOLTO SOTTILE (1.5px)
        // Questo e' il "filo" del fulmine, deve essere sottile e brillante
        sf::RectangleShape boltCore(sf::Vector2f(1.5f, segLen));
        boltCore.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g,
                                         COL_WHITE.b,
                                         (sf::Uint8)alpha));
        boltCore.setOrigin(0.75f, 0.f);
        boltCore.setPosition(p0.x, p0.y);
        boltCore.rotate(angle);
        target.draw(boltCore);
    }

    // --- 5. Flash centrale al punto di impatto ---
    sf::CircleShape flash(10.f);
    flash.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                  (sf::Uint8)alpha));
    flash.setPosition(lx - 10.f, ly - 10.f);
    target.draw(flash);

    // --- 6. Ramificazioni laterali (4 rami casuali lungo il path) ---
    // FIX: piu' rami (4 invece di 3) e piu' sottili (1px invece di 2px)
    for (int b = 0; b < 4; b++) {
        if (pts.size() < 4) break;
        int segIdx = 1 + (rand() % (int)(pts.size() - 2));
        sf::Vector2f bCur = pts[segIdx];
        // 5 segmenti brevi per ogni ramo (era 4)
        for (int s = 0; s < 5; s++) {
            float bx = bCur.x + ((rand() % 17) - 8);
            float by = bCur.y + 4.f + (rand() % 6);
            float blen = sqrtf((bx - bCur.x) * (bx - bCur.x) +
                               (by - bCur.y) * (by - bCur.y));
            if (blen < 0.1f) continue;
            // Glow del ramo (2px ciano)
            sf::RectangleShape branchGlow(sf::Vector2f(2.f, blen));
            branchGlow.setFillColor(sf::Color(COL_CYAN.r, COL_CYAN.g,
                                               COL_CYAN.b,
                                               (sf::Uint8)(alpha * 0.4f)));
            branchGlow.setOrigin(1.f, 0.f);
            branchGlow.setPosition(bCur.x, bCur.y);
            float bang = atan2f(bx - bCur.x, by - bCur.y) * 180.f / (float)M_PI;
            branchGlow.rotate(bang);
            target.draw(branchGlow);
            // Nucleo del ramo (1px bianco)
            sf::RectangleShape branch(sf::Vector2f(1.f, blen));
            branch.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g,
                                          COL_WHITE.b,
                                          (sf::Uint8)(alpha * 0.8f)));
            branch.setOrigin(0.5f, 0.f);
            branch.setPosition(bCur.x, bCur.y);
            branch.rotate(bang);
            target.draw(branch);
            bCur = sf::Vector2f(bx, by);
        }
    }

    // --- 7. Scintille radiali attorno al punto di impatto ---
    for (int i = 0; i < 10; i++) {
        float a = (i / 10.f) * 2.f * (float)M_PI;
        float r = 10.f + (rand() % 12);
        // Scintilla: 2 strati (glow + nucleo)
        sf::CircleShape sparkGlow(2.5f);
        sparkGlow.setFillColor(sf::Color(COL_CYAN.r, COL_CYAN.g,
                                          COL_CYAN.b,
                                          (sf::Uint8)(alpha * 0.5f)));
        sparkGlow.setPosition(lx + cosf(a) * r - 2.5f,
                              ly + sinf(a) * r - 2.5f);
        target.draw(sparkGlow);
        sf::CircleShape spark(1.2f);
        spark.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g,
                                     COL_WHITE.b,
                                     (sf::Uint8)(alpha * 0.9f)));
        spark.setPosition(lx + cosf(a) * r - 1.2f,
                          ly + sinf(a) * r - 1.2f);
        target.draw(spark);
    }

    // --- 8. Onda d'urto circolare (shockwave che si espande) ---
    float shockR = (1.f - (float)lt.life / (float)lt.maxLife) * 50.f;
    sf::CircleShape shock(shockR);
    shock.setFillColor(sf::Color(0, 0, 0, 0));
    shock.setOutlineThickness(1.5f);  // piu' sottile (era 2px)
    shock.setOutlineColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                     (sf::Uint8)(alpha * 0.4f)));
    shock.setPosition(lx - shockR, ly - shockR);
    target.draw(shock);
}

// ---------------------------------------------------------------------------
// drawFireAura: disegna l'aura di FUOCO attorno al giocatore quando e'
// invincibile (calice dell'immortalita'). Sostituisce la vecchia aura
// gialla con un effetto di fiamme animate che avvolgono il player.
//
// Effetti renderizzati:
//   1. Bagliore arancione pulsante (cerchio grande semitrasparente)
//   2. 8 fiamme triangolari attorno al player che fluttuano in altezza
//      con animazione sinusoidale (effetto movimento del fuoco)
//   3. Scintille bianche che salgono verso l'alto
//   4. Bagliore interno rosso-arancio
//
// Colori palette 16 colori OBBLIGATORIA:
//   * (220,160,40) oro = base fiamma
//   * (200,80,80) rosso = corpo fiamma
//   * (240,240,240) bianco = scintille
//   * (160,40,40) rosso scuro = bagliore interno
//
// (pos) e' il centro del player. invTimer e' il timer di invincibilita'
// residuo (ms), usato per la pulsazione (sinf(timer*0.01)).
// ---------------------------------------------------------------------------
void Game::drawFireAura(sf::RenderTarget& target, sf::Vector2f pos, int invTimer) {
    // Palette 16 colori OBBLIGATORIA
    const sf::Color COL_GOLD  (220, 160, 40);    // base fiamma
    const sf::Color COL_RED_L (200, 80, 80);     // corpo fiamma
    const sf::Color COL_RED_D (160, 40, 40);     // bagliore interno
    const sf::Color COL_WHITE (240, 240, 240);   // scintille
    const sf::Color COL_DARK  (48, 40, 36);      // outline
    const sf::Color COL_ORANGE(255, 100, 0);     // extra: orange brillante

    float invPulse = sinf(invTimer * 0.01f) * 0.2f + 1.f;
    // Tempo per animazione fuoco (usa static per persistere tra i frame)
    static float fireAnimTime = 0.f;
    fireAnimTime += 0.08f;

    // --- 0. Spritesheet PNG aura di fuoco (NUOVO) ---
    // Usa lo spritesheet effect_fireaura (6x4 frame 64x64) con blend ADDITIVO
    // per dare un effetto luminoso reale (il bianco del PNG si somma al
    //背景 dando glow). L'animazione cicla i frame "idle" o "walk" in base
    // allo stato del player. Lo sprite e' centrato (anchor 32,32).
    static SpriteSheet fireAuraSprite;
    static bool fireAuraLoaded = false;
    if (!fireAuraLoaded) {
        fireAuraLoaded = true;
        fireAuraSprite.load("assets/sprites/effect_fireaura");
    }
    if (fireAuraSprite.isLoaded()) {
        // Calcola frame animazione (cicla 6 frame idle/walk a 80ms)
        int frameDuration = 80;
        int frameCount = fireAuraSprite.getFrameCount("idle");
        if (frameCount <= 0) frameCount = 6;
        int frame = ((int)(fireAnimTime * 1000.f) / frameDuration) % frameCount;
        // Scala in base alla pulse di invincibilita'
        float spriteScale = 1.4f * invPulse;
        // Disegna lo sprite centrato sul player. Il blend e' alpha (normale),
        // ma i glow procedurali sottostanti danno luminosita' aggiuntiva.
        fireAuraSprite.render(target, "idle", frame, pos.x, pos.y, spriteScale, false);
    }

    // --- 1. Bagliore arancione pulsante (cerchio grande) ---
    float glowR = 32.f * invPulse;
    sf::CircleShape glowOuter(glowR);
    glowOuter.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 70));
    glowOuter.setPosition(pos.x - glowR, pos.y - glowR);
    target.draw(glowOuter);

    // --- 2. Bagliore interno rosso-arancio (piu' piccolo, piu' intenso) ---
    float innerR = 22.f * invPulse;
    sf::CircleShape glowInner(innerR);
    glowInner.setFillColor(sf::Color(COL_RED_D.r, COL_RED_D.g, COL_RED_D.b, 100));
    glowInner.setPosition(pos.x - innerR, pos.y - innerR);
    target.draw(glowInner);

    // --- 3. Glow centrale oro ---
    float midR = 14.f * invPulse;
    sf::CircleShape glowMid(midR);
    glowMid.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 90));
    glowMid.setPosition(pos.x - midR, pos.y - midR);
    target.draw(glowMid);

    // --- 4. Fiamme procedurali attorno al player (mantenute per dynamism) ---
    // 12 fiamme invece di 8, piu' piccole e dense, per dare "spessore" al
    // fuoco attorno al player. Alternate oro/rosso per varieta'.
    for (int i = 0; i < 12; i++) {
        float angle = (i / 12.f) * 2.f * (float)M_PI;
        float fx = pos.x + cosf(angle) * 20.f;
        float fy = pos.y + sinf(angle) * 20.f;
        float flameH = 10.f + sinf(fireAnimTime + i * 0.7f) * 5.f + 5.f;
        float flameW = 3.5f;
        // Colore: alterna oro (base) e rosso (apice)
        sf::ConvexShape flame;
        flame.setPointCount(3);
        flame.setPoint(0, sf::Vector2f(fx - flameW, fy));
        flame.setPoint(1, sf::Vector2f(fx + flameW, fy));
        flame.setPoint(2, sf::Vector2f(fx + sinf(fireAnimTime * 2.f + i) * 3.f,
                                        fy - flameH));
        flame.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 220));
        flame.setOutlineThickness(0.3f);
        flame.setOutlineColor(sf::Color(COL_RED_D.r, COL_RED_D.g, COL_RED_D.b, 180));
        target.draw(flame);
        // Apice rosso
        sf::ConvexShape flameTip;
        flameTip.setPointCount(3);
        float tipH = flameH * 0.6f;
        flameTip.setPoint(0, sf::Vector2f(fx - flameW * 0.6f, fy - flameH * 0.4f));
        flameTip.setPoint(1, sf::Vector2f(fx + flameW * 0.6f, fy - flameH * 0.4f));
        flameTip.setPoint(2, sf::Vector2f(fx + sinf(fireAnimTime * 2.f + i) * 3.f,
                                           fy - flameH - tipH * 0.3f));
        flameTip.setFillColor(sf::Color(COL_RED_L.r, COL_RED_L.g, COL_RED_L.b, 230));
        target.draw(flameTip);
    }

    // --- 5. Scintille bianche che salgono ---
    for (int i = 0; i < 8; i++) {
        float sparkX = pos.x + sinf(fireAnimTime * 1.5f + i * 1.2f) * 14.f;
        float sparkY = pos.y - 10.f - ((int)(fireAnimTime * 20.f + i * 8) % 35);
        float sparkR = 1.2f + sinf(fireAnimTime + i) * 0.5f;
        sf::CircleShape spark(sparkR);
        spark.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                      220 - (int)(fireAnimTime * 20.f + i * 8) % 35 * 6));
        spark.setPosition(sparkX - sparkR, sparkY - sparkR);
        target.draw(spark);
    }

    // --- 6. Nucleo centrale luminoso (pulsante) ---
    float coreR = 8.f * invPulse;
    sf::CircleShape core(coreR);
    core.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 180));
    core.setPosition(pos.x - coreR, pos.y - coreR);
    target.draw(core);
}

// ---------------------------------------------------------------------------
// drawFireBursts: disegna le esplosioni di fuoco sui nemici bruciati dal
// player invincibile. Sostituisce la vecchia logica "solo particelle
// triangolari" con uno spritesheet PNG animato (effect_fireburst) + glow
// radiale procedurale multistrato per dare un effetto fuoco realistico.
//
// Ogni FireBurst vive ~60 frame (1 secondo) e cicla 24 frame dell'animazione
// (6 frame per riga, 4 righe: idle/walk/attack/death). La fase cambia in
// base al tempo di vita: prima meta' = espansione (row 0/1), picco = row 2,
// dissipazione = row 3.
// ---------------------------------------------------------------------------
void Game::drawFireBursts(sf::RenderTarget& target) {
    if (fireBursts.empty()) return;

    // Palette
    const sf::Color COL_GOLD  (220, 160, 40);
    const sf::Color COL_RED_L (200, 80, 80);
    const sf::Color COL_RED_D (160, 40, 40);
    const sf::Color COL_WHITE (240, 240, 240);
    const sf::Color COL_ORANGE(255, 100, 0);

    // Carica lo spritesheet una tantum
    static SpriteSheet fireBurstSprite;
    static bool loaded = false;
    if (!loaded) {
        loaded = true;
        fireBurstSprite.load("assets/sprites/effect_fireburst");
    }

    for (const auto& fb : fireBursts) {
        float lifeRatio = (float)fb.life / (float)fb.maxLife;  // 1 = inizio, 0 = fine
        // Pulsa in base al tempo
        float pulse = 1.0f + sinf(fb.animTime * 0.3f) * 0.1f;

        // --- 1. Glow radiale ampissimo (arancione, alpha basso) ---
        float outerR = 28.f * fb.scale * pulse;
        sf::CircleShape glowOuter(outerR);
        glowOuter.setFillColor(sf::Color(COL_ORANGE.r, COL_ORANGE.g, COL_ORANGE.b,
                                          (sf::Uint8)(70 * lifeRatio)));
        glowOuter.setPosition(fb.pos.x - outerR, fb.pos.y - outerR);
        target.draw(glowOuter);

        // --- 2. Glow medio (rosso) ---
        float midR = 20.f * fb.scale * pulse;
        sf::CircleShape glowMid(midR);
        glowMid.setFillColor(sf::Color(COL_RED_L.r, COL_RED_L.g, COL_RED_L.b,
                                        (sf::Uint8)(100 * lifeRatio)));
        glowMid.setPosition(fb.pos.x - midR, fb.pos.y - midR);
        target.draw(glowMid);

        // --- 3. Glow interno (oro) ---
        float innerR = 12.f * fb.scale * pulse;
        sf::CircleShape glowInner(innerR);
        glowInner.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                          (sf::Uint8)(140 * lifeRatio)));
        glowInner.setPosition(fb.pos.x - innerR, fb.pos.y - innerR);
        target.draw(glowInner);

        // --- 4. Core bianco centrale ---
        float coreR = 6.f * fb.scale * pulse;
        sf::CircleShape core(coreR);
        core.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                     (sf::Uint8)(180 * lifeRatio)));
        core.setPosition(fb.pos.x - coreR, fb.pos.y - coreR);
        target.draw(core);

        // --- 5. Spritesheet PNG animato (effetto fuoco avanzato) ---
        if (fireBurstSprite.isLoaded()) {
            // Selezione animazione in base alla fase di vita
            std::string animName = "idle";
            int frameDuration = 50;
            // Prima 25% vita: idle (inizio espansione)
            // 25-50%: walk (espansione massima)
            // 50-75%: attack (picco)
            // 75-100%: death (dissipazione)
            if (lifeRatio > 0.75f) animName = "idle";
            else if (lifeRatio > 0.5f) animName = "walk";
            else if (lifeRatio > 0.25f) animName = "attack";
            else animName = "death";
            int frameCount = fireBurstSprite.getFrameCount(animName);
            if (frameCount <= 0) {
                animName = "idle";
                frameCount = fireBurstSprite.getFrameCount(animName);
            }
            if (frameCount > 0) {
                int elapsed = (int)((fb.maxLife - fb.life) * 50);  // ms simulati
                int frame = (elapsed / frameDuration) % frameCount;
                // Scala: cresce durante l'espansione, decresce nella dissipazione
                float spriteScale = fb.scale * (1.2f + (1.0f - lifeRatio) * 0.5f);
                // Tint con fade alpha in base al life ratio
                sf::Color tint(255, 255, 255, (sf::Uint8)(255 * lifeRatio));
                fireBurstSprite.render(target, animName, frame,
                                        fb.pos.x, fb.pos.y, spriteScale, false, tint);
            }
        }

        // --- 6. Scintille bianche che volano fuori (procedurali, per dynamism) ---
        for (int i = 0; i < 6; i++) {
            float angle = (i / 6.f) * 2.f * (float)M_PI + fb.animTime * 0.5f;
            float dist = (1.0f - lifeRatio) * 30.f * fb.scale;
            float sx = fb.pos.x + cosf(angle) * dist;
            float sy = fb.pos.y + sinf(angle) * dist - (1.0f - lifeRatio) * 10.f;
            sf::CircleShape spark(1.5f);
            spark.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b,
                                          (sf::Uint8)(220 * lifeRatio)));
            spark.setPosition(sx - 1.5f, sy - 1.5f);
            target.draw(spark);
        }
    }
}

// ---------------------------------------------------------------------------
// drawAshPiles: disegna i mucchi di cenere con spritesheet PNG avanzato
// (effect_ashpile) + braci incandescenti pulsanti + fumo procedurale.
// Sostituisce la vecchia logica "3 cerchi schiacciati" con un rendering
// molto piu' realistico.
// ---------------------------------------------------------------------------
void Game::drawAshPiles(sf::RenderTarget& target) {
    if (ashPiles.empty()) return;

    // Palette
    const sf::Color COL_ASH_LIGHT(200, 180, 160);
    const sf::Color COL_ASH_DARK (120, 100, 90);
    const sf::Color COL_ASH_MID  (160, 128, 112);
    const sf::Color COL_SOOT     (48, 40, 36);
    const sf::Color COL_BLACK    (12, 12, 12);
    const sf::Color COL_RED_L    (200, 80, 80);
    const sf::Color COL_GOLD     (220, 160, 40);
    const sf::Color COL_SMOKE    (180, 170, 160);

    // Carica lo spritesheet una tantum
    static SpriteSheet ashPileSprite;
    static bool loaded = false;
    if (!loaded) {
        loaded = true;
        ashPileSprite.load("assets/sprites/effect_ashpile");
    }

    for (const auto& ap : ashPiles) {
        float lifeRatio = (float)ap.life / (float)ap.maxLife;
        if (lifeRatio < 0.f) lifeRatio = 0.f;
        sf::Uint8 alpha = (sf::Uint8)(255 * lifeRatio);

        // --- 1. Ombra sul pavimento (schiacciata) ---
        float shadowR = ap.radius * 1.4f;
        sf::CircleShape shadow(shadowR);
        shadow.setFillColor(sf::Color(COL_BLACK.r, COL_BLACK.g, COL_BLACK.b,
                                        (sf::Uint8)(100 * lifeRatio)));
        shadow.setScale(1.3f, 0.4f);
        shadow.setPosition(ap.pos.x - shadowR, ap.pos.y - shadowR * 0.4f);
        target.draw(shadow);

        // --- 2. Spritesheet PNG del mucchio di cenere ---
        if (ashPileSprite.isLoaded()) {
            // Selezione animazione in base alla fase di vita
            std::string animName = "idle";
            if (lifeRatio > 0.75f) animName = "idle";       // fresco
            else if (lifeRatio > 0.5f) animName = "walk";   // smoldering
            else if (lifeRatio > 0.25f) animName = "attack"; // cooling
            else animName = "death";                          // old
            int frameCount = ashPileSprite.getFrameCount(animName);
            if (frameCount <= 0) {
                animName = "idle";
                frameCount = ashPileSprite.getFrameCount(animName);
            }
            if (frameCount > 0) {
                int frameDuration = 200;
                int frame = ((int)(ap.animTime * 1000.f) / frameDuration) % frameCount;
                // Scala in base al raggio (sprite 64x64 -> size reale)
                float spriteScale = ap.radius / 24.f;  // 24 = meta' di 48 (frame width)
                if (spriteScale < 0.8f) spriteScale = 0.8f;
                // Tint con fade alpha
                sf::Color tint(255, 255, 255, alpha);
                ashPileSprite.render(target, animName, frame,
                                      ap.pos.x, ap.pos.y, spriteScale, false, tint);
            }
        } else {
            // Fallback se lo sprite non e' caricato: 3 cerchi schiacciati
            // (vecchio comportamento, per robustezza)
            sf::CircleShape pile(ap.radius);
            pile.setFillColor(sf::Color(COL_ASH_DARK.r, COL_ASH_DARK.g, COL_ASH_DARK.b, alpha));
            pile.setScale(1.2f, 0.5f);
            pile.setPosition(ap.pos.x - ap.radius, ap.pos.y - ap.radius * 0.5f);
            target.draw(pile);
            sf::CircleShape pileMid(ap.radius * 0.7f);
            pileMid.setFillColor(sf::Color(COL_ASH_MID.r, COL_ASH_MID.g, COL_ASH_MID.b, alpha));
            pileMid.setScale(1.f, 0.6f);
            pileMid.setPosition(ap.pos.x - ap.radius * 0.7f, ap.pos.y - ap.radius * 0.6f);
            target.draw(pileMid);
            sf::CircleShape pileTop(ap.radius * 0.4f);
            pileTop.setFillColor(sf::Color(COL_ASH_LIGHT.r, COL_ASH_LIGHT.g, COL_ASH_LIGHT.b, alpha));
            pileTop.setPosition(ap.pos.x - ap.radius * 0.4f, ap.pos.y - ap.radius * 0.8f);
            target.draw(pileTop);
        }

        // --- 3. Braci incandescenti (puntini rossi/oro che brillano) ---
        // Solo nei primi 75% della vita (poi si spengono)
        if (lifeRatio > 0.25f) {
            float emberPulse = 0.7f + 0.3f * sinf(ap.animTime * 5.f);
            float emberAlpha = (lifeRatio - 0.25f) / 0.75f;  // 1 quando fresco, 0 quando spento
            for (int i = 0; i < 4; i++) {
                float angle = (i / 4.f) * 2.f * (float)M_PI + ap.animTime * 0.3f;
                float ex = ap.pos.x + cosf(angle) * ap.radius * 0.4f;
                float ey = ap.pos.y - 4.f + sinf(angle) * ap.radius * 0.2f - i * 2.f;
                // Glow attorno alla brace
                float glowR = 3.f * emberPulse;
                sf::CircleShape emberGlow(glowR);
                emberGlow.setFillColor(sf::Color(COL_RED_L.r, COL_RED_L.g, COL_RED_L.b,
                                                   (sf::Uint8)(80 * emberAlpha)));
                emberGlow.setPosition(ex - glowR, ey - glowR);
                target.draw(emberGlow);
                // Centro brace (rosso acceso)
                sf::CircleShape emberCore(1.f);
                emberCore.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                                   (sf::Uint8)(255 * emberAlpha)));
                emberCore.setPosition(ex - 1.f, ey - 1.f);
                target.draw(emberCore);
            }
        }

        // --- 4. Fumo che sale (particelle grigie) ---
        // Solo nei primi 60% della vita
        if (lifeRatio > 0.4f) {
            float smokeAlpha = (lifeRatio - 0.4f) / 0.6f;  // 1 quando fresco
            for (int i = 0; i < 5; i++) {
                float sx = ap.pos.x + sinf(ap.animTime + i * 2.f) * ap.radius * 0.5f;
                float sy = ap.pos.y - 8.f - ((int)(ap.animTime * 30.f + i * 20) % 40);
                float sr = 2.f + i * 0.5f;
                sf::CircleShape smoke(sr);
                smoke.setFillColor(sf::Color(COL_SMOKE.r, COL_SMOKE.g, COL_SMOKE.b,
                                               (sf::Uint8)(100 * smokeAlpha * (1.f - i * 0.15f))));
                smoke.setPosition(sx - sr, sy - sr);
                target.draw(smoke);
            }
        }

        // --- 5. Detriti di carbone (pezzi scuri attorno al mucchio) ---
        for (int i = 0; i < 5; i++) {
            float angle = (i / 5.f) * 2.f * (float)M_PI + 0.5f;
            float dist = ap.radius * 1.1f;
            float dx = ap.pos.x + cosf(angle) * dist;
            float dy = ap.pos.y + sinf(angle) * dist * 0.4f;  // schiacciato (pavimento)
            sf::RectangleShape debris(sf::Vector2f(3.f, 2.f));
            debris.setFillColor(sf::Color(COL_SOOT.r, COL_SOOT.g, COL_SOOT.b,
                                           (sf::Uint8)(200 * lifeRatio)));
            debris.setOrigin(1.5f, 1.f);
            debris.setPosition(dx, dy);
            debris.rotate(angle * 180.f / (float)M_PI);
            target.draw(debris);
        }
    }
}

// ---------------------------------------------------------------------------
// drawMenu: disegna il menu' principale (tema fantasy cavernoso).
//
// Elementi:
//   * Sfondo: gradiente notte (viola scuro -> nero in basso) + alone lunare
//   * 100 stelle generate con seed fisso (srand(42)) per non mutare ad
//     ogni frame; poi srand((unsigned int)time(NULL)) per ripristinare il random del gioco
//   * Nebbia bassa viola/azzurra che si muove lentamente
//   * Luna in alto a destra con due crateri + alone luminoso
//   * Fulmine casuale (overlay bianco + linee gialle) quando lightningTimer>0
//   * Titolo "ARCADE MAZE" dorato con ombra scura sfalsata (effetto 3D) +
//     ornamenti laterali (rune / fiammate) stile fantasy
//   * Crediti: "By" stilizzato (oro) + "Luca A. Greco" (avorio) in stile
//     fantasy, con piccoli rombi decorativi ai lati
//   * Riquadro pergamena con bordo marrone antico + angoli decorati
//   * 6 voci di menu'; la voce selezionata e' evidenziata in giallo con
//     "> ... <" e una piccola fiammella laterale
//   * Istruzioni in basso
// ---------------------------------------------------------------------------
void Game::drawMenu() {
    // --- Sfondo gradiente notte ---
    // Disegna 32 bande orizzontali che vanno dal viola scuro (alto) al
    // nero-bluastro (basso). Costo trascurabile (32 rettangoli).
    for (int i = 0; i < 32; i++) {
        float t = (float)i / 31.f;
        sf::Uint8 r = (sf::Uint8)(30  + (1.f - t) * 25.f);
        sf::Uint8 g = (sf::Uint8)(20  + (1.f - t) * 10.f);
        sf::Uint8 b = (sf::Uint8)(60  + (1.f - t) * 30.f);
        sf::RectangleShape band(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT / 32.f + 1.f));
        band.setFillColor(sf::Color(r, g, b));
        band.setPosition(0.f, i * (WINDOW_HEIGHT / 32.f));
        window.draw(band);
    }

    // --- Stelle: seed fisso per layout stabile ---
    srand(42);
    for(int i=0; i<140; i++) {
        // Stelle leggermente variate: alcune grandi, altre piccole
        float radius = 0.8f + (rand() % 30) * 0.05f;
        sf::CircleShape star(radius);
        // Colore: bianco/giallo/azzurro per dare profondita' al cielo
        sf::Uint8 br = 150 + (sf::Uint8)(rand() % 105);
        int tint = rand() % 3;
        sf::Color col = (tint == 0) ? sf::Color(255, 255, 220, br) :
                        (tint == 1) ? sf::Color(200, 220, 255, br) :
                                      sf::Color(255, 240, 200, br);
        star.setFillColor(col);
        star.setPosition((float)(rand()%WINDOW_WIDTH), (float)(rand()%(WINDOW_HEIGHT - 200)));
        window.draw(star);
        // Aggiungi un piccolo "cross" di luce alle stelle piu' grandi
        if (radius > 1.8f) {
            sf::RectangleShape cross1(sf::Vector2f(radius * 5.f, 1.f));
            cross1.setFillColor(sf::Color(255, 255, 200, br / 3));
            cross1.setPosition(star.getPosition().x - radius * 2.f, star.getPosition().y + radius * 0.5f);
            window.draw(cross1);
            sf::RectangleShape cross2(sf::Vector2f(1.f, radius * 5.f));
            cross2.setFillColor(sf::Color(255, 255, 200, br / 3));
            cross2.setPosition(star.getPosition().x + radius * 0.5f, star.getPosition().y - radius * 2.f);
            window.draw(cross2);
        }
    }
    // Ripristina il seed randomico per il resto del gioco
    srand((unsigned int)time(NULL));

    // --- Nebbia bassa: onde semitrasparenti viola/azzurre ---
    // 3 strati di nebbia che fluttuano lentamente con animazione sinusoidale.
    // L'animazione usa un tempo derivato da lightningTimer? No, sarebbe troppo
    // instabile: usiamo una static che persiste tra le frame.
    static float menuTime = 0.f;
    menuTime += 0.016f;
    for (int layer = 0; layer < 3; layer++) {
        sf::Color fogCol = (layer == 0) ? sf::Color(80, 40, 120, 60) :
                           (layer == 1) ? sf::Color(60, 70, 130, 50) :
                                          sf::Color(40, 50, 100, 40);
        float yBase = WINDOW_HEIGHT - 180.f + layer * 30.f;
        for (int x = 0; x < WINDOW_WIDTH; x += 16) {
            float y = yBase + sinf(menuTime * 0.5f + (float)x * 0.01f + (float)layer) * 15.f;
            sf::CircleShape fog(40.f);
            fog.setFillColor(fogCol);
            fog.setPosition((float)x - 40.f, y - 40.f);
            window.draw(fog);
        }
    }

    // --- Luna con alone luminoso e due crateri ---
    // Alone esterno: grande cerchio semitrasparente giallo-avorio
    sf::CircleShape moonGlow(140.f);
    moonGlow.setFillColor(sf::Color(230, 230, 180, 40));
    moonGlow.setPosition(WINDOW_WIDTH - 240.f, 40.f);
    window.draw(moonGlow);
    sf::CircleShape moonGlow2(110.f);
    moonGlow2.setFillColor(sf::Color(240, 240, 200, 60));
    moonGlow2.setPosition(WINDOW_WIDTH - 210.f, 70.f);
    window.draw(moonGlow2);
    // Luna piena
    sf::CircleShape moon(80.f);
    moon.setFillColor(sf::Color(240, 240, 200));
    moon.setOutlineThickness(4.f);
    moon.setOutlineColor(sf::Color(200, 200, 150));
    moon.setPosition(WINDOW_WIDTH - 200.f, 100.f);
    window.draw(moon);
    // Crateri
    sf::CircleShape crater1(10.f); crater1.setFillColor(sf::Color(210, 210, 160));
    crater1.setPosition(WINDOW_WIDTH - 160.f, 140.f); window.draw(crater1);
    crater1.setPosition(WINDOW_WIDTH - 180.f, 180.f); window.draw(crater1);
    crater1.setRadius(6.f); crater1.setPosition(WINDOW_WIDTH - 140.f, 170.f); window.draw(crater1);

    // --- Effetto fulmine: flash bianco che si dissolve + saetta verticale a zigzag ---
    if (lightningTimer > 0) {
        sf::RectangleShape flash(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        // Intensita' proporzionale al tempo residuo (fade out)
        flash.setFillColor(sf::Color(255, 255, 255, 150 * (lightningTimer / 10.f)));
        window.draw(flash);
        // Disegna il fulmine solo nei primi 5 frame (parte alta durata)
        if (lightningTimer > 5) {
            sf::Color lightningCol(255, 255, 200);
            float lx = WINDOW_WIDTH / 2.0f + (float)(rand()%400 - 200);
            for (int i = 0; i < 6; i++) {
                sf::RectangleShape line(sf::Vector2f(6.f, 100.f));
                line.setFillColor(lightningCol);
                line.setPosition(lx, i * 100.f);
                line.rotate(rand()%30 - 15);  // inclinazione casuale per zigzag
                window.draw(line);
                lx += (rand()%100 - 50);
            }
        }
    }

    // --- Titolo con effetto ombra: due copie sfalsate di 4 px ---
    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2, 120, 10, sf::Color(255, 215, 0));
    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2 - 4, 120 - 4, 10, sf::Color(180, 120, 40));

    // --- Ornamento tra titolo e crediti: linea dorata con rombo centrale ---
    // Una linea orizzontale spezzata da un rombo al centro, in stile fantasy.
    float ornY = 220.f;
    sf::Color ornGold(200, 160, 50);
    // Rombo centrale
    sf::ConvexShape diamond; diamond.setPointCount(4);
    diamond.setFillColor(ornGold); diamond.setOutlineThickness(1.f); diamond.setOutlineColor(sf::Color(120, 80, 20));
    diamond.setPoint(0, sf::Vector2f((float)WINDOW_WIDTH/2.f, ornY - 6.f));
    diamond.setPoint(1, sf::Vector2f((float)WINDOW_WIDTH/2.f + 8.f, ornY));
    diamond.setPoint(2, sf::Vector2f((float)WINDOW_WIDTH/2.f, ornY + 6.f));
    diamond.setPoint(3, sf::Vector2f((float)WINDOW_WIDTH/2.f - 8.f, ornY));
    window.draw(diamond);
    // Linee laterali
    sf::RectangleShape ornLineL(sf::Vector2f(180.f, 2.f));
    ornLineL.setFillColor(ornGold);
    ornLineL.setPosition((float)WINDOW_WIDTH/2.f - 200.f, ornY - 1.f);
    window.draw(ornLineL);
    sf::RectangleShape ornLineR(sf::Vector2f(180.f, 2.f));
    ornLineR.setFillColor(ornGold);
    ornLineR.setPosition((float)WINDOW_WIDTH/2.f + 20.f, ornY - 1.f);
    window.draw(ornLineR);
    // Piccoli rombi alle estremita' delle linee
    for (int side = 0; side < 2; side++) {
        float dx = (side == 0) ? -1.f : 1.f;
        sf::ConvexShape dot; dot.setPointCount(4);
        dot.setFillColor(ornGold);
        dot.setPoint(0, sf::Vector2f((float)WINDOW_WIDTH/2.f + dx * 200.f, ornY - 4.f));
        dot.setPoint(1, sf::Vector2f((float)WINDOW_WIDTH/2.f + dx * 204.f, ornY));
        dot.setPoint(2, sf::Vector2f((float)WINDOW_WIDTH/2.f + dx * 200.f, ornY + 4.f));
        dot.setPoint(3, sf::Vector2f((float)WINDOW_WIDTH/2.f + dx * 196.f, ornY));
        window.draw(dot);
    }

    // --- Crediti: "By" (oro) + "Luca A. Greco" (avorio) in stile fantasy ---
    // Sostituisce il vecchio "Lord Luca A. Greco".
    // Le due parti sono centrate come un'unica stringa.
    std::string byStr   = "By ";
    std::string nameStr = "Luca A. Greco";
    float byW = (float)byStr.length()   * 4 * 5;
    float nameW = (float)nameStr.length() * 4 * 5;
    float totalW = byW + nameW;
    float startX = (float)(WINDOW_WIDTH/2) - totalW/2.f;
    drawTextOutlined(window, byStr,   startX,             260, 5, sf::Color(255, 215, 100));
    drawTextOutlined(window, nameStr, startX + byW,       260, 5, sf::Color(245, 235, 200));

    // --- Riquadro pergamena con bordo marrone antico + angoli decorati ---
    sf::RectangleShape border(sf::Vector2f(WINDOW_WIDTH - 240, 500));
    border.setPosition(120, 360);
    // Sfondo pergamena scura semitrasparente
    border.setFillColor(sf::Color(20, 12, 8, 200));
    border.setOutlineThickness(6.f);
    border.setOutlineColor(sf::Color(140, 100, 50));
    window.draw(border);
    // Bordo interno piu' sottile (effetto doppia cornice)
    sf::RectangleShape innerBorder(sf::Vector2f(WINDOW_WIDTH - 268, 472));
    innerBorder.setPosition(134, 374);
    innerBorder.setFillColor(sf::Color(0, 0, 0, 0));
    innerBorder.setOutlineThickness(2.f);
    innerBorder.setOutlineColor(sf::Color(100, 70, 30));
    window.draw(innerBorder);
    // Angoli decorati (4 piccoli rombi dorati)
    auto drawCorner = [&](float cx, float cy) {
        sf::ConvexShape corner; corner.setPointCount(4);
        corner.setFillColor(sf::Color(220, 180, 60));
        corner.setOutlineThickness(1.f); corner.setOutlineColor(sf::Color(120, 80, 20));
        corner.setPoint(0, sf::Vector2f(cx, cy - 8.f));
        corner.setPoint(1, sf::Vector2f(cx + 8.f, cy));
        corner.setPoint(2, sf::Vector2f(cx, cy + 8.f));
        corner.setPoint(3, sf::Vector2f(cx - 8.f, cy));
        window.draw(corner);
    };
    drawCorner(120.f, 360.f);
    drawCorner(WINDOW_WIDTH - 120.f, 360.f);
    drawCorner(120.f, 860.f);
    drawCorner(WINDOW_WIDTH - 120.f, 860.f);

    // Voci di menu': valori dinamici per le prime 3 (giocatori/modalita'/musica)
    std::string items[] = {
        "NUMBER OF PLAYERS: " + std::to_string(numPlayers),
        "GAME MODE: " + std::string(gameMode == MODE_STORY ? "STORY" : "INFINITE"),
        "MUSIC: " + std::string(musicEnabled ? "ON" : "OFF"),
        "SELECT PLAYER",                        // nuova voce: selezione personaggio
#ifdef TEST_MODE_FEATURE
        "TEST MODE: " + std::string(testModeEnabled ? "ON" : "OFF"),
#else
        "TEST MODE: DISABLED",
#endif
        "CONFIGURE JOYSTICK",
        "START GAME"
    };

    // Disegna le 7 voci; quella selezionata e' in giallo con "> ... <"
    // e una piccola fiammella pulsante alla sua sinistra.
    // Distanza ridotta a 50px (era 65) per evitare che l'ultima voce esca
    // dal riquadro pergamena (360-860). Prima voce a Y=410 (era 360) per
    // lasciare margine superiore e non attaccarsi al bordo.
    for(int i=0; i<7; i++) {
        std::string text = (i == menuItemIndex) ? ("> " + items[i] + " <") : items[i];
        sf::Color color = (i == menuItemIndex) ? sf::Color::Yellow : sf::Color(180, 180, 180);
        float itemY = 410 + i * 50;
        drawTextCenteredOutlined(window, text, WINDOW_WIDTH/2, itemY, 3, color);

        // Fiammella laterale animata per la voce selezionata
        if (i == menuItemIndex) {
            float fx = 150.f;
            float flicker = sinf(menuTime * 15.f) * 1.5f;
            // Aura
            sf::CircleShape flameAura(8.f);
            flameAura.setFillColor(sf::Color(255, 180, 60, 80));
            flameAura.setPosition(fx - 8.f, itemY - 8.f + flicker * 0.3f);
            window.draw(flameAura);
            // Fiamma esterna rossa
            sf::CircleShape flame3(4.f + flicker);
            flame3.setFillColor(sf::Color(220, 50, 20, 230));
            flame3.setPosition(fx - 4.f - flicker, itemY - 4.f + flicker * 0.3f);
            window.draw(flame3);
            // Fiamma interna gialla
            sf::CircleShape flame2(2.5f);
            flame2.setFillColor(sf::Color(255, 220, 100, 240));
            flame2.setPosition(fx - 2.5f, itemY - 2.5f + flicker * 0.2f);
            window.draw(flame2);
        }
    }

    // Istruzioni in basso
    drawTextCenteredOutlined(window, "UP/DOWN TO SELECT - LEFT/RIGHT TO CHANGE", WINDOW_WIDTH/2, 900, 2, sf::Color(150, 150, 150));
}

// drawConfigJoy: schermata minimale per la configurazione del joystick.
// Mostra solo un titolo e un prompt che cambia in base a configJoyStep.
void Game::drawConfigJoy() {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
    bg.setFillColor(sf::Color(10, 10, 30));
    window.draw(bg);

    drawTextCenteredOutlined(window, "JOYSTICK CONFIGURATION - PLAYER 1", WINDOW_WIDTH/2, 200, 4, sf::Color::White);

    if (configJoyStep == 0) {
        drawTextCenteredOutlined(window, "PRESS BUTTON FOR JUMP", WINDOW_WIDTH/2, 450, 3, sf::Color::Yellow);
    } else if (configJoyStep == 1) {
        drawTextCenteredOutlined(window, "PRESS BUTTON FOR SHOOT", WINDOW_WIDTH/2, 450, 3, sf::Color::Yellow);
    }

    drawTextCenteredOutlined(window, "PRESS ESC TO CANCEL", WINDOW_WIDTH/2, 800, 2, sf::Color::Red);
}

// drawContinues: schermata "Continues?" con conto alla rovescia 10-0 e Yes/No.
void Game::drawContinues() {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
    bg.setFillColor(sf::Color(10, 0, 20));
    window.draw(bg);

    // Titolo
    drawTextCenteredOutlined(window, "CONTINUES?", WINDOW_WIDTH/2, 200, 5, sf::Color(255, 50, 50));

    // Crediti rimanenti
    drawTextCenteredOutlined(window, "CREDITS: " + std::to_string(continuesLeft),
        WINDOW_WIDTH/2, 300, 3, sf::Color(255, 215, 0));

    // Conto alla rovescia
    std::string timerStr = std::to_string(continuesTimer);
    sf::Color timerColor = (continuesTimer <= 3) ? sf::Color(255, 50, 50) : sf::Color::White;
    drawTextCenteredOutlined(window, timerStr, WINDOW_WIDTH/2, 400, 8, timerColor);

    // Yes / No
    std::string yesStr = (continuesChoice) ? "> YES <" : "YES";
    std::string noStr = (!continuesChoice) ? "> NO <" : "NO";
    sf::Color yesColor = (continuesChoice) ? sf::Color::Yellow : sf::Color(150, 150, 150);
    sf::Color noColor = (!continuesChoice) ? sf::Color::Yellow : sf::Color(150, 150, 150);
    drawTextCenteredOutlined(window, yesStr, WINDOW_WIDTH/2 - 150, 600, 3, yesColor);
    drawTextCenteredOutlined(window, noStr, WINDOW_WIDTH/2 + 150, 600, 3, noColor);

    // Istruzioni
    drawTextCenteredOutlined(window, "LEFT/RIGHT TO SELECT - ENTER TO CONFIRM",
        WINDOW_WIDTH/2, 800, 2, sf::Color(120, 120, 120));
}

// drawConfigJoy2: schermata minimale per la configurazione del secondo joystick.
// Mostra solo un titolo e un prompt che cambia in base a configJoyStep.
void Game::drawConfigJoy2() {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
    bg.setFillColor(sf::Color(10, 10, 30));
    window.draw(bg);

    drawTextCenteredOutlined(window, "JOYSTICK CONFIGURATION - PLAYER 2", WINDOW_WIDTH/2, 200, 4, sf::Color::White);

    if (configJoyStep == 0) {
        drawTextCenteredOutlined(window, "PRESS BUTTON FOR JUMP", WINDOW_WIDTH/2, 450, 3, sf::Color::Yellow);
    } else if (configJoyStep == 1) {
        drawTextCenteredOutlined(window, "PRESS BUTTON FOR SHOOT", WINDOW_WIDTH/2, 450, 3, sf::Color::Yellow);
    }

    drawTextCenteredOutlined(window, "PRESS ESC TO CANCEL", WINDOW_WIDTH/2, 800, 2, sf::Color::Red);
}

// ---------------------------------------------------------------------------
// drawSelectPlayer: schermata di selezione personaggio.
//
// Mostra gli 8 personaggi SOPRA una grande ruota di roccia disegnata IN
// PROSPETTIVA: invece di un cerchio piatto, la ruota e' un'ellisse (cerchio
// compresso verticalmente) e i personaggi stanno attorno al perimetro, come
// se fossero in piedi su un piatto rotante visto leggermente dall'alto.
//
//   * Personaggio corrente al FRONT (basso dell'ellisse, davanti al viewer,
//     piu' grande)
//   * Personaggi laterali ai LATI (medi)
//   * Personaggi dietro al BACK (alto dell'ellisse, piu' piccoli e piu'
//     trasparenti, parzialmente nascosti dalla ruota)
//   * Ordinamento z-buffer: prima i personaggi dietro, poi quelli davanti
//
// Navigazione: Left/Right (tastiera) o asse X joystick ruota la ruota di
// un passo per volta (animazione smooth). Enter conferma.
//
// In 2P: P1 sceglie prima (selectPlayerStep=0), poi P2 (selectPlayerStep=1).
// Se P2 sceglie lo stesso personaggio di P1, viene applicato un tint bluastro.
// ---------------------------------------------------------------------------
void Game::drawSelectPlayer() {
    // Sfondo: gradiente notte (stesso del menu')
    for (int i = 0; i < 32; i++) {
        float t = (float)i / 31.f;
        sf::Uint8 r = (sf::Uint8)(30  + (1.f - t) * 25.f);
        sf::Uint8 g = (sf::Uint8)(20  + (1.f - t) * 10.f);
        sf::Uint8 b = (sf::Uint8)(60  + (1.f - t) * 30.f);
        sf::RectangleShape band(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT / 32.f + 1.f));
        band.setFillColor(sf::Color(r, g, b));
        band.setPosition(0.f, i * (WINDOW_HEIGHT / 32.f));
        window.draw(band);
    }

    // --- Titolo ---
    std::string title = (selectPlayerStep == 0) ? "SELECT PLAYER 1" : "SELECT PLAYER 2";
    drawTextCenteredOutlined(window, title, WINDOW_WIDTH/2, 100, 5, sf::Color(255, 215, 0));
    drawTextCenteredOutlined(window, title, WINDOW_WIDTH/2 - 4, 100 - 4, 5, sf::Color(180, 120, 40));

    // --- Indicatore giocatore corrente ---
    sf::Color playerColor = (selectPlayerStep == 0) ? sf::Color(255, 215, 0) : sf::Color(120, 180, 255);
    drawTextCenteredOutlined(window, "(JOYSTICK LEFT/RIGHT OR ARROWS TO ROTATE)",
        WINDOW_WIDTH/2, 150, 2, sf::Color(150, 150, 150));
    drawTextCenteredOutlined(window, "PRESS ENTER TO CONFIRM",
        WINDOW_WIDTH/2, 175, 2, playerColor);

    // --- Posizione centrale della ruota ---
    float centerX = WINDOW_WIDTH / 2.f;
    float centerY = WINDOW_HEIGHT / 2.f + 80.f;  // piu' in basso per lasciare spazio al titolo

    // --- RUOTA IN PROSPETTIVA ---
    // La ruota e' un'ellisse (cerchio compresso verticalmente) per dare
    // l'effetto "vista dall'alto in avanti". I personaggi stanno IN PIEDI
    // attorno al perimetro della ruota (non su una piattaforma frontale).
    //   * wheelRadiusX = raggio orizzontale (largo)
    //   * wheelRadiusY = raggio verticale (schiacciato per prospettiva)
    //   * perspectiveRatio = Y/X = grado di compressione (0.30 = molto schiacciata)
    // Palette 16 colori per stile coerente.
    const sf::Color COL_ROCK_DARK (48, 40, 36);
    const sf::Color COL_ROCK_MID  (96, 80, 72);
    const sf::Color COL_ROCK_LIGHT(160, 128, 112);
    const sf::Color COL_METAL_DARK(48, 40, 36);
    const sf::Color COL_METAL_LIGHT(200, 180, 160);
    const sf::Color COL_GOLD (220, 160, 40);
    const sf::Color COL_BLACK(12, 12, 12);

    float wheelRadiusX = 340.f;                       // raggio orizzontale
    float perspectiveRatio = 0.32f;                   // compressione verticale
    float wheelRadiusY = wheelRadiusX * perspectiveRatio;  // ~108 px

    // Tempo per animazione ingranaggi (static per persistere tra i frame)
    static float gearAnimTime = 0.f;
    gearAnimTime += 0.04f;
    bool isRotating = (wheelIndex != wheelTargetIndex);
    float gearSpeed = isRotating ? 0.12f : 0.04f;
    float gearRotation = gearAnimTime * gearSpeed * (wheelTargetIndex > wheelIndex ? 1.f : -1.f);

    // --- Angolo di rotazione della ruota (personaggi girano attorno al perno) ---
    // Ogni personaggio occupa un settore di 2pi/8. L'angolo 0 = destra,
    // PI/2 = davanti (basso), PI = sinistra, -PI/2 = dietro (alto).
    // Il personaggio selezionato (wheelIndex) deve trovarsi al FRONT (PI/2).
    float anglePerChar = 2.f * (float)M_PI / (float)CHARACTER_TYPE_COUNT;

    // Interpolazione smooth: quando la ruota sta ruotando (wheelRotation
    // avanza da 0 a 1), aggiungiamo una frazione di passo per dare continuita'
    // visiva (il personaggio non salta da una posizione all'altra).
    int diff = wheelTargetIndex - wheelIndex;
    if (diff > CHARACTER_TYPE_COUNT / 2) diff -= CHARACTER_TYPE_COUNT;
    else if (diff < -CHARACTER_TYPE_COUNT / 2) diff += CHARACTER_TYPE_COUNT;
    float interpStep = (diff != 0) ? wheelRotation * (diff > 0 ? 1.f : -1.f) : 0.f;

    // Angolo base della ruota: posizione di wheelIndex + interpStep
    // Usiamo PI/2 - (wheelIndex + interpStep) * anglePerChar in modo che
    // all'aumentare di wheelIndex la ruota giri in senso antiorario
    // (visivamente: il personaggio a destra scorre verso il front).
    float wheelAngleBase = (float)M_PI / 2.f - ((float)wheelIndex + interpStep) * anglePerChar;

    // --- 1. Ombra sotto la ruota ---
    sf::CircleShape wheelShadow(wheelRadiusX);
    wheelShadow.setFillColor(sf::Color(COL_BLACK.r, COL_BLACK.g, COL_BLACK.b, 110));
    wheelShadow.setScale(1.15f, perspectiveRatio * 0.55f);
    wheelShadow.setPosition(centerX - wheelRadiusX,
                            centerY + wheelRadiusY * 0.85f);
    window.draw(wheelShadow);

    // --- 2. Spessore laterale della ruota (cilindro visto in prospettiva) ---
    // Per dare l'effetto 3D, disegniamo due "pareti" laterali che mostrano
    // lo spessore della ruota (come se fosse un cilindro schiacciato).
    float rimThickness = 24.f;  // spessore del bordo della ruota
    // Lato sinistro
    sf::ConvexShape wheelLeftSide;
    wheelLeftSide.setPointCount(4);
    wheelLeftSide.setPoint(0, sf::Vector2f(centerX - wheelRadiusX, centerY - wheelRadiusY * 0.05f));
    wheelLeftSide.setPoint(1, sf::Vector2f(centerX - wheelRadiusX - rimThickness * 0.4f,
                                          centerY - wheelRadiusY * 0.05f + rimThickness * 0.3f));
    wheelLeftSide.setPoint(2, sf::Vector2f(centerX - wheelRadiusX - rimThickness * 0.4f,
                                          centerY + wheelRadiusY * 0.85f + rimThickness));
    wheelLeftSide.setPoint(3, sf::Vector2f(centerX - wheelRadiusX, centerY + wheelRadiusY * 0.85f));
    wheelLeftSide.setFillColor(COL_ROCK_DARK);
    wheelLeftSide.setOutlineThickness(2.f);
    wheelLeftSide.setOutlineColor(COL_BLACK);
    window.draw(wheelLeftSide);
    // Lato destro
    sf::ConvexShape wheelRightSide;
    wheelRightSide.setPointCount(4);
    wheelRightSide.setPoint(0, sf::Vector2f(centerX + wheelRadiusX, centerY - wheelRadiusY * 0.05f));
    wheelRightSide.setPoint(1, sf::Vector2f(centerX + wheelRadiusX + rimThickness * 0.4f,
                                           centerY - wheelRadiusY * 0.05f + rimThickness * 0.3f));
    wheelRightSide.setPoint(2, sf::Vector2f(centerX + wheelRadiusX + rimThickness * 0.4f,
                                           centerY + wheelRadiusY * 0.85f + rimThickness));
    wheelRightSide.setPoint(3, sf::Vector2f(centerX + wheelRadiusX, centerY + wheelRadiusY * 0.85f));
    wheelRightSide.setFillColor(COL_ROCK_DARK);
    wheelRightSide.setOutlineThickness(2.f);
    wheelRightSide.setOutlineColor(COL_BLACK);
    window.draw(wheelRightSide);

    // --- 3. Base della ruota (ellisse: cerchio compresso verticalmente) ---
    sf::CircleShape wheelBase(wheelRadiusX);
    wheelBase.setFillColor(COL_ROCK_DARK);
    wheelBase.setOutlineThickness(8.f);
    wheelBase.setOutlineColor(COL_ROCK_MID);
    wheelBase.setScale(1.f, perspectiveRatio);
    wheelBase.setPosition(centerX - wheelRadiusX, centerY - wheelRadiusY);
    window.draw(wheelBase);

    // --- 4. Anello interno (roccia piu' chiara, effetto profondita') ---
    float innerRadius = wheelRadiusX - 28.f;
    sf::CircleShape wheelInner(innerRadius);
    wheelInner.setFillColor(COL_ROCK_MID);
    wheelInner.setScale(1.f, perspectiveRatio);
    wheelInner.setPosition(centerX - innerRadius,
                           centerY - innerRadius * perspectiveRatio);
    window.draw(wheelInner);

    // --- 5. Raggi della ruota (linee dal centro al bordo) ---
    // Disegnati PRIMA dei personaggi e del perno centrale. I raggi ruotano
    // con wheelAngleBase per dare l'effetto "ruota che gira".
    for (int s = 0; s < CHARACTER_TYPE_COUNT; s++) {
        float a = wheelAngleBase + s * anglePerChar;
        float x1 = centerX;
        float y1 = centerY;
        float x2 = centerX + cosf(a) * (innerRadius - 8.f);
        float y2 = centerY + sinf(a) * (innerRadius - 8.f) * perspectiveRatio;
        // Disegna il raggio come rettangolo sottile ruotato
        float dx = x2 - x1, dy = y2 - y1;
        float len = std::sqrt(dx * dx + dy * dy);
        if (len < 1.f) continue;
        float angleDeg = std::atan2(dy, dx) * 180.f / (float)M_PI;
        sf::RectangleShape spoke(sf::Vector2f(6.f, len));
        spoke.setFillColor(sf::Color(COL_ROCK_LIGHT.r, COL_ROCK_LIGHT.g, COL_ROCK_LIGHT.b, 140));
        spoke.setOrigin(3.f, 0.f);
        spoke.setPosition(x1, y1);
        spoke.setRotation(angleDeg - 90.f);
        window.draw(spoke);
    }

    // --- 6. Perno centrale (hub metallico) ---
    sf::CircleShape wheelHub(46.f);
    wheelHub.setFillColor(COL_METAL_DARK);
    wheelHub.setOutlineThickness(5.f);
    wheelHub.setOutlineColor(COL_GOLD);
    wheelHub.setScale(1.f, perspectiveRatio);
    wheelHub.setPosition(centerX - 46.f, centerY - 46.f * perspectiveRatio);
    window.draw(wheelHub);
    // Bullone centrale
    sf::CircleShape wheelBolt(14.f);
    wheelBolt.setFillColor(COL_GOLD);
    wheelBolt.setOutlineThickness(2.f);
    wheelBolt.setOutlineColor(COL_METAL_DARK);
    wheelBolt.setScale(1.f, perspectiveRatio);
    wheelBolt.setPosition(centerX - 14.f, centerY - 14.f * perspectiveRatio);
    window.draw(wheelBolt);

    // --- 7. Ingranaggi decorativi attorno alla ruota (lato dietro, in alto) ---
    // Disposti a semicerchio sul retro della ruota (parte alta dell'ellisse),
    // non sul front, per non coprire i personaggi davanti.
    for (int g = 0; g < 6; g++) {
        // Distribuiti da 200° a 340° (parte alta dell'ellisse)
        float angle = (200.f + g * 28.f) * (float)M_PI / 180.f;
        float gx = centerX + cosf(angle) * (wheelRadiusX + 38.f);
        float gy = centerY + sinf(angle) * (wheelRadiusY + 30.f);
        float gearR = 22.f;
        sf::CircleShape gear(gearR);
        gear.setFillColor(COL_METAL_DARK);
        gear.setOutlineThickness(3.f);
        gear.setOutlineColor(COL_GOLD);
        gear.setOrigin(gearR, gearR);
        gear.setPosition(gx, gy);
        gear.rotate(gearRotation * 180.f / (float)M_PI + g * 60.f);
        window.draw(gear);
        // Denti dell'ingranaggio (8 piccoli rettangoli attorno)
        for (int t = 0; t < 8; t++) {
            float tAngle = t * (2.f * (float)M_PI / 8.f);
            sf::RectangleShape tooth(sf::Vector2f(6.f, 10.f));
            tooth.setFillColor(COL_METAL_LIGHT);
            tooth.setOrigin(3.f, 5.f);
            tooth.setPosition(gx + cosf(tAngle) * gearR, gy + sinf(tAngle) * gearR);
            tooth.rotate(tAngle * 180.f / (float)M_PI + gearRotation * 180.f / (float)M_PI + g * 60.f);
            window.draw(tooth);
        }
        // Centro ingranaggio (perno)
        sf::CircleShape gearHub(6.f);
        gearHub.setFillColor(COL_GOLD);
        gearHub.setPosition(gx - 6.f, gy - 6.f);
        window.draw(gearHub);
    }

    // --- 8. Personaggi SOPRA la ruota (in prospettiva, attorno al perimetro) ---
    // Per ogni personaggio calcoliamo posizione sull'ellisse, profondita'
    // (sinf(angle)), scala e alpha in base alla profondita'.
    struct CharPlacement {
        int   charIdx;
        float x, y;        // posizione piedi sull'ellisse
        float scale;       // scala (1 = front, piu' piccolo sul retro)
        float depth;       // -1 = back, +1 = front
        float alpha;       // 0..255
    };
    std::vector<CharPlacement> placements;
    placements.reserve(CHARACTER_TYPE_COUNT);

    for (int i = 0; i < CHARACTER_TYPE_COUNT; i++) {
        float a = wheelAngleBase + (float)i * anglePerChar;
        // Posizione sull'ellisse (perimetro della ruota in prospettiva)
        float x = centerX + cosf(a) * wheelRadiusX;
        float y = centerY + sinf(a) * wheelRadiusY;
        // Profondita': sinf(a) > 0 = davanti al viewer (front), < 0 = dietro
        float depth = sinf(a);
        // Scala: front = piu' grande (1.8), back = piu' piccolo (0.8)
        // Mappiamo depth [-1, +1] -> scale [0.8, 1.8]
        float scale = 0.8f + (depth + 1.f) * 0.5f;
        // Alpha: front = piu' opaco (250), back = piu' trasparente (130)
        float alpha = 130.f + (depth + 1.f) * 60.f;
        placements.push_back({ i, x, y, scale, depth, alpha });
    }

    // Ordina per depth crescente: prima i personaggi dietro (depth minore),
    // poi quelli davanti. Cosi' quelli davanti vengono disegnati SOPRA
    // (z-order corretto per occlusione).
    std::sort(placements.begin(), placements.end(),
              [](const CharPlacement& a, const CharPlacement& b) {
                  return a.depth < b.depth;
              });

    // Disegna i personaggi in ordine (dietro -> davanti)
    for (const auto& p : placements) {
        CharacterType ct = (CharacterType)p.charIdx;

        // Tint: P1 = bianco, P2 = bluastro
        sf::Color tint = getPlayerTint(selectPlayerStep + 1);
        if (selectPlayerStep == 1 && ct == player1Character) {
            tint = getPlayerTint(2);
        }

        // Ombra del personaggio sulla ruota (schiacciata in prospettiva)
        sf::CircleShape charShadow(28.f * p.scale);
        charShadow.setFillColor(sf::Color(COL_BLACK.r, COL_BLACK.g, COL_BLACK.b,
                                           (sf::Uint8)(p.alpha * 0.35f)));
        charShadow.setScale(1.f, perspectiveRatio * 0.9f);
        charShadow.setPosition(p.x - 28.f * p.scale, p.y - 4.f);
        window.draw(charShadow);

        // Disegna anteprima personaggio SOPRA il punto di appoggio
        // (drawCharacterPreview usa (x, y) come posizione dei piedi)
        drawCharacterPreview(window, ct, p.x, p.y, p.scale, tint, (sf::Uint8)p.alpha);

        // Highlight per il personaggio al FRONT (selezione corrente)
        // Lo identifichiamo come quello piu' vicino a depth=1 (front).
        if (p.charIdx == wheelIndex) {
            float arrowY = p.y - 70.f * p.scale;
            sf::ConvexShape arrow;
            arrow.setPointCount(3);
            arrow.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                          (sf::Uint8)(200 + sinf(gearAnimTime * 5.f) * 55)));
            arrow.setPoint(0, sf::Vector2f(p.x, arrowY + 18.f));
            arrow.setPoint(1, sf::Vector2f(p.x - 14.f, arrowY));
            arrow.setPoint(2, sf::Vector2f(p.x + 14.f, arrowY));
            window.draw(arrow);

            // Cerchio luminescente attorno al personaggio selezionato
            sf::CircleShape selGlow(48.f * p.scale);
            selGlow.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0));
            selGlow.setOutlineThickness(4.f);
            selGlow.setOutlineColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
                                               (sf::Uint8)(120 + sinf(gearAnimTime * 4.f) * 60)));
            selGlow.setScale(1.f, perspectiveRatio);
            selGlow.setPosition(p.x - 48.f * p.scale, p.y - 48.f * p.scale * perspectiveRatio);
            window.draw(selGlow);
        }
    }

    // --- Nome personaggio corrente (sotto la ruota) ---
    std::string charName = getCharacterName((CharacterType)wheelIndex);
    drawTextCenteredOutlined(window, charName, WINDOW_WIDTH/2,
                              (int)(centerY + wheelRadiusY + 80.f), 5, playerColor);

    // --- Indicatore "P1 scelto: XXX" (in 2P, step 1) ---
    if (selectPlayerStep == 1) {
        std::string p1Info = "P1: " + getCharacterName(player1Character);
        drawTextCenteredOutlined(window, p1Info, WINDOW_WIDTH/2, 250, 3, sf::Color(255, 215, 0));
    }
    // --- Indicatore "P2: scegliere personaggio" (in 2P, step 1) ---
    if (selectPlayerStep == 1 && numPlayers == 2) {
        drawTextCenteredOutlined(window, "P2: SELECT YOUR CHARACTER", WINDOW_WIDTH/2, 280, 2, sf::Color(120, 180, 255));
    }
    // --- Indicatore conferma dopo che P2 ha scelto (torna al menu) ---
    if (selectPlayerStep == 0 && numPlayers == 2) {
        // Se siamo qui dopo una selezione P2, mostra entrambi per 1 frame
        // (il state cambia a STATE_MENU subito, quindi questo e' solo visivo
        // se si torna a SELECT_PLAYER)
    }

    // --- Istruzioni in basso ---
    drawTextCenteredOutlined(window, "ESC TO GO BACK", WINDOW_WIDTH/2, WINDOW_HEIGHT - 50, 2, sf::Color(120, 120, 120));
}

// ---------------------------------------------------------------------------
// drawCharacterPreview: disegna un'anteprima del personaggio per la schermata
// di selezione. Usa sprite PNG se disponibile (cached staticamente),
// altrimenti fallback a primitive SFML.
// ---------------------------------------------------------------------------
void Game::drawCharacterPreview(sf::RenderTarget& target, CharacterType ct,
                                 float x, float y, float scale,
                                 const sf::Color& tint, sf::Uint8 alpha) {
    // Cache statica di sprite per personaggio
    static SpriteSheet charSprites[CHARACTER_TYPE_COUNT];
    static bool charSpritesInit[CHARACTER_TYPE_COUNT] = {false};
    if (!charSpritesInit[(int)ct]) {
        charSpritesInit[(int)ct] = true;
        std::string basePath = getCharacterSpriteBase(ct);
        charSprites[(int)ct].load(basePath);
    }

    if (charSprites[(int)ct].isLoaded()) {
        sf::Color tintedAlpha(tint.r, tint.g, tint.b, alpha);
        charSprites[(int)ct].render(target, "idle", 0, x, y, scale, false, tintedAlpha);
    } else {
        // Fallback: primitive SFML (semplificato per anteprima)
        const sf::Color COL_DARK(48, 40, 36);
        const sf::Color COL_PALE(200, 180, 160);
        const sf::Color COL_GOLD(220, 160, 40);
        const sf::Color COL_BLACK(12, 12, 12);
        const sf::Color COL_RED_L(200, 80, 80);
        const sf::Color COL_BLUE_L(80, 160, 220);
        const sf::Color COL_GREEN_L(80, 120, 100);
        const sf::Color COL_RED(160, 40, 40);

        auto tcol = [&](const sf::Color& c) -> sf::Color {
            return sf::Color(
                (sf::Uint8)(c.r * tint.r / 255 * alpha / 255),
                (sf::Uint8)(c.g * tint.g / 255 * alpha / 255),
                (sf::Uint8)(c.b * tint.b / 255 * alpha / 255),
                alpha);
        };

        sf::Color bodyCol, headCol;
        switch (ct) {
            case CHAR_HERO_M:   bodyCol = COL_DARK;   headCol = COL_PALE; break;
            case CHAR_HERO_F:   bodyCol = COL_RED_L;  headCol = COL_PALE; break;
            case CHAR_MAGE:     bodyCol = COL_BLUE_L; headCol = COL_PALE; break;
            case CHAR_ORC:      bodyCol = COL_DARK;   headCol = COL_GREEN_L; break;
            case CHAR_ELF:      bodyCol = COL_GREEN_L; headCol = COL_PALE; break;
            case CHAR_KNIGHT:   bodyCol = COL_PALE;   headCol = COL_DARK; break;
            case CHAR_GOLEM:   bodyCol = COL_DARK;   headCol = COL_DARK; break;
            case CHAR_DRAGON:  bodyCol = COL_RED;    headCol = COL_RED_L; break;
            case CHAR_VAMPIRE: bodyCol = COL_BLACK;  headCol = COL_PALE; break;
        }
        bodyCol = tcol(bodyCol);
        headCol = tcol(headCol);

        float bw = 20.f * scale;
        float bh = 22.f * scale;
        sf::RectangleShape body(sf::Vector2f(bw, bh));
        body.setFillColor(bodyCol);
        body.setOutlineThickness(1.f);
        body.setOutlineColor(tcol(COL_BLACK));
        body.setOrigin(bw / 2.f, bh / 2.f);
        body.setPosition(x, y);
        target.draw(body);

        float hr = 7.f * scale;
        sf::CircleShape head(hr);
        head.setFillColor(headCol);
        head.setOutlineThickness(1.f);
        head.setOutlineColor(tcol(COL_BLACK));
        head.setPosition(x - hr, y - bh / 2.f - hr - 2.f);
        target.draw(head);

        float eyeR = 1.f * scale;
        sf::CircleShape eye1(eyeR);
        eye1.setFillColor(tcol(COL_BLACK));
        eye1.setPosition(x - 3.f * scale, y - bh / 2.f - hr);
        target.draw(eye1);
        sf::CircleShape eye2(eyeR);
        eye2.setFillColor(tcol(COL_BLACK));
        eye2.setPosition(x + 2.f * scale, y - bh / 2.f - hr);
        target.draw(eye2);

        // Dettagli per tipo
        switch (ct) {
            case CHAR_MAGE: {
                sf::ConvexShape hat;
                hat.setPointCount(3);
                hat.setFillColor(tcol(COL_BLUE_L));
                hat.setPoint(0, sf::Vector2f(x - 7.f * scale, y - bh/2.f - hr - 4.f));
                hat.setPoint(1, sf::Vector2f(x + 7.f * scale, y - bh/2.f - hr - 4.f));
                hat.setPoint(2, sf::Vector2f(x, y - bh/2.f - hr - 16.f * scale));
                target.draw(hat);
                break;
            }
            case CHAR_KNIGHT: {
                sf::RectangleShape helmet(sf::Vector2f(14.f * scale, 10.f * scale));
                helmet.setFillColor(tcol(COL_PALE));
                helmet.setOutlineThickness(1.f);
                helmet.setOutlineColor(tcol(COL_BLACK));
                helmet.setPosition(x - 7.f * scale, y - bh/2.f - hr - 10.f);
                target.draw(helmet);
                break;
            }
            case CHAR_ORC: {
                for (int side = 0; side < 2; side++) {
                    float dir = (side == 0) ? -1.f : 1.f;
                    sf::ConvexShape fang;
                    fang.setPointCount(3);
                    fang.setFillColor(tcol(COL_PALE));
                    fang.setPoint(0, sf::Vector2f(x + dir * 2.f * scale, y - bh/2.f + 2.f));
                    fang.setPoint(1, sf::Vector2f(x + dir * 3.f * scale, y - bh/2.f + 6.f * scale));
                    fang.setPoint(2, sf::Vector2f(x + dir * 1.f * scale, y - bh/2.f + 6.f * scale));
                    target.draw(fang);
                }
                break;
            }
            case CHAR_DRAGON: {
                for (int side = 0; side < 2; side++) {
                    float dir = (side == 0) ? -1.f : 1.f;
                    sf::ConvexShape wing;
                    wing.setPointCount(3);
                    wing.setFillColor(tcol(COL_RED));
                    wing.setPoint(0, sf::Vector2f(x + dir * 10.f * scale, y));
                    wing.setPoint(1, sf::Vector2f(x + dir * 20.f * scale, y - 6.f * scale));
                    wing.setPoint(2, sf::Vector2f(x + dir * 16.f * scale, y + 8.f * scale));
                    target.draw(wing);
                }
                break;
            }
            case CHAR_VAMPIRE: {
                sf::ConvexShape cloak;
                cloak.setPointCount(3);
                cloak.setFillColor(tcol(COL_BLACK));
                cloak.setPoint(0, sf::Vector2f(x, y - bh/2.f));
                cloak.setPoint(1, sf::Vector2f(x - 14.f * scale, y + bh/2.f));
                cloak.setPoint(2, sf::Vector2f(x + 14.f * scale, y + bh/2.f));
                target.draw(cloak);
                break;
            }
            default: break;
        }

        // Gambe
        float lw = 7.f * scale;
        float lh = 18.f * scale;
        sf::RectangleShape leg1(sf::Vector2f(lw, lh));
        leg1.setFillColor(tcol(COL_DARK));
        leg1.setOutlineThickness(0.5f);
        leg1.setOutlineColor(tcol(COL_BLACK));
        leg1.setPosition(x - 7.f * scale, y + bh/2.f);
        target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(lw, lh));
        leg2.setFillColor(tcol(COL_DARK));
        leg2.setOutlineThickness(0.5f);
        leg2.setOutlineColor(tcol(COL_BLACK));
        leg2.setPosition(x + 1.f * scale, y + bh/2.f);
        target.draw(leg2);
    }
}

// ---------------------------------------------------------------------------
// render: disegna tutto in base allo stato. Pulisce con nero (10,10,10)
// e chiama display() alla fine.
//
// Stati di rendering:
//   * MENU/CONFIG_JOY: sfondi dedicati
//   * PLAYING/LOSE/WIN_INFINITE: labirinto + UI + entita' (LOSE ha overlay)
//   * BOSS: sfondo nero + boss + armi + proiettili (nessun labirinto)
//   * WIN_STORY: sfondo + fuochi d'artificio + messaggi
// ---------------------------------------------------------------------------
void Game::render() {
    window.clear(sf::Color(10, 10, 10));

    if (state == STATE_MENU) {
        drawMenu();
    }
    else if (state == STATE_SELECT_PLAYER) {
        drawSelectPlayer();
    }
    else if (state == STATE_CONFIG_JOY) {
        drawConfigJoy();
    }
    else if (state == STATE_CONFIG_JOY_2) {
        drawConfigJoy2();
    }
    else if (state == STATE_CONTINUES) {
        drawContinues();
    }
    else if (state == STATE_PLAYING || state == STATE_LOSE || state == STATE_WIN_INFINITE) {
        // Rendering comune per gameplay/schermate finali
        maze.render(window);
        if (numPlayers == 2)
            ui.render(window, player, player2, maze.getRemainingTreasures());
        else
            ui.render(window, player, maze.getRemainingTreasures());
        player.render(window);
        if (numPlayers == 2) player2.render(window);
        // Render dei nemici: inclusi quelli in animazione di morte (isDying)
        // finche' non e' conclusa (isDeathAnimDone). Quelli gia' conclusi
        // non vengono renderizzati.
        for (const auto& enemy : enemies) if (!enemy.isDeathAnimDone()) enemy.render(window);

        // --- Rendering del mini-boss (se presente e non morto) ---
        // Il mini-boss e' renderizzato in stile boss ma con dimensioni piccole
        // (32-40px). Aura pulsante, corpo dettagliato, arma in mano, barra HP.
        if (miniBoss && !miniBoss->isDead()) {
            miniBoss->render(window);
        }

        // Proiettili nemici: piccoli cerchi rossi (3px) con outline
        for (const auto& p : enemyProjectiles) {
            if (p.active) {
                sf::CircleShape proj(3.f); proj.setFillColor(sf::Color(255, 80, 40));
                proj.setOutlineThickness(1.f); proj.setOutlineColor(sf::Color(120, 20, 0));
                proj.setPosition(p.pos.x - 3.f, p.pos.y - 3.f); window.draw(proj);
            }
        }

        // Particelle: alpha proporzionale al rapporto life/maxLife
        // Ogni particella ha un nucleo + glow per visibilita'. Le particelle
        // di tipo 1 (fiamme) sono triangoli che puntano verso l'alto, molto
        // piu' visibili dei cerchi. Le particelle tipo 2 sono quadrati
        // (detriti/cenere).
        for (const auto& p : particles) {
            float lifeRatio = (float)p.life / (float)p.maxLife;
            sf::Uint8 alpha = (sf::Uint8)(255 * lifeRatio);
            float sz = p.size;
            // --- Glow esterno (cerchio grande semitrasparente) ---
            sf::CircleShape glow(sz * 2.f);
            glow.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b,
                                        (sf::Uint8)(alpha * 0.35f)));
            glow.setPosition(p.pos.x - sz * 2.f, p.pos.y - sz * 2.f);
            window.draw(glow);
            // --- Nucleo (forma in base al type) ---
            if (p.type == 1) {
                // Fiamma triangolare (punta verso l'alto)
                sf::ConvexShape flame;
                flame.setPointCount(3);
                flame.setPoint(0, sf::Vector2f(p.pos.x - sz, p.pos.y + sz));      // base sx
                flame.setPoint(1, sf::Vector2f(p.pos.x + sz, p.pos.y + sz));      // base dx
                flame.setPoint(2, sf::Vector2f(p.pos.x, p.pos.y - sz * 1.5f));    // punta alto
                flame.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, alpha));
                window.draw(flame);
            } else if (p.type == 2) {
                // Quadrato (detriti/cenere)
                sf::RectangleShape sq(sf::Vector2f(sz * 2.f, sz * 2.f));
                sq.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, alpha));
                sq.setPosition(p.pos.x - sz, p.pos.y - sz);
                window.draw(sq);
            } else {
                // Cerchio (default: sangue/scintille)
                sf::CircleShape c(sz);
                c.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, alpha));
                c.setPosition(p.pos.x - sz, p.pos.y - sz);
                window.draw(c);
            }
        }

        // --- Macchie di sangue temporanee sul pavimento ---
        for (const auto& bs : bloodStains) {
            float alpha = 200.f * (float)bs.life / (float)bs.maxLife;
            if (alpha < 0) alpha = 0;
            // Macchia principale (irregolare)
            sf::CircleShape stain(bs.radius);
            stain.setFillColor(sf::Color(bs.color.r, bs.color.g, bs.color.b, (sf::Uint8)alpha));
            stain.setPosition(bs.pos.x - bs.radius, bs.pos.y - bs.radius);
            window.draw(stain);
            // Schizzi più piccoli attorno
            for (int i = 0; i < 4; i++) {
                float angle = i * (float)M_PI / 2.f + 0.5f;
                float dist = bs.radius * 1.5f;
                float sx = bs.pos.x + cosf(angle) * dist;
                float sy = bs.pos.y + sinf(angle) * dist;
                float sr = bs.radius * 0.4f;
                sf::CircleShape splash(sr);
                splash.setFillColor(sf::Color(bs.color.r, bs.color.g, bs.color.b, (sf::Uint8)(alpha * 0.7f)));
                splash.setPosition(sx - sr, sy - sr);
                window.draw(splash);
            }
        }

        // --- Mucchi di cenere (nemici bruciati dal player invincibile) ---
        // Renderizzato tramite drawAshPiles() che usa spritesheet PNG avanzato
        // (effect_ashpile) + braci incandescenti + fumo procedurale.
        drawAshPiles(window);

        // --- Esplosioni di fuoco (nemici bruciati dal player invincibile) ---
        // Renderizzato tramite drawFireBursts() che usa spritesheet PNG
        // avanzato (effect_fireburst) + glow radiale multistrato.
        drawFireBursts(window);

        // --- Rendering dello scettro magico (stile Gandalf) ---
        // Disegna il bastone di Gandalf: legno intagliato lungo, gemma
        // cristallina luminosa in cima tenuta da raggi dorati, impugnatura
        // con anelli metallici e cuoio. Implementazione centralizzata in
        // drawMagicScepter() per evitare duplicazione tra i 3 stati.
        if (scepter.active && !scepter.triggered) {
            float sx = scepter.pos.x;
            float sy = scepter.pos.y + scepter.bobOffset;
            float sPulse = sinf(scepter.pulse * 4.f) * 0.15f + 1.f;
            drawMagicScepter(window, sx, sy, sPulse);
        }

        // --- Rendering dei fulmini (scettro magico) ---
        // Il fulmine attraversa VERTICALMENTE lo schermo (dall'alto al
        // basso), e' molto piu' visibile del vecchio fulmine 6-segmenti:
        // -12 segmenti alti 25px ciascuno (altezza totale 300px)
        // -Larghezza 3px (era 2) con outline bianca
        // -Bagliore esterno semitrasparente
        // -Flash bianco centrale
        for (const auto& lt : lightnings) {
            drawLightning(window, lt);
        }

        // --- Rendering del calice d'oro (pozione magica) ---
        // Calice dettagliato stile fantasy: coppa d'oro lavorata con gemma
        // rossa incastonata, stelo decorato, base larga. Colori della palette
        // 16 colori OBBLIGATORIA (220,160,40)=oro, (160,40,40)=rosso scuro,
        // (200,80,80)=rosso chiaro, (240,240,240)=riflesso bianco, (48,40,36)=ombra.
        if (chalice.active) {
            float cx = chalice.pos.x;
            float cy = chalice.pos.y + chalice.bobOffset;
            float pulse = sinf(chalice.pulse * 4.f) * 0.15f + 1.f;
            // Colori palette 16
            const sf::Color COL_GOLD   (220, 160, 40);   // oro principale
            const sf::Color COL_RED_D  (160, 40, 40);    // rosso scuro (gemma)
            const sf::Color COL_RED_L  (200, 80, 80);    // rosso chiaro (highlight gemma)
            const sf::Color COL_WHITE  (240, 240, 240);   // riflesso
            const sf::Color COL_DARK   (48, 40, 36);      // outline/ombra
            // Aura dorata pulsante
            float auraR = 20.f * pulse;
            sf::CircleShape chaliceAura(auraR);
            chaliceAura.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 50));
            chaliceAura.setPosition(cx - auraR, cy - auraR);
            window.draw(chaliceAura);
            // Coppa d'oro (forma trapezoidale con ConvexShape per realismo)
            sf::ConvexShape cup;
            cup.setPointCount(6);
            cup.setPoint(0, sf::Vector2f(cx - 6.f, cy - 4.f));  // alto-sx
            cup.setPoint(1, sf::Vector2f(cx + 6.f, cy - 4.f));  // alto-dx
            cup.setPoint(2, sf::Vector2f(cx + 5.f, cy + 2.f));  // basso-dx
            cup.setPoint(3, sf::Vector2f(cx + 3.f, cy + 5.f));  // medio-dx
            cup.setPoint(4, sf::Vector2f(cx - 3.f, cy + 5.f));  // medio-sx
            cup.setPoint(5, sf::Vector2f(cx - 5.f, cy + 2.f));  // basso-sx
            cup.setFillColor(COL_GOLD);
            cup.setOutlineThickness(1.f);
            cup.setOutlineColor(COL_DARK);
            window.draw(cup);
            // Bordo superiore della coppa (ellisse per dare "profondita'")
            sf::CircleShape rim(6.f);
            rim.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 200));
            rim.setOutlineThickness(0.8f);
            rim.setOutlineColor(COL_DARK);
            rim.setScale(1.f, 0.35f);
            rim.setPosition(cx - 6.f, cy - 6.f);
            window.draw(rim);
            // Gemma rossa centrale (incastonata)
            float gemR = 2.5f * pulse;
            sf::CircleShape gem(gemR);
            gem.setFillColor(COL_RED_D);
            gem.setOutlineThickness(0.5f);
            gem.setOutlineColor(COL_DARK);
            gem.setPosition(cx - gemR, cy - 2.f);
            window.draw(gem);
            // Highlight gemma (riflesso rosso chiaro)
            sf::CircleShape gemHigh(0.8f);
            gemHigh.setFillColor(COL_RED_L);
            gemHigh.setPosition(cx - 1.5f, cy - 3.f);
            window.draw(gemHigh);
            // Stelo decorato (con anello centrale)
            sf::RectangleShape stem(sf::Vector2f(3.f, 6.f));
            stem.setFillColor(COL_GOLD);
            stem.setOutlineThickness(0.4f);
            stem.setOutlineColor(COL_DARK);
            stem.setPosition(cx - 1.5f, cy + 5.f);
            window.draw(stem);
            // Anello decorativo stelo (nodo centrale)
            sf::CircleShape stemNode(1.5f);
            stemNode.setFillColor(COL_GOLD);
            stemNode.setOutlineThickness(0.4f);
            stemNode.setOutlineColor(COL_DARK);
            stemNode.setPosition(cx - 1.5f, cy + 7.f);
            window.draw(stemNode);
            // Base larga (rettangolo + ellisse per profondita')
            sf::RectangleShape base(sf::Vector2f(14.f, 2.5f));
            base.setFillColor(COL_GOLD);
            base.setOutlineThickness(0.8f);
            base.setOutlineColor(COL_DARK);
            base.setPosition(cx - 7.f, cy + 11.f);
            window.draw(base);
            // Base ellisse inferiore (ombra)
            sf::CircleShape baseShadow(7.f);
            baseShadow.setFillColor(sf::Color(COL_DARK.r, COL_DARK.g, COL_DARK.b, 150));
            baseShadow.setScale(1.f, 0.3f);
            baseShadow.setPosition(cx - 7.f, cy + 12.f);
            window.draw(baseShadow);
            // Riflesso luce sulla coppa (linea bianca verticale)
            sf::RectangleShape ref(sf::Vector2f(1.f, 4.f));
            ref.setFillColor(sf::Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, 200));
            ref.setPosition(cx - 4.f, cy - 2.f);
            window.draw(ref);
            // Ombra del calice sul pavimento
            sf::CircleShape shadow(6.f);
            shadow.setFillColor(sf::Color(COL_DARK.r, COL_DARK.g, COL_DARK.b, 80));
            shadow.setScale(1.5f, 0.4f);
            shadow.setPosition(cx - 6.f, cy + 14.f);
            window.draw(shadow);
        }

        // --- Aura di FUOCO attorno al player1 (invincibilità calice) ---
        // Sostituisce la vecchia aura gialla: ora il player e' avvolto da
        // fiamme animate che bruciano i nemici al contatto.
        if (playerInvincibleTimer > 0) {
            drawFireAura(window, player.getPixelPos(), playerInvincibleTimer);
        }
        // --- Aura di FUOCO attorno al player2 (invincibilità calice) ---
        if (numPlayers == 2 && player2InvincibleTimer > 0) {
            drawFireAura(window, player2.getPixelPos(), player2InvincibleTimer);
        }

        // --- Rendering della mina ---
        if (mine.active) {
            float mx = mine.pos.x;
            float my = mine.pos.y;
            float pulse = sinf(mine.pulse * 5.f) * 0.2f + 1.f;

            // Aura rossa pulsante
            float auraR = 18.f * pulse;
            sf::CircleShape mineAura(auraR);
            mineAura.setFillColor(sf::Color(200, 50, 20, 50));
            mineAura.setPosition(mx - auraR, my - auraR);
            window.draw(mineAura);

            // Corpo della mina (cerchio metallico scuro)
            float bodyR = 7.f * pulse;
            sf::CircleShape mineBody(bodyR);
            mineBody.setFillColor(sf::Color(80, 70, 60));
            mineBody.setOutlineThickness(1.5f);
            mineBody.setOutlineColor(sf::Color(30, 25, 20));
            mineBody.setPosition(mx - bodyR, my - bodyR);
            window.draw(mineBody);

            // Spunzoni (4 piccoli triangoli attorno al corpo)
            for (int i = 0; i < 4; i++) {
                float a = mine.rotation + i * (float)M_PI / 2.f;
                float spikeLen = 5.f;
                sf::ConvexShape spike;
                spike.setPointCount(3);
                spike.setFillColor(sf::Color(100, 85, 70));
                spike.setOutlineThickness(0.5f);
                spike.setOutlineColor(sf::Color(30, 25, 20));
                float tipX = mx + cosf(a) * (bodyR + spikeLen);
                float tipY = my + sinf(a) * (bodyR + spikeLen);
                float perpX = -sinf(a) * 3.f;
                float perpY = cosf(a) * 3.f;
                float baseX = mx + cosf(a) * bodyR;
                float baseY = my + sinf(a) * bodyR;
                spike.setPoint(0, sf::Vector2f(tipX, tipY));
                spike.setPoint(1, sf::Vector2f(baseX + perpX, baseY + perpY));
                spike.setPoint(2, sf::Vector2f(baseX - perpX, baseY - perpY));
                window.draw(spike);
            }

            // LED rosso pulsante al centro
            float ledR = 2.f * pulse;
            sf::CircleShape led(ledR);
            led.setFillColor(sf::Color(255, 50 + (sf::Uint8)(sinf(mine.pulse * 8.f) * 50), 30, 240));
            led.setPosition(mx - ledR, my - ledR);
            window.draw(led);

            // Scia quando rimbalza
            if (mine.bouncing) {
                sf::CircleShape trail(3.f);
                trail.setFillColor(sf::Color(255, 150, 50, 100));
                trail.setPosition(mx - mine.vel.x - 3.f, my - mine.vel.y - 3.f);
                window.draw(trail);
            }
        }

        // --- Rendering del portale magico (respawn nemici) ---
        if (magicPortal.active) {
            float px = magicPortal.pos.x;
            float py = magicPortal.pos.y;
            float rot = magicPortal.rotation;
            float pulse = sinf(magicPortal.glowPulse * 4.f) * 0.2f + 1.f;

            // Aura esterna pulsante (viola-blu) - GRANDE per essere visibile
            float auraR = 55.f * pulse;
            sf::CircleShape portalAura(auraR);
            portalAura.setFillColor(sf::Color(120, 60, 220, 40));
            portalAura.setPosition(px - auraR, py - auraR);
            window.draw(portalAura);
            sf::CircleShape portalAura2(auraR * 0.65f);
            portalAura2.setFillColor(sf::Color(160, 80, 240, 60));
            portalAura2.setPosition(px - auraR * 0.65f, py - auraR * 0.65f);
            window.draw(portalAura2);
            sf::CircleShape portalAura3(auraR * 0.4f);
            portalAura3.setFillColor(sf::Color(200, 100, 255, 80));
            portalAura3.setPosition(px - auraR * 0.4f, py - auraR * 0.4f);
            window.draw(portalAura3);

            // Anelli rotanti del portale (4 anelli concentrici)
            for (int ring = 0; ring < 4; ring++) {
                float ringR = (16.f + ring * 8.f) * pulse;
                sf::CircleShape ringShape(ringR);
                ringShape.setFillColor(sf::Color(0, 0, 0, 0));
                ringShape.setOutlineThickness(3.f - ring * 0.5f);
                sf::Color ringCol = (ring == 0) ? sf::Color(220, 120, 255, 240) :
                                    (ring == 1) ? sf::Color(180, 90, 240, 200) :
                                    (ring == 2) ? sf::Color(140, 70, 210, 160) :
                                                   sf::Color(100, 50, 180, 120);
                ringShape.setOutlineColor(ringCol);
                ringShape.setPosition(px - ringR, py - ringR);
                window.draw(ringShape);
            }

            // Spirale di particelle rotanti (12 particelle)
            for (int i = 0; i < 12; i++) {
                float a = rot * 2.f + i * (float)M_PI / 6.f;
                float r = 14.f + sinf(rot + i) * 8.f;
                float sx = px + cosf(a) * r;
                float sy = py + sinf(a) * r;
                float sparkSize = 2.5f + sinf(rot * 3.f + i) * 1.f;
                sf::CircleShape spark(sparkSize);
                spark.setFillColor(sf::Color(230, 160, 255, 220));
                spark.setPosition(sx - sparkSize, sy - sparkSize);
                window.draw(spark);
            }

            // Centro del portale (nero/viola profondo)
            sf::CircleShape center(12.f);
            center.setFillColor(sf::Color(15, 5, 25, 220));
            center.setPosition(px - 12.f, py - 12.f);
            window.draw(center);

            // Bagliore centrale (fase-dependent)
            if (magicPortal.phase == 0) {
                // Apertura: bagliore crescente
                float openT = 1.f - (float)magicPortal.phaseTimer / 1000.f;
                float glowR = 6.f + openT * 12.f;
                sf::CircleShape innerGlow(glowR);
                innerGlow.setFillColor(sf::Color(200, 100, 255, (sf::Uint8)(180 * openT)));
                innerGlow.setPosition(px - glowR, py - glowR);
                window.draw(innerGlow);
            } else if (magicPortal.phase == 1) {
                // Spawn: bagliore intenso
                sf::CircleShape innerGlow(10.f);
                innerGlow.setFillColor(sf::Color(255, 150, 255, 180));
                innerGlow.setPosition(px - 10.f, py - 10.f);
                window.draw(innerGlow);
            } else if (magicPortal.phase == 2) {
                // Chiusura: bagliore decrescente
                float closeT = (float)magicPortal.phaseTimer / 800.f;
                float glowR = 4.f + closeT * 6.f;
                sf::CircleShape innerGlow(glowR);
                innerGlow.setFillColor(sf::Color(150, 80, 200, (sf::Uint8)(120 * closeT)));
                innerGlow.setPosition(px - glowR, py - glowR);
                window.draw(innerGlow);
            }
        }

        // --- Rendering della porta di uscita (exit door) ---
        // La porta appare dopo aver raccolto tutti i tesori. Ha:
        //   * Una cornice di pietra (architrave + stipiti)
        //   * Un'anta che si apre (animazione di 800ms)
        //   * Una scala visibile all'interno (gradini scuri che scendono)
        //   * Un'aura luminosa pulsante dorata
        if (exitDoor.active) {
            float dx = exitDoor.pos.x;
            float dy = exitDoor.pos.y;
            // Aura luminosa pulsante (dorata)
            float pulse = 1.0f + sinf(exitDoor.glowPulse * 3.f) * 0.15f;
            float auraR = 32.f * pulse;
            sf::CircleShape doorAura(auraR);
            doorAura.setFillColor(sf::Color(255, 200, 80, 50));
            doorAura.setPosition(dx - auraR, dy - auraR);
            window.draw(doorAura);
            sf::CircleShape doorAura2(auraR * 0.6f);
            doorAura2.setFillColor(sf::Color(255, 220, 100, 80));
            doorAura2.setPosition(dx - auraR * 0.6f, dy - auraR * 0.6f);
            window.draw(doorAura2);

            // Architrave (rettangolo orizzontale sopra la porta)
            sf::RectangleShape lintel(sf::Vector2f(40.f, 6.f));
            lintel.setFillColor(sf::Color(120, 100, 80));
            lintel.setOutlineThickness(1.f); lintel.setOutlineColor(sf::Color(50, 40, 30));
            lintel.setPosition(dx - 20.f, dy - 22.f);
            window.draw(lintel);
            // Decorazione architrave (simbolo)
            sf::CircleShape doorSym(3.f);
            doorSym.setFillColor(sf::Color(200, 160, 60));
            doorSym.setOutlineThickness(0.8f); doorSym.setOutlineColor(sf::Color(100, 80, 30));
            doorSym.setPosition(dx - 3.f, dy - 20.f);
            window.draw(doorSym);

            // Stipiti laterali (2 rettangoli verticali)
            sf::RectangleShape leftJamb(sf::Vector2f(4.f, 40.f));
            leftJamb.setFillColor(sf::Color(100, 85, 65));
            leftJamb.setOutlineThickness(0.8f); leftJamb.setOutlineColor(sf::Color(40, 35, 25));
            leftJamb.setPosition(dx - 20.f, dy - 16.f);
            window.draw(leftJamb);
            sf::RectangleShape rightJamb(sf::Vector2f(4.f, 40.f));
            rightJamb.setFillColor(sf::Color(100, 85, 65));
            rightJamb.setOutlineThickness(0.8f); rightJamb.setOutlineColor(sf::Color(40, 35, 25));
            rightJamb.setPosition(dx + 16.f, dy - 16.f);
            window.draw(rightJamb);

            // Interna della porta (apertura buia con gradiente verticale)
            // Il buio e' piu' intenso in alto (dove la scala sparisce in profondita')
            // e piu' chiaro in basso (dove inizia la scala, vicino al pavimento).
            float doorH = 36.f;
            for (int i = 0; i < 12; i++) {
                float t = (float)i / 11.f;
                float y0 = dy - 14.f + t * doorH;
                sf::Uint8 darkR = (sf::Uint8)(2 + t * 18);   // 2 -> 20
                sf::Uint8 darkG = (sf::Uint8)(2 + t * 12);   // 2 -> 14
                sf::Uint8 darkB = (sf::Uint8)(1 + t * 7);     // 1 -> 8
                sf::RectangleShape band(sf::Vector2f(32.f, doorH / 12.f + 1.f));
                band.setFillColor(sf::Color(darkR, darkG, darkB));
                band.setPosition(dx - 16.f, y0);
                window.draw(band);
            }

            // Gradini della scala che scendono (6 scalini con prospettiva)
            // Il primo gradino (in basso, vicino al pavimento) e' piu' largo
            // e piu' chiaro; l'ultimo (in alto, in profondita') e' piu' stretto
            // e piu' scuro. Questo da' l'effetto di una scala che scende
            // verso l'alto (prospettiva: ci si allontana verso il fondo).
            int numSteps = 6;
            float botStepY = dy + 16.f;   // partenza dal basso
            float stepSpacing = 5.f;
            float botStepW = 30.f;         // gradino in basso: largo e chiaro
            float topStepW = 14.f;         // gradino in alto: stretto e scuro
            for (int i = 0; i < numSteps; i++) {
                float t = (float)i / (float)(numSteps - 1);
                // i=0 e' in basso (largo/chiaro), i=numSteps-1 e' in alto (stretto/scuro)
                float stepY = botStepY - i * stepSpacing;
                float stepW = botStepW - (botStepW - topStepW) * t;
                // Colore: piu' scuro andando verso l'alto (profondita')
                sf::Uint8 sr = (sf::Uint8)(100 - t * 70);  // 100 -> 30
                sf::Uint8 sg = (sf::Uint8)(82 - t * 58);   // 82 -> 24
                sf::Uint8 sb = (sf::Uint8)(64 - t * 46);   // 64 -> 18
                // Gradino: rettangolo orizzontale (pianerottolo)
                sf::RectangleShape step(sf::Vector2f(stepW, 3.f));
                step.setFillColor(sf::Color(sr, sg, sb));
                step.setOutlineThickness(0.6f);
                step.setOutlineColor(sf::Color(sr / 2, sg / 2, sb / 2));
                step.setPosition(dx - stepW / 2.f, stepY);
                window.draw(step);
                // Alzata del gradino (parte verticale scura SOPRA il pianerottolo,
                // perche' la scala sale verso l'alto in profondita')
                if (i < numSteps - 1) {
                    sf::RectangleShape riser(sf::Vector2f(stepW, stepSpacing - 3.f));
                    sf::Uint8 rr = (sf::Uint8)(sr * 0.4f);
                    sf::Uint8 rg = (sf::Uint8)(sg * 0.4f);
                    sf::Uint8 rb = (sf::Uint8)(sb * 0.4f);
                    riser.setFillColor(sf::Color(rr, rg, rb));
                    riser.setPosition(dx - stepW / 2.f, stepY - (stepSpacing - 3.f));
                    window.draw(riser);
                }
                // Highlight sul bordo superiore del gradino (riflesso luce)
                sf::RectangleShape highlight(sf::Vector2f(stepW - 2.f, 0.8f));
                highlight.setFillColor(sf::Color(
                    (sf::Uint8)std::min(255, sr + 40),
                    (sf::Uint8)std::min(255, sg + 35),
                    (sf::Uint8)std::min(255, sb + 30), 200));
                highlight.setPosition(dx - (stepW - 2.f) / 2.f, stepY);
                window.draw(highlight);
            }

            // Bagliore profondo in fondo alla scala (in alto, punto luce che attira)
            float glowY = botStepY - (numSteps - 1) * stepSpacing - 2.f;
            float glowPulse2 = sinf(exitDoor.glowPulse * 2.f) * 0.3f + 0.7f;
            sf::CircleShape deepGlow(4.f * glowPulse2);
            deepGlow.setFillColor(sf::Color(200, 160, 60, 120));
            deepGlow.setPosition(dx - 4.f * glowPulse2, glowY - 4.f * glowPulse2);
            window.draw(deepGlow);
            // Scintilla centrale
            sf::CircleShape deepSpark(1.5f * glowPulse2);
            deepSpark.setFillColor(sf::Color(255, 230, 120, 200));
            deepSpark.setPosition(dx - 1.5f * glowPulse2, glowY - 1.5f * glowPulse2);
            window.draw(deepSpark);

            // Anta della porta (animazione di apertura: si apre verso destra)
            // Durante l'animazione (animTimer > 0), l'anta si sposta verso
            // destra rivelando la scala. Quando animTimer == 0, l'anta e'
            // completamente aperta.
            float openProgress = 1.0f - (float)exitDoor.animTimer / 800.f;
            if (openProgress < 0.f) openProgress = 0.f;
            if (openProgress > 1.f) openProgress = 1.f;
            float doorWidth = 32.f * (1.0f - openProgress);
            if (doorWidth > 0.5f) {
                sf::RectangleShape doorPanel(sf::Vector2f(doorWidth, 36.f));
                doorPanel.setFillColor(sf::Color(90, 60, 25));
                doorPanel.setOutlineThickness(1.f);
                doorPanel.setOutlineColor(sf::Color(40, 25, 10));
                doorPanel.setPosition(dx - 16.f, dy - 14.f);
                window.draw(doorPanel);
                // Venature del legno
                for (int i = 0; i < 3; i++) {
                    if (doorWidth > 4 + i * 6) {
                        sf::RectangleShape vein(sf::Vector2f(1.f, 30.f));
                        vein.setFillColor(sf::Color(60, 35, 15));
                        vein.setPosition(dx - 14.f + i * 6.f, dy - 12.f);
                        window.draw(vein);
                    }
                }
                // Maniglia (appare quando la porta e' quasi chiusa)
                if (openProgress < 0.3f) {
                    sf::CircleShape knob(1.5f);
                    knob.setFillColor(sf::Color(220, 180, 60));
                    knob.setOutlineThickness(0.4f);
                    knob.setOutlineColor(sf::Color(100, 70, 20));
                    knob.setPosition(dx + 8.f, dy + 1.f);
                    window.draw(knob);
                }
            }

            // Indicatore "ENTRA" sopra la porta quando e' aperta
            if (exitDoor.animTimer == 0) {
                float bobY = sinf(exitDoor.glowPulse * 4.f) * 2.f;
                drawTextCentered(window, "ENTRA", (int)dx, (int)(dy - 30.f + bobY), 1,
                                 sf::Color(255, 220, 80));
            }
        }

        // Overlay GAME OVER (solo in STATE_LOSE)
        if (state == STATE_LOSE) {
            sf::RectangleShape overlay(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
            overlay.setFillColor(sf::Color(0, 0, 0, 200));
            window.draw(overlay);
            drawTextCenteredOutlined(window, "GAME OVER", WINDOW_WIDTH/2, 350, 5, sf::Color::Red);
            drawTextCenteredOutlined(window, "PRESS ENTER", WINDOW_WIDTH/2, 450, 2, sf::Color::White);
        }
    }
    else if (state == STATE_BOSS) {
        // --- Stanza del boss: caverna scavata nella roccia ---
        // Sostituisce il vecchio sfondo nero piatto. Lo stile e' coerente
        // con quello del labirinto (Maze::render): pavimento terra battuta
        // scura con ciottoli sparsi, e muro perimetrale roccioso con bande
        // di illuminazione, ciottoli e crepe. NON viene usato il labirinto
        // vero e proprio: la stanza e' una grande arena quadrata.
        //
        // Tutte le variazioni sono deterministiche (hash 2D) per evitare
        // flicker tra frame. Le torce lungo i muri sono animate con una
        // static float (menuTime pattern gia' usato nel menu principale).
        {
            // --- Pavimento terra battuta ---
            // FIX: sfumatura continua (non a quadrati) basata sulla distanza
            // dal centro della stanza del boss, come fatto per il labirinto.
            auto floorHash = [](int c, int r) -> float {
                unsigned int h = (unsigned int)(c * 73856093u) ^ (unsigned int)(r * 19349663u);
                h ^= h >> 13;
                h *= 0x5bd1e995u;
                h ^= h >> 15;
                return (float)(h & 0xFFFFu) / 65535.f;
            };
            const int cellSize = 128;
            const int playTop = UI_HEIGHT;
            const int playH = WINDOW_HEIGHT - UI_HEIGHT;
            const int colsFloor = (WINDOW_WIDTH + cellSize - 1) / cellSize;
            const int rowsFloor = (playH + cellSize - 1) / cellSize;
            // Centro della stanza per il gradiente continuo
            float centerCol = colsFloor / 2.f;
            float centerRow = rowsFloor / 2.f;
            for (int fc = 0; fc < colsFloor; fc++) {
                for (int fr = 0; fr < rowsFloor; fr++) {
                    float fx = fc * cellSize;
                    float fy = playTop + fr * cellSize;
                    // Gradiente continuo: piu' chiaro al centro, scuro ai bordi
                    float dx = (fc - centerCol) / centerCol;
                    float dy = (fr - centerRow) / centerRow;
                    float dist = sqrtf(dx * dx + dy * dy);
                    dist = std::min(1.f, dist);
                    float brightness = 22.f - dist * 16.f;  // 22 centro, 6 bordi
                    sf::Uint8 bgr = (sf::Uint8)std::max(0, std::min(255, (int)(18 + brightness)));
                    sf::Uint8 bgg = (sf::Uint8)std::max(0, std::min(255, (int)(13 + brightness * 0.7f)));
                    sf::Uint8 bgb = (sf::Uint8)std::max(0, std::min(255, (int)(10 + brightness * 0.4f)));
                    sf::RectangleShape floorTile(sf::Vector2f((float)cellSize, (float)cellSize));
                    floorTile.setFillColor(sf::Color(bgr, bgg, bgb));
                    floorTile.setPosition(fx, fy);
                    window.draw(floorTile);
                    // 2-3 ciottoli sparsi sul pavimento per cella
                    int nPeb = 2 + (int)(floorHash(fc + 200, fr + 100) * 2.f);
                    for (int i = 0; i < nPeb; i++) {
                        float h1 = floorHash(fc * 17 + i + 100, fr * 3 + i + 50);
                        float h2 = floorHash(fc * 7 + i + 200, fr * 13 + i + 70);
                        float h3 = floorHash(fc * 23 + i + 1,  fr * 11 + i + 13);
                        float px = fx + 8.f + h1 * (cellSize - 16.f);
                        float py = fy + 8.f + h2 * (cellSize - 16.f);
                        float radius = 2.f + h3 * 2.5f;
                        sf::Uint8 pr = (sf::Uint8)(60 + h3 * 30);
                        sf::Uint8 pg = (sf::Uint8)(50 + h3 * 25);
                        sf::Uint8 pb = (sf::Uint8)(40 + h3 * 18);
                        sf::CircleShape pebble(radius);
                        pebble.setFillColor(sf::Color(pr, pg, pb));
                        pebble.setPosition(px - radius, py - radius);
                        window.draw(pebble);
                    }
                    // Macchie di terra scura in ~15% delle celle
                    if (floorHash(fc + 700, fr + 350) > 0.85f) {
                        float h1 = floorHash(fc + 800, fr + 400);
                        float h2 = floorHash(fc + 900, fr + 500);
                        float sx = fx + 16.f + h1 * (cellSize - 48.f);
                        float sy = fy + 16.f + h2 * (cellSize - 48.f);
                        sf::CircleShape stain(6.f + h1 * 5.f);
                        stain.setFillColor(sf::Color(8, 5, 3, 180));
                        stain.setPosition(sx - 6.f, sy - 6.f);
                        window.draw(stain);
                    }
                }
            }

            // --- Muri perimetrali rocciosi ---
            // Cornice di 24 px tutto attorno all'area di gioco (sotto la UI).
            // Stile cavernoso uguale a quello del labirinto: banda superiore
            // chiara (illuminazione), banda inferiore scura (ombra), ciottoli
            // e crepe deterministiche.
            const float wallThickness = 24.f;
            sf::Color rockBase(70, 60, 55);
            // Colore banda chiara (illuminazione calda da torcia)
            sf::Color rockLight(
                (sf::Uint8)std::min(255, rockBase.r + 40),
                (sf::Uint8)std::min(255, rockBase.g + 32),
                (sf::Uint8)std::min(255, rockBase.b + 22));
            // Colore banda scura (ombra / fessura)
            sf::Color rockDark(15, 10, 8);
            // Colore base scuro (ombra profonda)
            sf::Color rockDeep(
                (sf::Uint8)std::max(0, rockBase.r - 20),
                (sf::Uint8)std::max(0, rockBase.g - 18),
                (sf::Uint8)std::max(0, rockBase.b - 15));

            // Muro superiore (sotto la UI)
            sf::RectangleShape topWall(sf::Vector2f(WINDOW_WIDTH, wallThickness));
            topWall.setFillColor(rockDeep);
            topWall.setPosition(0, playTop);
            window.draw(topWall);
            // Banda chiara in basso del muro superiore (illuminazione verso il pavimento)
            sf::RectangleShape topLight(sf::Vector2f(WINDOW_WIDTH, 6.f));
            topLight.setFillColor(rockLight);
            topLight.setPosition(0, playTop + wallThickness - 6.f);
            window.draw(topLight);
            // Banda scura in alto (ombra verso UI)
            sf::RectangleShape topDark(sf::Vector2f(WINDOW_WIDTH, 4.f));
            topDark.setFillColor(rockDark);
            topDark.setPosition(0, playTop);
            window.draw(topDark);

            // Muro inferiore
            sf::RectangleShape botWall(sf::Vector2f(WINDOW_WIDTH, wallThickness));
            botWall.setFillColor(rockDeep);
            botWall.setPosition(0, WINDOW_HEIGHT - wallThickness);
            window.draw(botWall);
            sf::RectangleShape botLight(sf::Vector2f(WINDOW_WIDTH, 6.f));
            botLight.setFillColor(rockLight);
            botLight.setPosition(0, WINDOW_HEIGHT - wallThickness);
            window.draw(botLight);
            sf::RectangleShape botDark(sf::Vector2f(WINDOW_WIDTH, 4.f));
            botDark.setFillColor(rockDark);
            botDark.setPosition(0, WINDOW_HEIGHT - 4.f);
            window.draw(botDark);

            // Muro sinistro
            sf::RectangleShape leftWall(sf::Vector2f(wallThickness, playH));
            leftWall.setFillColor(rockDeep);
            leftWall.setPosition(0, playTop);
            window.draw(leftWall);
            sf::RectangleShape leftLight(sf::Vector2f(6.f, playH));
            leftLight.setFillColor(rockLight);
            leftLight.setPosition(wallThickness - 6.f, playTop);
            window.draw(leftLight);
            sf::RectangleShape leftDark(sf::Vector2f(4.f, playH));
            leftDark.setFillColor(rockDark);
            leftDark.setPosition(0, playTop);
            window.draw(leftDark);

            // Muro destro
            sf::RectangleShape rightWall(sf::Vector2f(wallThickness, playH));
            rightWall.setFillColor(rockDeep);
            rightWall.setPosition(WINDOW_WIDTH - wallThickness, playTop);
            window.draw(rightWall);
            sf::RectangleShape rightLight(sf::Vector2f(6.f, playH));
            rightLight.setFillColor(rockLight);
            rightLight.setPosition(WINDOW_WIDTH - wallThickness, playTop);
            window.draw(rightLight);
            sf::RectangleShape rightDark(sf::Vector2f(4.f, playH));
            rightDark.setFillColor(rockDark);
            rightDark.setPosition(WINDOW_WIDTH - 4.f, playTop);
            window.draw(rightDark);

            // Ciottoli sparsi sui muri (per ogni segmento di 32 px sui 4 lati)
            auto wallHash = [](int c, int r) -> float {
                unsigned int h = (unsigned int)(c * 73856093u) ^ (unsigned int)(r * 19349663u);
                h ^= h >> 13;
                h *= 0x5bd1e995u;
                h ^= h >> 15;
                return (float)(h & 0xFFFFu) / 65535.f;
            };
            // Muro superiore: ciottoli lungo la fascia
            for (int i = 0; i < WINDOW_WIDTH / 32; i++) {
                float h1 = wallHash(i + 1, 999);
                float h2 = wallHash(i + 500, 333);
                float h3 = wallHash(i + 100, 777);
                float cx = i * 32.f + 8.f + h1 * 16.f;
                float cy = playTop + 6.f + h2 * 12.f;
                float radius = 2.f + h3 * 2.f;
                sf::Uint8 cr = (sf::Uint8)std::min(255, rockBase.r + 15);
                sf::Uint8 cg = (sf::Uint8)std::min(255, rockBase.g + 12);
                sf::Uint8 cb = (sf::Uint8)std::min(255, rockBase.b + 8);
                sf::CircleShape pebble(radius);
                pebble.setFillColor(sf::Color(cr, cg, cb));
                pebble.setPosition(cx - radius, cy - radius);
                window.draw(pebble);
            }
            // Muro inferiore
            for (int i = 0; i < WINDOW_WIDTH / 32; i++) {
                float h1 = wallHash(i + 2, 998);
                float h2 = wallHash(i + 501, 334);
                float h3 = wallHash(i + 101, 778);
                float cx = i * 32.f + 8.f + h1 * 16.f;
                float cy = WINDOW_HEIGHT - wallThickness + 6.f + h2 * 12.f;
                float radius = 2.f + h3 * 2.f;
                sf::Uint8 cr = (sf::Uint8)std::min(255, rockBase.r + 15);
                sf::Uint8 cg = (sf::Uint8)std::min(255, rockBase.g + 12);
                sf::Uint8 cb = (sf::Uint8)std::min(255, rockBase.b + 8);
                sf::CircleShape pebble(radius);
                pebble.setFillColor(sf::Color(cr, cg, cb));
                pebble.setPosition(cx - radius, cy - radius);
                window.draw(pebble);
            }
            // Muro sinistro
            for (int i = 0; i < (playH) / 32; i++) {
                float h1 = wallHash(i + 3, 997);
                float h2 = wallHash(i + 502, 335);
                float h3 = wallHash(i + 102, 779);
                float cx = 6.f + h1 * 12.f;
                float cy = playTop + i * 32.f + 8.f + h2 * 16.f;
                float radius = 2.f + h3 * 2.f;
                sf::Uint8 cr = (sf::Uint8)std::min(255, rockBase.r + 15);
                sf::Uint8 cg = (sf::Uint8)std::min(255, rockBase.g + 12);
                sf::Uint8 cb = (sf::Uint8)std::min(255, rockBase.b + 8);
                sf::CircleShape pebble(radius);
                pebble.setFillColor(sf::Color(cr, cg, cb));
                pebble.setPosition(cx - radius, cy - radius);
                window.draw(pebble);
            }
            // Muro destro
            for (int i = 0; i < (playH) / 32; i++) {
                float h1 = wallHash(i + 4, 996);
                float h2 = wallHash(i + 503, 336);
                float h3 = wallHash(i + 103, 780);
                float cx = (float)(WINDOW_WIDTH - wallThickness) + 6.f + h1 * 12.f;
                float cy = playTop + i * 32.f + 8.f + h2 * 16.f;
                float radius = 2.f + h3 * 2.f;
                sf::Uint8 cr = (sf::Uint8)std::min(255, rockBase.r + 15);
                sf::Uint8 cg = (sf::Uint8)std::min(255, rockBase.g + 12);
                sf::Uint8 cb = (sf::Uint8)std::min(255, rockBase.b + 8);
                sf::CircleShape pebble(radius);
                pebble.setFillColor(sf::Color(cr, cg, cb));
                pebble.setPosition(cx - radius, cy - radius);
                window.draw(pebble);
            }

            // --- Torce animate lungo i muri ---
            // 4 torce per lato (totale 16), posizionate a distanze regolari.
            // Ogni torcia: bastone + cestello + fiamma a 3 strati animata +
            // aura luminosa. Stesso stile di quelle del menu principale.
            static float bossRoomTime = 0.f;
            bossRoomTime += 0.016f;
            auto drawTorch = [&](float x, float yBase) {
                // Bastone
                sf::RectangleShape handle(sf::Vector2f(5.f, 16.f));
                handle.setFillColor(sf::Color(60, 30, 10));
                handle.setOutlineThickness(0.8f); handle.setOutlineColor(sf::Color(20, 10, 0));
                handle.setPosition(x - 2.5f, yBase);
                window.draw(handle);
                // Cestello metallico
                sf::RectangleShape bracket(sf::Vector2f(10.f, 6.f));
                bracket.setFillColor(sf::Color(80, 80, 80));
                bracket.setOutlineThickness(0.8f); bracket.setOutlineColor(sf::Color(40, 40, 40));
                bracket.setPosition(x - 5.f, yBase - 6.f);
                window.draw(bracket);
                // Aura
                sf::CircleShape aura(20.f);
                aura.setFillColor(sf::Color(255, 180, 60, 35));
                aura.setPosition(x - 20.f, yBase - 38.f);
                window.draw(aura);
                // Fiamma animata (3 strati)
                float flicker = sinf(bossRoomTime * 18.f + x) * 2.f;
                // Strato esterno (rosso)
                sf::CircleShape flame3(8.f + flicker);
                flame3.setFillColor(sf::Color(180, 30, 10, 220));
                flame3.setPosition(x - 8.f - flicker, yBase - 26.f);
                window.draw(flame3);
                // Strato medio (arancione)
                sf::CircleShape flame2(5.5f + flicker * 0.5f);
                flame2.setFillColor(sf::Color(255, 140, 30, 240));
                flame2.setPosition(x - 5.5f - flicker * 0.5f, yBase - 22.f);
                window.draw(flame2);
                // Strato interno (giallo-bianco)
                sf::CircleShape flame1(3.f);
                flame1.setFillColor(sf::Color(255, 240, 180, 250));
                flame1.setPosition(x - 3.f, yBase - 18.f);
                window.draw(flame1);
            };
            // 4 torce sul muro superiore (appese, fiamma verso il basso)
            for (int i = 0; i < 4; i++) {
                float x = 200.f + i * (WINDOW_WIDTH - 400.f) / 3.f;
                drawTorch(x, playTop + wallThickness + 4.f);
            }
            // 4 torce sul muro inferiore
            for (int i = 0; i < 4; i++) {
                float x = 200.f + i * (WINDOW_WIDTH - 400.f) / 3.f;
                drawTorch(x, WINDOW_HEIGHT - wallThickness - 30.f);
            }
            // 3 torce sul muro sinistro
            for (int i = 0; i < 3; i++) {
                float y = playTop + 150.f + i * (playH - 300.f) / 2.f;
                drawTorch(wallThickness + 4.f, y);
            }
            // 3 torce sul muro destro
            for (int i = 0; i < 3; i++) {
                float y = playTop + 150.f + i * (playH - 300.f) / 2.f;
                drawTorch(WINDOW_WIDTH - wallThickness - 6.f, y);
            }

            // --- Vignette: leggero scuro ai bordi per dare profondita' ---
            // 4 bande sfumate molto sottili che scuriscono leggermente
            // gli angoli della stanza (effetto "luce centrale").
            // Implementazione economica: 4 rettangoli semitrasparenti
            // spessori 40 px sui lati.
            sf::RectangleShape vigL(sf::Vector2f(40.f, playH));
            vigL.setFillColor(sf::Color(0, 0, 0, 60));
            vigL.setPosition(wallThickness, playTop);
            window.draw(vigL);
            sf::RectangleShape vigR(sf::Vector2f(40.f, playH));
            vigR.setFillColor(sf::Color(0, 0, 0, 60));
            vigR.setPosition(WINDOW_WIDTH - wallThickness - 40.f, playTop);
            window.draw(vigR);
            sf::RectangleShape vigT(sf::Vector2f(WINDOW_WIDTH, 30.f));
            vigT.setFillColor(sf::Color(0, 0, 0, 60));
            vigT.setPosition(0, playTop + wallThickness);
            window.draw(vigT);
            sf::RectangleShape vigB(sf::Vector2f(WINDOW_WIDTH, 30.f));
            vigB.setFillColor(sf::Color(0, 0, 0, 60));
            vigB.setPosition(0, WINDOW_HEIGHT - wallThickness - 30.f);
            window.draw(vigB);

            // --- Decorazioni fantasy: cripta / tempio in rovina ---
            // La stanza del boss e' ambientata in una cripta scavata nella
            // roccia con resti di un antico tempio: colonne spezzate, basi
            // di colonna, capitelli caduti, tombe scoperchiate, lastre di
            // pietra con incisioni, teschi cumuli.
            //
            // Tutte le decorazioni sono POSIZIONATE AI BORDI della stanza
            // (lungo i muri perimetrali) per non interferire col movimento
            // del player e del boss, che occupano l'area centrale.
            // Sono puramente decorative: niente collisioni.
            //
            // I colori delle decorazioni sono in tema col tipo di boss:
            // ogni tipo di boss ha la propria palette cromatica per dare
            // carattere distintivo alla stanza (D&D-style). Le palette sono:
            //   * GOLEM/GHOUL_LORD   : pietra grigia + muschio verde (cripta antica)
            //   * LICH/CULT_HERALD    : pietra viola necrotica (cripta necromantica)
            //   * DEMON               : pietra nera + rosso fuoco (sala infernale)
            //   * SPIDER              : pietra grigia + ragnatele bianche (caverna)
            //   * ABOMINATION/RAT_KING: pietra marrone + carne (caverna carnosa)
            //   * KRAKEN              : pietra blu-verde + alghe (grotta sommersa)
            //   * DRAGON/SPECTRAL_ALPHA: pietra rossa + oro (sala del tesoro)
            //   * WRAITH_LORD/TWILIGHT: pietra ciano + ombre (cripta spettrale)
            //   * VAMPIRE              : pietra scura + sangue (cripta gotica)
            //   * BEHOLDER/SUPREME_WITCH: pietra arcana + bagliori magici (torre)
            //   * COLOSSAL_MIMIC       : pietra dorata + bava (sala del tesoro)
            sf::Color stoneBase(80, 70, 60);
            sf::Color stoneDark(50, 42, 35);
            sf::Color stoneLight(120, 110, 95);
            sf::Color stoneMoss(60, 80, 50, 180);
            sf::Color boneCol(220, 210, 180);
            sf::Color boneDark(140, 130, 100);
            // Colore della "luce ambientale" che tinge la stanza: cambia in
            // base al tipo di boss. Applicato come overlay sottile.
            sf::Color ambientLight(255, 200, 120, 18);  // default: torcia calda
            // Adjust palette per boss type
            if (boss) {
                BossType bt = boss->getType();
                switch (bt) {
                    case BOSS_GOLEM:
                    case BOSS_GHOUL_LORD:
                        // Cripta antica grigia + muschio
                        stoneBase = sf::Color(85, 80, 72);
                        stoneDark = sf::Color(48, 45, 38);
                        stoneLight = sf::Color(130, 122, 105);
                        ambientLight = sf::Color(255, 220, 140, 18);
                        break;
                    case BOSS_LICH:
                    case BOSS_CULT_HERALD:
                        // Cripta necromantica viola
                        stoneBase = sf::Color(75, 60, 90);
                        stoneDark = sf::Color(40, 30, 55);
                        stoneLight = sf::Color(125, 95, 145);
                        stoneMoss = sf::Color(120, 60, 150, 180); // muschio viola necrotico
                        ambientLight = sf::Color(180, 80, 220, 22);
                        break;
                    case BOSS_DEMON:
                        // Sala infernale rossa
                        stoneBase = sf::Color(85, 45, 35);
                        stoneDark = sf::Color(45, 18, 12);
                        stoneLight = sf::Color(135, 70, 50);
                        ambientLight = sf::Color(255, 80, 30, 25);
                        break;
                    case BOSS_SPIDER:
                        // Caverna della ragnatela (grigio-bianca)
                        stoneBase = sf::Color(85, 85, 85);
                        stoneDark = sf::Color(45, 45, 48);
                        stoneLight = sf::Color(140, 140, 140);
                        stoneMoss = sf::Color(220, 220, 220, 180); // ragnatele bianche
                        ambientLight = sf::Color(200, 200, 220, 18);
                        break;
                    case BOSS_ABOMINATION:
                    case BOSS_RAT_KING:
                        // Caverna carnosa marrone
                        stoneBase = sf::Color(90, 65, 50);
                        stoneDark = sf::Color(50, 30, 22);
                        stoneLight = sf::Color(135, 95, 70);
                        stoneMoss = sf::Color(150, 60, 50, 180); // carne
                        ambientLight = sf::Color(200, 100, 80, 20);
                        break;
                    case BOSS_KRAKEN:
                        // Grotta sommersa blu-verde
                        stoneBase = sf::Color(55, 80, 80);
                        stoneDark = sf::Color(25, 45, 50);
                        stoneLight = sf::Color(85, 130, 125);
                        stoneMoss = sf::Color(50, 130, 100, 180); // alghe
                        ambientLight = sf::Color(80, 200, 220, 22);
                        break;
                    case BOSS_DRAGON:
                    case BOSS_SPECTRAL_ALPHA:
                        // Sala del tesoro rossa + oro
                        stoneBase = sf::Color(95, 70, 45);
                        stoneDark = sf::Color(55, 35, 18);
                        stoneLight = sf::Color(155, 115, 70);
                        stoneMoss = sf::Color(255, 215, 0, 200); // oro
                        ambientLight = sf::Color(255, 180, 60, 22);
                        break;
                    case BOSS_WRAITH_LORD:
                    case BOSS_TWILIGHT_KNIGHT:
                        // Cripta spettrale ciano
                        stoneBase = sf::Color(60, 75, 85);
                        stoneDark = sf::Color(28, 38, 48);
                        stoneLight = sf::Color(95, 120, 135);
                        ambientLight = sf::Color(100, 200, 255, 22);
                        break;
                    case BOSS_VAMPIRE:
                        // Cripta gotica rosso sangue
                        stoneBase = sf::Color(70, 55, 60);
                        stoneDark = sf::Color(35, 25, 30);
                        stoneLight = sf::Color(110, 85, 95);
                        stoneMoss = sf::Color(150, 30, 40, 200); // sangue
                        ambientLight = sf::Color(220, 50, 60, 22);
                        break;
                    case BOSS_BEHOLDER:
                    case BOSS_SUPREME_WITCH:
                        // Torre arcana multicolore
                        stoneBase = sf::Color(70, 65, 90);
                        stoneDark = sf::Color(35, 30, 55);
                        stoneLight = sf::Color(115, 105, 145);
                        stoneMoss = sf::Color(180, 80, 220, 200); // magia
                        ambientLight = sf::Color(200, 100, 240, 24);
                        break;
                    case BOSS_COLOSSAL_MIMIC:
                        // Sala del tesoro dorata
                        stoneBase = sf::Color(90, 75, 50);
                        stoneDark = sf::Color(50, 35, 18);
                        stoneLight = sf::Color(150, 120, 75);
                        stoneMoss = sf::Color(180, 150, 60, 200); // patina
                        ambientLight = sf::Color(255, 200, 100, 22);
                        break;
                }
            }

            // --- Luce ambientale colorata (overlay sottile su tutta la stanza) ---
            // Da un effetto "tinta" che cambia l'atmosfera della stanza secondo
            // il tipo di boss. Sottile (alpha 18-25) per non nascondere i dettagli.
            {
                sf::RectangleShape ambLight(sf::Vector2f(WINDOW_WIDTH, playH));
                ambLight.setFillColor(ambientLight);
                ambLight.setPosition(0, playTop);
                window.draw(ambLight);
            }

            // --- Pulsazione luminosa attorno al boss (effetto aura magica) ---
            // Cerchio semitrasparente pulsante che segue il boss, in armonia
            // cromatica col tipo. Da' al boss una presenza "magica" e illumina
            // l'area circostante.
            if (boss) {
                sf::Vector2f bpos = boss->getPos();
                float pulse = 1.0f + sinf(bossRoomTime * 2.5f) * 0.08f;
                float auraR = (boss->getSize() * 0.9f) * pulse;
                sf::CircleShape bossAura(auraR);
                // Colore dell'aura = ambientLight ma più intenso
                sf::Color auraC = ambientLight;
                auraC.a = 35;
                bossAura.setFillColor(auraC);
                bossAura.setPosition(bpos.x - auraR, bpos.y - auraR);
                window.draw(bossAura);
                // Aura interna più intensa
                float auraR2 = (boss->getSize() * 0.5f) * pulse;
                sf::CircleShape bossAura2(auraR2);
                sf::Color auraC2 = ambientLight;
                auraC2.a = 25;
                bossAura2.setFillColor(auraC2);
                bossAura2.setPosition(bpos.x - auraR2, bpos.y - auraR2);
                window.draw(bossAura2);
            }

            // --- 4 colonne di tempio in rovina (una per angolo) ---
            // Ogni colonna e' una base + fusto (con scanalature) + capitello.
            // Le colonne sono "spezzate": la parte superiore e' troncata
            // (effetto rovina) con pezzi di pietra caduti di lato.
            auto drawRuinColumn = [&](float x, float yBase, float height) {
                // Ombra a terra
                sf::CircleShape colShadow(28.f);
                colShadow.setFillColor(sf::Color(0, 0, 0, 110));
                colShadow.setPosition(x - 28.f, yBase + 4.f);
                window.draw(colShadow);
                // Base (rettangolo largo piu' del fusto)
                sf::RectangleShape baseBot(sf::Vector2f(40.f, 6.f));
                baseBot.setFillColor(stoneDark);
                baseBot.setOutlineThickness(1.f); baseBot.setOutlineColor(stoneBase);
                baseBot.setPosition(x - 20.f, yBase - 6.f);
                window.draw(baseBot);
                sf::RectangleShape baseTop(sf::Vector2f(36.f, 3.f));
                baseTop.setFillColor(stoneLight);
                baseTop.setPosition(x - 18.f, yBase - 6.f);
                window.draw(baseTop);
                // Fusto (rettangolo con scanalature verticali)
                sf::RectangleShape shaft(sf::Vector2f(28.f, height));
                shaft.setFillColor(stoneBase);
                shaft.setOutlineThickness(1.f); shaft.setOutlineColor(stoneDark);
                shaft.setPosition(x - 14.f, yBase - 6.f - height);
                window.draw(shaft);
                // Scanalature (3 linee verticali scure)
                for (int i = 0; i < 3; i++) {
                    sf::RectangleShape flute(sf::Vector2f(1.5f, height - 4.f));
                    flute.setFillColor(stoneDark);
                    flute.setPosition(x - 10.f + i * 7.f, yBase - 8.f - height);
                    window.draw(flute);
                }
                // Gradiente verticale del fusto (luce da sinistra)
                sf::RectangleShape shaftLight(sf::Vector2f(6.f, height - 4.f));
                shaftLight.setFillColor(sf::Color(
                    (sf::Uint8)std::min(255, stoneBase.r + 30),
                    (sf::Uint8)std::min(255, stoneBase.g + 25),
                    (sf::Uint8)std::min(255, stoneBase.b + 20), 160));
                shaftLight.setPosition(x - 14.f, yBase - 8.f - height);
                window.draw(shaftLight);
                // Capitello (in cima, se la colonna non e' troncata)
                // Per le colonne "in rovina" il capitello manca o e' caduto
                // di lato. Lo mettiamo solo su 2 colonne su 4 (alternanza).
                // Top del fusto: bordo irregolare (piccoli triangoli)
                for (int i = 0; i < 5; i++) {
                    sf::ConvexShape top; top.setPointCount(3);
                    top.setFillColor(stoneDark);
                    top.setPoint(0, sf::Vector2f(x - 14.f + i * 7.f, yBase - 6.f - height));
                    top.setPoint(1, sf::Vector2f(x - 14.f + (i+1) * 7.f, yBase - 6.f - height));
                    top.setPoint(2, sf::Vector2f(x - 14.f + i * 7.f + 3.5f,
                        yBase - 6.f - height - (i % 2 == 0 ? 6.f : 3.f)));
                    window.draw(top);
                }
                // Pezzo di capitello caduto a terra (piccolo blocco)
                sf::RectangleShape fallen(sf::Vector2f(14.f, 8.f));
                fallen.setFillColor(stoneLight);
                fallen.setOutlineThickness(1.f); fallen.setOutlineColor(stoneDark);
                fallen.setPosition(x + 18.f, yBase - 2.f);
                window.draw(fallen);
                // Muschio alla base della colonna
                sf::CircleShape moss1(3.f);
                moss1.setFillColor(stoneMoss);
                moss1.setPosition(x - 16.f, yBase - 4.f);
                window.draw(moss1);
                sf::CircleShape moss2(2.f);
                moss2.setFillColor(stoneMoss);
                moss2.setPosition(x + 12.f, yBase - 2.f);
                window.draw(moss2);
            };

            // --- Tombe scoperchiate sul pavimento (laterali) ---
            // Sarcofagi di pietra aperti con coperchio caduto di lato.
            // Posizionati sui lati sinistro e destro della stanza, a meta'
            // altezza, in modo da non ostacolare il player (che si muove
            // nell'area centrale).
            auto drawSarcophagus = [&](float cx, float cy, bool flipped) {
                // Ombra a terra
                sf::CircleShape sarShadow(40.f);
                sarShadow.setFillColor(sf::Color(0, 0, 0, 130));
                sarShadow.setPosition(cx - 40.f, cy + 8.f);
                window.draw(sarShadow);
                // Corpo del sarcofago (rettangolo con bordi smussati)
                sf::RectangleShape body(sf::Vector2f(60.f, 22.f));
                body.setFillColor(stoneDark);
                body.setOutlineThickness(1.5f); body.setOutlineColor(stoneBase);
                body.setPosition(cx - 30.f, cy - 4.f);
                window.draw(body);
                // Strato superiore del corpo (pietra piu' chiara)
                sf::RectangleShape bodyTop(sf::Vector2f(58.f, 6.f));
                bodyTop.setFillColor(stoneBase);
                bodyTop.setPosition(cx - 29.f, cy - 4.f);
                window.draw(bodyTop);
                // Strato superiore-chiaro (riflesso)
                sf::RectangleShape bodyRef(sf::Vector2f(54.f, 1.5f));
                bodyRef.setFillColor(stoneLight);
                bodyRef.setPosition(cx - 27.f, cy - 4.f);
                window.draw(bodyRef);
                // Decorazione frontale (croce templare incisa)
                sf::RectangleShape cross1(sf::Vector2f(2.f, 12.f));
                cross1.setFillColor(stoneLight);
                cross1.setPosition(cx - 1.f, cy + 2.f);
                window.draw(cross1);
                sf::RectangleShape cross2(sf::Vector2f(8.f, 2.f));
                cross2.setFillColor(stoneLight);
                cross2.setPosition(cx - 4.f, cy + 6.f);
                window.draw(cross2);
                // Bordo inferiore (zoccolo)
                sf::RectangleShape socle(sf::Vector2f(64.f, 4.f));
                socle.setFillColor(stoneDark);
                socle.setOutlineThickness(1.f); socle.setOutlineColor(stoneBase);
                socle.setPosition(cx - 32.f, cy + 16.f);
                window.draw(socle);

                // Coperchio scoperchiato (caduto di lato)
                // E' un pezzo lungo, appoggiato obliquo sul pavimento.
                float lidX = (flipped ? cx - 50.f : cx + 30.f);
                float lidY = cy + 18.f;
                sf::ConvexShape lid; lid.setPointCount(4);
                lid.setFillColor(stoneBase);
                lid.setOutlineThickness(1.5f); lid.setOutlineColor(stoneDark);
                lid.setPoint(0, sf::Vector2f(lidX, lidY));
                lid.setPoint(1, sf::Vector2f(lidX + 30.f, lidY - 4.f));
                lid.setPoint(2, sf::Vector2f(lidX + 30.f, lidY + 4.f));
                lid.setPoint(3, sf::Vector2f(lidX, lidY + 8.f));
                window.draw(lid);
                // Riflesso del coperchio
                sf::ConvexShape lidRef; lidRef.setPointCount(4);
                lidRef.setFillColor(stoneLight);
                lidRef.setPoint(0, sf::Vector2f(lidX + 2.f, lidY + 0.5f));
                lidRef.setPoint(1, sf::Vector2f(lidX + 28.f, lidY - 3.f));
                lidRef.setPoint(2, sf::Vector2f(lidX + 28.f, lidY - 1.f));
                lidRef.setPoint(3, sf::Vector2f(lidX + 2.f, lidY + 1.5f));
                window.draw(lidRef);

                // Osso / teschio che sporge dal sarcofago (interno scuro)
                sf::RectangleShape interior(sf::Vector2f(50.f, 6.f));
                interior.setFillColor(sf::Color(10, 8, 5));
                interior.setPosition(cx - 25.f, cy - 2.f);
                window.draw(interior);
                // Teschio (solo se non flipped: visibile da un lato)
                if (!flipped) {
                    // Teschio bianco sporco
                    sf::CircleShape skull(5.f, 8);
                    skull.setFillColor(boneCol);
                    skull.setOutlineThickness(0.8f); skull.setOutlineColor(boneDark);
                    skull.setPosition(cx - 5.f, cy - 6.f);
                    window.draw(skull);
                    // Occhi neri
                    sf::CircleShape eyeS(1.f);
                    eyeS.setFillColor(sf::Color::Black);
                    eyeS.setPosition(cx - 3.5f, cy - 3.f);
                    window.draw(eyeS);
                    eyeS.setPosition(cx + 0.5f, cy - 3.f);
                    window.draw(eyeS);
                    // Denti (piccoli segmenti)
                    for (int i = 0; i < 3; i++) {
                        sf::RectangleShape tooth(sf::Vector2f(1.f, 1.5f));
                        tooth.setFillColor(boneDark);
                        tooth.setPosition(cx - 2.f + i * 1.5f, cy + 1.f);
                        window.draw(tooth);
                    }
                } else {
                    // Osso lungo (femore) che sporge
                    sf::RectangleShape bone(sf::Vector2f(20.f, 3.f));
                    bone.setFillColor(boneCol);
                    bone.setOutlineThickness(0.5f); bone.setOutlineColor(boneDark);
                    bone.setPosition(cx - 18.f, cy - 3.f);
                    bone.rotate(-15.f);
                    window.draw(bone);
                    // Testa del femore (sfera)
                    sf::CircleShape boneHead(2.f);
                    boneHead.setFillColor(boneCol);
                    boneHead.setOutlineThickness(0.5f); boneHead.setOutlineColor(boneDark);
                    boneHead.setPosition(cx + 0.f, cy - 4.f);
                    window.draw(boneHead);
                }
                // Muschio ai bordi del sarcofago
                sf::CircleShape mossS1(3.f);
                mossS1.setFillColor(stoneMoss);
                mossS1.setPosition(cx - 32.f, cy + 12.f);
                window.draw(mossS1);
                sf::CircleShape mossS2(2.f);
                mossS2.setFillColor(stoneMoss);
                mossS2.setPosition(cx + 26.f, cy + 14.f);
                window.draw(mossS2);
            };

            // --- Lastre di pietra con incisioni (lapidi) ---
            // Piccole lapidi inclinate posizionate vicino ai muri laterali,
            // come una cripta con tombe antiche.
            auto drawTombstone = [&](float cx, float cy, float tilt) {
                // Ombra
                sf::CircleShape tsShadow(18.f);
                tsShadow.setFillColor(sf::Color(0, 0, 0, 110));
                tsShadow.setPosition(cx - 18.f, cy + 12.f);
                window.draw(tsShadow);
                // Base (rettangolo largo)
                sf::RectangleShape base(sf::Vector2f(24.f, 4.f));
                base.setFillColor(stoneDark);
                base.setOutlineThickness(0.8f); base.setOutlineColor(stoneBase);
                base.setPosition(cx - 12.f, cy + 12.f);
                window.draw(base);
                // Stele (rettangolo con cima arrotondata)
                sf::ConvexShape stele; stele.setPointCount(6);
                stele.setFillColor(stoneBase);
                stele.setOutlineThickness(1.f); stele.setOutlineColor(stoneDark);
                stele.setPoint(0, sf::Vector2f(cx - 10.f, cy + 12.f));
                stele.setPoint(1, sf::Vector2f(cx + 10.f, cy + 12.f));
                stele.setPoint(2, sf::Vector2f(cx + 10.f, cy - 14.f));
                stele.setPoint(3, sf::Vector2f(cx + 7.f,  cy - 18.f));
                stele.setPoint(4, sf::Vector2f(cx - 7.f,  cy - 18.f));
                stele.setPoint(5, sf::Vector2f(cx - 10.f, cy - 14.f));
                // Applica inclinazione (effetto lapide inclinata)
                stele.rotate(tilt);
                window.draw(stele);
                // Riflesso della stele (luce da sinistra)
                sf::RectangleShape steleRef(sf::Vector2f(3.f, 24.f));
                steleRef.setFillColor(stoneLight);
                steleRef.setPosition(cx - 9.f, cy - 12.f);
                steleRef.rotate(tilt);
                window.draw(steleRef);
                // Incisione (piccola croce o simbolo)
                sf::RectangleShape ins1(sf::Vector2f(1.5f, 8.f));
                ins1.setFillColor(stoneDark);
                ins1.setPosition(cx - 0.75f, cy - 8.f);
                ins1.rotate(tilt);
                window.draw(ins1);
                sf::RectangleShape ins2(sf::Vector2f(6.f, 1.5f));
                ins2.setFillColor(stoneDark);
                ins2.setPosition(cx - 3.f, cy - 4.f);
                ins2.rotate(tilt);
                window.draw(ins2);
                // Muschio alla base
                sf::CircleShape mossT(2.5f);
                mossT.setFillColor(stoneMoss);
                mossT.setPosition(cx - 10.f, cy + 10.f);
                window.draw(mossT);
            };

            // --- Blocchi di pietra caduti (cumuli di rovine) ---
            // Piccoli blocchi sparsi lungo il perimetro della stanza,
            // come resti di un tempio crollato.
            auto drawRubblePile = [&](float cx, float cy) {
                // Ombra
                sf::CircleShape rubbleShadow(22.f);
                rubbleShadow.setFillColor(sf::Color(0, 0, 0, 100));
                rubbleShadow.setPosition(cx - 22.f, cy + 6.f);
                window.draw(rubbleShadow);
                // 3-4 blocchi di pietra di grandezze e toni diversi
                sf::RectangleShape block1(sf::Vector2f(20.f, 12.f));
                block1.setFillColor(stoneDark);
                block1.setOutlineThickness(0.8f); block1.setOutlineColor(stoneBase);
                block1.setPosition(cx - 14.f, cy);
                block1.rotate(-5.f);
                window.draw(block1);
                sf::RectangleShape block2(sf::Vector2f(16.f, 10.f));
                block2.setFillColor(stoneBase);
                block2.setOutlineThickness(0.8f); block2.setOutlineColor(stoneDark);
                block2.setPosition(cx + 4.f, cy + 4.f);
                block2.rotate(8.f);
                window.draw(block2);
                // Riflesso sul blocco superiore
                sf::RectangleShape block2Ref(sf::Vector2f(14.f, 1.5f));
                block2Ref.setFillColor(stoneLight);
                block2Ref.setPosition(cx + 5.f, cy + 4.f);
                block2Ref.rotate(8.f);
                window.draw(block2Ref);
                // Blocco piu' piccolo sopra
                sf::RectangleShape block3(sf::Vector2f(10.f, 6.f));
                block3.setFillColor(stoneLight);
                block3.setOutlineThickness(0.5f); block3.setOutlineColor(stoneDark);
                block3.setPosition(cx - 6.f, cy - 4.f);
                block3.rotate(-12.f);
                window.draw(block3);
                // Muschio sui blocchi
                sf::CircleShape mossR(2.f);
                mossR.setFillColor(stoneMoss);
                mossR.setPosition(cx - 12.f, cy + 8.f);
                window.draw(mossR);
                mossR.setPosition(cx + 8.f, cy + 2.f);
                window.draw(mossR);
            };

            // --- Teschi cumulo sul pavimento (decorazione macabra) ---
            // Piccolo cumulo di teschi in un angolo della stanza.
            {
                float pileX = wallThickness + 40.f;
                float pileY = WINDOW_HEIGHT - wallThickness - 30.f;
                // Ombra
                sf::CircleShape pileShadow(20.f);
                pileShadow.setFillColor(sf::Color(0, 0, 0, 120));
                pileShadow.setPosition(pileX - 20.f, pileY + 4.f);
                window.draw(pileShadow);
                // 5 teschi disposti a piramide
                float skullPos[5][2] = {
                    {0.f,  0.f}, {10.f, 2.f}, {-10.f, 2.f}, {5.f, -8.f}, {-5.f, -6.f}
                };
                for (int i = 0; i < 5; i++) {
                    float sx = pileX + skullPos[i][0];
                    float sy = pileY + skullPos[i][1];
                    // Teschio
                    sf::CircleShape skull(4.f, 8);
                    skull.setFillColor(boneCol);
                    skull.setOutlineThickness(0.5f); skull.setOutlineColor(boneDark);
                    skull.setPosition(sx - 4.f, sy - 4.f);
                    window.draw(skull);
                    // Occhi
                    sf::CircleShape eye1(0.8f);
                    eye1.setFillColor(sf::Color::Black);
                    eye1.setPosition(sx - 2.5f, sy - 1.5f);
                    window.draw(eye1);
                    sf::CircleShape eye2(0.8f);
                    eye2.setFillColor(sf::Color::Black);
                    eye2.setPosition(sx + 1.f, sy - 1.5f);
                    window.draw(eye2);
                    // Naso (piccolo triangolo)
                    sf::ConvexShape nose; nose.setPointCount(3);
                    nose.setFillColor(boneDark);
                    nose.setPoint(0, sf::Vector2f(sx - 1.f, sy + 0.5f));
                    nose.setPoint(1, sf::Vector2f(sx + 1.f, sy + 0.5f));
                    nose.setPoint(2, sf::Vector2f(sx, sy + 2.f));
                    window.draw(nose);
                }
            }
            // Cumulo di teschi nell'angolo opposto (simmetrico)
            {
                float pileX = (float)(WINDOW_WIDTH - wallThickness) - 40.f;
                float pileY = playTop + wallThickness + 30.f;
                sf::CircleShape pileShadow(20.f);
                pileShadow.setFillColor(sf::Color(0, 0, 0, 120));
                pileShadow.setPosition(pileX - 20.f, pileY + 4.f);
                window.draw(pileShadow);
                float skullPos[5][2] = {
                    {0.f,  0.f}, {10.f, 2.f}, {-10.f, 2.f}, {5.f, -8.f}, {-5.f, -6.f}
                };
                for (int i = 0; i < 5; i++) {
                    float sx = pileX + skullPos[i][0];
                    float sy = pileY + skullPos[i][1];
                    sf::CircleShape skull(4.f, 8);
                    skull.setFillColor(boneCol);
                    skull.setOutlineThickness(0.5f); skull.setOutlineColor(boneDark);
                    skull.setPosition(sx - 4.f, sy - 4.f);
                    window.draw(skull);
                    sf::CircleShape eye1(0.8f);
                    eye1.setFillColor(sf::Color::Black);
                    eye1.setPosition(sx - 2.5f, sy - 1.5f);
                    window.draw(eye1);
                    sf::CircleShape eye2(0.8f);
                    eye2.setFillColor(sf::Color::Black);
                    eye2.setPosition(sx + 1.f, sy - 1.5f);
                    window.draw(eye2);
                    sf::ConvexShape nose; nose.setPointCount(3);
                    nose.setFillColor(boneDark);
                    nose.setPoint(0, sf::Vector2f(sx - 1.f, sy + 0.5f));
                    nose.setPoint(1, sf::Vector2f(sx + 1.f, sy + 0.5f));
                    nose.setPoint(2, sf::Vector2f(sx, sy + 2.f));
                    window.draw(nose);
                }
            }

            // --- Bracieri ardenti agli angoli della stanza ---
            // Piccoli bracieri con fiamma animata per dare atmosfera
            // e illuminazione calda, in stile cripta infernale.
            auto drawBrazier = [&](float cx, float cy) {
                // Ombra
                sf::CircleShape brShadow(16.f);
                brShadow.setFillColor(sf::Color(0, 0, 0, 120));
                brShadow.setPosition(cx - 16.f, cy + 8.f);
                window.draw(brShadow);
                // Treppiede (3 gambe metalliche)
                for (int i = 0; i < 3; i++) {
                    sf::RectangleShape leg(sf::Vector2f(2.f, 12.f));
                    leg.setFillColor(sf::Color(50, 45, 40));
                    leg.setOutlineThickness(0.5f); leg.setOutlineColor(sf::Color(20, 15, 10));
                    leg.setOrigin(1.f, 0.f);
                    leg.setPosition(cx, cy);
                    leg.rotate(i * 120.f + 30.f);
                    window.draw(leg);
                }
                // Coppa del braciere (semicerchio rovesciato)
                sf::ConvexShape bowl; bowl.setPointCount(6);
                bowl.setFillColor(sf::Color(70, 60, 50));
                bowl.setOutlineThickness(1.f); bowl.setOutlineColor(sf::Color(30, 25, 20));
                bowl.setPoint(0, sf::Vector2f(cx - 12.f, cy - 4.f));
                bowl.setPoint(1, sf::Vector2f(cx + 12.f, cy - 4.f));
                bowl.setPoint(2, sf::Vector2f(cx + 10.f, cy + 2.f));
                bowl.setPoint(3, sf::Vector2f(cx + 6.f,  cy + 6.f));
                bowl.setPoint(4, sf::Vector2f(cx - 6.f,  cy + 6.f));
                bowl.setPoint(5, sf::Vector2f(cx - 10.f, cy + 2.f));
                window.draw(bowl);
                // Bordo superiore della coppa
                sf::RectangleShape bowlRim(sf::Vector2f(24.f, 2.f));
                bowlRim.setFillColor(sf::Color(100, 90, 75));
                bowlRim.setOutlineThickness(0.5f); bowlRim.setOutlineColor(sf::Color(30, 25, 20));
                bowlRim.setPosition(cx - 12.f, cy - 5.f);
                window.draw(bowlRim);
                // Aura luminosa calda
                sf::CircleShape bAura(28.f);
                bAura.setFillColor(sf::Color(255, 180, 60, 30));
                bAura.setPosition(cx - 28.f, cy - 50.f);
                window.draw(bAura);
                // Fiamma animata (3 strati)
                float flicker = sinf(bossRoomTime * 16.f + cx) * 1.5f;
                // Strato esterno (rosso)
                sf::CircleShape flame3(7.f + flicker);
                flame3.setFillColor(sf::Color(180, 30, 10, 220));
                flame3.setPosition(cx - 7.f - flicker * 0.5f, cy - 18.f);
                window.draw(flame3);
                // Strato medio (arancione)
                sf::CircleShape flame2(5.f + flicker * 0.5f);
                flame2.setFillColor(sf::Color(255, 140, 30, 240));
                flame2.setPosition(cx - 5.f - flicker * 0.3f, cy - 16.f);
                window.draw(flame2);
                // Strato interno (giallo)
                sf::CircleShape flame1(2.5f);
                flame1.setFillColor(sf::Color(255, 240, 180, 250));
                flame1.setPosition(cx - 2.5f, cy - 13.f);
                window.draw(flame1);
                // Piccola scintilla sopra
                sf::CircleShape spark(0.6f);
                spark.setFillColor(sf::Color(255, 220, 120, 200));
                spark.setPosition(cx - 0.3f, cy - 22.f - flicker);
                window.draw(spark);
            };

            // --- Catene appese ai muri (decorazione gotica) ---
            // Catene di ferro arrugginito appese al muro superiore e inferiore,
            // come una prigione / cripta.
            auto drawHangingChain = [&](float x, float yTop, float length) {
                // Anelli di catena (cerchi scuri impilati)
                int numLinks = (int)(length / 5.f);
                for (int i = 0; i < numLinks; i++) {
                    float y = yTop + i * 5.f;
                    // Anello verticale
                    sf::RectangleShape linkV(sf::Vector2f(2.f, 5.f));
                    linkV.setFillColor(sf::Color(45, 40, 35));
                    linkV.setOutlineThickness(0.5f); linkV.setOutlineColor(sf::Color(20, 18, 15));
                    linkV.setPosition(x - 1.f, y);
                    window.draw(linkV);
                    // Anello orizzontale (alternato)
                    if (i % 2 == 0) {
                        sf::RectangleShape linkH(sf::Vector2f(5.f, 2.f));
                        linkH.setFillColor(sf::Color(55, 50, 45));
                        linkH.setOutlineThickness(0.5f); linkH.setOutlineColor(sf::Color(20, 18, 15));
                        linkH.setPosition(x - 2.5f, y + 1.5f);
                        window.draw(linkH);
                    }
                }
                // Ultimo anello con un gancio (uncino)
                sf::ConvexShape hook; hook.setPointCount(4);
                hook.setFillColor(sf::Color(50, 45, 40));
                hook.setOutlineThickness(0.5f); hook.setOutlineColor(sf::Color(20, 18, 15));
                hook.setPoint(0, sf::Vector2f(x - 1.f, yTop + length));
                hook.setPoint(1, sf::Vector2f(x + 1.f, yTop + length));
                hook.setPoint(2, sf::Vector2f(x + 4.f, yTop + length + 4.f));
                hook.setPoint(3, sf::Vector2f(x + 2.f, yTop + length + 6.f));
                window.draw(hook);
            };

            // ============ NUOVI TIPI DI DECORAZIONE ============
            // Per variare le stanze dei boss: ogni tipo ha un subset diverso
            // di decorazioni, con posizioni e quantita' diverse. Questi nuovi
            // lambda si aggiungono a quelli esistenti (drawRuinColumn,
            // drawSarcophagus, drawTombstone, drawRubblePile, drawBrazier,
            // drawHangingChain).

            // --- Pilastro intatto (colonna snella, non in rovina) ---
            auto drawPillar = [&](float x, float yBase, float height) {
                sf::CircleShape pShadow(20.f);
                pShadow.setFillColor(sf::Color(0, 0, 0, 110));
                pShadow.setPosition(x - 20.f, yBase + 4.f);
                window.draw(pShadow);
                // Base
                sf::RectangleShape base(sf::Vector2f(28.f, 6.f));
                base.setFillColor(stoneDark);
                base.setOutlineThickness(1.f); base.setOutlineColor(stoneBase);
                base.setPosition(x - 14.f, yBase - 6.f);
                window.draw(base);
                // Fusto
                sf::RectangleShape shaft(sf::Vector2f(18.f, height));
                shaft.setFillColor(stoneBase);
                shaft.setOutlineThickness(1.f); shaft.setOutlineColor(stoneDark);
                shaft.setPosition(x - 9.f, yBase - 6.f - height);
                window.draw(shaft);
                // Riflesso laterale
                sf::RectangleShape shaftRef(sf::Vector2f(4.f, height - 4.f));
                shaftRef.setFillColor(stoneLight);
                shaftRef.setPosition(x - 9.f, yBase - 8.f - height);
                window.draw(shaftRef);
                // Capitello (in cima, intact)
                sf::RectangleShape cap(sf::Vector2f(26.f, 5.f));
                cap.setFillColor(stoneLight);
                cap.setOutlineThickness(0.8f); cap.setOutlineColor(stoneDark);
                cap.setPosition(x - 13.f, yBase - 6.f - height - 5.f);
                window.draw(cap);
                sf::RectangleShape capTop(sf::Vector2f(30.f, 3.f));
                capTop.setFillColor(stoneBase);
                capTop.setPosition(x - 15.f, yBase - 6.f - height - 8.f);
                window.draw(capTop);
            };

            // --- Stalagmite (cono di roccia naturale, per caverne) ---
            auto drawStalagmite = [&](float x, float yBase, float height) {
                sf::CircleShape sShadow(16.f);
                sShadow.setFillColor(sf::Color(0, 0, 0, 110));
                sShadow.setPosition(x - 16.f, yBase + 2.f);
                window.draw(sShadow);
                // Cono: ConvexShape triangolare largo in basso, stretto in alto
                sf::ConvexShape cone; cone.setPointCount(3);
                cone.setFillColor(stoneDark);
                cone.setOutlineThickness(1.f); cone.setOutlineColor(stoneBase);
                cone.setPoint(0, sf::Vector2f(x - 10.f, yBase));
                cone.setPoint(1, sf::Vector2f(x + 10.f, yBase));
                cone.setPoint(2, sf::Vector2f(x, yBase - height));
                window.draw(cone);
                // Highlight laterale
                sf::ConvexShape coneRef; coneRef.setPointCount(3);
                coneRef.setFillColor(stoneLight);
                coneRef.setPoint(0, sf::Vector2f(x - 8.f, yBase - 2.f));
                coneRef.setPoint(1, sf::Vector2f(x - 4.f, yBase - 2.f));
                coneRef.setPoint(2, sf::Vector2f(x - 2.f, yBase - height * 0.8f));
                window.draw(coneRef);
            };

            // --- Cassa di legno (per stanze tesoro/mimic) ---
            auto drawCrate = [&](float x, float yBase) {
                sf::CircleShape cShadow(14.f);
                cShadow.setFillColor(sf::Color(0, 0, 0, 110));
                cShadow.setPosition(x - 14.f, yBase + 4.f);
                window.draw(cShadow);
                // Corpo cassa
                sf::RectangleShape body(sf::Vector2f(20.f, 16.f));
                body.setFillColor(sf::Color(110, 70, 30));
                body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(50, 30, 10));
                body.setPosition(x - 10.f, yBase - 12.f);
                window.draw(body);
                // Strato superiore
                sf::RectangleShape top(sf::Vector2f(22.f, 3.f));
                top.setFillColor(sf::Color(140, 90, 40));
                top.setPosition(x - 11.f, yBase - 12.f);
                window.draw(top);
                // Venature
                sf::RectangleShape vein1(sf::Vector2f(18.f, 0.6f));
                vein1.setFillColor(sf::Color(60, 35, 15));
                vein1.setPosition(x - 9.f, yBase - 6.f);
                window.draw(vein1);
                vein1.setPosition(x - 9.f, yBase - 1.f);
                window.draw(vein1);
                // Rinforzi metallici (angoli)
                sf::RectangleShape bracket1(sf::Vector2f(2.f, 4.f));
                bracket1.setFillColor(sf::Color(180, 160, 60));
                bracket1.setPosition(x - 10.f, yBase - 12.f);
                window.draw(bracket1);
                bracket1.setPosition(x + 8.f, yBase - 12.f);
                window.draw(bracket1);
            };

            // --- Stendardo appeso al muro (per stanze cavaliere/wraith) ---
            auto drawBanner = [&](float x, float yTop, float height, sf::Color bannerCol) {
                // Asta orizzontale in alto
                sf::RectangleShape rod(sf::Vector2f(28.f, 2.f));
                rod.setFillColor(sf::Color(100, 80, 50));
                rod.setOutlineThickness(0.5f); rod.setOutlineColor(sf::Color(40, 30, 15));
                rod.setPosition(x - 14.f, yTop);
                window.draw(rod);
                // Terminali dell'asta (palline)
                sf::CircleShape cap1(2.f);
                cap1.setFillColor(sf::Color(180, 160, 60));
                cap1.setPosition(x - 16.f, yTop - 1.f);
                window.draw(cap1);
                cap1.setPosition(x + 12.f, yTop - 1.f);
                window.draw(cap1);
                // Drappo (rettangolo con punta triangolare in basso)
                sf::ConvexShape cloth; cloth.setPointCount(5);
                cloth.setFillColor(bannerCol);
                cloth.setOutlineThickness(0.8f); cloth.setOutlineColor(stoneDark);
                cloth.setPoint(0, sf::Vector2f(x - 10.f, yTop + 2.f));
                cloth.setPoint(1, sf::Vector2f(x + 10.f, yTop + 2.f));
                cloth.setPoint(2, sf::Vector2f(x + 10.f, yTop + height - 6.f));
                cloth.setPoint(3, sf::Vector2f(x, yTop + height));
                cloth.setPoint(4, sf::Vector2f(x - 10.f, yTop + height - 6.f));
                window.draw(cloth);
                // Simbolo centrale (croce/emblema)
                sf::RectangleShape sym1(sf::Vector2f(1.5f, 10.f));
                sym1.setFillColor(sf::Color(255, 215, 0));
                sym1.setPosition(x - 0.75f, yTop + 6.f);
                window.draw(sym1);
                sf::RectangleShape sym2(sf::Vector2f(6.f, 1.5f));
                sym2.setFillColor(sf::Color(255, 215, 0));
                sym2.setPosition(x - 3.f, yTop + 9.f);
                window.draw(sym2);
            };

            // --- Candelabro da parete (braccio + candela) ---
            auto drawWallCandle = [&](float x, float y) {
                // Braccio a S
                sf::RectangleShape arm(sf::Vector2f(10.f, 1.5f));
                arm.setFillColor(sf::Color(80, 70, 50));
                arm.setOutlineThickness(0.4f); arm.setOutlineColor(sf::Color(40, 30, 15));
                arm.setPosition(x, y);
                window.draw(arm);
                // Candela
                sf::RectangleShape candle(sf::Vector2f(3.f, 8.f));
                candle.setFillColor(sf::Color(230, 220, 200));
                candle.setOutlineThickness(0.4f); candle.setOutlineColor(sf::Color(120, 110, 90));
                candle.setPosition(x + 8.f, y - 8.f);
                window.draw(candle);
                // Fiamma animata
                float flick = sinf(bossRoomTime * 14.f + x) * 0.8f;
                sf::CircleShape flame(1.5f + flick);
                flame.setFillColor(sf::Color(255, 180, 60, 230));
                flame.setPosition(x + 8.f - flick, y - 12.f);
                window.draw(flame);
                // Aura
                sf::CircleShape cAura(5.f);
                cAura.setFillColor(sf::Color(255, 180, 60, 50));
                cAura.setPosition(x + 4.f, y - 16.f);
                window.draw(cAura);
            };

            // --- Altare sacrificale (pietra con canali di sangue) ---
            auto drawAltar = [&](float x, float yBase) {
                sf::CircleShape aShadow(24.f);
                aShadow.setFillColor(sf::Color(0, 0, 0, 130));
                aShadow.setPosition(x - 24.f, yBase + 6.f);
                window.draw(aShadow);
                // Base
                sf::RectangleShape base(sf::Vector2f(40.f, 6.f));
                base.setFillColor(stoneDark);
                base.setOutlineThickness(1.f); base.setOutlineColor(stoneBase);
                base.setPosition(x - 20.f, yBase);
                window.draw(base);
                // Topo altare (con canale)
                sf::RectangleShape top(sf::Vector2f(36.f, 10.f));
                top.setFillColor(stoneBase);
                top.setOutlineThickness(0.8f); top.setOutlineColor(stoneDark);
                top.setPosition(x - 18.f, yBase - 10.f);
                window.draw(top);
                // Canale di scolo (solco centrale)
                sf::RectangleShape groove(sf::Vector2f(2.f, 10.f));
                groove.setFillColor(stoneMoss);  // rosso sangue o muschio a seconda del tema
                groove.setPosition(x - 1.f, yBase - 10.f);
                window.draw(groove);
                // Macchia sul top (sangue/muschio)
                sf::CircleShape stain(4.f);
                stain.setFillColor(stoneMoss);
                stain.setPosition(x - 4.f, yBase - 6.f);
                window.draw(stain);
                // Riflesso
                sf::RectangleShape topRef(sf::Vector2f(32.f, 1.2f));
                topRef.setFillColor(stoneLight);
                topRef.setPosition(x - 16.f, yBase - 10.f);
                window.draw(topRef);
            };

            // ============ DECORAZIONI VARIABILI PER TIPO DI BOSS ============
            // Ogni tipo di boss ha un subset diverso di decorazioni periferiche,
            // con posizioni e quantita' diverse. Questo rende ogni stanza del
            // boss immediatamente riconoscibile anche senza guardare il boss.
            if (boss) {
                BossType bt = boss->getType();
                switch (bt) {
                    case BOSS_GOLEM:
                    case BOSS_GHOUL_LORD: {
                        // Cripta antica: 4 colonne in rovina agli angoli + 4 lapidi laterali + 2 bracieri
                        drawRuinColumn(wallThickness + 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 80.f);
                        drawRuinColumn(WINDOW_WIDTH - wallThickness - 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 80.f);
                        drawRuinColumn(wallThickness + 60.f, playTop + wallThickness + 60.f, 60.f);
                        drawRuinColumn(WINDOW_WIDTH - wallThickness - 60.f, playTop + wallThickness + 60.f, 60.f);
                        drawTombstone(wallThickness + 80.f, playTop + playH * 0.3f, -8.f);
                        drawTombstone(wallThickness + 80.f, playTop + playH * 0.7f, 6.f);
                        drawTombstone(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.3f, 8.f);
                        drawTombstone(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.7f, -6.f);
                        drawBrazier(wallThickness + 30.f, playTop + wallThickness + 30.f);
                        drawBrazier(WINDOW_WIDTH - wallThickness - 30.f, WINDOW_HEIGHT - wallThickness - 30.f);
                        break;
                    }
                    case BOSS_LICH:
                    case BOSS_CULT_HERALD: {
                        // Cripta necromantica: altari laterali + 2 sarcofagi + catene
                        drawAltar(wallThickness + 80.f, playTop + playH * 0.3f);
                        drawAltar(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.7f);
                        drawSarcophagus(wallThickness + 100.f, playTop + playH * 0.5f, false);
                        drawSarcophagus(WINDOW_WIDTH - wallThickness - 100.f, playTop + playH * 0.5f, true);
                        drawHangingChain(WINDOW_WIDTH * 0.25f, playTop + wallThickness, 30.f);
                        drawHangingChain(WINDOW_WIDTH * 0.75f, playTop + wallThickness, 28.f);
                        drawHangingChain(WINDOW_WIDTH * 0.5f, WINDOW_HEIGHT - wallThickness - 28.f, 18.f);
                        break;
                    }
                    case BOSS_DEMON: {
                        // Sala infernale: bracieri multipli + stalagmite neri + catene
                        drawStalagmite(wallThickness + 60.f, playTop + playH * 0.5f, 60.f);
                        drawStalagmite(WINDOW_WIDTH - wallThickness - 60.f, playTop + playH * 0.5f, 50.f);
                        drawStalagmite(wallThickness + 100.f, playTop + playH * 0.3f, 40.f);
                        drawStalagmite(WINDOW_WIDTH - wallThickness - 100.f, playTop + playH * 0.7f, 45.f);
                        drawBrazier(wallThickness + 30.f, playTop + wallThickness + 30.f);
                        drawBrazier(WINDOW_WIDTH - wallThickness - 30.f, playTop + wallThickness + 30.f);
                        drawBrazier(wallThickness + 30.f, WINDOW_HEIGHT - wallThickness - 30.f);
                        drawBrazier(WINDOW_WIDTH - wallThickness - 30.f, WINDOW_HEIGHT - wallThickness - 30.f);
                        drawHangingChain(WINDOW_WIDTH * 0.5f, playTop + wallThickness, 30.f);
                        drawHangingChain(WINDOW_WIDTH * 0.5f, WINDOW_HEIGHT - wallThickness - 32.f, 24.f);
                        break;
                    }
                    case BOSS_SPIDER: {
                        // Caverna: stalagmiti naturali + ragnatele (le ragnatele sono gia'
                        // nella feature centrale, qui aggiungiamo solo stalagmiti + cumuli)
                        drawStalagmite(wallThickness + 60.f, playTop + playH * 0.5f, 70.f);
                        drawStalagmite(WINDOW_WIDTH - wallThickness - 60.f, playTop + playH * 0.5f, 65.f);
                        drawStalagmite(wallThickness + 50.f, WINDOW_HEIGHT - wallThickness - 40.f, 50.f);
                        drawStalagmite(WINDOW_WIDTH - wallThickness - 50.f, WINDOW_HEIGHT - wallThickness - 40.f, 55.f);
                        drawRubblePile(wallThickness + 100.f, playTop + playH * 0.3f);
                        drawRubblePile(WINDOW_WIDTH - wallThickness - 100.f, playTop + playH * 0.7f);
                        break;
                    }
                    case BOSS_ABOMINATION:
                    case BOSS_RAT_KING: {
                        // Caverna carnosa: gabbie (feature) + cassse rotte + cumuli
                        drawCrate(wallThickness + 80.f, playTop + playH * 0.3f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.7f);
                        drawCrate(wallThickness + 100.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 100.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        drawRubblePile(wallThickness + 50.f, playTop + playH * 0.5f);
                        drawRubblePile(WINDOW_WIDTH - wallThickness - 50.f, playTop + playH * 0.5f);
                        break;
                    }
                    case BOSS_KRAKEN: {
                        // Grotta sommersa: stalagmiti + pozze (feature) + alghe (cumuli verdi)
                        drawStalagmite(wallThickness + 60.f, playTop + playH * 0.3f, 50.f);
                        drawStalagmite(WINDOW_WIDTH - wallThickness - 60.f, playTop + playH * 0.7f, 55.f);
                        drawStalagmite(wallThickness + 50.f, WINDOW_HEIGHT - wallThickness - 60.f, 45.f);
                        drawStalagmite(WINDOW_WIDTH - wallThickness - 50.f, WINDOW_HEIGHT - wallThickness - 60.f, 40.f);
                        drawRubblePile(WINDOW_WIDTH / 2.f - 200.f, playTop + wallThickness + 40.f);
                        drawRubblePile(WINDOW_WIDTH / 2.f + 200.f, WINDOW_HEIGHT - wallThickness - 40.f);
                        break;
                    }
                    case BOSS_DRAGON:
                    case BOSS_SPECTRAL_ALPHA: {
                        // Sala del tesoro: pilastri intatti + casse + cumuli (feature tesori)
                        drawPillar(wallThickness + 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 90.f);
                        drawPillar(WINDOW_WIDTH - wallThickness - 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 90.f);
                        drawPillar(wallThickness + 60.f, playTop + wallThickness + 50.f, 70.f);
                        drawPillar(WINDOW_WIDTH - wallThickness - 60.f, playTop + wallThickness + 50.f, 70.f);
                        drawCrate(wallThickness + 100.f, playTop + playH * 0.5f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 100.f, playTop + playH * 0.5f);
                        drawCrate(wallThickness + 80.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 80.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        break;
                    }
                    case BOSS_WRAITH_LORD:
                    case BOSS_TWILIGHT_KNIGHT: {
                        // Cripta spettrale: stendardi appesi + candelabri da parete + catene
                        drawBanner(wallThickness + 30.f, playTop + wallThickness + 30.f, 60.f, sf::Color(80, 60, 120));
                        drawBanner(WINDOW_WIDTH - wallThickness - 30.f, playTop + wallThickness + 30.f, 60.f, sf::Color(80, 60, 120));
                        drawBanner(wallThickness + 30.f, WINDOW_HEIGHT - wallThickness - 80.f, 50.f, sf::Color(60, 80, 120));
                        drawBanner(WINDOW_WIDTH - wallThickness - 30.f, WINDOW_HEIGHT - wallThickness - 80.f, 50.f, sf::Color(60, 80, 120));
                        drawWallCandle(wallThickness + 5.f, playTop + playH * 0.3f);
                        drawWallCandle(WINDOW_WIDTH - wallThickness - 15.f, playTop + playH * 0.7f);
                        drawWallCandle(wallThickness + 5.f, WINDOW_HEIGHT - wallThickness - 80.f);
                        drawWallCandle(WINDOW_WIDTH - wallThickness - 15.f, playTop + playH * 0.3f);
                        drawHangingChain(WINDOW_WIDTH * 0.25f, playTop + wallThickness, 25.f);
                        drawHangingChain(WINDOW_WIDTH * 0.75f, playTop + wallThickness, 25.f);
                        break;
                    }
                    case BOSS_VAMPIRE: {
                        // Cripta gotica: bara (feature) + stendardi rossi + candelabri
                        drawBanner(wallThickness + 30.f, playTop + wallThickness + 40.f, 70.f, sf::Color(120, 20, 30));
                        drawBanner(WINDOW_WIDTH - wallThickness - 30.f, playTop + wallThickness + 40.f, 70.f, sf::Color(120, 20, 30));
                        drawWallCandle(wallThickness + 5.f, playTop + playH * 0.25f);
                        drawWallCandle(WINDOW_WIDTH - wallThickness - 15.f, playTop + playH * 0.25f);
                        drawWallCandle(wallThickness + 5.f, playTop + playH * 0.75f);
                        drawWallCandle(WINDOW_WIDTH - wallThickness - 15.f, playTop + playH * 0.75f);
                        drawHangingChain(WINDOW_WIDTH * 0.5f, playTop + wallThickness, 30.f);
                        drawHangingChain(WINDOW_WIDTH * 0.5f, WINDOW_HEIGHT - wallThickness - 30.f, 24.f);
                        break;
                    }
                    case BOSS_BEHOLDER:
                    case BOSS_SUPREME_WITCH: {
                        // Torre arcana: pilastri + altari + cristalli magici (cumuli)
                        drawPillar(wallThickness + 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 80.f);
                        drawPillar(WINDOW_WIDTH - wallThickness - 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 80.f);
                        drawAltar(wallThickness + 80.f, playTop + playH * 0.5f);
                        drawAltar(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.5f);
                        drawRubblePile(wallThickness + 50.f, playTop + wallThickness + 50.f);
                        drawRubblePile(WINDOW_WIDTH - wallThickness - 50.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        drawBrazier(wallThickness + 30.f, playTop + wallThickness + 30.f);
                        drawBrazier(WINDOW_WIDTH - wallThickness - 30.f, WINDOW_HEIGHT - wallThickness - 30.f);
                        break;
                    }
                    case BOSS_COLOSSAL_MIMIC: {
                        // Sala del tesoro dorata: casse ovunque + forziere gigante (feature)
                        drawCrate(wallThickness + 80.f, playTop + playH * 0.3f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.3f);
                        drawCrate(wallThickness + 80.f, playTop + playH * 0.7f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 80.f, playTop + playH * 0.7f);
                        drawCrate(wallThickness + 100.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        drawCrate(WINDOW_WIDTH - wallThickness - 100.f, WINDOW_HEIGHT - wallThickness - 50.f);
                        drawPillar(wallThickness + 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 60.f);
                        drawPillar(WINDOW_WIDTH - wallThickness - 60.f, WINDOW_HEIGHT - wallThickness - 10.f, 60.f);
                        break;
                    }
                }
            }

            // --- Elemento "feature" unico per tipo di boss (D&D-style) ---
            // Ogni tipo di boss ha un elemento decorativo caratteristico che
            // rende la stanza immediatamente riconoscibile:
            //   * GOLEM/GHOUL_LORD   : lapidi con incisioni runiche
            //   * LICH/CULT_HERALD    : altare necromantico con candele viola
            //   * DEMON               : pozzo di lava con fiamme
            //   * SPIDER              : grosse ragnatele negli angoli
            //   * ABOMINATION/RAT_KING: gabbie di ferro aperte
            //   * KRAKEN              : pozza d'acqua con bolle
            //   * DRAGON/SPECTRAL_ALPHA: cumulo di tesori (monete+gemme)
            //   * WRAITH_LORD/TWILIGHT: candeliere gigante a 3 braccia
            //   * VAMPIRE              : bara di legno aperta
            //   * BEHOLDER/SUPREME_WITCH: libreria di tomi magici
            //   * COLOSSAL_MIMIC       : forziere gigante (esca)
            if (boss) {
                BossType bt = boss->getType();
                switch (bt) {
                    case BOSS_GOLEM:
                    case BOSS_GHOUL_LORD: {
                        // Lapide runica centrale sul pavimento (dietro il boss)
                        float lx = WINDOW_WIDTH / 2.f;
                        float ly = playTop + playH * 0.5f + 80.f;
                        // Ombra
                        sf::CircleShape rs(28.f);
                        rs.setFillColor(sf::Color(0, 0, 0, 120));
                        rs.setPosition(lx - 28.f, ly + 12.f);
                        window.draw(rs);
                        // Stele grande con runa
                        sf::ConvexShape stele; stele.setPointCount(6);
                        stele.setFillColor(stoneBase);
                        stele.setOutlineThickness(1.5f);
                        stele.setOutlineColor(stoneDark);
                        stele.setPoint(0, sf::Vector2f(lx - 16.f, ly + 14.f));
                        stele.setPoint(1, sf::Vector2f(lx + 16.f, ly + 14.f));
                        stele.setPoint(2, sf::Vector2f(lx + 16.f, ly - 20.f));
                        stele.setPoint(3, sf::Vector2f(lx + 12.f, ly - 26.f));
                        stele.setPoint(4, sf::Vector2f(lx - 12.f, ly - 26.f));
                        stele.setPoint(5, sf::Vector2f(lx - 16.f, ly - 20.f));
                        window.draw(stele);
                        // Runa centrale (cerchio con linee)
                        sf::CircleShape runeCircle(8.f);
                        runeCircle.setFillColor(sf::Color(0, 0, 0, 0));
                        runeCircle.setOutlineThickness(1.5f);
                        runeCircle.setOutlineColor(stoneLight);
                        runeCircle.setPosition(lx - 8.f, ly - 14.f);
                        window.draw(runeCircle);
                        // Linea verticale runica
                        sf::RectangleShape runeLine(sf::Vector2f(1.5f, 16.f));
                        runeLine.setFillColor(stoneLight);
                        runeLine.setPosition(lx - 0.75f, ly - 16.f);
                        window.draw(runeLine);
                        break;
                    }
                    case BOSS_LICH:
                    case BOSS_CULT_HERALD: {
                        // Altare necromantico con 3 candele viola
                        float ax = WINDOW_WIDTH / 2.f;
                        float ay = playTop + playH * 0.5f + 100.f;
                        // Base altare
                        sf::RectangleShape altar(sf::Vector2f(60.f, 14.f));
                        altar.setFillColor(stoneDark);
                        altar.setOutlineThickness(1.f);
                        altar.setOutlineColor(stoneBase);
                        altar.setPosition(ax - 30.f, ay);
                        window.draw(altar);
                        sf::RectangleShape altarTop(sf::Vector2f(64.f, 4.f));
                        altarTop.setFillColor(stoneLight);
                        altarTop.setPosition(ax - 32.f, ay);
                        window.draw(altarTop);
                        // 3 candele viola sopra l'altare
                        for (int i = 0; i < 3; i++) {
                            float cx = ax - 18.f + i * 18.f;
                            // Candela
                            sf::RectangleShape candle(sf::Vector2f(4.f, 12.f));
                            candle.setFillColor(sf::Color(220, 200, 240));
                            candle.setOutlineThickness(0.5f);
                            candle.setOutlineColor(sf::Color(100, 60, 130));
                            candle.setPosition(cx - 2.f, ay - 12.f);
                            window.draw(candle);
                            // Fiamma viola animata
                            float flick = sinf(bossRoomTime * 14.f + i * 1.5f) * 1.f;
                            sf::CircleShape cFlame(2.f + flick);
                            cFlame.setFillColor(sf::Color(200, 100, 240, 230));
                            cFlame.setPosition(cx - 2.f - flick, ay - 18.f);
                            window.draw(cFlame);
                            // Aura fiamma
                            sf::CircleShape cAura(6.f);
                            cAura.setFillColor(sf::Color(180, 80, 220, 50));
                            cAura.setPosition(cx - 6.f, ay - 22.f);
                            window.draw(cAura);
                        }
                        break;
                    }
                    case BOSS_DEMON: {
                        // Pozzo di lava con fiamme
                        float lx = WINDOW_WIDTH / 2.f;
                        float ly = playTop + playH * 0.5f + 100.f;
                        // Pozzo (cerchio scuro)
                        sf::CircleShape lava(28.f);
                        lava.setFillColor(sf::Color(80, 20, 5));
                        lava.setOutlineThickness(2.f);
                        lava.setOutlineColor(stoneDark);
                        lava.setPosition(lx - 28.f, ly - 8.f);
                        window.draw(lava);
                        // Lava incandescente
                        sf::CircleShape lavaGlow(22.f);
                        lavaGlow.setFillColor(sf::Color(255, 100, 20, 200));
                        lavaGlow.setPosition(lx - 22.f, ly - 2.f);
                        window.draw(lavaGlow);
                        // Bagliore
                        sf::CircleShape lavaBright(14.f);
                        lavaBright.setFillColor(sf::Color(255, 200, 80, 180));
                        lavaBright.setPosition(lx - 14.f, ly + 2.f);
                        window.draw(lavaBright);
                        // Fiammelle che si alzano
                        for (int i = 0; i < 5; i++) {
                            float fx = lx - 18.f + i * 9.f;
                            float fyOff = sinf(bossRoomTime * 8.f + i) * 4.f;
                            sf::CircleShape flame(2.5f + sinf(bossRoomTime * 10.f + i) * 0.5f);
                            flame.setFillColor(sf::Color(255, 150, 40, 220));
                            flame.setPosition(fx - 2.5f, ly - 14.f + fyOff);
                            window.draw(flame);
                        }
                        break;
                    }
                    case BOSS_SPIDER: {
                        // Ragnatele negli angoli (sopra le decorazioni esistenti)
                        // 4 ragnatele grandi agli angoli della stanza
                        for (int corner = 0; corner < 4; corner++) {
                            float cx = (corner % 2 == 0) ? wallThickness + 50.f
                                                         : WINDOW_WIDTH - wallThickness - 50.f;
                            float cy = (corner < 2) ? playTop + wallThickness + 50.f
                                                     : WINDOW_HEIGHT - wallThickness - 50.f;
                            // Ragnatela: 6 fili radiali + 2 cerchi concentrici
                            for (int r = 0; r < 6; r++) {
                                float a = r * (float)M_PI / 3.f + corner * 0.5f;
                                sf::RectangleShape thread(sf::Vector2f(0.8f, 24.f));
                                thread.setFillColor(sf::Color(240, 240, 240, 140));
                                thread.setOrigin(0.4f, 0.f);
                                thread.setPosition(cx, cy);
                                thread.rotate(a * 180.f / (float)M_PI);
                                window.draw(thread);
                            }
                            // Cerchio concentrico
                            sf::CircleShape webC1(16.f);
                            webC1.setFillColor(sf::Color(0, 0, 0, 0));
                            webC1.setOutlineThickness(0.6f);
                            webC1.setOutlineColor(sf::Color(240, 240, 240, 120));
                            webC1.setPosition(cx - 16.f, cy - 16.f);
                            window.draw(webC1);
                            sf::CircleShape webC2(8.f);
                            webC2.setFillColor(sf::Color(0, 0, 0, 0));
                            webC2.setOutlineThickness(0.6f);
                            webC2.setOutlineColor(sf::Color(240, 240, 240, 140));
                            webC2.setPosition(cx - 8.f, cy - 8.f);
                            window.draw(webC2);
                        }
                        break;
                    }
                    case BOSS_ABOMINATION:
                    case BOSS_RAT_KING: {
                        // Gabbie di ferro aperte sul pavimento
                        float gx = WINDOW_WIDTH / 2.f;
                        float gy = playTop + playH * 0.5f + 90.f;
                        // Base gabbia
                        sf::RectangleShape cageBase(sf::Vector2f(40.f, 6.f));
                        cageBase.setFillColor(sf::Color(50, 40, 30));
                        cageBase.setOutlineThickness(0.8f);
                        cageBase.setOutlineColor(sf::Color(20, 15, 10));
                        cageBase.setPosition(gx - 20.f, gy + 8.f);
                        window.draw(cageBase);
                        // Sbarre verticali (5)
                        for (int i = 0; i < 5; i++) {
                            sf::RectangleShape bar(sf::Vector2f(1.5f, 22.f));
                            bar.setFillColor(sf::Color(70, 60, 50));
                            bar.setOutlineThickness(0.4f);
                            bar.setOutlineColor(sf::Color(30, 25, 20));
                            bar.setPosition(gx - 18.f + i * 9.f, gy - 14.f);
                            window.draw(bar);
                        }
                        // Top della gabbia aperto (pendente)
                        sf::ConvexShape cageTop; cageTop.setPointCount(4);
                        cageTop.setFillColor(sf::Color(50, 40, 30));
                        cageTop.setOutlineThickness(0.5f);
                        cageTop.setOutlineColor(sf::Color(20, 15, 10));
                        cageTop.setPoint(0, sf::Vector2f(gx - 20.f, gy - 14.f));
                        cageTop.setPoint(1, sf::Vector2f(gx - 8.f, gy - 14.f));
                        cageTop.setPoint(2, sf::Vector2f(gx - 6.f, gy - 24.f));
                        cageTop.setPoint(3, sf::Vector2f(gx - 18.f, gy - 22.f));
                        window.draw(cageTop);
                        // Osso dentro la gabbia
                        sf::RectangleShape bone(sf::Vector2f(12.f, 2.f));
                        bone.setFillColor(boneCol);
                        bone.setOutlineThickness(0.4f);
                        bone.setOutlineColor(boneDark);
                        bone.setPosition(gx - 6.f, gy + 4.f);
                        window.draw(bone);
                        break;
                    }
                    case BOSS_KRAKEN: {
                        // Pozza d'acqua con bolle animate
                        float wx = WINDOW_WIDTH / 2.f;
                        float wy = playTop + playH * 0.5f + 100.f;
                        // Pozza (ellisse scura)
                        sf::CircleShape pool(30.f);
                        pool.setFillColor(sf::Color(20, 50, 60, 200));
                        pool.setOutlineThickness(1.5f);
                        pool.setOutlineColor(sf::Color(40, 80, 90));
                        pool.setScale(1.f, 0.5f);
                        pool.setPosition(wx - 30.f, wy - 5.f);
                        window.draw(pool);
                        // Riflesso
                        sf::CircleShape poolRef(22.f);
                        poolRef.setFillColor(sf::Color(80, 150, 170, 100));
                        poolRef.setScale(1.f, 0.5f);
                        poolRef.setPosition(wx - 22.f, wy - 1.f);
                        window.draw(poolRef);
                        // Bolle animate
                        for (int i = 0; i < 6; i++) {
                            float bx = wx - 18.f + (i * 7.f);
                            float byOff = sinf(bossRoomTime * 3.f + i * 1.2f) * 4.f;
                            sf::CircleShape bubble(1.5f + (i % 2) * 0.5f);
                            bubble.setFillColor(sf::Color(180, 220, 230, 180));
                            bubble.setPosition(bx, wy - 3.f + byOff);
                            window.draw(bubble);
                        }
                        break;
                    }
                    case BOSS_DRAGON:
                    case BOSS_SPECTRAL_ALPHA: {
                        // Cumulo di tesori (monete + gemme)
                        float tx = WINDOW_WIDTH / 2.f;
                        float ty = playTop + playH * 0.5f + 90.f;
                        // Ombra
                        sf::CircleShape tShadow(36.f);
                        tShadow.setFillColor(sf::Color(0, 0, 0, 130));
                        tShadow.setPosition(tx - 36.f, ty + 4.f);
                        window.draw(tShadow);
                        // 6 monete d'oro
                        for (int i = 0; i < 6; i++) {
                            sf::CircleShape coin(5.f);
                            coin.setFillColor(sf::Color(255, 215, 0));
                            coin.setOutlineThickness(0.6f);
                            coin.setOutlineColor(sf::Color(180, 130, 30));
                            coin.setPosition(tx - 22.f + i * 8.f + (i % 2) * 3.f, ty + 4.f - (i % 3) * 2.f);
                            window.draw(coin);
                            // Riflesso
                            sf::RectangleShape cRef(sf::Vector2f(6.f, 0.8f));
                            cRef.setFillColor(sf::Color(255, 245, 150));
                            cRef.setPosition(tx - 21.f + i * 8.f + (i % 2) * 3.f, ty + 4.f - (i % 3) * 2.f);
                            window.draw(cRef);
                        }
                        // 3 gemme colorate
                        sf::Color gemCols[3] = {
                            sf::Color(220, 30, 30),
                            sf::Color(30, 180, 80),
                            sf::Color(80, 80, 220)
                        };
                        for (int i = 0; i < 3; i++) {
                            sf::ConvexShape gem; gem.setPointCount(4);
                            gem.setFillColor(gemCols[i]);
                            gem.setOutlineThickness(0.6f);
                            gem.setOutlineColor(sf::Color(20, 20, 20));
                            gem.setPoint(0, sf::Vector2f(tx - 12.f + i * 12.f, ty - 2.f));
                            gem.setPoint(1, sf::Vector2f(tx - 9.f + i * 12.f, ty + 1.f));
                            gem.setPoint(2, sf::Vector2f(tx - 12.f + i * 12.f, ty + 4.f));
                            gem.setPoint(3, sf::Vector2f(tx - 15.f + i * 12.f, ty + 1.f));
                            window.draw(gem);
                        }
                        // Calice d'oro al centro del cumulo
                        // FIX -Wshadow: variabile locale rinominata da
                        // 'chalice' a 'chaliceIcon' per evitare shadowing
                        // del membro Game::chalice.
                        sf::RectangleShape chaliceIcon(sf::Vector2f(10.f, 8.f));
                        chaliceIcon.setFillColor(sf::Color(255, 215, 0));
                        chaliceIcon.setOutlineThickness(0.8f);
                        chaliceIcon.setOutlineColor(sf::Color(180, 130, 30));
                        chaliceIcon.setPosition(tx - 5.f, ty - 8.f);
                        window.draw(chaliceIcon);
                        break;
                    }
                    case BOSS_WRAITH_LORD:
                    case BOSS_TWILIGHT_KNIGHT: {
                        // Candeliere gigante a 3 braccia
                        float cx = WINDOW_WIDTH / 2.f;
                        float cy = playTop + playH * 0.5f + 100.f;
                        // Base
                        sf::RectangleShape base(sf::Vector2f(20.f, 4.f));
                        base.setFillColor(stoneDark);
                        base.setOutlineThickness(0.8f);
                        base.setOutlineColor(stoneBase);
                        base.setPosition(cx - 10.f, cy + 10.f);
                        window.draw(base);
                        // Stelo centrale
                        sf::RectangleShape stem(sf::Vector2f(3.f, 24.f));
                        stem.setFillColor(stoneBase);
                        stem.setOutlineThickness(0.5f);
                        stem.setOutlineColor(stoneDark);
                        stem.setPosition(cx - 1.5f, cy - 14.f);
                        window.draw(stem);
                        // 3 braccia (a diverse altezze)
                        for (int i = 0; i < 3; i++) {
                            float by = cy - 10.f + i * 8.f;
                            float dx = (i % 2 == 0) ? -14.f : 14.f;
                            // Braccio orizzontale
                            sf::RectangleShape arm(sf::Vector2f(std::abs(dx) + 4.f, 1.5f));
                            arm.setFillColor(stoneBase);
                            arm.setOutlineThickness(0.4f);
                            arm.setOutlineColor(stoneDark);
                            arm.setPosition((dx < 0) ? cx + dx : cx, by);
                            window.draw(arm);
                            // Candela in cima
                            sf::RectangleShape candle(sf::Vector2f(3.f, 6.f));
                            candle.setFillColor(sf::Color(220, 220, 200));
                            candle.setPosition(cx + dx - 1.5f, by - 6.f);
                            window.draw(candle);
                            // Fiamma ciano animata
                            float flick = sinf(bossRoomTime * 12.f + i * 1.3f) * 0.8f;
                            sf::CircleShape flame(1.5f + flick);
                            flame.setFillColor(sf::Color(150, 220, 255, 230));
                            flame.setPosition(cx + dx - 1.5f - flick, by - 10.f);
                            window.draw(flame);
                            // Aura
                            sf::CircleShape cAura(5.f);
                            cAura.setFillColor(sf::Color(100, 200, 255, 50));
                            cAura.setPosition(cx + dx - 5.f, by - 14.f);
                            window.draw(cAura);
                        }
                        break;
                    }
                    case BOSS_VAMPIRE: {
                        // Bara di legno aperta
                        float bx = WINDOW_WIDTH / 2.f;
                        float by = playTop + playH * 0.5f + 90.f;
                        // Ombra
                        sf::CircleShape bShadow(34.f);
                        bShadow.setFillColor(sf::Color(0, 0, 0, 130));
                        bShadow.setPosition(bx - 34.f, by + 8.f);
                        window.draw(bShadow);
                        // Bara (rettangolo scuro)
                        sf::RectangleShape coffin(sf::Vector2f(50.f, 22.f));
                        coffin.setFillColor(sf::Color(60, 30, 20));
                        coffin.setOutlineThickness(1.5f);
                        coffin.setOutlineColor(sf::Color(30, 15, 10));
                        coffin.setPosition(bx - 25.f, by - 4.f);
                        window.draw(coffin);
                        // Interno rosso (seta)
                        sf::RectangleShape silk(sf::Vector2f(46.f, 18.f));
                        silk.setFillColor(sf::Color(120, 30, 30));
                        silk.setPosition(bx - 23.f, by - 2.f);
                        window.draw(silk);
                        // Coperchio aperto (pendente di lato)
                        sf::ConvexShape lid; lid.setPointCount(4);
                        lid.setFillColor(sf::Color(50, 25, 15));
                        lid.setOutlineThickness(1.f);
                        lid.setOutlineColor(sf::Color(20, 10, 5));
                        lid.setPoint(0, sf::Vector2f(bx - 25.f, by - 4.f));
                        lid.setPoint(1, sf::Vector2f(bx + 25.f, by - 4.f));
                        lid.setPoint(2, sf::Vector2f(bx + 38.f, by - 18.f));
                        lid.setPoint(3, sf::Vector2f(bx - 12.f, by - 22.f));
                        window.draw(lid);
                        // Cross ornamentale sul coperchio
                        sf::RectangleShape cross1(sf::Vector2f(2.f, 10.f));
                        cross1.setFillColor(sf::Color(200, 200, 200));
                        cross1.setPosition(bx + 10.f, by - 14.f);
                        window.draw(cross1);
                        sf::RectangleShape cross2(sf::Vector2f(8.f, 2.f));
                        cross2.setFillColor(sf::Color(200, 200, 200));
                        cross2.setPosition(bx + 7.f, by - 10.f);
                        window.draw(cross2);
                        break;
                    }
                    case BOSS_BEHOLDER:
                    case BOSS_SUPREME_WITCH: {
                        // Libreria di tomi magici
                        float bx = WINDOW_WIDTH / 2.f;
                        float by = playTop + playH * 0.5f + 100.f;
                        // Base
                        sf::RectangleShape base(sf::Vector2f(48.f, 4.f));
                        base.setFillColor(stoneDark);
                        base.setOutlineThickness(0.8f);
                        base.setOutlineColor(stoneBase);
                        base.setPosition(bx - 24.f, by + 8.f);
                        window.draw(base);
                        // 5 tomi affiancati
                        sf::Color bookCols[5] = {
                            sf::Color(180, 50, 50),    // rosso
                            sf::Color(50, 100, 180),   // blu
                            sf::Color(50, 150, 60),    // verde
                            sf::Color(180, 130, 40),   // giallo
                            sf::Color(140, 60, 180)    // viola
                        };
                        for (int i = 0; i < 5; i++) {
                            // Copertina del tomo
                            sf::RectangleShape book(sf::Vector2f(7.f, 18.f));
                            book.setFillColor(bookCols[i]);
                            book.setOutlineThickness(0.6f);
                            book.setOutlineColor(sf::Color(30, 30, 30));
                            book.setPosition(bx - 22.f + i * 9.f, by - 10.f);
                            window.draw(book);
                            // Pagine (striscia chiara)
                            sf::RectangleShape pages(sf::Vector2f(5.f, 14.f));
                            pages.setFillColor(sf::Color(240, 230, 200));
                            pages.setPosition(bx - 21.f + i * 9.f, by - 8.f);
                            window.draw(pages);
                            // Simbolo magico sul dorso (punto dorato)
                            sf::CircleShape symbol(0.8f);
                            symbol.setFillColor(sf::Color(255, 215, 0));
                            symbol.setPosition(bx - 19.f + i * 9.f, by - 4.f);
                            window.draw(symbol);
                        }
                        // Aura magica sopra la libreria
                        sf::CircleShape bookAura(20.f);
                        bookAura.setFillColor(sf::Color(180, 80, 220, 40));
                        bookAura.setPosition(bx - 20.f, by - 28.f);
                        window.draw(bookAura);
                        break;
                    }
                    case BOSS_COLOSSAL_MIMIC: {
                        // Forziere gigante (esca)
                        float cx = WINDOW_WIDTH / 2.f;
                        float cy = playTop + playH * 0.5f + 90.f;
                        // Ombra
                        sf::CircleShape tShadow(36.f);
                        tShadow.setFillColor(sf::Color(0, 0, 0, 130));
                        tShadow.setPosition(cx - 36.f, cy + 6.f);
                        window.draw(tShadow);
                        // Corpo forziere
                        sf::RectangleShape body(sf::Vector2f(60.f, 32.f));
                        body.setFillColor(sf::Color(110, 65, 25));
                        body.setOutlineThickness(1.5f);
                        body.setOutlineColor(sf::Color(60, 35, 15));
                        body.setPosition(cx - 30.f, cy - 8.f);
                        window.draw(body);
                        // Strato superiore
                        sf::RectangleShape bodyTop(sf::Vector2f(60.f, 6.f));
                        bodyTop.setFillColor(sf::Color(140, 85, 35));
                        bodyTop.setPosition(cx - 30.f, cy - 8.f);
                        window.draw(bodyTop);
                        // Coperchio arcuato
                        sf::ConvexShape lid; lid.setPointCount(6);
                        lid.setFillColor(sf::Color(90, 55, 20));
                        lid.setOutlineThickness(1.f);
                        lid.setOutlineColor(sf::Color(50, 30, 10));
                        lid.setPoint(0, sf::Vector2f(cx - 30.f, cy - 8.f));
                        lid.setPoint(1, sf::Vector2f(cx + 30.f, cy - 8.f));
                        lid.setPoint(2, sf::Vector2f(cx + 26.f, cy - 18.f));
                        lid.setPoint(3, sf::Vector2f(cx + 16.f, cy - 24.f));
                        lid.setPoint(4, sf::Vector2f(cx - 16.f, cy - 24.f));
                        lid.setPoint(5, sf::Vector2f(cx - 26.f, cy - 18.f));
                        window.draw(lid);
                        // Bocca aperta (dente) - indica che e' un mimic
                        sf::RectangleShape maw(sf::Vector2f(36.f, 6.f));
                        maw.setFillColor(sf::Color::Black);
                        maw.setPosition(cx - 18.f, cy + 4.f);
                        window.draw(maw);
                        // 6 denti
                        for (int i = 0; i < 6; i++) {
                            sf::ConvexShape tooth; tooth.setPointCount(3);
                            tooth.setFillColor(sf::Color(255, 255, 220));
                            float tw = 6.f;
                            tooth.setPoint(0, sf::Vector2f(cx - 18.f + i * tw, cy + 4.f));
                            tooth.setPoint(1, sf::Vector2f(cx - 18.f + (i+1) * tw, cy + 4.f));
                            tooth.setPoint(2, sf::Vector2f(cx - 18.f + i * tw + tw/2, cy + 10.f));
                            window.draw(tooth);
                        }
                        // Occhio gigante (indizio che e' un mimic)
                        sf::CircleShape eye(4.f);
                        eye.setFillColor(sf::Color(255, 240, 100));
                        eye.setOutlineThickness(0.8f);
                        eye.setOutlineColor(sf::Color(80, 60, 10));
                        eye.setPosition(cx - 2.f, cy - 18.f);
                        window.draw(eye);
                        sf::CircleShape pupil(1.5f);
                        pupil.setFillColor(sf::Color::Black);
                        pupil.setPosition(cx - 0.5f, cy - 16.5f);
                        window.draw(pupil);
                        break;
                    }
                }
            }

            // --- Particelle ambientali animate (effetto luce) ---
            // Piccoli punti luminosi fluttuanti colorati in base al tipo di
            // boss (es. scintille per DEMON, bolle per KRAKEN, anime per WRAITH,
            // spore per SUPREME_WITCH). Generati con seed fisso per stabilita'.
            {
                // Colore particelle = ambientLight ma più vivo
                sf::Color particleCol = ambientLight;
                particleCol.a = 180;
                // 12 particelle, posizioni deterministiche ma con animazione
                // verticale sinusoidale (effetto fluttuazione).
                srand(7);  // seed fisso per layout stabile
                for (int i = 0; i < 14; i++) {
                    float baseX = (float)(rand() % (WINDOW_WIDTH - 100)) + 50.f;
                    float baseY = (float)(rand() % (playH - 100)) + playTop + 50.f;
                    // Animazione: oscillazione sinusoidale attorno alla posizione base
                    float t = bossRoomTime + i * 0.7f;
                    float dx = sinf(t * 1.5f) * 8.f;
                    float dy = cosf(t * 1.2f) * 6.f;
                    float px = baseX + dx;
                    float py = baseY + dy;
                    // Pulsazione alpha
                    float alphaPulse = (sinf(t * 3.f) + 1.f) * 0.5f;  // 0..1
                    sf::Uint8 pAlpha = (sf::Uint8)(100 + alphaPulse * 100);
                    // Particella principale
                    sf::CircleShape particle(1.5f);
                    sf::Color pCol = particleCol;
                    pCol.a = pAlpha;
                    particle.setFillColor(pCol);
                    particle.setPosition(px - 1.5f, py - 1.5f);
                    window.draw(particle);
                    // Aura più larga e debole
                    sf::CircleShape pAura(4.f);
                    sf::Color aCol = particleCol;
                    aCol.a = pAlpha / 4;
                    pAura.setFillColor(aCol);
                    pAura.setPosition(px - 4.f, py - 4.f);
                    window.draw(pAura);
                }
                srand((unsigned int)time(NULL));  // ripristina seed randomico
            }
        }

        // UI senza tesori (passiamo 0)
        if (numPlayers == 2)
            ui.render(window, player, player2, 0);
        else
            ui.render(window, player, 0);
        // Armi a terra (raccoglibili)
        for (const auto& brw : bossRoomWeapons) brw.w.render(window, brw.pos.x - TILE_SIZE/2, brw.pos.y - TILE_SIZE/2);
        // Bonus scarpe alate (se attivo, disegna sprite + aura)
        // Lambda per disegnare un paio di scarpe (riusato per speedBoots
        // e speedBoots2 in modalita' 2P).
        auto drawSpeedBoots = [&](const SpeedBootsBonus& boots) {
            if (!boots.active) return;
            float bx = boots.pos.x;
            float by = boots.pos.y + boots.bobOffset;
            // Carica lo sprite delle scarpe alate se non gia' fatto
            static SpriteSheet bootsSprite;
            static bool bootsLoaded = false;
            if (!bootsLoaded) {
                bootsLoaded = bootsSprite.load("assets/sprites/bonus_speedboots");
            }
            if (bootsSprite.isLoaded()) {
                bootsSprite.render(window, "idle", 0, bx, by, 1.0f, false);
            } else {
                // Fallback: disegna scarpe con ali primitive
                sf::RectangleShape boot1(sf::Vector2f(8.f, 6.f));
                boot1.setFillColor(sf::Color(80, 50, 20));
                boot1.setPosition(bx - 6.f, by); window.draw(boot1);
                boot1.setPosition(bx + 2.f, by); window.draw(boot1);
                // Ali bianche
                sf::ConvexShape wing; wing.setPointCount(4);
                wing.setFillColor(sf::Color(240, 240, 240));
                wing.setPoint(0, sf::Vector2f(bx-4, by-2));
                wing.setPoint(1, sf::Vector2f(bx-12, by-6));
                wing.setPoint(2, sf::Vector2f(bx-10, by+2));
                wing.setPoint(3, sf::Vector2f(bx-4, by+2));
                window.draw(wing);
            }
            // Aura gialla pulsante
            sf::CircleShape aura(20.f + sinf(boots.bobOffset * 0.5f) * 3.f);
            aura.setFillColor(sf::Color(255, 220, 80, 40));
            aura.setPosition(bx - 20.f, by - 20.f);
            window.draw(aura);
        };
        // Disegna speedBoots (player1 o 1P)
        drawSpeedBoots(speedBoots);
        // Disegna speedBoots2 (player2 in 2P)
        if (numPlayers == 2) drawSpeedBoots(speedBoots2);

        // --- Rendering dello scettro magico (nella stanza del boss, stile Gandalf) ---
        // Lo scettro può apparire anche nella stanza del boss (vedi
        // startBossFight riga 377), e se il player lo raccoglie li' deve
        // vederlo. Inoltre i fulmini devono essere renderizzati nel boss
        // anche se lo scettro e' stato raccolto nel labirinto (i 5 fulmini
        // a intervalli di 3 secondi continuano nella stanza del boss se il
        // player ci entra prima che finiscano).
        if (scepter.active && !scepter.triggered) {
            float sx = scepter.pos.x;
            float sy = scepter.pos.y + scepter.bobOffset;
            float sPulse = sinf(scepter.pulse * 4.f) * 0.15f + 1.f;
            drawMagicScepter(window, sx, sy, sPulse);
        }

        // --- Rendering dei fulmini (nella stanza del boss) ---
        for (const auto& lt : lightnings) {
            drawLightning(window, lt);
        }

        // --- Particelle (fiammate, scintille, sangue) nella stanza del boss ---
        // Prima non venivano renderizzate in STATE_BOSS: le fiammate dei
        // nemici bruciati dal player invincibile non si vedevano. Ora le
        // disegniamo con glow + nucleo (come STATE_PLAYING), supportando
        // anche le fiamme triangolari (type 1).
        for (const auto& p : particles) {
            float lifeRatio = (float)p.life / (float)p.maxLife;
            sf::Uint8 alpha = (sf::Uint8)(255 * lifeRatio);
            float sz = p.size;
            sf::CircleShape glow(sz * 2.f);
            glow.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b,
                                        (sf::Uint8)(alpha * 0.35f)));
            glow.setPosition(p.pos.x - sz * 2.f, p.pos.y - sz * 2.f);
            window.draw(glow);
            if (p.type == 1) {
                sf::ConvexShape flame;
                flame.setPointCount(3);
                flame.setPoint(0, sf::Vector2f(p.pos.x - sz, p.pos.y + sz));
                flame.setPoint(1, sf::Vector2f(p.pos.x + sz, p.pos.y + sz));
                flame.setPoint(2, sf::Vector2f(p.pos.x, p.pos.y - sz * 1.5f));
                flame.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, alpha));
                window.draw(flame);
            } else if (p.type == 2) {
                sf::RectangleShape sq(sf::Vector2f(sz * 2.f, sz * 2.f));
                sq.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, alpha));
                sq.setPosition(p.pos.x - sz, p.pos.y - sz);
                window.draw(sq);
            } else {
                sf::CircleShape c(sz);
                c.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, alpha));
                c.setPosition(p.pos.x - sz, p.pos.y - sz);
                window.draw(c);
            }
        }

        // --- Macchie di sangue/cenere sul pavimento (stanza del boss) ---
        for (const auto& bs : bloodStains) {
            float alpha = 200.f * (float)bs.life / (float)bs.maxLife;
            if (alpha < 0) alpha = 0;
            sf::CircleShape stain(bs.radius);
            stain.setFillColor(sf::Color(bs.color.r, bs.color.g, bs.color.b, (sf::Uint8)alpha));
            stain.setPosition(bs.pos.x - bs.radius, bs.pos.y - bs.radius);
            window.draw(stain);
            // Schizzi più piccoli attorno
            for (int i = 0; i < 4; i++) {
                float angle = i * (float)M_PI / 2.f + 0.5f;
                float dist = bs.radius * 1.5f;
                float sx = bs.pos.x + cosf(angle) * dist;
                float sy = bs.pos.y + sinf(angle) * dist;
                float sr = bs.radius * 0.4f;
                sf::CircleShape splash(sr);
                splash.setFillColor(sf::Color(bs.color.r, bs.color.g, bs.color.b, (sf::Uint8)(alpha * 0.7f)));
                splash.setPosition(sx - sr, sy - sr);
                window.draw(splash);
            }
        }

        // --- Mucchi di cenere sul pavimento (stanza del boss) ---
        // Renderizzato tramite drawAshPiles() (stesso metodo di STATE_PLAYING)
        // che usa spritesheet PNG avanzato (effect_ashpile) + braci + fumo.
        drawAshPiles(window);

        // --- Esplosioni di fuoco (nemici bruciati dal player invincibile) ---
        // Renderizzato tramite drawFireBursts() (stesso metodo di STATE_PLAYING).
        drawFireBursts(window);
        player.render(window);
        if (numPlayers == 2) player2.render(window);
        boss->render(window);

        // --- Proiettili boss: rendering type-specific ---
        // Ogni BossProjKind ha forma/colore/animazione propri. L'homing e'
        // evidenziato con un'aura aggiuntiva attorno al proiettile.
        for (const auto& p : bossProjectiles) {
            if (!p.active) continue;
            float px = p.pos.x;
            float py = p.pos.y;
            // Aura per proiettili homing (chiazza luminosa attorno)
            if (p.homingTimer > 0) {
                sf::CircleShape homAura(10.f);
                homAura.setFillColor(sf::Color(180, 80, 255, 60));
                homAura.setPosition(px - 10.f, py - 10.f);
                window.draw(homAura);
            }
            switch (p.bpKind) {
                case BP_BOULDER: {
                    // GOLEM: blocco di pietra squadrato con angoli smussati
                    // (non piu' un pallino, ma un vero masso quadrato)
                    sf::ConvexShape boulder; boulder.setPointCount(6);
                    boulder.setFillColor(sf::Color(110, 100, 85));
                    boulder.setOutlineThickness(1.f);
                    boulder.setOutlineColor(sf::Color(50, 45, 35));
                    // Esagono irregolare (masso)
                    boulder.setPoint(0, sf::Vector2f(px - 5.f, py - 4.f));
                    boulder.setPoint(1, sf::Vector2f(px + 5.f, py - 5.f));
                    boulder.setPoint(2, sf::Vector2f(px + 6.f, py + 2.f));
                    boulder.setPoint(3, sf::Vector2f(px + 4.f, py + 5.f));
                    boulder.setPoint(4, sf::Vector2f(px - 5.f, py + 5.f));
                    boulder.setPoint(5, sf::Vector2f(px - 6.f, py - 1.f));
                    window.draw(boulder);
                    // Highlight (sfaccettatura)
                    sf::ConvexShape bHigh; bHigh.setPointCount(3);
                    bHigh.setFillColor(sf::Color(170, 160, 140));
                    bHigh.setPoint(0, sf::Vector2f(px - 3.f, py - 3.f));
                    bHigh.setPoint(1, sf::Vector2f(px + 3.f, py - 3.f));
                    bHigh.setPoint(2, sf::Vector2f(px, py));
                    window.draw(bHigh);
                    // Crepa
                    sf::RectangleShape crack(sf::Vector2f(0.8f, 5.f));
                    crack.setFillColor(sf::Color(40, 35, 28));
                    crack.setOrigin(0.4f, 2.5f);
                    crack.setPosition(px + 1.f, py);
                    crack.rotate(25.f);
                    window.draw(crack);
                    break;
                }
                case BP_NECRO_BOLT: {
                    // LICH: fulmine necrotico verde a zigzag
                    // (non piu' un pallino, ma una vera saetta)
                    sf::CircleShape necAura(8.f);
                    necAura.setFillColor(sf::Color(80, 220, 80, 60));
                    necAura.setPosition(px - 8.f, py - 8.f);
                    window.draw(necAura);
                    // Fulmine zigzag: 4 segmenti collegati a forma di ConvexShape
                    sf::ConvexShape bolt; bolt.setPointCount(8);
                    bolt.setFillColor(sf::Color(120, 255, 120));
                    bolt.setOutlineThickness(0.6f);
                    bolt.setOutlineColor(sf::Color(40, 120, 40));
                    // Forma a saetta: parte larga in alto, zigzag, punta in basso
                    bolt.setPoint(0, sf::Vector2f(px - 1.5f, py - 6.f));
                    bolt.setPoint(1, sf::Vector2f(px + 1.5f, py - 6.f));
                    bolt.setPoint(2, sf::Vector2f(px + 3.f,  py - 2.f));
                    bolt.setPoint(3, sf::Vector2f(px + 1.f,  py - 1.f));
                    bolt.setPoint(4, sf::Vector2f(px + 3.f,  py + 2.f));
                    bolt.setPoint(5, sf::Vector2f(px + 1.5f, py + 6.f));
                    bolt.setPoint(6, sf::Vector2f(px - 1.5f, py + 6.f));
                    bolt.setPoint(7, sf::Vector2f(px - 1.f,  py + 2.f));
                    // (i punti formano un fulmine stilizzato)
                    window.draw(bolt);
                    // Scintilla centrale bianca
                    sf::CircleShape spark(1.f);
                    spark.setFillColor(sf::Color(240, 255, 240));
                    spark.setPosition(px - 1.f, py - 1.f);
                    window.draw(spark);
                    break;
                }
                case BP_FIREBALL: {
                    // DEMON: palla di fuoco con lingue di fiamma
                    // (non piu' un pallino, ma una sfera con 4 fiamme che si alzano)
                    float pulse = sinf(p.age * 0.02f) * 0.8f;
                    sf::CircleShape fAura(7.f + pulse);
                    fAura.setFillColor(sf::Color(255, 100, 30, 80));
                    fAura.setPosition(px - 7.f - pulse, py - 7.f - pulse);
                    window.draw(fAura);
                    // 4 lingue di fiamma che si alzano (triangoli animati)
                    for (int i = 0; i < 4; i++) {
                        float ang = i * (float)M_PI / 2.f + p.age * 0.005f;
                        float flameLen = 4.f + sinf(p.age * 0.025f + i) * 1.5f;
                        sf::ConvexShape flame; flame.setPointCount(3);
                        flame.setFillColor(sf::Color(255, 140, 30, 200));
                        // Triangolo che parte dal centro verso l'esterno
                        flame.setPoint(0, sf::Vector2f(px + cosf(ang) * 3.f, py + sinf(ang) * 3.f));
                        flame.setPoint(1, sf::Vector2f(px + cosf(ang + 0.3f) * 1.5f, py + sinf(ang + 0.3f) * 1.5f));
                        flame.setPoint(2, sf::Vector2f(px + cosf(ang) * (3.f + flameLen),
                                                         py + sinf(ang) * (3.f + flameLen)));
                        window.draw(flame);
                    }
                    // Nucleo centrale (sfera di fuoco)
                    sf::CircleShape fb(3.f);
                    fb.setFillColor(sf::Color(255, 160, 40));
                    fb.setOutlineThickness(0.6f);
                    fb.setOutlineColor(sf::Color(180, 60, 10));
                    fb.setPosition(px - 3.f, py - 3.f);
                    window.draw(fb);
                    // Nucleo giallo
                    sf::CircleShape fCore(1.5f);
                    fCore.setFillColor(sf::Color(255, 240, 150));
                    fCore.setPosition(px - 1.5f, py - 1.5f);
                    window.draw(fCore);
                    break;
                }
                case BP_WEBSHOT: {
                    // SPIDER: piccola ragnatela bianca a 8 raggi
                    sf::CircleShape wAura(5.f);
                    wAura.setFillColor(sf::Color(240, 240, 240, 100));
                    wAura.setPosition(px - 5.f, py - 5.f);
                    window.draw(wAura);
                    // 8 raggi della ragnatela
                    for (int i = 0; i < 8; i++) {
                        float a = i * (float)M_PI / 4.f;
                        sf::RectangleShape ray(sf::Vector2f(1.f, 5.f));
                        ray.setFillColor(sf::Color(220, 220, 220, 200));
                        ray.setOrigin(0.5f, 0.f);
                        ray.setPosition(px, py);
                        ray.rotate(a * 180.f / (float)M_PI);
                        window.draw(ray);
                    }
                    // Centro
                    sf::CircleShape wCenter(1.5f);
                    wCenter.setFillColor(sf::Color(255, 255, 255));
                    wCenter.setPosition(px - 1.5f, py - 1.5f);
                    window.draw(wCenter);
                    break;
                }
                case BP_FLESH_CHUNK: {
                    // ABOMINATION: brandello di carne rossa irregolare
                    sf::CircleShape flesh(5.f, 6);  // 6 segmenti = forma irregolare
                    flesh.setFillColor(sf::Color(150, 60, 60));
                    flesh.setOutlineThickness(0.8f);
                    flesh.setOutlineColor(sf::Color(80, 30, 30));
                    flesh.setPosition(px - 5.f, py - 5.f);
                    window.draw(flesh);
                    // Macchie più scure
                    sf::CircleShape spot1(1.5f);
                    spot1.setFillColor(sf::Color(80, 30, 30));
                    spot1.setPosition(px - 2.f, py - 1.f);
                    window.draw(spot1);
                    spot1.setPosition(px + 1.f, py + 1.f);
                    window.draw(spot1);
                    break;
                }
                case BP_INK_SPRAY: {
                    // KRAKEN: catena di gocce d'inchiostro viola
                    // (non piu' un pallino, ma una sequenza di 3 gocce)
                    // Aura
                    sf::CircleShape inkAura(7.f);
                    inkAura.setFillColor(sf::Color(80, 30, 110, 70));
                    inkAura.setPosition(px - 7.f, py - 7.f);
                    window.draw(inkAura);
                    // Calcola angolo di volo per allineare la catena
                    float inkAng = atan2(p.dir.y, p.dir.x) * 180.f / (float)M_PI;
                    // 3 gocce di inchiostro disposte lungo la direzione di volo
                    for (int i = 0; i < 3; i++) {
                        float t = (i - 1.f) * 3.f;  // offset lungo la direzione
                        float dx = cosf(inkAng * (float)M_PI / 180.f) * t;
                        float dy = sinf(inkAng * (float)M_PI / 180.f) * t;
                        sf::CircleShape drop(2.5f - i * 0.4f);
                        drop.setFillColor(sf::Color(60, 20, 80));
                        drop.setOutlineThickness(0.5f);
                        drop.setOutlineColor(sf::Color(20, 5, 30));
                        drop.setPosition(px + dx - 2.5f + i * 0.4f, py + dy - 2.5f + i * 0.4f);
                        window.draw(drop);
                    }
                    // Goccia centrale più chiara
                    sf::CircleShape inkCore(1.5f);
                    inkCore.setFillColor(sf::Color(120, 60, 150));
                    inkCore.setPosition(px - 1.5f, py - 1.5f);
                    window.draw(inkCore);
                    break;
                }
                case BP_DRAGON_BREATH: {
                    // DRAGON: cono di fuoco (non piu' un pallino, ma un piccolo
                    // soffio conico rivolto nella direzione di volo)
                    float pulse = sinf(p.age * 0.025f) * 0.5f;
                    sf::CircleShape bAura(6.f + pulse);
                    bAura.setFillColor(sf::Color(255, 200, 80, 100));
                    bAura.setPosition(px - 6.f - pulse, py - 6.f - pulse);
                    window.draw(bAura);
                    // Cono: ConvexShape triangolare allungato nella direzione di volo
                    float bAng = atan2(p.dir.y, p.dir.x) * 180.f / (float)M_PI;
                    float perpX = -sinf(bAng * (float)M_PI / 180.f);
                    float perpY = cosf(bAng * (float)M_PI / 180.f);
                    sf::ConvexShape cone; cone.setPointCount(3);
                    cone.setFillColor(sf::Color(255, 180, 60));
                    cone.setOutlineThickness(0.5f);
                    cone.setOutlineColor(sf::Color(200, 80, 20));
                    // Punta in avanti, base larga dietro
                    cone.setPoint(0, sf::Vector2f(px + cosf(bAng * (float)M_PI / 180.f) * 5.f,
                                                   py + sinf(bAng * (float)M_PI / 180.f) * 5.f));
                    cone.setPoint(1, sf::Vector2f(px - cosf(bAng * (float)M_PI / 180.f) * 2.f + perpX * 3.f,
                                                   py - sinf(bAng * (float)M_PI / 180.f) * 2.f + perpY * 3.f));
                    cone.setPoint(2, sf::Vector2f(px - cosf(bAng * (float)M_PI / 180.f) * 2.f - perpX * 3.f,
                                                   py - sinf(bAng * (float)M_PI / 180.f) * 2.f - perpY * 3.f));
                    window.draw(cone);
                    // Nucleo giallo centrale
                    sf::CircleShape core(1.5f);
                    core.setFillColor(sf::Color(255, 240, 150));
                    core.setPosition(px - 1.5f, py - 1.5f);
                    window.draw(core);
                    break;
                }
                case BP_GHOST_BOLT: {
                    // WRAITH_LORD: piccolo fantasma svolazzante ciano
                    // (non piu' un pallino, ma un fantasma con testa + corpo ondulato)
                    sf::CircleShape gAura(8.f);
                    gAura.setFillColor(sf::Color(120, 220, 255, 70));
                    gAura.setPosition(px - 8.f, py - 8.f);
                    window.draw(gAura);
                    // Testa del fantasma (semicerchio)
                    sf::CircleShape head(3.f, 8);  // 8 segmenti
                    head.setFillColor(sf::Color(180, 240, 255, 220));
                    head.setOutlineThickness(0.5f);
                    head.setOutlineColor(sf::Color(60, 120, 180));
                    head.setPosition(px - 3.f, py - 4.f);
                    window.draw(head);
                    // Corpo: rettangolo con bordo inferiore ondulato (3 punte)
                    sf::ConvexShape body; body.setPointCount(6);
                    body.setFillColor(sf::Color(180, 240, 255, 200));
                    body.setOutlineThickness(0.5f);
                    body.setOutlineColor(sf::Color(60, 120, 180));
                    body.setPoint(0, sf::Vector2f(px - 3.f, py - 1.f));
                    body.setPoint(1, sf::Vector2f(px + 3.f, py - 1.f));
                    body.setPoint(2, sf::Vector2f(px + 3.f, py + 4.f));
                    body.setPoint(3, sf::Vector2f(px + 1.f, py + 6.f));
                    body.setPoint(4, sf::Vector2f(px,     py + 4.f));
                    body.setPoint(5, sf::Vector2f(px - 1.f, py + 6.f));
                    // Nota: il 6° punto chiude tornando al 1° (px-3, py-1)
                    // Inseriamo l'ultimo punto inferiore sx
                    body.setPoint(5, sf::Vector2f(px - 3.f, py + 4.f));
                    window.draw(body);
                    // Occhi neri
                    sf::CircleShape eye(0.6f);
                    eye.setFillColor(sf::Color(20, 20, 40));
                    eye.setPosition(px - 1.6f, py - 2.f);
                    window.draw(eye);
                    eye.setPosition(px + 0.6f, py - 2.f);
                    window.draw(eye);
                    break;
                }
                case BP_BLOOD_BOLT: {
                    // VAMPIRE: freccia/dardo di sangue appuntito
                    // (non piu' un pallino, ma una freccia ruotata nella direzione di volo)
                    sf::CircleShape bAura(7.f);
                    bAura.setFillColor(sf::Color(180, 20, 30, 80));
                    bAura.setPosition(px - 7.f, py - 7.f);
                    window.draw(bAura);
                    // Calcola angolo di volo
                    float bAng = atan2(p.dir.y, p.dir.x) * 180.f / (float)M_PI;
                    // Asta della freccia (rettangolo allungato)
                    sf::RectangleShape shaft(sf::Vector2f(8.f, 1.5f));
                    shaft.setFillColor(sf::Color(180, 30, 40));
                    shaft.setOutlineThickness(0.4f);
                    shaft.setOutlineColor(sf::Color(100, 10, 20));
                    shaft.setOrigin(2.f, 0.75f);  // origine verso la coda
                    shaft.setPosition(px, py);
                    shaft.rotate(bAng);
                    window.draw(shaft);
                    // Punta della freccia (triangolo)
                    sf::ConvexShape head; head.setPointCount(3);
                    head.setFillColor(sf::Color(220, 50, 60));
                    head.setOutlineThickness(0.4f);
                    head.setOutlineColor(sf::Color(100, 10, 20));
                    // Punta davanti all'asta
                    float hx = px + cosf(bAng * (float)M_PI / 180.f) * 4.f;
                    float hy = py + sinf(bAng * (float)M_PI / 180.f) * 4.f;
                    float perpX = -sinf(bAng * (float)M_PI / 180.f);
                    float perpY = cosf(bAng * (float)M_PI / 180.f);
                    head.setPoint(0, sf::Vector2f(hx, hy));  // punta
                    head.setPoint(1, sf::Vector2f(hx - cosf(bAng * (float)M_PI / 180.f) * 3.f + perpX * 2.f,
                                                  hy - sinf(bAng * (float)M_PI / 180.f) * 3.f + perpY * 2.f));
                    head.setPoint(2, sf::Vector2f(hx - cosf(bAng * (float)M_PI / 180.f) * 3.f - perpX * 2.f,
                                                  hy - sinf(bAng * (float)M_PI / 180.f) * 3.f - perpY * 2.f));
                    window.draw(head);
                    // Piume della coda (2 piccoli triangoli)
                    for (int side = 0; side < 2; side++) {
                        float s = (side == 0) ? 1.f : -1.f;
                        sf::ConvexShape fletch; fletch.setPointCount(3);
                        fletch.setFillColor(sf::Color(140, 20, 30));
                        float tx = px - cosf(bAng * (float)M_PI / 180.f) * 3.f;
                        float ty = py - sinf(bAng * (float)M_PI / 180.f) * 3.f;
                        fletch.setPoint(0, sf::Vector2f(tx, ty));
                        fletch.setPoint(1, sf::Vector2f(tx - cosf(bAng * (float)M_PI / 180.f) * 2.f + perpX * s * 2.f,
                                                        ty - sinf(bAng * (float)M_PI / 180.f) * 2.f + perpY * s * 2.f));
                        fletch.setPoint(2, sf::Vector2f(tx - cosf(bAng * (float)M_PI / 180.f) * 4.f,
                                                        ty - sinf(bAng * (float)M_PI / 180.f) * 4.f));
                        window.draw(fletch);
                    }
                    break;
                }
                case BP_EYE_RAY: {
                    // BEHOLDER: raggio energetico colorato (variant 0..4)
                    sf::Color rayColors[5] = {
                        sf::Color(255, 80, 80),    // rosso
                        sf::Color(80, 255, 80),    // verde
                        sf::Color(80, 180, 255),  // blu
                        sf::Color(255, 200, 80),  // giallo
                        sf::Color(220, 80, 255)   // viola (potente)
                    };
                    sf::Color rayCol = rayColors[p.variant % 5];
                    sf::CircleShape rAura(6.f);
                    rAura.setFillColor(sf::Color(rayCol.r, rayCol.g, rayCol.b, 80));
                    rAura.setPosition(px - 6.f, py - 6.f);
                    window.draw(rAura);
                    sf::CircleShape ray(3.5f);
                    ray.setFillColor(rayCol);
                    ray.setOutlineThickness(0.8f);
                    ray.setOutlineColor(sf::Color(rayCol.r / 3, rayCol.g / 3, rayCol.b / 3));
                    ray.setPosition(px - 3.5f, py - 3.5f);
                    window.draw(ray);
                    // Nucleo bianco
                    sf::CircleShape rayCore(1.2f);
                    rayCore.setFillColor(sf::Color(255, 255, 255));
                    rayCore.setPosition(px - 1.2f, py - 1.2f);
                    window.draw(rayCore);
                    break;
                }
                case BP_GHOUL_CLAW: {
                    // GHOUL_LORD: artiglio osseo a 3 punte
                    sf::ConvexShape claw; claw.setPointCount(3);
                    claw.setFillColor(sf::Color(220, 210, 180));
                    claw.setOutlineThickness(0.8f);
                    claw.setOutlineColor(sf::Color(100, 90, 70));
                    claw.setPoint(0, sf::Vector2f(px - 4.f, py + 3.f));
                    claw.setPoint(1, sf::Vector2f(px + 4.f, py + 3.f));
                    claw.setPoint(2, sf::Vector2f(px, py - 5.f));
                    window.draw(claw);
                    break;
                }
                case BP_SPECTRAL_FANG: {
                    // SPECTRAL_ALPHA: zanna spettrale ciano-bianca
                    sf::CircleShape fAura(5.f);
                    fAura.setFillColor(sf::Color(180, 230, 255, 80));
                    fAura.setPosition(px - 5.f, py - 5.f);
                    window.draw(fAura);
                    sf::ConvexShape fang; fang.setPointCount(3);
                    fang.setFillColor(sf::Color(220, 250, 255));
                    fang.setOutlineThickness(0.5f);
                    fang.setOutlineColor(sf::Color(120, 180, 200));
                    fang.setPoint(0, sf::Vector2f(px - 3.f, py + 2.f));
                    fang.setPoint(1, sf::Vector2f(px + 3.f, py + 2.f));
                    fang.setPoint(2, sf::Vector2f(px, py - 5.f));
                    window.draw(fang);
                    break;
                }
                case BP_CULT_ORB: {
                    // CULT_HERALD: libro magico volante con pagine
                    // (non piu' un pallino, ma un piccolo tomo aperto)
                    float pulse = sinf(p.age * 0.02f) * 0.6f;
                    sf::CircleShape oAura(7.f + pulse);
                    oAura.setFillColor(sf::Color(180, 60, 220, 70));
                    oAura.setPosition(px - 7.f - pulse, py - 7.f - pulse);
                    window.draw(oAura);
                    // Copertina del libro (rettangolo viola scuro)
                    sf::RectangleShape book(sf::Vector2f(8.f, 6.f));
                    book.setFillColor(sf::Color(100, 40, 130));
                    book.setOutlineThickness(0.6f);
                    book.setOutlineColor(sf::Color(50, 20, 70));
                    book.setOrigin(4.f, 3.f);
                    book.setPosition(px, py);
                    // Ruota leggermente il libro (effetto "fluttuante")
                    book.rotate(sinf(p.age * 0.015f) * 15.f);
                    window.draw(book);
                    // Pagine (striscia chiara centrale)
                    sf::RectangleShape pages(sf::Vector2f(6.f, 4.f));
                    pages.setFillColor(sf::Color(240, 220, 240));
                    pages.setOrigin(3.f, 2.f);
                    pages.setPosition(px, py);
                    pages.rotate(sinf(p.age * 0.015f) * 15.f);
                    window.draw(pages);
                    // Simbolo magico sul libro (punto dorato)
                    sf::CircleShape sym(1.f);
                    sym.setFillColor(sf::Color(255, 215, 0));
                    sym.setPosition(px - 1.f, py - 1.f);
                    window.draw(sym);
                    // Linea di rilegatura
                    sf::RectangleShape spine(sf::Vector2f(0.5f, 6.f));
                    spine.setFillColor(sf::Color(60, 25, 80));
                    spine.setOrigin(0.25f, 3.f);
                    spine.setPosition(px, py);
                    spine.rotate(sinf(p.age * 0.015f) * 15.f);
                    window.draw(spine);
                    break;
                }
                case BP_MIMIC_GOO: {
                    // COLOSSAL_MIMIC: bava verde-gialla appiccicosa
                    sf::CircleShape goo(4.f, 6);  // forma irregolare
                    goo.setFillColor(sf::Color(150, 200, 60));
                    goo.setOutlineThickness(0.8f);
                    goo.setOutlineColor(sf::Color(80, 110, 30));
                    goo.setPosition(px - 4.f, py - 4.f);
                    window.draw(goo);
                    // Bolla
                    sf::CircleShape bubble(1.5f);
                    bubble.setFillColor(sf::Color(200, 240, 120));
                    bubble.setPosition(px - 1.f, py - 2.f);
                    window.draw(bubble);
                    break;
                }
                case BP_RAT_SWARM: {
                    // RAT_KING: piccolo ratto grigio-marrone
                    sf::CircleShape ratBody(3.f);
                    ratBody.setFillColor(sf::Color(90, 75, 60));
                    ratBody.setOutlineThickness(0.5f);
                    ratBody.setOutlineColor(sf::Color(40, 30, 20));
                    ratBody.setPosition(px - 3.f, py - 3.f);
                    window.draw(ratBody);
                    // Occhio rosso
                    sf::CircleShape ratEye(0.6f);
                    ratEye.setFillColor(sf::Color(255, 60, 60));
                    ratEye.setPosition(px + 0.5f, py - 1.f);
                    window.draw(ratEye);
                    // Coda
                    sf::RectangleShape tail(sf::Vector2f(4.f, 0.8f));
                    tail.setFillColor(sf::Color(80, 65, 50));
                    tail.setPosition(px - 4.f, py);
                    window.draw(tail);
                    break;
                }
                case BP_WITCH_HEX: {
                    // SUPREME_WITCH: piccolo calderone ribollente viola
                    // (non piu' un pallino, ma un calderone con bolle animate)
                    float pulse = sinf(p.age * 0.018f) * 0.7f;
                    // Aura estesa se homing (chiazza più grande)
                    float auraR = (p.homingTimer > 0) ? 10.f : 7.f;
                    sf::CircleShape hAura(auraR + pulse);
                    hAura.setFillColor(sf::Color(180, 60, 240, 90));
                    hAura.setPosition(px - auraR - pulse, py - auraR - pulse);
                    window.draw(hAura);
                    // Corpo del calderone (ConvexShape trapezoidale: largo in alto, stretto in basso)
                    sf::ConvexShape cauldron; cauldron.setPointCount(4);
                    cauldron.setFillColor(sf::Color(60, 30, 80));
                    cauldron.setOutlineThickness(0.8f);
                    cauldron.setOutlineColor(sf::Color(30, 15, 40));
                    cauldron.setPoint(0, sf::Vector2f(px - 5.f, py - 2.f));
                    cauldron.setPoint(1, sf::Vector2f(px + 5.f, py - 2.f));
                    cauldron.setPoint(2, sf::Vector2f(px + 3.f, py + 5.f));
                    cauldron.setPoint(3, sf::Vector2f(px - 3.f, py + 5.f));
                    window.draw(cauldron);
                    // Bordo superiore del calderone (cerniera)
                    sf::RectangleShape rim(sf::Vector2f(11.f, 1.5f));
                    rim.setFillColor(sf::Color(40, 20, 60));
                    rim.setPosition(px - 5.5f, py - 3.f);
                    window.draw(rim);
                    // Contenuto ribollente (palline viola animate)
                    for (int i = 0; i < 3; i++) {
                        float bubbleX = px - 3.f + i * 3.f;
                        float bubbleY = py - 3.f + sinf(p.age * 0.03f + i * 1.5f) * 1.f;
                        sf::CircleShape bubble(1.f + (i % 2) * 0.4f);
                        bubble.setFillColor(sf::Color(200, 80, 230));
                        bubble.setOutlineThickness(0.3f);
                        bubble.setOutlineColor(sf::Color(100, 30, 130));
                        bubble.setPosition(bubbleX - 1.f, bubbleY);
                        window.draw(bubble);
                    }
                    // Simbolo runico centrale sul calderone (piccolo rombo)
                    sf::ConvexShape rune; rune.setPointCount(4);
                    rune.setFillColor(sf::Color(255, 200, 255));
                    rune.setPoint(0, sf::Vector2f(px, py + 1.f));
                    rune.setPoint(1, sf::Vector2f(px + 1.5f, py + 2.5f));
                    rune.setPoint(2, sf::Vector2f(px, py + 4.f));
                    rune.setPoint(3, sf::Vector2f(px - 1.5f, py + 2.5f));
                    window.draw(rune);
                    break;
                }
                case BP_TWILIGHT_BLADE: {
                    // TWILIGHT_KNIGHT: lama d'ombra viola scura
                    sf::RectangleShape blade(sf::Vector2f(2.f, 8.f));
                    blade.setFillColor(sf::Color(80, 30, 120));
                    blade.setOutlineThickness(0.5f);
                    blade.setOutlineColor(sf::Color(40, 15, 60));
                    blade.setOrigin(1.f, 4.f);
                    blade.setPosition(px, py);
                    // Ruota nella direzione di volo
                    float ang = atan2(p.dir.y, p.dir.x) * 180.f / (float)M_PI + 90.f;
                    blade.rotate(ang);
                    window.draw(blade);
                    // Aura
                    sf::CircleShape tAura(5.f);
                    tAura.setFillColor(sf::Color(120, 60, 180, 70));
                    tAura.setPosition(px - 5.f, py - 5.f);
                    window.draw(tAura);
                    break;
                }
                case BP_NORMAL:
                default: {
                    // Fallback: proiettile rosso standard (vecchio render)
                    sf::CircleShape proj(4.f);
                    proj.setFillColor(sf::Color(255, 60, 40));
                    proj.setOutlineThickness(1.f);
                    proj.setOutlineColor(sf::Color(120, 20, 0));
                    proj.setPosition(px - 4.f, py - 4.f);
                    window.draw(proj);
                    break;
                }
            }
        }

        // --- Rendering scettro magico nella stanza del boss (stile Gandalf) ---
        if (scepter.active && !scepter.triggered) {
            float sx = scepter.pos.x;
            float sy = scepter.pos.y + scepter.bobOffset;
            float sPulse = sinf(scepter.pulse * 4.f) * 0.15f + 1.f;
            drawMagicScepter(window, sx, sy, sPulse);
        }

        // --- Rendering fulmini nella stanza del boss (effetto traversante) ---
        for (const auto& lt : lightnings) {
            drawLightning(window, lt);
        }

        // --- Rendering mina nella stanza del boss ---
        if (mine.active) {
            float mx = mine.pos.x;
            float my = mine.pos.y;
            float mPulse = sinf(mine.pulse * 5.f) * 0.2f + 1.f;
            float auraR = 18.f * mPulse;
            sf::CircleShape mineAura(auraR);
            mineAura.setFillColor(sf::Color(200, 50, 20, 50));
            mineAura.setPosition(mx - auraR, my - auraR);
            window.draw(mineAura);
            float bodyR = 7.f * mPulse;
            sf::CircleShape mineBody(bodyR);
            mineBody.setFillColor(sf::Color(80, 70, 60));
            mineBody.setOutlineThickness(1.5f);
            mineBody.setOutlineColor(sf::Color(30, 25, 20));
            mineBody.setPosition(mx - bodyR, my - bodyR);
            window.draw(mineBody);
            for (int i = 0; i < 4; i++) {
                float a = mine.rotation + i * (float)M_PI / 2.f;
                float spikeLen = 5.f;
                sf::ConvexShape spike;
                spike.setPointCount(3);
                spike.setFillColor(sf::Color(100, 85, 70));
                spike.setOutlineThickness(0.5f);
                spike.setOutlineColor(sf::Color(30, 25, 20));
                float tipX = mx + cosf(a) * (bodyR + spikeLen);
                float tipY = my + sinf(a) * (bodyR + spikeLen);
                float perpX = -sinf(a) * 3.f;
                float perpY = cosf(a) * 3.f;
                float baseX = mx + cosf(a) * bodyR;
                float baseY = my + sinf(a) * bodyR;
                spike.setPoint(0, sf::Vector2f(tipX, tipY));
                spike.setPoint(1, sf::Vector2f(baseX + perpX, baseY + perpY));
                spike.setPoint(2, sf::Vector2f(baseX - perpX, baseY - perpY));
                window.draw(spike);
            }
            float ledR = 2.f * mPulse;
            sf::CircleShape led(ledR);
            led.setFillColor(sf::Color(255, 50 + (sf::Uint8)(sinf(mine.pulse * 8.f) * 50), 30, 240));
            led.setPosition(mx - ledR, my - ledR);
            window.draw(led);
            if (mine.bouncing) {
                sf::CircleShape trail(3.f);
                trail.setFillColor(sf::Color(255, 150, 50, 100));
                trail.setPosition(mx - mine.vel.x - 3.f, my - mine.vel.y - 3.f);
                window.draw(trail);
            }
        }

        // --- Rendering aura FUOCO player1 nella stanza boss ---
        if (playerInvincibleTimer > 0) {
            drawFireAura(window, player.getPixelPos(), playerInvincibleTimer);
        }
        // --- Rendering aura FUOCO player2 nella stanza boss ---
        if (numPlayers == 2 && player2InvincibleTimer > 0) {
            drawFireAura(window, player2.getPixelPos(), player2InvincibleTimer);
        }

        // Etichetta del livello boss in alto
        drawTextCenteredOutlined(window, "BOSS LEVEL " + std::to_string(currentLevel), WINDOW_WIDTH/2, 100, 3, sf::Color::Red);
    }
    else if (state == STATE_WIN_STORY) {
        // Sfondo scuro + fuochi d'artificio + messaggi di vittoria
        sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        bg.setFillColor(sf::Color(10, 10, 30));
        window.draw(bg);

        // Fuochi d'artificio con alpha proporzionale alla vita
        for (const auto& fw : fireworks) {
            sf::CircleShape c(6.f);
            c.setFillColor(sf::Color(fw.color.r, fw.color.g, fw.color.b, 255 * fw.life / 60));
            c.setPosition(fw.pos.x - 6.f, fw.pos.y - 6.f);
            window.draw(c);
        }

        // Messaggi di vittoria
        drawTextCenteredOutlined(window, "CONGRATULATIONS!", WINDOW_WIDTH/2, 200, 5, sf::Color::Green);
        drawTextCenteredOutlined(window, "YOU FINISHED THE STORY MODE", WINDOW_WIDTH/2, 300, 3, sf::Color::Yellow);
        drawTextCenteredOutlined(window, "COMPLIMENTI PER LA TENACIA", WINDOW_WIDTH/2, 500, 3, sf::Color::White);
        drawTextCenteredOutlined(window, "E GRAZIE PER AVER GIOCATO!", WINDOW_WIDTH/2, 580, 3, sf::Color::White);
        drawTextCenteredOutlined(window, "PRESS ENTER", WINDOW_WIDTH/2, 800, 2, sf::Color::Red);
    }

    // --- Overlay flash bianco (effetto lampo fulmine) ---
    // Quando un fulmine appare, screenFlashTimer viene impostato a 120ms.
    // Decrementa ad ogni render (~16ms) e disegna un rettangolo bianco
    // semi-trasparente su TUTTO lo schermo con alpha proporzionale al
    // tempo residuo. Vale per STATE_PLAYING e STATE_BOSS.
    //
    // NOTA: il flash e' stato reso MOLTO PIU' SOTTILE per non affaticare
    // gli occhi (l'utente aveva segnalato fastidio). Durata ridotta da
    // 250ms a 120ms e alpha massimo ridotto da 180 a 80. Il fulmine resta
    // visibile grazie al suo glow e alle scintille, non serve un flash
    // bianco cosi' intenso.
    if (screenFlashTimer > 0) {
        if (screenFlashTimer > 16) screenFlashTimer -= 16;
        else screenFlashTimer = 0;
        // Alpha: parte da 80 (era 180) e scende a 0 in 120ms (era 250ms)
        float ratio = (float)screenFlashTimer / 120.f;
        sf::Uint8 flashAlpha = (sf::Uint8)(80.f * ratio);
        sf::RectangleShape flashOverlay(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        flashOverlay.setFillColor(sf::Color(255, 255, 255, flashAlpha));
        flashOverlay.setPosition(0.f, 0.f);
        window.draw(flashOverlay);
    }

    window.display();
}

// ---------------------------------------------------------------------------
// run: ciclo principale. Resta in esecuzione finche' isRunning e' true.
// L'ordine e' fisso: events -> update -> render. A 60 FPS ogni iterazione
// dura ~16 ms.
// ---------------------------------------------------------------------------
void Game::run() {
    while (isRunning) {
        handleEvents();
        update();
        render();
    }
}
