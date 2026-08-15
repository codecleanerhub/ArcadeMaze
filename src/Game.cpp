#include "Game.h"
#include <iostream>
#include <cstdlib>
#include <algorithm>
#include <cmath> // <-- AGGIUNTO PER sin()

Game::Game() : window(sf::VideoMode(1024, 1024), "Arcade Maze Fantasy"), state(STATE_MENU), boss(nullptr), currentLevel(1), selectedModeIndex(0), isRunning(true), musicEnabled(false), lightningTimer(0) {
    displayModes = sf::VideoMode::getFullscreenModes();
    selectedModeIndex = 0;
    for(int i=0; i<5; i++) {
        // Corretto narrowing conversion con (float)
        menuBats.push_back({sf::Vector2f(rand()%WINDOW_WIDTH, rand()%400), (float)(1 + rand()%2), (float)(rand()%360)});
    }
}

bool Game::init() {
    window.setFramerateLimit(60);
    sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
    window.setView(view);
    config = loadConfig("config.ini");
    return true;
}

void Game::startLevel(int lvl) {
    currentLevel = lvl;
    maze.generate();
    player.resetPosition();
    spawnEnemies();
    state = STATE_PLAYING;
    if (musicEnabled) audio.playLevelMusic(currentLevel, false);
}

void Game::spawnEnemies() {
    enemies.clear();
    // 3 pool di 5 nemici per tema Horror/Fantasy
    EnemyType pool1[] = {ENEMY_ZOMBIE, ENEMY_GHOUL, ENEMY_RAT, ENEMY_BAT, ENEMY_SKELETON}; // Cripta
    EnemyType pool2[] = {ENEMY_CULTIST, ENEMY_SPIDER, ENEMY_SLIME, ENEMY_GOBLIN, ENEMY_ORC}; // Dungeon
    EnemyType pool3[] = {ENEMY_IMP, ENEMY_DEMON, ENEMY_WRAITH, ENEMY_GHOST, ENEMY_ROBOT};    // Inferno/Dimensione
    
    EnemyType* currentPool = (currentLevel % 3 == 0) ? pool3 : (currentLevel % 2 == 0 ? pool2 : pool1);
    
    for (int i = 0; i < 5; ++i) {
        int c, r;
        do {
            c = 1 + rand() % (MAZE_COLS - 2);
            r = 1 + rand() % (MAZE_ROWS - 2);
        } while (maze.isWall(c, r) || (c < 5 && r < 5));
        enemies.push_back(Enemy(currentPool[i], c, r));
    }
}

void Game::startBossFight() {
    state = STATE_BOSS;
    if(boss) delete boss;
    boss = new Boss(currentLevel, WINDOW_WIDTH, WINDOW_HEIGHT);
    player.resetPosition();
    player.setPosition(WINDOW_WIDTH / 2.0f, WINDOW_HEIGHT - 100.0f);
    bossProjectiles.clear();
    spawnBossRoomWeapons();
    if (musicEnabled) audio.playLevelMusic(currentLevel, true);
}

