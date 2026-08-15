#include "Game.h"
#include <iostream>
#include <cstdlib>
#include <algorithm>
#include <cmath>

Game::Game() : window(sf::VideoMode::getDesktopMode(), "Arcade Maze Fantasy", sf::Style::Fullscreen), state(STATE_MENU), boss(nullptr), currentLevel(1), selectedModeIndex(0), isRunning(true), musicEnabled(false), lightningTimer(0), menuItemIndex(0), gameMode(MODE_STORY), configJoyStep(0) {
    displayModes = sf::VideoMode::getFullscreenModes();
    selectedModeIndex = 0;
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
    enemyProjectiles.clear();
    state = STATE_PLAYING;
    if (musicEnabled) audio.playLevelMusic(currentLevel, false);
}

void Game::spawnEnemies() {
    enemies.clear();
    EnemyType allTypes[] = {
        ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT, 
        ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
        ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
        ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST
    };
    
    for (int i = 0; i < 5; ++i) {
        EnemyType t = allTypes[rand() % 15];
        int c, r;
        do {
            c = 1 + rand() % (MAZE_COLS - 2);
            r = 1 + rand() % (MAZE_ROWS - 2);
        } while (maze.isWall(c, r) || (c < 5 && r < 5));
        enemies.push_back(Enemy(t, c, r));
    }
}

void Game::startBossFight() {
    state = STATE_BOSS;
    if(boss) delete boss;
    boss = new Boss(currentLevel, WINDOW_WIDTH, WINDOW_HEIGHT);
    player.resetPosition();
    player.setPosition(WINDOW_WIDTH / 2.0f, WINDOW_HEIGHT - 100.0f);
    bossProjectiles.clear();
    enemyProjectiles.clear();
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
            if (key == sf::Keyboard::Escape) {
                if (state == STATE_CONFIG_JOY) state = STATE_MENU;
                else if (state == STATE_MENU) isRunning = false;
                else { state = STATE_MENU; currentLevel = 1; }
            }
            
            if (state == STATE_MENU) {
                if (key == sf::Keyboard::Up) menuItemIndex = (menuItemIndex - 1 + 5) % 5;
                else if (key == sf::Keyboard::Down) menuItemIndex = (menuItemIndex + 1) % 5;
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
                else if (key == sf::Keyboard::Return) {
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
            } else if (state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) {
                if (key == sf::Keyboard::Return) {
                    state = STATE_MENU;
                    currentLevel = 1;
                }
            }
        }
        else if (event.type == sf::Event::JoystickButtonPressed) {
            if (state == STATE_MENU) {
                if (event.joystickButton.joystickId == 0 && event.joystickButton.button == config.joy_jump) {
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
                if (event.joystickButton.joystickId == 0) {
                    if (configJoyStep == 0) { config.joy_jump = event.joystickButton.button; configJoyStep = 1; }
                    else if (configJoyStep == 1) { config.joy_shoot = event.joystickButton.button; state = STATE_MENU; }
                }
            } else if (state == STATE_WIN_STORY || state == STATE_WIN_INFINITE || state == STATE_LOSE) {
                if (event.joystickButton.joystickId == 0 && event.joystickButton.button == config.joy_jump) {
                    state = STATE_MENU;
                    currentLevel = 1;
                }
            }
        }
    }
}

