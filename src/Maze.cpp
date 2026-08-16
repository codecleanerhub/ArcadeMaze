#include "Maze.h"
#include <cstdlib>
#include <algorithm>
#include <random>

// ===========================================================================
// Maze.cpp - Implementazione del labirinto.
//
// Algoritmo di generazione:
//   1. Parte con tutte le celle a muro.
//   2. Esegue una DFS iterativa ("recursive backtracker") che scava
//      passaggi muovendosi di 2 celle alla volta, lasciando un muro ogni 2.
//   3. Aggiunge ~15 passaggi extra dove il muro ha esattamente 2 vicini
//      muro, per creare anelli nel labirinto (no percorsi unici).
//   4. Raccoglie tutte le celle vuote, le mischia e ne sceglie:
//        - 8 come tesori
//        - 5 come armi casuali
//   5. Assegna colori casuali ai muri (variazione 40..90 per canale RGB).
// ===========================================================================

// Costruttore: inizializza la griglia e genera subito un labirinto, cosi'
// l'oggetto e' sempre in stato valido anche prima di un esplicito generate().
Maze::Maze() {
    grid.resize(MAZE_COLS, std::vector<Cell>(MAZE_ROWS));
    generate();
}

// ---------------------------------------------------------------------------
// generate: rigenera completamente il labirinto come descritto in testa al
// file. Non restituisce nulla; modifica `grid`, `wallColor` e `bgColor`.
// ---------------------------------------------------------------------------
void Maze::generate() {
    // 1) Riempi tutto di muri (punto di partenza).
    for (int c = 0; c < MAZE_COLS; ++c)
        for (int r = 0; r < MAZE_ROWS; ++r)
            grid[c][r].type = CELL_WALL;

    // 2) DFS iterativa con stack esplicito (niente ricorsione per evitare
    //    stack overflow su griglie grandi). Le direzioni usano passo 2
    //    per scavare un muro si e lasciarne uno no: pattern classico dei
    //    labirinti "perfect maze".
    std::vector<Vec2> stack;
    grid[1][1].type = CELL_EMPTY;  // cella di partenza
    stack.push_back({1, 1});
    // delta col/row per le 4 direzioni (su, destra, giu, sinistra) con passo 2
    int dc[] = {0, 2, 0, -2}, dr[] = {-2, 0, 2, 0};

    while (!stack.empty()) {
        Vec2 curr = stack.back();
        std::vector<int> neighbors;
        // Cerca direzioni valide: cella destinazione ancora muro e in griglia.
        for (int i = 0; i < 4; ++i) {
            int nc = curr.x + dc[i], nr = curr.y + dr[i];
            if (nc > 0 && nc < MAZE_COLS - 1 && nr > 0 && nr < MAZE_ROWS - 1 && grid[nc][nr].type == CELL_WALL) neighbors.push_back(i);
        }
        if (!neighbors.empty()) {
            // Sceglie una direzione casuale, scava il muro intermedio (a meta'
            // percorso) e la cella destinazione, poi prosegue la DFS.
            int dir = neighbors[rand() % neighbors.size()];
            grid[curr.x + dc[dir]/2][curr.y + dr[dir]/2].type = CELL_EMPTY;
            grid[curr.x + dc[dir]][curr.y + dr[dir]].type = CELL_EMPTY;
            stack.push_back({curr.x + dc[dir], curr.y + dr[dir]});
        } else stack.pop_back();  // backtracking: nessun vicino disponibile
    }

    // 3) Apertura extra: 15 muri isolati (con esattamente 2 vicini muro)
    //    vengono trasformati in pavimento. Questo crea dei cicli nel
    //    labirinto e lo rende meno "a senso unico", piu' godibile.
    for (int i = 0; i < 15; ++i) {
        int c = 1 + rand() % (MAZE_COLS - 2), r = 1 + rand() % (MAZE_ROWS - 2);
        if (grid[c][r].type == CELL_WALL && countNeighboringWalls(c, r) == 2) grid[c][r].type = CELL_EMPTY;
    }

    // 4) Posiziona tesori e armi in celle vuote casuali.
    //    Raccogliamo tutte le celle vuote in un vettore, lo mischiamo con
    //    un PRNG (mt19937 + random_device) per avere una distribuzione
    //    uniforme, e preleviamo dai primi elementi.
    std::vector<Vec2> emptyCells;
    for (int c = 1; c < MAZE_COLS - 1; ++c)
        for (int r = 1; r < MAZE_ROWS - 1; ++r)
            if (grid[c][r].type == CELL_EMPTY) emptyCells.push_back({c, r});

    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(emptyCells.begin(), emptyCells.end(), g);

    // 8 tesori, tipo casuale (solo estetica).
    for(int i=0; i<8 && !emptyCells.empty(); i++) {
        Vec2 p = emptyCells.back(); emptyCells.pop_back();
        grid[p.x][p.y].type = CELL_TREASURE;
        grid[p.x][p.y].treasure = static_cast<TreasureType>(rand() % 5);
    }
    // 5 armi casuali (potere e munizioni decisi dalla factory di Weapon).
    for(int i=0; i<5 && !emptyCells.empty(); i++) {
        Vec2 p = emptyCells.back(); emptyCells.pop_back();
        grid[p.x][p.y].type = CELL_WEAPON;
        grid[p.x][p.y].weapon = Weapon::generateRandom();
    }

    // 5) Colori: muri con toni grigi casuali (40..90 per canale), sfondo
    //    fisso scuro. La variazione cromatica dei muri fa percepire ogni
    //    livello come diverso anche se la struttura e' simile.
    wallColor = sf::Color(rand() % 50 + 40, rand() % 50 + 40, rand() % 50 + 40);
    bgColor = sf::Color(15, 15, 15);
}