void Game::spawnBossRoomWeapons() {
    bossRoomWeapons.clear();
    for(int i=0; i<3; i++) {
        Weapon w = Weapon::generateRandom();
        w.ammo = 5;
        bossRoomWeapons.push_back({w, sf::Vector2f(200.0f + i * 300.0f, 200.0f)});
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
    sf::Event event;
    while (window.pollEvent(event)) {
        if (event.type == sf::Event::Closed) isRunning = false;
        else if (event.type == sf::Event::Resized) {
            float windowRatio = (float)event.size.width / (float)event.size.height;
            float viewRatio = (float)WINDOW_WIDTH / (float)WINDOW_HEIGHT;
            sf::FloatRect viewport(0.f, 0.f, 1.f, 1.f);
            if (windowRatio > viewRatio) {
                viewport.width = viewRatio / windowRatio;
                viewport.left = (1.f - viewport.width) / 2.f;
            } else {
                viewport.height = windowRatio / viewRatio;
                viewport.top = (1.f - viewport.height) / 2.f;
            }
            sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
            view.setViewport(viewport);
            window.setView(view);
        }
        else if (event.type == sf::Event::KeyPressed) {
            int key = event.key.code;
            if (key == sf::Keyboard::Escape) isRunning = false;
            
            if (state == STATE_MENU) {
                if (key == sf::Keyboard::Up) selectedModeIndex = (selectedModeIndex - 1 + displayModes.size()) % displayModes.size();
                else if (key == sf::Keyboard::Down) selectedModeIndex = (selectedModeIndex + 1) % displayModes.size();
                else if (key == sf::Keyboard::M) {
                    musicEnabled = !musicEnabled;
                    if(musicEnabled) audio.playLevelMusic(1, false);
                    else audio.stopMusic();
                }
                else if (key == sf::Keyboard::Return) {
                    sf::VideoMode mode = displayModes[selectedModeIndex];
                    window.create(mode, "Arcade Maze Fantasy", sf::Style::Fullscreen);
                    window.setFramerateLimit(60);
                    sf::View view(sf::FloatRect(0.f, 0.f, WINDOW_WIDTH, WINDOW_HEIGHT));
                    window.setView(view);
                    startLevel(1);
                }
            } else if (state == STATE_PLAYING || state == STATE_BOSS) {
                player.handleInput(key, config);
            } else if (state == STATE_WIN || state == STATE_LOSE) {
                if (key == sf::Keyboard::Return) {
                    currentLevel = 1;
                    player.reset();
                    startLevel(1);
                }
            }
        }
    }
}

void Game::update() {
    if (state == STATE_MENU) {
        for (auto& bat : menuBats) {
            bat.pos.x += bat.speed;
            if (bat.pos.x > WINDOW_WIDTH + 20) bat.pos.x = -20;
            bat.pos.y += sin(bat.phase) * 0.5f;
            bat.phase += 0.1f;
        }
        if (rand() % 1000 < 5) lightningTimer = 8;
        if (lightningTimer > 0) lightningTimer--;
    }

    if (state == STATE_PLAYING || state == STATE_BOSS) {
        if (sf::Keyboard::isKeyPressed(sf::Keyboard::Space)) {
            if (player.getShootCooldown() == 0) {
                int ammoBefore = player.getCurrentWeapon().ammo;
                player.shoot();
                if (player.getCurrentWeapon().ammo < ammoBefore) {
                    audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                }
                player.setShootCooldown(150);
            }
        }
        if (sf::Keyboard::isKeyPressed(sf::Keyboard::LAlt)) {
            player.activateJump();
        }
    }

    if (state == STATE_PLAYING) {
        int treasuresBefore = maze.getRemainingTreasures();
        player.update(maze, false, particles);
        
        if (maze.getRemainingTreasures() < treasuresBefore) audio.playSound(SOUND_TREASURE);
        
        sf::Vector2f pPos = player.getPixelPos();
        for (auto& enemy : enemies) {
            if (!enemy.isDead()) enemy.update(maze, player.getGridPos());
        }
        
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
                        for(int i=0; i<20; i++) {
                            particles.push_back({enemy.getPixelPos(), {(float)(rand()%8-4), (float)(rand()%8-4)}, sf::Color(150, 0, 0), 40, 40});
                        }
                    }
                    break;
                }
            }
        }
        
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
        if (player.getLives() <= 0) state = STATE_LOSE;
        if (maze.getRemainingTreasures() == 0) startBossFight();
    } 
    else if (state == STATE_BOSS) {
        player.update(maze, true, particles);
        boss->update(player.getPixelPos().x, player.getPixelPos().y, bossProjectiles);
        
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
        
        for (auto it = bossRoomWeapons.begin(); it != bossRoomWeapons.end(); ) {
            float dx = it->pos.x - player.getPixelPos().x;
            float dy = it->pos.y - player.getPixelPos().y;
            if (dx*dx + dy*dy < 1000) { 
                player.collectWeapon(it->w);
                it = bossRoomWeapons.erase(it);
            } else ++it;
        }
        
        if (player.getCurrentWeapon().ammo <= 0 && bossRoomWeapons.empty()) spawnBossRoomWeapons();
        if (player.getLives() <= 0) state = STATE_LOSE;
        if (boss->isDead()) {
            audio.playSound(SOUND_BOSS_DEATH);
            currentLevel++;
            startLevel(currentLevel);
        }
    }

    for (auto& p : particles) {
        p.pos += p.vel;
        p.life--;
    }
    particles.erase(std::remove_if(particles.begin(), particles.end(), [](const Particle& p) { return p.life <= 0; }), particles.end());
}