void Game::update() {
    sf::Joystick::update();

    if (state == STATE_MENU) {
        if (sf::Joystick::isConnected(0)) {
            float y = sf::Joystick::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_y);
            static bool joyMoved = false;
            if (fabs(y) > 50 && !joyMoved) {
                joyMoved = true;
                if (y < 0) menuItemIndex = (menuItemIndex - 1 + 5) % 5;
                else menuItemIndex = (menuItemIndex + 1) % 5;
            } else if (fabs(y) < 20) joyMoved = false;
        }

        if (rand() % 600 < 5) lightningTimer = 10;
        if (lightningTimer > 0) lightningTimer--;
    }

    if (state == STATE_PLAYING || state == STATE_BOSS) {
        bool moved = false;
        if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_up)) { player.setDirection(0, -1); moved = true; }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_down)) { player.setDirection(0, 1); moved = true; }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_left)) { player.setDirection(-1, 0); moved = true; }
        else if (sf::Keyboard::isKeyPressed((sf::Keyboard::Key)config.key_right)) { player.setDirection(1, 0); moved = true; }
        
        if (sf::Joystick::isConnected(0)) {
            float x = sf::Joystick::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_x);
            float y = sf::Joystick::getAxisPosition(0, (sf::Joystick::Axis)config.joy_axis_y);
            if (fabs(x) > 30 || fabs(y) > 30) {
                if (fabs(x) > fabs(y)) {
                    if (x > 30) { player.setDirection(1, 0); moved = true; }
                    else if (x < -30) { player.setDirection(-1, 0); moved = true; }
                } else {
                    if (y > 30) { player.setDirection(0, 1); moved = true; }
                    else if (y < -30) { player.setDirection(0, -1); moved = true; }
                }
            }
            if (sf::Joystick::isButtonPressed(0, config.joy_shoot)) {
                if (player.getShootCooldown() == 0) {
                    int ammoBefore = player.getCurrentWeapon().ammo;
                    player.shoot();
                    if (player.getCurrentWeapon().ammo < ammoBefore) audio.playSound(getWeaponSound(player.getCurrentWeapon().type));
                    player.setShootCooldown(150);
                }
            }
            if (sf::Joystick::isButtonPressed(0, config.joy_jump)) player.activateJump();
        }
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

    if (state == STATE_PLAYING) {
        int treasuresBefore = maze.getRemainingTreasures();
        player.update(maze, false, particles);
        if (maze.getRemainingTreasures() < treasuresBefore) audio.playSound(SOUND_TREASURE);
        
        sf::Vector2f pPos = player.getPixelPos();
        for (auto& enemy : enemies) {
            if (!enemy.isDead()) enemy.update(maze, player.getGridPos(), pPos, enemyProjectiles);
        }
        
        // --- FIX CRITICO: AGGIORNAMENTO PROIETTILI NEMICI ---
        for (auto& proj : enemyProjectiles) {
            if (!proj.active) continue;
            proj.pos += proj.dir; // Muove il proiettile nemico!
            if (proj.pos.x < 0 || proj.pos.x > WINDOW_WIDTH || proj.pos.y < UI_HEIGHT || proj.pos.y > WINDOW_HEIGHT) {
                proj.active = false;
            }
        }
        // ----------------------------------------------------

        // Collisioni proiettili giocatore
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
                        for(int i=0; i<20; i++) particles.push_back({enemy.getPixelPos(), {(float)(rand()%8-4), (float)(rand()%8-4)}, sf::Color(150, 0, 0), 40, 40});
                    }
                    break;
                }
            }
        }
        
        // Collisioni proiettili nemici
        if (!player.isInvulnerable() && !player.isJumping()) {
            for (auto& proj : enemyProjectiles) {
                if (!proj.active) continue;
                float dx = proj.pos.x - player.getPixelPos().x;
                float dy = proj.pos.y - player.getPixelPos().y;
                if (dx*dx + dy*dy < 600) { 
                    proj.active = false;
                    int livesBefore = player.getLives();
                    player.takeDamage();
                    if (player.getLives() < livesBefore || player.getEnergy() < player.getMaxEnergy()) audio.playSound(SOUND_LOSE_LIFE);
                    break;
                }
            }
            enemyProjectiles.erase(std::remove_if(enemyProjectiles.begin(), enemyProjectiles.end(), [](const Projectile& p) { return !p.active; }), enemyProjectiles.end());
        }

        // Collisioni corpo a corpo
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
        
        // --- AGGIORNAMENTO PROIETTILI BOSS ---
        for (auto& proj : bossProjectiles) {
            if (!proj.active) continue;
            proj.pos += proj.dir; // Muove il proiettile/bomba
            if (proj.pos.x < 0 || proj.pos.x > WINDOW_WIDTH || proj.pos.y < UI_HEIGHT || proj.pos.y > WINDOW_HEIGHT) {
                proj.active = false;
            }
        }
        
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
            if (dx*dx + dy*dy < 1000) { player.collectWeapon(it->w); it = bossRoomWeapons.erase(it); } else ++it;
        }
        
        if (player.getCurrentWeapon().ammo <= 0 && bossRoomWeapons.empty()) spawnBossRoomWeapons();
        if (player.getLives() <= 0) state = STATE_LOSE;
        if (boss->isDead()) {
            audio.playSound(SOUND_BOSS_DEATH);
            player.addLife(); // Guadagni una vita dopo aver sconfitto il boss
            currentLevel++;
            
            if (gameMode == MODE_STORY && currentLevel > 10) {
                state = STATE_WIN_STORY;
                audio.stopMusic();
            } else {
                startLevel(currentLevel);
            }
        }
    } else if (state == STATE_WIN_STORY) {
        if (rand() % 10 == 0) spawnFirework();
        for (auto& fw : fireworks) {
            fw.pos += fw.vel;
            fw.vel.y += 0.1f;
            fw.life--;
        }
        fireworks.erase(std::remove_if(fireworks.begin(), fireworks.end(), [](const Firework& fw) { return fw.life <= 0; }), fireworks.end());
    }

    for (auto& p : particles) {
        p.pos += p.vel;
        p.life--;
    }
    particles.erase(std::remove_if(particles.begin(), particles.end(), [](const Particle& p) { return p.life <= 0; }), particles.end());
}