// Conta i muri tra le 4 celle ortogonalmente adiacenti a (c, r).
// Non effettua controlli sui bordi: viene chiamato solo su celle interne.
int Maze::countNeighboringWalls(int c, int r) {
    int count = 0;
    if (grid[c-1][r].type == CELL_WALL) count++;
    if (grid[c+1][r].type == CELL_WALL) count++;
    if (grid[c][r-1].type == CELL_WALL) count++;
    if (grid[c][r+1].type == CELL_WALL) count++;
    return count;
}

// True se la cella e' muro o fuori dalla griglia (considerata come muro).
// Utilizzato da player, nemici e proiettili per il collision detection.
bool Maze::isWall(int col, int row) {
    if (col < 0 || col >= MAZE_COLS || row < 0 || row >= MAZE_ROWS) return true;
    return grid[col][row].type == CELL_WALL;
}

// Tipo della cella (con trattamento "muro" per le coordinate fuori griglia).
CellType Maze::getCellType(int col, int row) {
    if (col < 0 || col >= MAZE_COLS || row < 0 || row >= MAZE_ROWS) return CELL_WALL;
    return grid[col][row].type;
}

// Raccoglie l'arma dalla cella e la resetta a EMPTY. Il chiamante deve
// gia' sapere che la cella e' di tipo CELL_WEAPON (altrimenti restituisce
// un Weapon con valori casuali non inizializzati - da evitare).
Weapon Maze::collectWeapon(int col, int row) {
    Weapon w = grid[col][row].weapon;
    grid[col][row].type = CELL_EMPTY;
    return w;
}

// Raccoglie il tesoro: segna la cella come EMPTY. Il tipo di tesoro non
// influenza il punteggio (sempre 10000, deciso dal chiamante in Player).
void Maze::collectTreasure(int col, int row) { grid[col][row].type = CELL_EMPTY; }

// Conta i tesori rimasti nel labirinto. Quando arriva a 0, Game attiva
// la transizione alla stanza del boss. Costo: O(cols*rows), ma la griglia
// e' piccola (21x19=399) e la scansione e' trascurabile.
int Maze::getRemainingTreasures() {
    int count = 0;
    for (int c = 0; c < MAZE_COLS; ++c)
        for (int r = 0; r < MAZE_ROWS; ++r)
            if (grid[c][r].type == CELL_TREASURE) count++;
    return count;
}