void Game::drawMenu() {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
    bg.setFillColor(sf::Color(10, 10, 30));
    window.draw(bg);
    
    srand(42);
    for(int i=0; i<80; i++) {
        sf::CircleShape star(1 + rand()%2);
        star.setFillColor(sf::Color(200, 200, 255, 100 + rand()%155));
        star.setPosition(rand()%WINDOW_WIDTH, rand()%WINDOW_HEIGHT);
        window.draw(star);
    }
    srand(time(NULL));

    sf::CircleShape moon(80.f);
    moon.setFillColor(sf::Color(230, 230, 180));
    moon.setOutlineThickness(4.f);
    moon.setOutlineColor(sf::Color(180, 180, 130));
    moon.setPosition(WINDOW_WIDTH - 200.f, 100.f);
    window.draw(moon);
    sf::CircleShape crater1(10.f); crater1.setFillColor(sf::Color(200, 200, 150));
    crater1.setPosition(WINDOW_WIDTH - 160.f, 140.f); window.draw(crater1);
    crater1.setPosition(WINDOW_WIDTH - 180.f, 180.f); window.draw(crater1);

    for (const auto& bat : menuBats) {
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color::Black);
        wing.setPoint(0, sf::Vector2f(bat.pos.x, bat.pos.y));
        wing.setPoint(1, sf::Vector2f(bat.pos.x - 20, bat.pos.y - 8));
        wing.setPoint(2, sf::Vector2f(bat.pos.x - 16, bat.pos.y + 4));
        wing.setPoint(3, sf::Vector2f(bat.pos.x - 4, bat.pos.y + 4));
        window.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(bat.pos.x, bat.pos.y); window.draw(wing);
        sf::CircleShape body(8.f); body.setFillColor(sf::Color::Black);
        body.setPosition(bat.pos.x - 8.f, bat.pos.y - 8.f); window.draw(body);
    }

    if (lightningTimer > 0) {
        sf::RectangleShape flash(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        flash.setFillColor(sf::Color(255, 255, 255, 100 * (lightningTimer / 8.f)));
        window.draw(flash);
        if (lightningTimer > 4) {
            sf::Color lightningCol(255, 255, 200);
            float lx = WINDOW_WIDTH / 2.0f + (rand()%400 - 200);
            for (int i = 0; i < 5; i++) {
                sf::Vertex line[] = {
                    sf::Vertex(sf::Vector2f(lx, i * 100.f), lightningCol),
                    sf::Vertex(sf::Vector2f(lx + (rand()%100 - 50), (i+1) * 100.f), lightningCol)
                };
                window.draw(line, 2, sf::Lines);
            }
        }
    }

    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2, 220, 8, sf::Color(255, 215, 0));
    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2 - 4, 220 - 4, 8, sf::Color(180, 120, 40));
    
    std::string lordStr = "Lord ";
    std::string nameStr = "Luca A. Greco";
    float lordW = lordStr.length() * 4 * 3;
    float nameW = nameStr.length() * 4 * 3;
    float totalW = lordW + nameW;
    float startX = WINDOW_WIDTH/2 - totalW/2.f;
    drawTextOutlined(window, lordStr, startX, 340, 3, sf::Color(220, 20, 20));
    drawTextOutlined(window, nameStr, startX + lordW, 340, 3, sf::Color::White);

    sf::RectangleShape border(sf::Vector2f(WINDOW_WIDTH - 120, WINDOW_HEIGHT - 480));
    border.setPosition(60, 420);
    border.setFillColor(sf::Color(0, 0, 0, 150));
    border.setOutlineThickness(6.f);
    border.setOutlineColor(sf::Color(100, 80, 50));
    window.draw(border);

    drawTextCenteredOutlined(window, "SELECT RESOLUTION", WINDOW_WIDTH/2, 450, 3, sf::Color::White);
    for (size_t i = 0; i < displayModes.size() && i < 8; ++i) {
        std::string res = std::to_string(displayModes[i].width) + "x" + std::to_string(displayModes[i].height);
        std::string text = (i == selectedModeIndex) ? ("> " + res + " <") : res;
        sf::Color color = (i == selectedModeIndex) ? sf::Color::Yellow : sf::Color(180, 180, 180);
        drawTextCenteredOutlined(window, text, WINDOW_WIDTH/2, 520 + i * 40, 2, color);
    }

    drawTextCenteredOutlined(window, "PRESS 'M' TO TOGGLE MUSIC:", WINDOW_WIDTH/2, 850, 2, sf::Color::White);
    drawTextCenteredOutlined(window, musicEnabled ? "[ ON ]" : "[ OFF ]", WINDOW_WIDTH/2, 890, 2, musicEnabled ? sf::Color::Green : sf::Color::Red);
    
    drawTextCenteredOutlined(window, "UP/DOWN TO SELECT", WINDOW_WIDTH/2, 940, 2, sf::Color(150, 150, 150));
    drawTextCenteredOutlined(window, "PRESS ENTER TO START", WINDOW_WIDTH/2, 980, 3, sf::Color(255, 255, 0));
}

