#include "Game.h"
#include <iostream>
#include <cstdlib>

Game::Game() {
    window = nullptr;
    renderer = nullptr;
    isRunning = false;
    state = STATE_PLAYING;
}

Game::~Game() {
    cleanup();
}

bool Game::init() {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        std::cerr << "SDL non inizializzato! Errore: " << SDL_GetError() << std::endl;
        return false;
    }
    
    window = SDL_CreateWindow("Arcade Maze Shooter", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_SHOWN);
    if (!window) return false;
    
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) return false;
    
    config = loadConfig("config.ini");
    spawnEnemies();
    
    isRunning = true;
    return true;
}

void Game::spawnEnemies() {
    enemies.clear();
    // Genera 4 nemici di tipi diversi in posizioni casuali lontane dal giocatore
    EnemyType types[] = {ENEMY_ALIEN, ENEMY_GHOST, ENEMY_ROBOT, ENEMY_FANTASY};
    
    for (int i = 0; i < 4; ++i) {
        int c, r;
        do {
            c = 1 + rand() % (MAZE_COLS - 2);
            r = 1 + rand() % (MAZE_ROWS - 2);
        } while (maze.isWall(c, r) || (c < 5 && r < 5)); // Non spawnare vicino al player
        
        enemies.push_back(Enemy(types[i], c, r));
    }
}

void Game::resetGame() {
    maze.generate();
    player.reset();
    spawnEnemies();
    state = STATE_PLAYING;
}

void Game::handleEvents() {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            isRunning = false;
        } else if (e.type == SDL_KEYDOWN) {
            // Utilizziamo SDL_Scancode per robustezza
            SDL_Scancode scancode = e.key.keysym.scancode;
            
            if (scancode == SDL_SCANCODE_ESCAPE) {
                isRunning = false;
            }
            
            if (state == STATE_PLAYING) {
                player.handleInput(scancode, config, maze);
            } else if (scancode == SDL_SCANCODE_RETURN) {
                resetGame();
            }
        }
    }
}

void Game::update() {
    if (state != STATE_PLAYING) return;
    
    player.update(maze);
    
    Vec2 playerGridPos = player.getGridPos();
    
    // Aggiorna nemici
    for (auto& enemy : enemies) {
        if (!enemy.isDead()) {
            enemy.update(maze, playerGridPos);
        }
    }
    
    // Collisioni Proiettili - Nemici
    for (auto& proj : player.getProjectiles()) {
        if (!proj.active) continue;
        
        Vec2 projGrid = { (int)(proj.x / TILE_SIZE), (int)(proj.y / TILE_SIZE) };
        
        for (auto& enemy : enemies) {
            if (enemy.isDead()) continue;
            
            Vec2 enGrid = enemy.getGridPos();
            if (projGrid.x == enGrid.x && projGrid.y == enGrid.y) {
                enemy.takeDamage(proj.power);
                proj.active = false;
                if (enemy.isDead()) {
                    player.addScore(5000);
                }
                break;
            }
        }
    }
    
    // Collisioni Nemici - Giocatore
    if (!player.isInvulnerable()) {
        for (auto& enemy : enemies) {
            if (enemy.isDead()) continue;
            
            Vec2 enGrid = enemy.getGridPos();
            if (playerGridPos.x == enGrid.x && playerGridPos.y == enGrid.y) {
                if (!player.isJumping()) {
                    player.takeDamage();
                    if (player.getLives() <= 0) {
                        state = STATE_LOSE;
                    }
                }
                break;
            }
        }
    }
    
    // Controllo vittoria
    if (maze.getRemainingDots() == 0) {
        state = STATE_WIN;
    }
}

void Game::render() {
    maze.render(renderer);
    ui.render(renderer, player, maze.getRemainingDots());
    
    player.render(renderer);
    
    for (const auto& enemy : enemies) {
        if (!enemy.isDead()) {
            enemy.render(renderer);
        }
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
    
    SDL_RenderPresent(renderer);
}

void Game::run() {
    while (isRunning) {
        handleEvents();
        update();
        render();
        SDL_Delay(16); // Cap a ~60 FPS
    }
}

void Game::cleanup() {
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
}