void Game::spawnFirework() {
    float x = 100 + rand() % (WINDOW_WIDTH - 200);
    float y = 100 + rand() % (WINDOW_HEIGHT / 2);
    sf::Color colors[] = {sf::Color::Red, sf::Color::Green, sf::Color::Blue, sf::Color::Yellow, sf::Color::Magenta, sf::Color::Cyan};
    sf::Color col = colors[rand() % 6];
    for(int i=0; i<30; i++) {
        float angle = i * (M_PI * 2 / 30);
        fireworks.push_back({sf::Vector2f(x, y), sf::Vector2f(cos(angle)*4, sin(angle)*4), col, 60});
    }
}

void Game::drawMenu() {
    sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
    bg.setFillColor(sf::Color(30, 30, 60));
    window.draw(bg);
    
    srand(42);
    for(int i=0; i<100; i++) {
        sf::CircleShape star(1 + rand()%2);
        star.setFillColor(sf::Color(200, 200, 255, 150 + rand()%105));
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

    if (lightningTimer > 0) {
        sf::RectangleShape flash(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        flash.setFillColor(sf::Color(255, 255, 255, 150 * (lightningTimer / 10.f)));
        window.draw(flash);
        if (lightningTimer > 5) {
            sf::Color lightningCol(255, 255, 200);
            float lx = WINDOW_WIDTH / 2.0f + (rand()%400 - 200);
            for (int i = 0; i < 6; i++) {
                sf::RectangleShape line(sf::Vector2f(6.f, 100.f));
                line.setFillColor(lightningCol);
                line.setPosition(lx, i * 100.f);
                line.rotate(rand()%30 - 15);
                window.draw(line);
                lx += (rand()%100 - 50);
            }
        }
    }

    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2, 120, 10, sf::Color(255, 215, 0));
    drawTextCenteredOutlined(window, "ARCADE MAZE", WINDOW_WIDTH/2 - 4, 120 - 4, 10, sf::Color(180, 120, 40));
    
    std::string lordStr = "Lord ";
    std::string nameStr = "Luca A. Greco";
    float lordW = lordStr.length() * 4 * 4;
    float nameW = nameStr.length() * 4 * 4;
    float totalW = lordW + nameW;
    float startX = WINDOW_WIDTH/2 - totalW/2.f;
    drawTextOutlined(window, lordStr, startX, 260, 4, sf::Color(220, 20, 20));
    drawTextOutlined(window, nameStr, startX + lordW, 260, 4, sf::Color::White);

    sf::RectangleShape border(sf::Vector2f(WINDOW_WIDTH - 240, 500));
    border.setPosition(120, 360);
    border.setFillColor(sf::Color(0, 0, 0, 150));
    border.setOutlineThickness(6.f);
    border.setOutlineColor(sf::Color(100, 80, 50));
    window.draw(border);

    std::string items[] = {
        "GAME MODE: " + std::string(gameMode == MODE_STORY ? "STORY" : "INFINITE"),
        "RESOLUTION: " + std::to_string(displayModes[selectedModeIndex].width) + "x" + std::to_string(displayModes[selectedModeIndex].height),
        "MUSIC: " + std::string(musicEnabled ? "ON" : "OFF"),
        "CONFIGURE JOYSTICK",
        "START GAME"
    };

    for(int i=0; i<5; i++) {
        std::string text = (i == menuItemIndex) ? ("> " + items[i] + " <") : items[i];
        sf::Color color = (i == menuItemIndex) ? sf::Color::Yellow : sf::Color(180, 180, 180);
        drawTextCenteredOutlined(window, text, WINDOW_WIDTH/2, 400 + i * 80, 3, color);
    }
    
    drawTextCenteredOutlined(window, "UP/DOWN TO SELECT - LEFT/RIGHT TO CHANGE", WINDOW_WIDTH/2, 900, 2, sf::Color(150, 150, 150));
}

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

void Game::render() {
    window.clear(sf::Color(10, 10, 10));
    
    if (state == STATE_MENU) {
        drawMenu();
    } 
    else if (state == STATE_CONFIG_JOY) {
        drawConfigJoy();
    }
    else if (state == STATE_PLAYING || state == STATE_LOSE || state == STATE_WIN_INFINITE) {
        maze.render(window);
        ui.render(window, player, maze.getRemainingTreasures());
        player.render(window);
        for (const auto& enemy : enemies) if (!enemy.isDead()) enemy.render(window);
        
        for (const auto& p : enemyProjectiles) {
            if (p.active) {
                sf::CircleShape proj(4.f); proj.setFillColor(sf::Color(255, 100, 0));
                proj.setPosition(p.pos.x - 4.f, p.pos.y - 4.f); window.draw(proj);
            }
        }
        
        for (const auto& p : particles) {
            sf::CircleShape c(4.f);
            c.setFillColor(sf::Color(p.color.r, p.color.g, p.color.b, 255 * p.life / p.maxLife));
            c.setPosition(p.pos.x - 4.f, p.pos.y - 4.f);
            window.draw(c);
        }

        if (state == STATE_LOSE) {
            sf::RectangleShape overlay(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
            overlay.setFillColor(sf::Color(0, 0, 0, 200));
            window.draw(overlay);
            drawTextCenteredOutlined(window, "GAME OVER", WINDOW_WIDTH/2, 350, 5, sf::Color::Red);
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
                if (p.type == WPN_ROCKET) {
                    sf::CircleShape proj(12.f); proj.setFillColor(sf::Color(150, 0, 150));
                    proj.setPosition(p.pos.x - 12.f, p.pos.y - 12.f); window.draw(proj);
                } else {
                    sf::CircleShape proj(8.f); proj.setFillColor(sf::Color(255, 50, 50));
                    proj.setPosition(p.pos.x - 8.f, p.pos.y - 8.f); window.draw(proj);
                }
            }
        }
        drawTextCenteredOutlined(window, "BOSS LEVEL " + std::to_string(currentLevel), WINDOW_WIDTH/2, 100, 3, sf::Color::Red);
    }
    else if (state == STATE_WIN_STORY) {
        sf::RectangleShape bg(sf::Vector2f(WINDOW_WIDTH, WINDOW_HEIGHT));
        bg.setFillColor(sf::Color(10, 10, 30));
        window.draw(bg);
        
        for (const auto& fw : fireworks) {
            sf::CircleShape c(6.f);
            c.setFillColor(sf::Color(fw.color.r, fw.color.g, fw.color.b, 255 * fw.life / 60));
            c.setPosition(fw.pos.x - 6.f, fw.pos.y - 6.f);
            window.draw(c);
        }
        
        drawTextCenteredOutlined(window, "CONGRATULATIONS!", WINDOW_WIDTH/2, 200, 5, sf::Color::Green);
        drawTextCenteredOutlined(window, "YOU FINISHED THE STORY MODE", WINDOW_WIDTH/2, 300, 3, sf::Color::Yellow);
        drawTextCenteredOutlined(window, "COMPLIMENTI PER LA TENACIA", WINDOW_WIDTH/2, 500, 3, sf::Color::White);
        drawTextCenteredOutlined(window, "E GRAZIE PER AVER GIOCATO!", WINDOW_WIDTH/2, 580, 3, sf::Color::White);
        drawTextCenteredOutlined(window, "PRESS ENTER", WINDOW_WIDTH/2, 800, 2, sf::Color::Red);
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