void Game::render() {
    window.clear(sf::Color(10, 10, 10));
    
    if (state == STATE_MENU) {
        drawMenu();
    } 
    else if (state == STATE_PLAYING || state == STATE_WIN || state == STATE_LOSE) {
        maze.render(window);
        ui.render(window, player, maze.getRemainingTreasures());
        player.render(window);
        for (const auto& enemy : enemies) if (!enemy.isDead()) enemy.render(window);
        
        for (const auto& p : particles) {
            sf::CircleShape c(4.f);
            c.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, 255 * p.life / p.maxLife));
            c.setPosition(p.pos.x - 4.f, p.pos.y - 4.f);
            window.draw(c);
        }

        if (state == STATE_WIN) {
            sf::RectangleShape overlay(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
            overlay.setFillColor(sf::Color(0, 0, 0, 200));
            window.draw(overlay);
            drawTextCenteredOutlined(window, "YOU WIN", WINDOW_WIDTH/2, 350, 4, sf::Color::Green);
            drawTextCenteredOutlined(window, "PRESS ENTER", WINDOW_WIDTH/2, 450, 2, sf::Color::White);
        } else if (state == STATE_LOSE) {
            sf::RectangleShape overlay(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
            overlay.setFillColor(sf::Color(0, 0, 0, 200));
            window.draw(overlay);
            drawTextCenteredOutlined(window, "GAME OVER", WINDOW_WIDTH/2, 350, 4, sf::Color::Red);
            drawTextCenteredOutlined(window, "PRESS ENTER", WINDOW_WIDTH/2, 450, 2, sf::Color::White);
        }
    } 
    else if (state == STATE_BOSS) {
        sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        bg.setFillColor(sf::Color(5, 5, 5));
        window.draw(bg);
        
        ui.render(window, player, 0);
        for (const auto& brw : bossRoomWeapons) brw.w.render(window, brw.pos.x - TILE_SIZE/2, brw.pos.y - TILE_SIZE/2);
        player.render(window);
        boss->render(window);
        for (const auto& p : bossProjectiles) {
            if (p.active) {
                sf::CircleShape proj(10.f); proj.setFillColor(sf::Color(255, 50, 50));
                proj.setPosition(p.pos.x - 10.f, p.pos.y - 10.f); window.draw(proj);
            }
        }
        drawTextCenteredOutlined(window, "BOSS LEVEL " + std::to_string(currentLevel), WINDOW_WIDTH/2, 100, 3, sf::Color::Red);
    }
    
    window.display();
}

void Game::run() {
    while (isRunning) {
        handleEvents();
        update();
        render();
    }
}