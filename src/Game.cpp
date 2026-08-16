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
// ---------------------------------------------------------------------------
// Nota: l'ordine della initializer list deve rispettare l'ordine di
// dichiarazione dei membri in Game.h, altrimenti g++ emette -Wreorder.
// Ordine dichiarazione: window, boss, state, gameMode, isRunning,
// currentLevel, selectedModeIndex, menuItemIndex, musicEnabled,
// lightningTimer, configJoyStep.
Game::Game() : window(sf::VideoMode::getDesktopMode(), "Arcade Maze Fantasy", sf::Style::Fullscreen), boss(nullptr), state(STATE_MENU), gameMode(MODE_STORY), isRunning(true), currentLevel(1), selectedModeIndex(0), menuItemIndex(0), musicEnabled(false), lightningTimer(0), configJoyStep(0) {
    displayModes = sf::VideoMode::getFullscreenModes();
    selectedModeIndex = 0;
}

// init: imposta framerate, view iniziale e carica la configurazione comandi.
bool Game::init() {
    window.setFramerateLimit(60);
    sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
    window.setView(view);
    config = loadConfig("config.ini");
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
    player.resetPosition();
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
    // Tutti i tipi disponibili (15)
    EnemyType allTypes[] = {
        ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT,
        ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
        ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
        ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST
    };

    for (int i = 0; i < 5; ++i) {
        EnemyType t = allTypes[rand() % 15];
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
// ---------------------------------------------------------------------------
void Game::startBossFight() {
    state = STATE_BOSS;
    if(boss) delete boss;
    boss = new Boss(currentLevel, WINDOW_WIDTH, WINDOW_HEIGHT);
    player.resetPosition();
    // Posiziona il giocatore in fondo alla stanza (centro orizzontale)
    player.setPosition(WINDOW_WIDTH / 2.0f, WINDOW_HEIGHT - 100.0f);
    bossProjectiles.clear();
    enemyProjectiles.clear();
    spawnBossRoomWeapons();
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
                if (state == STATE_CONFIG_JOY) state = STATE_MENU;
                else if (state == STATE_MENU) isRunning = false;
                else { state = STATE_MENU; currentLevel = 1; }
            }

            // Navigazione menu'
            if (state == STATE_MENU) {
                // Su/Giu: cambio voce selezionata (5 voci totali, wrap con +5 %5)
                if (key == sf::Keyboard::Up) menuItemIndex = (menuItemIndex - 1 + 5) % 5;
                else if (key == sf::Keyboard::Down) menuItemIndex = (menuItemIndex + 1) % 5;
                // Sinistra/Destra: modifica dell'opzione selezionata
                else if (key == sf::Keyboard::Left) {
                    if (menuItemIndex == 0) gameMode = (gameMode == MODE_STORY) ? MODE_INFINITE : MODE_STORY;
                    if (menuItemIndex == 1) selectedModeIndex = (selectedModeIndex - 1 + displayModes.size()) % displayModes.size();
                    if (menuItemIndex == 2) { musicEnabled = !musicEnabled; if(musicEnabled) audio.playLevelMusic(1, false); else audio.stopMusic(); }
                }
                else if (key == sf::Keyboard::Right) {
                    if (menuItemIndex == 0) gameMode = (gameMode == MODE_STORY) ? MODE_INFINITE : MODE_STORY;
                    if (menuItemIndex == 1) selectedModeIndex = (selectedModeIndex + 1) % displayModes.size();
                    if (menuItemIndex == 2) { musicEnabled = !musicEnabled; if(musicEnabled) audio.playLevelMusic(1, false); else audio.stopMusic(); }
                }
                // Return: conferma (solo voci 3 = config joystick, 4 = avvia partita)
                else if (key == sf::Keyboard::Return) {
                    if (menuItemIndex == 3) { state = STATE_CONFIG_JOY; configJoyStep = 0; }
                    else if (menuItemIndex == 4) {
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
            } else if (state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) {
                // Schermate finali: Enter torna al menu'
                if (key == sf::Keyboard::Return) {
                    state = STATE_MENU;
                    currentLevel = 1;
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
                    if (menuItemIndex == 3) { state = STATE_CONFIG_JOY; configJoyStep = 0; }
                    else if (menuItemIndex == 4) {
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
                    else if (configJoyStep == 1) { config.joy_shoot = event.joystickButton.button; state = STATE_MENU; }
                }
            } else if (state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) {
                if (event.joystickButton.joystickId == 0 && event.joystickButton.button == (unsigned)config.joy_jump) {
                    state = STATE_MENU;
                    currentLevel = 1;
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
                if (y < 0) menuItemIndex = (menuItemIndex - 1 + 5) % 5;
                else menuItemIndex = (menuItemIndex + 1) % 5;
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
            if (sf::Joystick::isButtonPressed(0, config.joy_jump)) player.activateJump();
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
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_jump)) player.activateJump();
    }

    // --- Logica STATE_PLAYING: labirinto ---
    if (state == STATE_PLAYING) {
        // Tesori: rileva raccolta confrontando il conteggio prima/dopo update
        int treasuresBefore = maze.getRemainingTreasures();
        player.update(maze, false, particles);
        if (maze.getRemainingTreasures() < treasuresBefore) audio.playSound(SOUND_TREASURE);

        // Aggiornamento nemici (passa pos giocatore per AI + sparo)
        sf::Vector2f pPos = player.getPixelPos();
        for (auto& enemy : enemies) {
            if (!enemy.isDead()) enemy.update(maze, player.getGridPos(), pPos, enemyProjectiles);
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
        // Transizioni di stato
        if (player.getLives() <= 0) state = STATE_LOSE;
        if (maze.getRemainingTreasures() == 0) startBossFight();
    }
    // --- Logica STATE_BOSS: stanza del boss ---
    else if (state == STATE_BOSS) {
        // freeMovement=true: il giocatore si muove liberamente (non snap-to-grid)
        player.update(maze, true, particles);
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

        // Se il giocatore ha finito le munizioni e non ci sono armi a terra,
        // ne spawniamo altre 3 (evita soft-lock: il boss diventerebbe
        // invincibile se il giocatore non puo' piu' attaccare).
        if (player.getCurrentWeapon().ammo <= 0 && bossRoomWeapons.empty()) spawnBossRoomWeapons();
        if (player.getLives() <= 0) state = STATE_LOSE;
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
// drawMenu: disegna il menu' principale.
//
// Elementi:
//   * Sfondo blu scuro
//   * 100 stelle generate con seed fisso (srand(42)) per non mutare ad
//     ogni frame; poi srand(time(NULL)) per ripristinare il random del gioco
//   * Luna in alto a destra con due crateri
//   * Fulmine casuale (overlay bianco + linee gialle) quando lightningTimer>0
//   * Titolo "ARCADE MAZE" dorato con ombra scura sfalsata (effetto 3D)
//   * Crediti "Lord Luca A. Greco"
//   * Riquadro con 5 voci di menu'; la voce selezionata e' evidenziata in
//     giallo e racchiusa fra "> " e " <"
//   * Istruzioni in basso
// ---------------------------------------------------------------------------
void Game::drawMenu() {
    // Sfondo
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
    bg.setFillColor(sf::Color(30, 30, 60));
    window.draw(bg);

    // Stelle: seed fisso per layout stabile
    srand(42);
    for(int i=0; i<100; i++) {
        sf::CircleShape star(1 + rand()%2);
        star.setFillColor(sf::Color(200, 200, 255, 150 + rand()%105));
        star.setPosition(rand()%WINDOW_WIDTH, rand()%WINDOW_HEIGHT);
        window.draw(star);
    }
    // Ripristina il seed randomico per il resto del gioco
    srand(time(NULL));

    // Luna con outline e due crateri
    sf::CircleShape moon(80.f);
    moon.setFillColor(sf::Color(230, 230, 180));
    moon.setOutlineThickness(4.f);
    moon.setOutlineColor(sf::Color(180, 180, 130));
    moon.setPosition(WINDOW_WIDTH - 200.f, 100.f);
    window.draw(moon);
    sf::CircleShape crater1(10.f); crater1.setFillColor(sf::Color(200, 200, 150));
    crater1.setPosition(WINDOW_WIDTH - 160.f, 140.f); window.draw(crater1);
    crater1.setPosition(WINDOW_WIDTH - 180.f, 180.f); window.draw(crater1);

    // Effetto fulmine: flash bianco che si dissolve + saetta verticale a zigzag
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

    // Titolo con effetto ombra: due copie sfalsate di 4 px
    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2, 120, 10, sf::Color(255, 215, 0));
    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2 - 4, 120 - 4, 10, sf::Color(180, 120, 40));

    // Crediti: "Lord" in rosso + nome in bianco, centrati come un'unica stringa
    std::string lordStr = "Lord ";
    std::string nameStr = "Luca A. Greco";
    float lordW = lordStr.length() * 4 * 4;
    float nameW = nameStr.length() * 4 * 4;
    float totalW = lordW + nameW;
    float startX = WINDOW_WIDTH/2 - totalW/2.f;
    drawTextOutlined(window, lordStr, startX, 260, 4, sf::Color(220, 20, 20));
    drawTextOutlined(window, nameStr, startX + lordW, 260, 4, sf::Color::White);

    // Riquadro delle opzioni (sfondo semitrasparente con bordo marrone)
    sf::RectangleShape border(sf::Vector2f(WINDOW_WIDTH - 240, 500));
    border.setPosition(120, 360);
    border.setFillColor(sf::Color(0, 0, 0, 150));
    border.setOutlineThickness(6.f);
    border.setOutlineColor(sf::Color(100, 80, 50));
    window.draw(border);

    // Voci di menu': valori dinamici per le prime 3 (modalita'/risoluzione/musica)
    std::string items[] = {
        "GAME MODE: " + std::string(gameMode == MODE_STORY ? "STORY" : "INFINITE"),
        "RESOLUTION: " + std::to_string(displayModes[selectedModeIndex].width) + "x" + std::to_string(displayModes[selectedModeIndex].height),
        "MUSIC: " + std::string(musicEnabled ? "ON" : "OFF"),
        "CONFIGURE JOYSTICK",
        "START GAME"
    };

    // Disegna le 5 voci; quella selezionata e' in giallo con "> ... <"
    for(int i=0; i<5; i++) {
        std::string text = (i == menuItemIndex) ? ("> " + items[i] + " <") : items[i];
        sf::Color color = (i == menuItemIndex) ? sf::Color::Yellow : sf::Color(180, 180, 180);
        drawTextCenteredOutlined(window, text, WINDOW_WIDTH/2, 400 + i * 80, 3, color);
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

    drawTextCenteredOutlined(window, "JOYSTICK CONFIGURATION", WINDOW_WIDTH/2, 200, 4, sf::Color::White);

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
    else if (state == STATE_PLAYING || state == STATE_LOSE || state == STATE_WIN_INFINITE) {
        // Rendering comune per gameplay/schermate finali
        maze.render(window);
        ui.render(window, player, maze.getRemainingTreasures());
        player.render(window);
        for (const auto& enemy : enemies) if (!enemy.isDead()) enemy.render(window);

        // Proiettili nemici: piccoli cerchi arancioni
        for (const auto& p : enemyProjectiles) {
            if (p.active) {
                sf::CircleShape proj(4.f); proj.setFillColor(sf::Color(255, 100, 0));
                proj.setPosition(p.pos.x - 4.f, p.pos.y - 4.f); window.draw(proj);
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
        // Sfondo completamente nero (no labirinto)
        sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        bg.setFillColor(sf::Color(5, 5, 5));
        window.draw(bg);

        // UI senza tesori (passiamo 0)
        ui.render(window, player, 0);
        // Armi a terra (raccoglibili)
        for (const auto& brw : bossRoomWeapons) brw.w.render(window, brw.pos.x - TILE_SIZE/2, brw.pos.y - TILE_SIZE/2);
        player.render(window);
        boss->render(window);

        // Proiettili boss: forma diversa per tipo (razzo = grande viola, altri = rosso)
        for (const auto& p : bossProjectiles) {
            if (p.active) {
                if (p.type == WPN_ROCKET) {
                    sf::CircleShape proj(12.f); proj.setFillColor(sf::Color(150, 0, 150));
                    proj.setPosition(p.pos.x - 12.f, p.pos.y - 12.f); window.draw(proj);
                } else {
                    sf::CircleShape proj(8.f); proj.setFillColor(sf::Color(255, 50, 50));
                    proj.setPosition(p.pos.x - 8.f, p.pos.y - 8.f); window.draw(proj);
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
