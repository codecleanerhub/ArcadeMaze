#include "Game.h"
#include <iostream>
#include <cstdlib>
#include <algorithm> // <-- AGGIUNTO PER std::remove_if

Game::Game() {
    window = nullptr;
    renderer = nullptr;
    isRunning = false;
    state = STATE_MENU;
    boss = nullptr;
    currentLevel = 1;
    selectedModeIndex = 0;
}

Game::~Game() {
    cleanup();
}

bool Game::init() {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0) return false;
    
    // Enumera risoluzioni a 60Hz
    int numModes = SDL_GetNumDisplayModes(0);
    for (int i = 0; i < numModes; ++i) {
        SDL_DisplayMode mode;
        SDL_GetDisplayMode(0, i, &mode);
        if (mode.refresh_rate == 60 && mode.w >= 800 && mode.h >= 600) {
            bool found = false;
            for(const auto& m : displayModes) {
                if(m.w == mode.w && m.h == mode.h) { found = true; break; }
            }
            if(!found) displayModes.push_back(mode);
        }
    }
    if (displayModes.empty()) {
        displayModes.push_back({SDL_PIXELFORMAT_UNKNOWN, 800, 800, 60, nullptr});
    }
    
    // Crea finestra iniziale
    SDL_DisplayMode initialMode = displayModes[0];
    window = SDL_CreateWindow("Arcade Maze Shooter", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, initialMode.w, initialMode.h, SDL_WINDOW_SHOWN);
    if (!window) return false;
    
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) return false;
    
    SDL_RenderSetLogicalSize(renderer, WINDOW_WIDTH, WINDOW_HEIGHT);
    
    config = loadConfig("config.ini");
    startLevel(1);
    
    isRunning = true;
    return true;
}

void Game::startLevel(int lvl) {
    currentLevel = lvl;
    maze.generate();
    player.resetPosition();
    spawnEnemies();
    state = STATE_PLAYING;
}

void Game::spawnEnemies() {
    enemies.clear();
    EnemyType types[] = {ENEMY_ALIEN, ENEMY_GHOST, ENEMY_ROBOT, ENEMY_FANTASY};
    for (int i = 0; i < 4; ++i) {
        int c, r;
        do {
            c = 1 + rand() % (MAZE_COLS - 2);
            r = 1 + rand() % (MAZE_ROWS - 2);
        } while (maze.isWall(c, r) || (c < 5 && r < 5));
        enemies.push_back(Enemy(types[i], c, r));
    }
}

void Game::startBossFight() {
    state = STATE_BOSS;
    if(boss) delete boss;
    boss = new Boss(currentLevel, WINDOW_WIDTH, WINDOW_HEIGHT);
    player.resetPosition();
    player.setPosition(WINDOW_WIDTH / 2.0f, WINDOW_HEIGHT - 50.0f); // <-- USATO METODO PUBBLICO
    bossProjectiles.clear();
    spawnBossRoomWeapons();
}

void Game::spawnBossRoomWeapons() {
    bossRoomWeapons.clear();
    for(int i=0; i<3; i++) {
        Weapon w = Weapon::generateRandom();
        w.ammo = 5; // Poche munizioni, costringe a raccoglierne di più
        bossRoomWeapons.push_back(w);
    }
}

SoundType Game::getWeaponSound(WeaponType wt) {
    switch(wt) {
        case WPN_PISTOL: return SOUND_PISTOL;
        case WPN_SHOTGUN: return SOUND_SHOTGUN;
        case WPN_ROCKET: return SOUND_ROCKET;
        case WPN_LASER: return SOUND_LASER;
    }
    return SOUND_PISTOL;
}