// ---------------------------------------------------------------------------
// render: disegna l'intero labirinto.
//
// Per ogni cella:
//   * Muro: disegna un rettangolo colorato con due bande orizzontali
//     (sopra piu' chiara, sotto piu' scura) per simulare un effetto 3D
//     "pietra". Questo pattern e' molto economico (3 draw per cella) ma
//     dà profondita' ai muri senza usare texture.
//   * Pavimento: rettangolo piatto del colore `bgColor`.
//   * Tesoro: pedistallo scuro + sprite specifica (corona, gemma, forziere,
//     coppa, monete). Tutti i tesori sono costruiti con primitive SFML.
//   * Arma: chiama Weapon::render sul tile (l'arma ha gia' la sua ombra).
//
// La posizione y tiene conto dell'offset UI_HEIGHT (la barra in alto).
// ---------------------------------------------------------------------------
void Maze::render(sf::RenderTarget& target) {
    sf::RectangleShape rect(sf::Vector2f(TILE_SIZE, TILE_SIZE));
    sf::Color outline(10, 10, 10);

    for (int c = 0; c < MAZE_COLS; ++c) {
        for (int r = 0; r < MAZE_ROWS; ++r) {
            rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
            if (grid[c][r].type == CELL_WALL) {
                // --- Muro 3D pietra ---
                // Rettangolo base
                rect.setFillColor(wallColor);
                target.draw(rect);
                // Banda superiore piu' chiara (effetto illuminazione)
                rect.setSize(sf::Vector2f(TILE_SIZE, 8.f));
                rect.setFillColor(sf::Color(wallColor.r + 30, wallColor.g + 30, wallColor.b + 30));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);
                // Banda inferiore piu' scura (ombra)
                rect.setSize(sf::Vector2f(TILE_SIZE, 8.f));
                rect.setFillColor(sf::Color(wallColor.r - 20, wallColor.g - 20, wallColor.b - 20));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT + TILE_SIZE - 8);
                target.draw(rect);
                // Ripristina dimensione del rettangolo base per il prossimo tile
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE));
            } else {
                // Pavimento piatto
                rect.setFillColor(bgColor);
                target.draw(rect);

                // Centro del tile (usato per tesori/oggetti)
                float cx = c * TILE_SIZE + TILE_SIZE/2.f;
                float cy = r * TILE_SIZE + TILE_SIZE/2.f + UI_HEIGHT;

                if (grid[c][r].type == CELL_TREASURE) {
                    // Pedistallo ombreggiato che evidenzia il tesoro
                    sf::CircleShape ped(20.f); ped.setFillColor(sf::Color(30, 30, 30, 150));
                    ped.setPosition(cx-20.f, cy-12.f); target.draw(ped);

                    if (grid[c][r].treasure == TRES_CROWN) {
                        // Corona: base + 3 punte + gemme rosse/blu
                        sf::RectangleShape base(sf::Vector2f(28.f, 8.f)); base.setFillColor(sf::Color(255, 215, 0)); base.setOutlineThickness(1.5f); base.setOutlineColor(outline);
                        base.setPosition(cx-14.f, cy+4.f); target.draw(base);
                        sf::RectangleShape s1(sf::Vector2f(6.f, 8.f)); s1.setFillColor(sf::Color(255, 215, 0)); s1.setOutlineThickness(1.f); s1.setOutlineColor(outline);
                        s1.setPosition(cx-14.f, cy-2.f); target.draw(s1);
                        s1.setSize(sf::Vector2f(6.f, 14.f)); s1.setPosition(cx-3.f, cy-8.f); target.draw(s1);
                        s1.setSize(sf::Vector2f(6.f, 8.f)); s1.setPosition(cx+8.f, cy-2.f); target.draw(s1);
                        // Gemme decorative
                        sf::CircleShape gem(2.f); gem.setFillColor(sf::Color::Red);
                        gem.setPosition(cx-12.f, cy+4.f); target.draw(gem);
                        gem.setFillColor(sf::Color::Blue);
                        gem.setPosition(cx+10.f, cy+4.f); target.draw(gem);
                    }
                    else if (grid[c][r].treasure == TRES_GEM) {
                        // Gemma ciano con alone luminoso e riflesso bianco
                        sf::CircleShape glow(16.f); glow.setFillColor(sf::Color(0, 255, 255, 50));
                        glow.setPosition(cx-16.f, cy-16.f); target.draw(glow);

                        sf::ConvexShape gem; gem.setPointCount(4);
                        gem.setFillColor(sf::Color(0, 255, 255)); gem.setOutlineThickness(1.5f); gem.setOutlineColor(outline);
                        gem.setPoint(0, sf::Vector2f(cx, cy-16)); gem.setPoint(1, sf::Vector2f(cx+12, cy));
                        gem.setPoint(2, sf::Vector2f(cx, cy+16)); gem.setPoint(3, sf::Vector2f(cx-12, cy));
                        target.draw(gem);
                        // riflesso (piccolo triangolo bianco)
                        sf::ConvexShape gleam; gleam.setPointCount(3);
                        gleam.setFillColor(sf::Color(255, 255, 255));
                        gleam.setPoint(0, sf::Vector2f(cx-4, cy-8)); gleam.setPoint(1, sf::Vector2f(cx, cy-12)); gleam.setPoint(2, sf::Vector2f(cx-8, cy));
                        target.draw(gleam);
                    }
                    else if (grid[c][r].treasure == TRES_CHEST) {
                        // Forziere: corpo + coperchio + bande metalliche + lucchetto
                        sf::RectangleShape body(sf::Vector2f(28.f, 18.f)); body.setFillColor(sf::Color(139, 69, 19)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
                        body.setPosition(cx-14.f, cy-4.f); target.draw(body);
                        sf::RectangleShape top(sf::Vector2f(28.f, 6.f)); top.setFillColor(sf::Color(100, 50, 10)); top.setOutlineThickness(1.f); top.setOutlineColor(outline);
                        top.setPosition(cx-14.f, cy-10.f); target.draw(top);
                        sf::RectangleShape band1(sf::Vector2f(2.f, 18.f)); band1.setFillColor(sf::Color(200, 200, 200));
                        band1.setPosition(cx-8.f, cy-4.f); target.draw(band1);
                        band1.setPosition(cx+6.f, cy-4.f); target.draw(band1);
                        sf::RectangleShape lock(sf::Vector2f(6.f, 6.f)); lock.setFillColor(sf::Color(255, 215, 0));
                        lock.setPosition(cx-3.f, cy-2.f); target.draw(lock);
                    }
                    else if (grid[c][r].treasure == TRES_CUP) {
                        // Coppa d'oro: calice + stelo + base + gemma
                        sf::RectangleShape cup(sf::Vector2f(16.f, 12.f)); cup.setFillColor(sf::Color(255, 215, 0)); cup.setOutlineThickness(1.5f); cup.setOutlineColor(outline);
                        cup.setPosition(cx-8.f, cy-8.f); target.draw(cup);
                        sf::RectangleShape stand(sf::Vector2f(6.f, 4.f)); stand.setFillColor(sf::Color(200, 180, 0));
                        stand.setPosition(cx-3.f, cy+4.f); target.draw(stand);
                        sf::RectangleShape base(sf::Vector2f(16.f, 4.f)); base.setFillColor(sf::Color(255, 215, 0)); base.setOutlineThickness(1.f); base.setOutlineColor(outline);
                        base.setPosition(cx-8.f, cy+8.f); target.draw(base);
                        sf::CircleShape gem(3.f); gem.setFillColor(sf::Color::Red);
                        gem.setPosition(cx-3.f, cy-4.f); target.draw(gem);
                    }
                    else if (grid[c][r].treasure == TRES_GOLD) {
                        // Pila di monete d'oro
                        sf::CircleShape coin1(8.f); coin1.setFillColor(sf::Color(255, 215, 0)); coin1.setOutlineThickness(1.f); coin1.setOutlineColor(outline);
                        coin1.setPosition(cx-12.f, cy+4.f); target.draw(coin1);
                        sf::CircleShape coin2(8.f); coin2.setFillColor(sf::Color(255, 235, 50)); coin2.setOutlineThickness(1.f); coin2.setOutlineColor(outline);
                        coin2.setPosition(cx+2.f, cy+4.f); target.draw(coin2);
                        sf::CircleShape coin3(10.f); coin3.setFillColor(sf::Color(255, 255, 100)); coin3.setOutlineThickness(1.f); coin3.setOutlineColor(outline);
                        coin3.setPosition(cx-5.f, cy-6.f); target.draw(coin3);
                    }
                } else if (grid[c][r].type == CELL_WEAPON) {
                    // Arma a terra: delega a Weapon::render
                    grid[c][r].weapon.render(target, c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                }
            }
        }
    }
}
