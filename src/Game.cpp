#include "Game.h"
#include <iostream>
#include <cstdlib>
#include <algorithm>
#include <cmath>

// ===========================================================================
// Game.cpp - Implementazione del ciclo di gioco centrale.
//
// Flusso di una partita tipica:
//   1. Menu: scelta modalita'/risoluzione/musica, configurazione joystick,
//      avvio partita.
//   2. Per ogni livello (1..10):
//      a. STATE_PLAYING: esplorazione labirinto, raccolta tesori, scontro
//         con i nemici. Quando `maze.getRemainingTreasures()==0` si passa
//         al boss.
//      b. STATE_BOSS: scontro nella stanza del boss. Quando il boss muore
//         si guadagna una vita e si passa al livello successivo; al livello
//         11 in modalita' story si vince.
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
// currentLevel, displayModes, selectedModeIndex, menuItemIndex, musicEnabled,
// lightningTimer, configJoyStep.
// Qui inizializziamo solo i membri non di default; gli altri (vettori, maze,
// player) sono costruiti di default.
// ---------------------------------------------------------------------------
Game::Game() : window(sf::VideoMode::getDesktopMode(), "Arcade Maze Fantasy", sf::Style::Fullscreen), numPlayers(1), boss(nullptr), state(STATE_MENU), gameMode(MODE_STORY), isRunning(true), currentLevel(1), selectedModeIndex(0), menuItemIndex(0), musicEnabled(false), lightningTimer(0), configJoyStep(0), continuesLeft(3), continuesTimer(10), continuesTimerMs(0), continuesChoice(true), diedInBoss(false) {
    displayModes = sf::VideoMode::getFullscreenModes();
    selectedModeIndex = 0;
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
    // Carica gli sprite dei giocatori (player1 e player2 distinti).
    // Carichiamo sempre entrambi: se il file non esiste resta unloaded e il
    // render fa fallback alle primitive. numPlayers verra' scelto dopo nel menu.
    player.loadSprite("assets/sprites/player1");
    player2.loadSprite("assets/sprites/player2");
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
    maze.generate();
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
// startBossFight: transizione alla stanza del boss.
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
        // Continua la fight esistente: il boss resta invariato.
        // (nessuna ricreazione, nessun reset HP)
    } else {
        // Creazione boss nuova o reset completo.
        if (boss) delete boss;
        boss = new Boss(currentLevel, WINDOW_WIDTH, WINDOW_HEIGHT);
    }
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
    // Spawn bonus scarpe alate: posizionato a sinistra della stanza
    speedBoots.active = true;
    speedBoots.pos = sf::Vector2f(150.0f, 200.0f);
    speedBoots.bobOffset = 0.f;
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
                else { state = STATE_MENU; currentLevel = 1; }
            }

            // Navigazione menu'
            if (state == STATE_MENU) {
                // Su/Giu: cambio voce selezionata (6 voci totali, wrap con +6 %6)
                if (key == sf::Keyboard::Up) { menuItemIndex = (menuItemIndex - 1 + 6) % 6; audio.playSound(SOUND_MENU_SELECT); }
                else if (key == sf::Keyboard::Down) { menuItemIndex = (menuItemIndex + 1) % 6; audio.playSound(SOUND_MENU_SELECT); }
                // Sinistra/Destra: modifica dell'opzione selezionata
                else if (key == sf::Keyboard::Left) {
                    if (menuItemIndex == 0) numPlayers = (numPlayers == 1) ? 2 : 1;
                    if (menuItemIndex == 1) gameMode = (gameMode == MODE_STORY) ? MODE_INFINITE : MODE_STORY;
                    if (menuItemIndex == 2) selectedModeIndex = (selectedModeIndex - 1 + displayModes.size()) % displayModes.size();
                    if (menuItemIndex == 3) { musicEnabled = !musicEnabled; if(musicEnabled) audio.playLevelMusic(1, false); else audio.stopMusic(); }
                }
                else if (key == sf::Keyboard::Right) {
                    if (menuItemIndex == 0) numPlayers = (numPlayers == 1) ? 2 : 1;
                    if (menuItemIndex == 1) gameMode = (gameMode == MODE_STORY) ? MODE_INFINITE : MODE_STORY;
                    if (menuItemIndex == 2) selectedModeIndex = (selectedModeIndex + 1) % displayModes.size();
                    if (menuItemIndex == 3) { musicEnabled = !musicEnabled; if(musicEnabled) audio.playLevelMusic(1, false); else audio.stopMusic(); }
                }
                // Return: conferma (voci 4 = config joystick, 5 = avvia partita)
                else if (key == sf::Keyboard::Return) {
                    audio.playSound(SOUND_MENU_CONFIRM);
                    if (menuItemIndex == 4) { state = STATE_CONFIG_JOY; configJoyStep = 0; }
                    else if (menuItemIndex == 5) {
                        // Applica la risoluzione selezionata e avvia il livello 1
                        sf::VideoMode mode = displayModes[selectedModeIndex];
                        window.create(mode, "Arcade Maze Fantasy", sf::Style::Fullscreen);
                        window.setFramerateLimit(60);
                        sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
                        window.setView(view);
                        currentLevel = 1;
                        startLevel(1);
                    }
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
                }
            }
        }
        else if (event.type == sf::Event::JoystickButtonPressed) {
            // Supporto joystick: riproduce la stessa logica del menu' da tastiera.
            // Pulsante "jump" del joystick e' usato come "conferma" perche' e'
            // quello piu' intuitivo (es. pulsante A di un pad Xbox).
            if (state == STATE_MENU) {
                // Cast a unsigned: event.joystickButton.button e' unsigned int,
                // config.joy_jump e' int (perche' letto da file INI come intero).
                if (event.joystickButton.joystickId == 0 && event.joystickButton.button == (unsigned)config.joy_jump) {
                    audio.playSound(SOUND_MENU_CONFIRM);
                    if (menuItemIndex == 4) { state = STATE_CONFIG_JOY; configJoyStep = 0; }
                    else if (menuItemIndex == 5) {
                        sf::VideoMode mode = displayModes[selectedModeIndex];
                        window.create(mode, "Arcade Maze Fantasy", sf::Style::Fullscreen);
                        window.setFramerateLimit(60);
                        sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
                        window.setView(view);
                        currentLevel = 1;
                        startLevel(1);
                    }
                }
            } else if (state == STATE_CONFIG_JOY) {
                // Configurazione joystick a 2 step:
                //   step 0: cattura pulsante per salto
                //   step 1: cattura pulsante per sparo, poi torna al menu'
                if (event.joystickButton.joystickId == 0) {
                    if (configJoyStep == 0) { config.joy_jump = event.joystickButton.button; configJoyStep = 1; }
                    else if (configJoyStep == 1) { config.joy_shoot = event.joystickButton.button; 
                        if (numPlayers == 2) state = STATE_CONFIG_JOY_2; 
                        else state = STATE_MENU; 
                    }
                }
            } else if (state == STATE_CONFIG_JOY_2) {
                // Configurazione joystick secondo giocatore (joystick 1).
                // Usa i campi joy2_* dedicati: NON tocca config.joy_jump/joy_shoot
                // del giocatore 1 (bug critico della versione precedente).
                if (event.joystickButton.joystickId == 1) {
                    if (configJoyStep == 0) { config.joy2_jump = event.joystickButton.button; configJoyStep = 1; }
                    else if (configJoyStep == 1) { config.joy2_shoot = event.joystickButton.button; state = STATE_MENU; }
                }
            } else if (state == STATE_CONTINUES) {
                // Joystick: pulsante jump = conferma, pulsante shoot = toggle
                if (event.joystickButton.joystickId == 0) {
                    if (event.joystickButton.button == (unsigned)config.joy_jump) {
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
                    } else if (event.joystickButton.button == (unsigned)config.joy_shoot) {
                        continuesChoice = !continuesChoice;
                        audio.playSound(SOUND_MENU_SELECT);
                    }
                }
            } else if (state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) {
                if (event.joystickButton.joystickId == 0 && event.joystickButton.button == (unsigned)config.joy_jump) {
                    state = STATE_MENU;
                    currentLevel = 1;
                    continuesLeft = 3;
                }
            }
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
    sf::Joystick::update();

    // --- Stato MENU: navigazione joystick + fulmini casuali ---
    if (state == STATE_MENU) {
        if (sf::Joystick::isConnected(0)) {
            float y = sf::Joystick::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_y);
            // joyMoved e' static: serve da "debounce" per evitare che un
            // solo movimento dell'analogico faccia scorrere tutte le voci.
            static bool joyMoved = false;
            if (fabs(y) > 50 && !joyMoved) {
                joyMoved = true;
                if (y < 0) { menuItemIndex = (menuItemIndex - 1 + 6) % 6; audio.playSound(SOUND_MENU_SELECT); }
                else { menuItemIndex = (menuItemIndex + 1) % 6; audio.playSound(SOUND_MENU_SELECT); }
            } else if (fabs(y) < 20) joyMoved = false;  // isteresi per il ritorno
        }

        // Fulmine casuale: ~5/600 di probabilita' per frame, durata 10 frame
        if (rand() % 600 < 5) lightningTimer = 10;
        if (lightningTimer > 0) lightningTimer--;
    }

    // --- Input giocatore (sia STATE_PLAYING che STATE_BOSS) ---
    if (state == STATE_PLAYING || state == STATE_BOSS) {
        // Tastiera: direzioni (mutuamente esclusive con else-if)
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_up))    { player.setDirection(0, -1); }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_down))  { player.setDirection(0, 1);  }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_left))  { player.setDirection(-1, 0); }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_right)) { player.setDirection(1, 0);  }

        // Joystick: prevale sulla tastiera se fuori dalla deadzone (30%)
        if (sf::Joystick::isConnected(0)) {
            float x = sf::Joystick::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_x);
            float y = sf::Joystick::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_y);
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
            if (sf::Joystick::isButtonPressed(0, config.joy_shoot)) {
                if (player.getShootCooldown() == 0) {
                    int ammoBefore = player.getCurrentWeapon().ammo;
                    player.shoot();
                    // Suono solo se effettivamente sparato (munizioni calate)
                    if (player.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                    player.setShootCooldown(150);
                }
            }
            if (sf::Joystick::isButtonPressed(0, (unsigned)config.joy_jump)) {
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

        // Joystick 1 (configurabile da STATE_CONFIG_JOY_2). Prevale sulla
        // tastiera se fuori dalla deadzone (30%). Usa joy2_* / joy2_axis_*.
        if (sf::Joystick::isConnected(1)) {
            float x = sf::Joystick::getAxisPosition(1, (sf::Joystick::Axis)config.joy2_axis_x);
            float y = sf::Joystick::getAxisPosition(1, (sf::Joystick::Axis)config.joy2_axis_y);
            if (fabs(x) > 30 || fabs(y) > 30) {
                if (fabs(x) > fabs(y)) {
                    if (x > 30) { player2.setDirection(1, 0); }
                    else if (x < -30) { player2.setDirection(-1, 0); }
                } else {
                    if (y > 30) { player2.setDirection(0, 1); }
                    else if (y < -30) { player2.setDirection(0, -1); }
                }
            }
            // Sparo joystick: cooldown 150 ms (~9 frame)
            if (sf::Joystick::isButtonPressed(1, (unsigned)config.joy2_shoot)) {
                if (player2.getShootCooldown() == 0) {
                    int ammoBefore = player2.getCurrentWeapon().ammo;
                    player2.shoot();
                    if (player2.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player2.getCurrentWeapon().type));
                    player2.setShootCooldown(150);
                }
            }
            if (sf::Joystick::isButtonPressed(1, (unsigned)config.joy2_jump)) {
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
        if (numPlayers == 2) player2.update(maze, false, particles);
        if (maze.getRemainingTreasures() < treasuresBefore) audio.playSound(SOUND_TREASURE);

        // Aggiornamento nemici (passa pos giocatore per AI + sparo)
        sf::Vector2f pPos = player.getPixelPos();
        for (auto& enemy : enemies) {
            if (!enemy.isDeathAnimDone()) enemy.update(maze, player.getGridPos(), pPos, enemyProjectiles);
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
                        // Effetto particellare: sangue rosso (20 particelle)
                        for(int i=0; i<20; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%8-4), (float)(rand()%8-4)}, sf::Color(150, 0, 0), 40, 40});
                    }
                    break;  // un proiettile colpisce un solo nemico
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
                            player2.addScore(5000);  // Bonus per uccisione
                            audio.playSound(SOUND_ENEMY_DEATH);
                            for(int i=0; i<20; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%8-4), (float)(rand()%8-4)}, sf::Color(0, 150, 0), 40, 40});
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
        if (maze.getRemainingTreasures() == 0) startBossFight();
    }
    // --- Logica STATE_BOSS: stanza del boss ---
    else if (state == STATE_BOSS) {
        // freeMovement=true: il giocatore si muove liberamente (non snap-to-grid)
        player.update(maze, true, particles);
        if (numPlayers == 2) player2.update(maze, true, particles);
        boss->update(player.getPixelPos().x, player.getPixelPos().y, bossProjectiles);

        // --- Aggiornamento proiettili boss ---
        for (auto& proj : bossProjectiles) {
            if (!proj.active) continue;
            proj.pos += proj.dir; // Muove il proiettile/bomba
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
            if (dx*dx + dy*dy < 1000) { player.collectWeapon(it->w); it = bossRoomWeapons.erase(it); } else ++it;
        }

        // --- Raccolta bonus scarpe alate (speed boost) ---
        if (speedBoots.active) {
            static float bootsAnimTime = 0.f;
            bootsAnimTime += 16.f;
            speedBoots.bobOffset = sin(bootsAnimTime * 0.005f) * 5.f;  // fluttua
            float dx = speedBoots.pos.x - player.getPixelPos().x;
            float dy = speedBoots.pos.y - player.getPixelPos().y;
            if (dx*dx + dy*dy < 1000) {
                player.activateSpeedBoost();
                speedBoots.active = false;
                audio.playSound(SOUND_TREASURE);  // suono raccolta
            }
            if (numPlayers == 2) {
                float dx2 = speedBoots.pos.x - player2.getPixelPos().x;
                float dy2 = speedBoots.pos.y - player2.getPixelPos().y;
                if (dx2*dx2 + dy2*dy2 < 1000) {
                    player2.activateSpeedBoost();
                    speedBoots.active = false;
                    audio.playSound(SOUND_TREASURE);
                }
            }
        }

        // --- Raccolta armi player2 (solo se 2 giocatori) ---
        if (numPlayers == 2) {
            for (auto it = bossRoomWeapons.begin(); it != bossRoomWeapons.end(); ) {
                float dx = it->pos.x - player2.getPixelPos().x;
                float dy = it->pos.y - player2.getPixelPos().y;
                if (dx*dx + dy*dy < 1000) { player2.collectWeapon(it->w); it = bossRoomWeapons.erase(it); } else ++it;
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

        // Se entrambi i giocatori hanno finito le munizioni e non ci sono armi
        // a terra, ne spawniamo altre 3 (evita soft-lock: il boss diventerebbe
        // invincibile se nessuno puo' piu' attaccare).
        if (player.getCurrentWeapon().ammo <= 0
            && (numPlayers == 1 || player2.getCurrentWeapon().ammo <= 0)
            && bossRoomWeapons.empty()) {
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
        if (boss->isDead()) {
            audio.playSound(SOUND_BOSS_DEATH);
            player.addLife(); // Guadagni una vita dopo aver sconfitto il boss
            currentLevel++;

            // Modalita' story: vittoria dopo il livello 10 (boss del 10 morto)
            if (gameMode == MODE_STORY && currentLevel > 10) {
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
    float x = 100 + rand() % (WINDOW_WIDTH - 200);
    float y = 100 + rand() % (WINDOW_HEIGHT / 2);  // solo meta' alta dello schermo
    sf::Color colors[] = {sf::Color::Red, sf::Color::Green, sf::Color::Blue, sf::Color::Yellow, sf::Color::Magenta, sf::Color::Cyan};
    sf::Color col = colors[rand() % 6];
    for(int i=0; i<30; i++) {
        float angle = i * (M_PI * 2 / 30);  // 30 particelle uniformi su 360°
        fireworks.push_back({sf::Vector2f(x, y), sf::Vector2f(cos(angle)*4, sin(angle)*4), col, 60});
    }
}

// ---------------------------------------------------------------------------
// drawMenu: disegna il menu' principale (tema fantasy cavernoso).
//
// Elementi:
//   * Sfondo: gradiente notte (viola scuro -> nero in basso) + alone lunare
//   * 100 stelle generate con seed fisso (srand(42)) per non mutare ad
//     ogni frame; poi srand(time(NULL)) per ripristinare il random del gioco
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
        star.setPosition(rand()%WINDOW_WIDTH, rand()%(WINDOW_HEIGHT - 200));
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
    srand(time(NULL));

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
            float y = yBase + sin(menuTime * 0.5f + x * 0.01f + layer) * 15.f;
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
            float lx = WINDOW_WIDTH / 2.0f + (rand()%400 - 200);
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

    // --- Ornamenti fantasy ai lati del titolo: torce con fiamma animata ---
    // Posizionate a meta' altezza del titolo, ai lati esterni.
    auto drawTorch = [&](float x, float yBase) {
        // Bastone della torcia (legno scuro)
        sf::RectangleShape handle(sf::Vector2f(6.f, 36.f));
        handle.setFillColor(sf::Color(60, 30, 10));
        handle.setOutlineThickness(1.f); handle.setOutlineColor(sf::Color(20, 10, 0));
        handle.setPosition(x - 3.f, yBase);
        window.draw(handle);
        // Cestello metallico della fiamma
        sf::RectangleShape bracket(sf::Vector2f(14.f, 8.f));
        bracket.setFillColor(sf::Color(80, 80, 80));
        bracket.setOutlineThickness(1.f); bracket.setOutlineColor(sf::Color(40, 40, 40));
        bracket.setPosition(x - 7.f, yBase - 8.f);
        window.draw(bracket);
        // Fiamma animata (3 strati: rosso scuro, arancione, giallo)
        float flicker = sin(menuTime * 18.f + x) * 2.f;
        // Strato esterno (rosso)
        sf::CircleShape flame3(10.f + flicker);
        flame3.setFillColor(sf::Color(180, 30, 10, 220));
        flame3.setPosition(x - 10.f - flicker, yBase - 30.f);
        window.draw(flame3);
        // Strato medio (arancione)
        sf::CircleShape flame2(7.f + flicker * 0.5f);
        flame2.setFillColor(sf::Color(255, 140, 30, 240));
        flame2.setPosition(x - 7.f - flicker * 0.5f, yBase - 26.f);
        window.draw(flame2);
        // Strato interno (giallo-bianco)
        sf::CircleShape flame1(4.f);
        flame1.setFillColor(sf::Color(255, 240, 180, 250));
        flame1.setPosition(x - 4.f, yBase - 22.f);
        window.draw(flame1);
        // Aura luminosa attorno alla fiamma
        sf::CircleShape aura(22.f);
        aura.setFillColor(sf::Color(255, 180, 60, 30));
        aura.setPosition(x - 22.f, yBase - 42.f);
        window.draw(aura);
    };
    drawTorch(WINDOW_WIDTH / 2.f - 360.f, 200.f);
    drawTorch(WINDOW_WIDTH / 2.f + 360.f, 200.f);

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
    diamond.setPoint(0, sf::Vector2f(WINDOW_WIDTH/2.f, ornY - 6.f));
    diamond.setPoint(1, sf::Vector2f(WINDOW_WIDTH/2.f + 8.f, ornY));
    diamond.setPoint(2, sf::Vector2f(WINDOW_WIDTH/2.f, ornY + 6.f));
    diamond.setPoint(3, sf::Vector2f(WINDOW_WIDTH/2.f - 8.f, ornY));
    window.draw(diamond);
    // Linee laterali
    sf::RectangleShape ornLineL(sf::Vector2f(180.f, 2.f));
    ornLineL.setFillColor(ornGold);
    ornLineL.setPosition(WINDOW_WIDTH/2.f - 200.f, ornY - 1.f);
    window.draw(ornLineL);
    sf::RectangleShape ornLineR(sf::Vector2f(180.f, 2.f));
    ornLineR.setFillColor(ornGold);
    ornLineR.setPosition(WINDOW_WIDTH/2.f + 20.f, ornY - 1.f);
    window.draw(ornLineR);
    // Piccoli rombi alle estremita' delle linee
    for (int side = 0; side < 2; side++) {
        float dx = (side == 0) ? -1.f : 1.f;
        sf::ConvexShape dot; dot.setPointCount(4);
        dot.setFillColor(ornGold);
        dot.setPoint(0, sf::Vector2f(WINDOW_WIDTH/2.f + dx * 200.f, ornY - 4.f));
        dot.setPoint(1, sf::Vector2f(WINDOW_WIDTH/2.f + dx * 204.f, ornY));
        dot.setPoint(2, sf::Vector2f(WINDOW_WIDTH/2.f + dx * 200.f, ornY + 4.f));
        dot.setPoint(3, sf::Vector2f(WINDOW_WIDTH/2.f + dx * 196.f, ornY));
        window.draw(dot);
    }

    // --- Crediti: "By" (oro) + "Luca A. Greco" (avorio) in stile fantasy ---
    // Sostituisce il vecchio "Lord Luca A. Greco".
    // Le due parti sono centrate come un'unica stringa.
    std::string byStr   = "By ";
    std::string nameStr = "Luca A. Greco";
    float byW   = byStr.length()   * 4 * 5;
    float nameW = nameStr.length() * 4 * 5;
    float totalW = byW + nameW;
    float startX = WINDOW_WIDTH/2 - totalW/2.f;
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

    // Voci di menu': valori dinamici per le prime 4 (giocatori/modalita'/risoluzione/musica)
    std::string items[] = {
        "NUMBER OF PLAYERS: " + std::to_string(numPlayers),
        "GAME MODE: " + std::string(gameMode == MODE_STORY ? "STORY" : "INFINITE"),
        "RESOLUTION: " + std::to_string(displayModes[selectedModeIndex].width) + "x" + std::to_string(displayModes[selectedModeIndex].height),
        "MUSIC: " + std::string(musicEnabled ? "ON" : "OFF"),
        "CONFIGURE JOYSTICK",
        "START GAME"
    };

    // Disegna le 6 voci; quella selezionata e' in giallo con "> ... <"
    // e una piccola fiammella pulsante alla sua sinistra.
    for(int i=0; i<6; i++) {
        std::string text = (i == menuItemIndex) ? ("> " + items[i] + " <") : items[i];
        sf::Color color = (i == menuItemIndex) ? sf::Color::Yellow : sf::Color(180, 180, 180);
        float itemY = 380 + i * 70;
        drawTextCenteredOutlined(window, text, WINDOW_WIDTH/2, itemY, 3, color);

        // Fiammella laterale animata per la voce selezionata
        if (i == menuItemIndex) {
            float fx = 150.f;
            float flicker = sin(menuTime * 15.f) * 1.5f;
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
        ui.render(window, player, maze.getRemainingTreasures());
        player.render(window);
        if (numPlayers == 2) player2.render(window);
        // Render dei nemici: inclusi quelli in animazione di morte (isDying)
        // finche' non e' conclusa (isDeathAnimDone). Quelli gia' conclusi
        // non vengono renderizzati.
        for (const auto& enemy : enemies) if (!enemy.isDeathAnimDone()) enemy.render(window);

        // Proiettili nemici: piccoli cerchi rossi (3px) con outline
        for (const auto& p : enemyProjectiles) {
            if (p.active) {
                sf::CircleShape proj(3.f); proj.setFillColor(sf::Color(255, 80, 40));
                proj.setOutlineThickness(1.f); proj.setOutlineColor(sf::Color(120, 20, 0));
                proj.setPosition(p.pos.x - 3.f, p.pos.y - 3.f); window.draw(proj);
            }
        }

        // Particelle: alpha proporzionale al rapporto life/maxLife
        for (const auto& p : particles) {
            sf::CircleShape c(4.f);
            c.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, 255 * p.life / p.maxLife));
            c.setPosition(p.pos.x - 4.f, p.pos.y - 4.f);
            window.draw(c);
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
            // 64 celle da 128x128 px (8x8 griglia) per coprire 1024x944.
            // Per ogni cella: colore base + variazione hash + ciottoli
            // sparsi + macchie scure. Identico al pavimento del labirinto
            // ma con celle piu' grandi (l'arena e' piu' spaziosa).
            auto floorHash = [](int c, int r) -> float {
                unsigned int h = (unsigned int)(c * 73856093u) ^ (unsigned int)(r * 19349663u);
                h ^= h >> 13;
                h *= 0x5bd1e995u;
                h ^= h >> 15;
                return (float)(h & 0xFFFFu) / 65535.f;
            };
            const int cellSize = 128;
            // Area di gioco: da UI_HEIGHT (80) a WINDOW_HEIGHT (1024)
            const int playTop = UI_HEIGHT;
            const int playH = WINDOW_HEIGHT - UI_HEIGHT;
            const int colsFloor = (WINDOW_WIDTH + cellSize - 1) / cellSize;
            const int rowsFloor = (playH + cellSize - 1) / cellSize;
            for (int fc = 0; fc < colsFloor; fc++) {
                for (int fr = 0; fr < rowsFloor; fr++) {
                    float fx = fc * cellSize;
                    float fy = playTop + fr * cellSize;
                    float v = floorHash(fc + 1, fr + 1);
                    // Colore base terra scura con variazione
                    sf::Uint8 bgr = (sf::Uint8)(18 + (v - 0.5f) * 12.f);
                    sf::Uint8 bgg = (sf::Uint8)(13 + (v - 0.5f) * 8.f);
                    sf::Uint8 bgb = (sf::Uint8)(10 + (v - 0.5f) * 6.f);
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
                float cx = WINDOW_WIDTH - wallThickness + 6.f + h1 * 12.f;
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
                float flicker = sin(bossRoomTime * 18.f + x) * 2.f;
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
        }

        // UI senza tesori (passiamo 0)
        ui.render(window, player, 0);
        // Armi a terra (raccoglibili)
        for (const auto& brw : bossRoomWeapons) brw.w.render(window, brw.pos.x - TILE_SIZE/2, brw.pos.y - TILE_SIZE/2);
        // Bonus scarpe alate (se attivo, disegna sprite + aura)
        if (speedBoots.active) {
            float bx = speedBoots.pos.x;
            float by = speedBoots.pos.y + speedBoots.bobOffset;
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
            sf::CircleShape aura(20.f + sin(speedBoots.bobOffset * 0.5f) * 3.f);
            aura.setFillColor(sf::Color(255, 220, 80, 40));
            aura.setPosition(bx - 20.f, by - 20.f);
            window.draw(aura);
        }
        player.render(window);
        if (numPlayers == 2) player2.render(window);
        boss->render(window);

        // Proiettili boss: piccoli e diversi per tipo
        for (const auto& p : bossProjectiles) {
            if (p.active) {
                if (p.type == WPN_ROCKET) {
                    // Razzo: piccolo corpo viola + punta
                    sf::RectangleShape body(sf::Vector2f(6.f, 4.f));
                    body.setFillColor(sf::Color(150, 0, 150));
                    body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(60, 0, 60));
                    body.setPosition(p.pos.x - 3.f, p.pos.y - 2.f); window.draw(body);
                    sf::CircleShape tip(2.f); tip.setFillColor(sf::Color(200, 50, 200));
                    tip.setPosition(p.pos.x + 1.f, p.pos.y - 2.f); window.draw(tip);
                } else {
                    // Proiettile normale: piccolo cerchio rosso (4px)
                    sf::CircleShape proj(4.f); proj.setFillColor(sf::Color(255, 60, 40));
                    proj.setOutlineThickness(1.f); proj.setOutlineColor(sf::Color(120, 20, 0));
                    proj.setPosition(p.pos.x - 4.f, p.pos.y - 4.f); window.draw(proj);
                }
            }
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