void Game::handleEvents() {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            isRunning = false;
        } else if (e.type == SDL_KEYDOWN) {
            SDL_Scancode scancode = e.key.keysym.scancode;
            
            if (scancode == SDL_SCANCODE_ESCAPE) isRunning = false;
            
            if (state == STATE_MENU) {
                if (scancode == SDL_SCANCODE_UP) {
                    selectedModeIndex = (selectedModeIndex - 1 + displayModes.size()) % displayModes.size();
                } else if (scancode == SDL_SCANCODE_DOWN) {
                    selectedModeIndex = (selectedModeIndex + 1) % displayModes.size();
                } else if (scancode == SDL_SCANCODE_RETURN) {
                    SDL_DisplayMode mode = displayModes[selectedModeIndex];
                    SDL_SetWindowSize(window, mode.w, mode.h);
                    SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
                    startLevel(1);
                }
            } else if (state == STATE_PLAYING) {
                int ammoBefore = player.getCurrentWeapon().ammo;
                player.handleInput(scancode, config, maze);
                if (player.getCurrentWeapon().ammo < ammoBefore) {
                    audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                }
            } else if (state == STATE_BOSS) {
                int ammoBefore = player.getCurrentWeapon().ammo;
                player.handleInput(scancode, config, maze);
                if (player.getCurrentWeapon().ammo < ammoBefore) {
                    audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                }
            } else if (state == STATE_WIN || state == STATE_LOSE) {
                if (scancode == SDL_SCANCODE_RETURN) {
                    currentLevel = 1;
                    player.reset();
                    startLevel(1);
                }
            }
        }
    }
}

void Game::update() {
    if (state == STATE_PLAYING) {
        int dotsBefore = maze.getRemainingDots();
        player.update(maze, false);
        
        if (maze.getRemainingDots() < dotsBefore) audio.playSound(SOUND_DOT);
        
        Vec2 playerGridPos = player.getGridPos();
        
        for (auto& enemy : enemies) {
            if (!enemy.isDead()) enemy.update(maze, playerGridPos);
        }
        
        for (auto& proj : player.getProjectiles()) {
            if (!proj.active) continue;
            Vec2 projGrid = { (int)(proj.x / TILE_SIZE), (int)((proj.y - UI_HEIGHT) / TILE_SIZE) };
            for (auto& enemy : enemies) {
                if (enemy.isDead()) continue;
                Vec2 enGrid = enemy.getGridPos();
                if (projGrid.x == enGrid.x && projGrid.y == enGrid.y) {
                    enemy.takeDamage(proj.power);
                    proj.active = false;
                    if (enemy.isDead()) {
                        player.addScore(5000);
                        audio.playSound(SOUND_ENEMY_DEATH);
                    }
                    break;
                }
            }
        }
        
        if (!player.isInvulnerable()) {
            for (auto& enemy : enemies) {
                if (enemy.isDead()) continue;
                Vec2 enGrid = enemy.getGridPos();
                if (playerGridPos.x == enGrid.x && playerGridPos.y == enGrid.y) {
                    if (!player.isJumping()) {
                        int livesBefore = player.getLives();
                        player.takeDamage();
                        if (player.getLives() < livesBefore) audio.playSound(SOUND_LOSE_LIFE);
                    }
                    break;
                }
            }
        }
        
        if (player.getLives() <= 0) state = STATE_LOSE;
        if (maze.getRemainingDots() == 0) startBossFight();
    } 
    else if (state == STATE_BOSS) {
        player.update(maze, true);
        boss->update(player.getPixelPos().x, player.getPixelPos().y, bossProjectiles);
        
        // Collisioni proiettili giocatore -> boss
        for (auto& proj : player.getProjectiles()) {
            if (!proj.active) continue;
            int dx = proj.x - boss->getPos().x;
            int dy = proj.y - boss->getPos().y;
            if (dx*dx + dy*dy < (boss->getSize()/2)*(boss->getSize()/2)) {
                boss->takeDamage(proj.power);
                proj.active = false;
                audio.playSound(SOUND_BOSS_HIT);
            }
        }
        
        // Collisioni proiettili boss -> giocatore
        if (!player.isInvulnerable()) {
            for (auto& proj : bossProjectiles) {
                if (!proj.active) continue;
                int dx = proj.x - player.getPixelPos().x;
                int dy = proj.y - player.getPixelPos().y;
                if (dx*dx + dy*dy < 100) { // Raggio 10
                    proj.active = false;
                    int livesBefore = player.getLives();
                    player.takeDamage();
                    if (player.getLives() < livesBefore) audio.playSound(SOUND_LOSE_LIFE);
                }
            }
            bossProjectiles.erase(std::remove_if(bossProjectiles.begin(), bossProjectiles.end(), [](const Projectile& p) { return !p.active; }), bossProjectiles.end());
        }
        
        // Raccogli armi nella boss room
        for (auto it = bossRoomWeapons.begin(); it != bossRoomWeapons.end(); ) {
            int dx = WINDOW_WIDTH / 2 + (it - bossRoomWeapons.begin()) * 100 - player.getPixelPos().x;
            int dy = WINDOW_HEIGHT - 30 - player.getPixelPos().y;
            if (dx*dx + dy*dy < 400) {
                player.collectWeapon(*it);
                it = bossRoomWeapons.erase(it);
            } else {
                ++it;
            }
        }
        
        // Se le munizioni scendono sotto 1, spawniamo nuove armi
        if (player.getCurrentWeapon().ammo <= 0 && bossRoomWeapons.empty()) {
            spawnBossRoomWeapons();
        }
        
        if (player.getLives() <= 0) state = STATE_LOSE;
        if (boss->isDead()) {
            audio.playSound(SOUND_BOSS_DEATH);
            currentLevel++;
            startLevel(currentLevel);
        }
    }
}

void Game::render() {
    if (state == STATE_MENU) {
        SDL_SetRenderDrawColor(renderer, 20, 20, 40, 255);
        SDL_RenderClear(renderer);
        
        drawText(renderer, "SELECT RESOLUTION", 250, 100, 3, {255, 255, 255, 255});
        
        for (size_t i = 0; i < displayModes.size(); ++i) {
            std::string res = std::to_string(displayModes[i].w) + "x" + std::to_string(displayModes[i].h);
            SDL_Color color = (i == selectedModeIndex) ? SDL_Color{255, 255, 0, 255} : SDL_Color{200, 200, 200, 255};
            drawText(renderer, res, 300, 200 + i * 40, 2, color);
        }
        
        drawText(renderer, "UP/DOWN TO SELECT", 220, 600, 2, {255, 255, 255, 255});
        drawText(renderer, "ENTER TO START", 250, 650, 2, {255, 255, 255, 255});
        
        SDL_RenderPresent(renderer);
        return;
    }
    
    if (state == STATE_PLAYING || state == STATE_WIN || state == STATE_LOSE) {
        maze.render(renderer);
        ui.render(renderer, player, maze.getRemainingDots());
        
        player.render(renderer);
        
        for (const auto& enemy : enemies) {
            if (!enemy.isDead()) enemy.render(renderer);
        }
        
        if (state == STATE_WIN) {
            SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200);
            SDL_Rect overlay = {0, 0, WINDOW_WIDTH, WINDOW_HEIGHT};
            SDL_RenderFillRect(renderer, &overlay);
            drawText(renderer, "YOU WIN", 300, 350, 4, {0, 255, 0, 255});
            drawText(renderer, "PRESS ENTER", 250, 450, 2, {255, 255, 255, 255});
        } else if (state == STATE_LOSE) {
            SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200);
            SDL_Rect overlay = {0, 0, WINDOW_WIDTH, WINDOW_HEIGHT};
            SDL_RenderFillRect(renderer, &overlay);
            drawText(renderer, "GAME OVER", 280, 350, 4, {255, 0, 0, 255});
            drawText(renderer, "PRESS ENTER", 250, 450, 2, {255, 255, 255, 255});
        }
    } 
    else if (state == STATE_BOSS) {
        SDL_SetRenderDrawColor(renderer, 10, 10, 10, 255);
        SDL_RenderClear(renderer);
        
        ui.render(renderer, player, 0);
        
        // Disegna armi a terra
        for (size_t i = 0; i < bossRoomWeapons.size(); ++i) {
            bossRoomWeapons[i].render(renderer, WINDOW_WIDTH / 2 + i * 100 - TILE_SIZE/2, WINDOW_HEIGHT - 30 - TILE_SIZE/2);
        }
        
        player.render(renderer);
        boss->render(renderer);
        
        // Disegna proiettili boss
        SDL_SetRenderDrawColor(renderer, 255, 50, 50, 255);
        for (const auto& p : bossProjectiles) {
            if (p.active) {
                drawFilledCircle(renderer, (int)p.x, (int)p.y, 6, {255, 50, 50, 255});
            }
        }
        
        std::string lvlText = "BOSS LEVEL " + std::to_string(currentLevel);
        drawText(renderer, lvlText, 300, 100, 3, {255, 0, 0, 255});
    }
    
    SDL_RenderPresent(renderer);
}

void Game::run() {
    while (isRunning) {
        handleEvents();
        update();
        render();
        SDL_Delay(16);
    }
}

void Game::cleanup() {
    if (boss) delete boss;
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
}