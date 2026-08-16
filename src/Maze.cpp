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
// render: disegna l'intero labirinto in stile "dungeon scavato nella roccia".
//
// Per ogni cella:
//   * Muro: disegna un blocco di roccia cavernosa composto da:
//       - Rettangolo base scuro (pietra)
//       - Banda superiore piu' chiara (illuminazione dall'alto)
//       - Banda inferiore molto scura (ombra / fessura con il pavimento)
//       - 3-4 "ciottoli" di roccia piu' chiari in posizioni pseudo-casuali ma
//         deterministiche (hash della cella) per dare texture varia
//       - Piccole crepe nere per dare l'effetto "roccia erosa"
//       - Un paio di muschigli verdi chiari (rarissimi) per profondita'
//   * Pavimento: terra battuta scura con leggere variazioni di colore
//     determinate dalla posizione (hash), per evitare l'effetto "piatto".
//     Aggiunge anche qualche piccola pietra/ciottolo sparso sul pavimento.
//   * Tesoro: pedistallo di pietra + sprite specifica (corona, gemma,
//     forziere, coppa, monete). Tutti i tesori sono costruiti con primitive.
//   * Arma: chiama Weapon::render sul tile (l'arma ha gia' la sua ombra).
//
// Inoltre, dopo aver disegnato tutte le celle, vengono aggiunti:
//   * Torce animate lungo i muri interni del labirinto (una ogni ~6 celle
//     muro adiacenti a una cella vuota), con fiamma a 3 strati e aura.
//   * Urne decorative sul pavimento in posizioni vuote casuali
//     determinate dalla hash della cella.
//
// La posizione y tiene conto dell'offset UI_HEIGHT (la barra in alto).
//
// NOTA: tutte le variazioni procedurali sono deterministiche (derivate da
// una funzione hash delle coordinate della cella), per evitare flickering
// tra un frame e il successivo. Solo le torce sono animate nel tempo
// (fiamma che guizza).
// ---------------------------------------------------------------------------
namespace {
    // Hash 2D deterministico -> [0, 1). Usato per variazioni procedurali
    // stabili su ogni cella (niente flicker tra frame).
    float cellHash(int c, int r) {
        unsigned int h = (unsigned int)(c * 73856093u) ^ (unsigned int)(r * 19349663u);
        h ^= h >> 13;
        h *= 0x5bd1e995u;
        h ^= h >> 15;
        return (float)(h & 0xFFFFu) / 65535.f;
    }
}

void Maze::render(sf::RenderTarget& target) {
    sf::RectangleShape rect(sf::Vector2f(TILE_SIZE, TILE_SIZE));
    sf::Color outline(10, 10, 10);

    // Tempo globale per le animazioni (torce). Static per persistere tra
    // le chiamate di render: ~16 ms per frame a 60 FPS.
    static float animTime = 0.f;
    animTime += 0.016f;

    // Prima passata: celle del labirinto (muri, pavimento, tesori, armi).
    for (int c = 0; c < MAZE_COLS; ++c) {
        for (int r = 0; r < MAZE_ROWS; ++r) {
            rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
            if (grid[c][r].type == CELL_WALL) {
                // --- Muro 3D roccia cavernosa ---
                // Colore base piu' scuro del wallColor (effetto ombra profonda).
                sf::Color baseCol = sf::Color(
                    (sf::Uint8)std::max(0,   wallColor.r - 25),
                    (sf::Uint8)std::max(0,   wallColor.g - 25),
                    (sf::Uint8)std::max(0,   wallColor.b - 25));
                rect.setFillColor(baseCol);
                target.draw(rect);

                // Banda superiore piu' chiara (effetto illuminazione)
                // Colorazione leggermente calda, come luce di torcia.
                rect.setSize(sf::Vector2f(TILE_SIZE, 10.f));
                rect.setFillColor(sf::Color(
                    (sf::Uint8)std::min(255, wallColor.r + 40),
                    (sf::Uint8)std::min(255, wallColor.g + 35),
                    (sf::Uint8)std::min(255, wallColor.b + 25)));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);

                // Banda inferiore molto scura (ombra / fessura col pavimento)
                rect.setSize(sf::Vector2f(TILE_SIZE, 6.f));
                rect.setFillColor(sf::Color(15, 10, 8));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT + TILE_SIZE - 6);
                target.draw(rect);

                // Ciottoli di roccia: 3 macchie chiare in posizioni deterministiche
                // per dare texture rocciosa. La grandezza varia leggermente.
                for (int i = 0; i < 3; i++) {
                    float h1 = cellHash(c * 7 + i, r * 3 + i);
                    float h2 = cellHash(c * 13 + i, r * 5 + i + 7);
                    float h3 = cellHash(c * 3 + i + 11, r * 11 + i + 3);
                    // Posizione dentro la cella (margini di 6 px)
                    float px = c * TILE_SIZE + 6.f + h1 * (TILE_SIZE - 12.f);
                    float py = r * TILE_SIZE + UI_HEIGHT + 12.f + h2 * (TILE_SIZE - 20.f);
                    float radius = 2.5f + h3 * 2.5f;  // 2.5..5
                    // Colore piu' chiaro del base ma piu' scuro della banda alta
                    sf::Uint8 cr = (sf::Uint8)std::min(255, wallColor.r + 15);
                    sf::Uint8 cg = (sf::Uint8)std::min(255, wallColor.g + 12);
                    sf::Uint8 cb = (sf::Uint8)std::min(255, wallColor.b + 8);
                    // Aggiunge una leggera variazione per ogni ciottolo
                    sf::Int8 variation = (sf::Int8)(h3 * 20.f) - 10;
                    cr = (sf::Uint8)std::max(0, std::min(255, (int)cr + variation));
                    cg = (sf::Uint8)std::max(0, std::min(255, (int)cg + variation));
                    cb = (sf::Uint8)std::max(0, std::min(255, (int)cb + variation));
                    sf::CircleShape pebble(radius);
                    pebble.setFillColor(sf::Color(cr, cg, cb));
                    pebble.setPosition(px - radius, py - radius);
                    target.draw(pebble);
                    // Piccolo highlight in alto a sinistra (effetto volumetrico)
                    sf::CircleShape highlight(radius * 0.4f);
                    highlight.setFillColor(sf::Color(
                        (sf::Uint8)std::min(255, (int)cr + 25),
                        (sf::Uint8)std::min(255, (int)cg + 22),
                        (sf::Uint8)std::min(255, (int)cb + 18)));
                    highlight.setPosition(px - radius * 0.6f, py - radius * 0.6f);
                    target.draw(highlight);
                }

                // Crepe nere sottili (1-2 per cella, posizioni deterministiche)
                int numCracks = (cellHash(c + 99, r + 17) > 0.6f) ? 2 : 1;
                for (int i = 0; i < numCracks; i++) {
                    float h1 = cellHash(c * 5 + i + 31, r * 7 + i + 19);
                    float h2 = cellHash(c * 11 + i + 41, r * 2 + i + 73);
                    float cx = c * TILE_SIZE + 4.f + h1 * (TILE_SIZE - 8.f);
                    float cy = r * TILE_SIZE + UI_HEIGHT + 14.f + h2 * (TILE_SIZE - 24.f);
                    // Breve segmento verticale o diagonale
                    float ang = (h1 + h2) * 90.f;
                    sf::RectangleShape crack(sf::Vector2f(2.f, 8.f + h2 * 8.f));
                    crack.setFillColor(sf::Color(5, 5, 5, 200));
                    crack.setOrigin(1.f, crack.getSize().y * 0.5f);
                    crack.setPosition(cx, cy);
                    crack.rotate(ang);
                    target.draw(crack);
                }

                // Muschio verde raro (5% delle celle muro) per dare colore
                if (cellHash(c + 555, r + 333) > 0.95f) {
                    float mx = c * TILE_SIZE + 6.f + cellHash(c, r) * (TILE_SIZE - 12.f);
                    float my = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE - 8.f;
                    sf::CircleShape moss(3.f);
                    moss.setFillColor(sf::Color(50, 90, 40, 200));
                    moss.setPosition(mx - 3.f, my - 3.f);
                    target.draw(moss);
                    moss.setRadius(2.f);
                    moss.setPosition(mx + 4.f, my - 1.f);
                    target.draw(moss);
                }

                // Ripristina dimensione del rettangolo base per il prossimo tile
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE));
            } else {
                // --- Pavimento terra battuta ---
                // Colore base (terra scura). Variazione deterministica per
                // evitare effetto piatto uniforme.
                float v = cellHash(c + 1, r + 1);
                sf::Uint8 fr = (sf::Uint8)(bgColor.r + (v - 0.5f) * 12.f);
                sf::Uint8 fg = (sf::Uint8)(bgColor.g + (v - 0.5f) * 8.f);
                sf::Uint8 fb = (sf::Uint8)(bgColor.b + (v - 0.5f) * 6.f);
                rect.setFillColor(sf::Color(fr, fg, fb));
                target.draw(rect);

                // Piccoli ciottoli sparsi sul pavimento (2-3 per cella)
                int numFloorPebbles = 2 + (int)(cellHash(c + 200, r + 100) * 2.f);
                for (int i = 0; i < numFloorPebbles; i++) {
                    float h1 = cellHash(c * 17 + i + 100, r * 3 + i + 50);
                    float h2 = cellHash(c * 7 + i + 200, r * 13 + i + 70);
                    float h3 = cellHash(c * 23 + i + 1,   r * 11 + i + 13);
                    float px = c * TILE_SIZE + 4.f + h1 * (TILE_SIZE - 8.f);
                    float py = r * TILE_SIZE + UI_HEIGHT + 4.f + h2 * (TILE_SIZE - 8.f);
                    float radius = 1.f + h3 * 1.5f;
                    // Colore grigio-marrone chiaro
                    sf::Uint8 pr = (sf::Uint8)(60 + h3 * 30);
                    sf::Uint8 pg = (sf::Uint8)(50 + h3 * 25);
                    sf::Uint8 pb = (sf::Uint8)(40 + h3 * 18);
                    sf::CircleShape pebble(radius);
                    pebble.setFillColor(sf::Color(pr, pg, pb));
                    pebble.setPosition(px - radius, py - radius);
                    target.draw(pebble);
                }

                // Macchie di terra piu' scura (~15% delle celle pavimento)
                if (cellHash(c + 700, r + 350) > 0.85f) {
                    float h1 = cellHash(c + 800, r + 400);
                    float h2 = cellHash(c + 900, r + 500);
                    float sx = c * TILE_SIZE + 8.f + h1 * (TILE_SIZE - 24.f);
                    float sy = r * TILE_SIZE + UI_HEIGHT + 8.f + h2 * (TILE_SIZE - 24.f);
                    sf::CircleShape stain(4.f + h1 * 3.f);
                    stain.setFillColor(sf::Color(8, 5, 3, 180));
                    stain.setPosition(sx - 4.f, sy - 4.f);
                    target.draw(stain);
                }

                // Centro del tile (usato per tesori/oggetti)
                float cx = c * TILE_SIZE + TILE_SIZE/2.f;
                float cy = r * TILE_SIZE + TILE_SIZE/2.f + UI_HEIGHT;

                if (grid[c][r].type == CELL_TREASURE) {
                    // Pedistallo di pietra ombreggiato che evidenzia il tesoro
                    // Piastrella circolare scura con anello chiaro (effetto altare)
                    sf::CircleShape ped(20.f); ped.setFillColor(sf::Color(30, 30, 30, 150));
                    ped.setPosition(cx-20.f, cy-12.f); target.draw(ped);
                    sf::CircleShape pedRing(18.f); pedRing.setFillColor(sf::Color(0, 0, 0, 0));
                    pedRing.setOutlineThickness(2.f); pedRing.setOutlineColor(sf::Color(120, 100, 80, 200));
                    pedRing.setPosition(cx-18.f, cy-10.f); target.draw(pedRing);

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

    // ===================================================================
    // SECONDA PASSATA: torce animate lungo i muri + urne decorative.
    // Viene fatta dopo le celle cosi' gli elementi decorativi sono sopra
    // i muri/pavimento ma SOTTO i tesori e le armi (che sono sopra tutto).
    //
    // Torce: vengono disegnate sulle celle muro che sono adiacenti a una
    // cella vuota (cosi' la torcia e' visibile dal corridoio) e selezionate
    // con probabilita' deterministica (~1 ogni 6 celle muro adiacenti).
    // Ogni torcia: bastone + cestello + fiamma a 3 strati animata + aura
    // luminosa calda. La direzione della torcia (appesa sopra il muro o
    // laterale) dipende da quale lato del muro e' adiacente al vuoto.
    //
    // Urne: vasi decorativi posizionati sul pavimento in celle vuote
    // casuali (~3% delle celle vuote). Ogni urna: corpo ovoidale + bocca
    // + base + decoro. Varieta' di colori per dare carattere fantasy.
    // ===================================================================

    // Lambda: disegna una torcia animata in posizione (x, y) dove y e' la
    // base del bastone (la fiamma e' sopra).
    auto drawTorch = [&](float x, float yBase, float torchTime) {
        // Aura luminosa calda (grande cerchio semitrasparente)
        sf::CircleShape aura(22.f);
        aura.setFillColor(sf::Color(255, 180, 60, 35));
        aura.setPosition(x - 22.f, yBase - 44.f);
        target.draw(aura);
        sf::CircleShape aura2(14.f);
        aura2.setFillColor(sf::Color(255, 200, 80, 55));
        aura2.setPosition(x - 14.f, yBase - 34.f);
        target.draw(aura2);
        // Bastone della torcia (legno scuro)
        sf::RectangleShape handle(sf::Vector2f(4.f, 12.f));
        handle.setFillColor(sf::Color(60, 30, 10));
        handle.setOutlineThickness(0.8f); handle.setOutlineColor(sf::Color(20, 10, 0));
        handle.setPosition(x - 2.f, yBase - 4.f);
        target.draw(handle);
        // Cestello metallico della fiamma (trapezio rovesciato)
        sf::ConvexShape bracket; bracket.setPointCount(4);
        bracket.setFillColor(sf::Color(80, 70, 60));
        bracket.setOutlineThickness(0.8f); bracket.setOutlineColor(sf::Color(40, 30, 20));
        bracket.setPoint(0, sf::Vector2f(x - 5.f, yBase - 4.f));
        bracket.setPoint(1, sf::Vector2f(x + 5.f, yBase - 4.f));
        bracket.setPoint(2, sf::Vector2f(x + 4.f, yBase - 10.f));
        bracket.setPoint(3, sf::Vector2f(x - 4.f, yBase - 10.f));
        target.draw(bracket);
        // Fiamma animata (3 strati)
        float flicker = sin(torchTime * 18.f + x) * 1.5f;
        float flicker2 = cos(torchTime * 22.f + x * 0.7f) * 1.f;
        // Strato esterno (rosso scuro)
        sf::CircleShape flame3(6.f + flicker);
        flame3.setFillColor(sf::Color(180, 30, 10, 220));
        flame3.setPosition(x - 6.f - flicker * 0.5f, yBase - 24.f + flicker2 * 0.3f);
        target.draw(flame3);
        // Strato medio (arancione)
        sf::CircleShape flame2(4.f + flicker * 0.6f);
        flame2.setFillColor(sf::Color(255, 140, 30, 240));
        flame2.setPosition(x - 4.f - flicker * 0.3f, yBase - 22.f + flicker2 * 0.2f);
        target.draw(flame2);
        // Strato interno (giallo-bianco)
        sf::CircleShape flame1(2.f);
        flame1.setFillColor(sf::Color(255, 240, 180, 250));
        flame1.setPosition(x - 2.f, yBase - 19.f);
        target.draw(flame1);
    };

    // --- Torce lungo i muri ---
    // Per ogni cella muro adiacente a una cella vuota, ~17% di probabilita'
    // (deterministica) di avere una torcia. Posiziona la torcia sul bordo
    // del muro verso la cella vuota.
    for (int c = 1; c < MAZE_COLS - 1; ++c) {
        for (int r = 1; r < MAZE_ROWS - 1; ++r) {
            if (grid[c][r].type != CELL_WALL) continue;
            // Determina quali lati del muro sono adiacenti a una cella vuota.
            bool openUp    = (grid[c][r-1].type != CELL_WALL);
            bool openDown  = (grid[c][r+1].type != CELL_WALL);
            bool openLeft  = (grid[c-1][r].type != CELL_WALL);
            bool openRight = (grid[c+1][r].type != CELL_WALL);
            // Almeno un lato aperto: e' un muro "di confine" col corridoio.
            if (!openUp && !openDown && !openLeft && !openRight) continue;
            // Soglia deterministica: ~17% dei muri di confine hanno una torcia
            float torchChance = cellHash(c + 1111, r + 2222);
            if (torchChance > 0.17f) continue;

            // Centro del muro
            float mcx = c * TILE_SIZE + TILE_SIZE / 2.f;
            float mcy = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;

            // Sceglie il lato preferenziale: prio Orizzontali (su/giu) per
            // avere torce piu' visibili dal corridoio. Se il muro e' aperto
            // solo lateralmente, usa il lato laterale.
            if (openDown) {
                // Torcia appesa SOTTO il centro del muro (fiamma punta in su,
                // verso il corridoio inferiore). yBase = bordo inferiore del
                // muro, dove il bastone sporge di 4 px nel corridoio.
                float yBase = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE + 4.f;
                drawTorch(mcx, yBase, animTime);
            } else if (openUp) {
                // Torcia appesa Sopra il centro del muro (fiamma punta in su,
                // nel corridoio superiore). yBase = bordo superiore del muro.
                float yBase = r * TILE_SIZE + UI_HEIGHT - 4.f;
                drawTorch(mcx, yBase, animTime);
            } else if (openRight) {
                // Torcia laterale sul lato destro del muro
                float x = (c + 1) * TILE_SIZE + 4.f;
                float yBase = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
                drawTorch(x, yBase, animTime);
            } else if (openLeft) {
                // Torcia laterale sul lato sinistro del muro
                float x = c * TILE_SIZE - 4.f;
                float yBase = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
                drawTorch(x, yBase, animTime);
            }
        }
    }

    // --- Urne decorative sul pavimento ---
    // Vasi ornati posizionati in celle vuote casuali (~2.5% delle celle
    // vuote). Solo celle che non sono tesori/armi. Le urne sono puramente
    // decorative: non bloccano il movimento ne' sono raccoglibili.
    auto drawUrn = [&](float cx, float cy) {
        // Varieta' di colori determinata dalla hash della cella
        // (le urne hanno 3 varianti: pietra grigia, bronzo, marmo scuro).
        // Recuperiamo la hash dalla posizione approssimativa della cella.
        int cellC = (int)(cx / TILE_SIZE);
        int cellR = (int)((cy - UI_HEIGHT) / TILE_SIZE);
        float urnHash = cellHash(cellC + 333, cellR + 777);
        sf::Color urnCol, urnDark, urnLight, urnDecor;
        if (urnHash < 0.33f) {
            // Pietra grigia
            urnCol   = sf::Color(110, 105, 100);
            urnDark  = sf::Color(70, 65, 60);
            urnLight = sf::Color(170, 165, 160);
            urnDecor = sf::Color(180, 140, 60);  // decoro dorato
        } else if (urnHash < 0.66f) {
            // Bronzo
            urnCol   = sf::Color(120, 90, 50);
            urnDark  = sf::Color(70, 50, 25);
            urnLight = sf::Color(180, 140, 80);
            urnDecor = sf::Color(80, 30, 20);  // decoro rosso scuro
        } else {
            // Marmo scuro
            urnCol   = sf::Color(60, 55, 70);
            urnDark  = sf::Color(30, 25, 40);
            urnLight = sf::Color(100, 95, 110);
            urnDecor = sf::Color(220, 200, 80);  // decoro oro chiaro
        }
        sf::Color outlineUrn(20, 15, 10);

        // Ombra a terra morbida
        sf::CircleShape urnShadow(12.f);
        urnShadow.setFillColor(sf::Color(0, 0, 0, 120));
        urnShadow.setPosition(cx - 12.f, cy + 8.f);
        target.draw(urnShadow);

        // Base dell'urna (rettangolo piu' largo in basso)
        sf::RectangleShape base(sf::Vector2f(14.f, 3.f));
        base.setFillColor(urnDark);
        base.setOutlineThickness(0.8f); base.setOutlineColor(outlineUrn);
        base.setPosition(cx - 7.f, cy + 6.f);
        target.draw(base);

        // Corpo ovoidale (ConvexShape a 4 punti: stretto in alto/basso,
        // largo al centro - effetto vaso).
        sf::ConvexShape body; body.setPointCount(4);
        body.setFillColor(urnCol);
        body.setOutlineThickness(1.f); body.setOutlineColor(outlineUrn);
        body.setPoint(0, sf::Vector2f(cx - 4.f, cy - 6.f));   // alto sx
        body.setPoint(1, sf::Vector2f(cx + 4.f, cy - 6.f));   // alto dx
        body.setPoint(2, sf::Vector2f(cx + 8.f, cy + 2.f));   // centro dx (largo)
        body.setPoint(3, sf::Vector2f(cx - 8.f, cy + 2.f));   // centro sx (largo)
        target.draw(body);
        // Parte inferiore del corpo (restringimento verso la base)
        sf::ConvexShape bodyBot; bodyBot.setPointCount(4);
        bodyBot.setFillColor(urnCol);
        bodyBot.setOutlineThickness(1.f); bodyBot.setOutlineColor(outlineUrn);
        bodyBot.setPoint(0, sf::Vector2f(cx - 8.f, cy + 2.f));
        bodyBot.setPoint(1, sf::Vector2f(cx + 8.f, cy + 2.f));
        bodyBot.setPoint(2, sf::Vector2f(cx + 5.f, cy + 6.f));
        bodyBot.setPoint(3, sf::Vector2f(cx - 5.f, cy + 6.f));
        target.draw(bodyBot);

        // Highlight verticale (riflesso luce sul lato sinistro del corpo)
        sf::RectangleShape highlight(sf::Vector2f(1.5f, 10.f));
        highlight.setFillColor(urnLight);
        highlight.setPosition(cx - 5.f, cy - 5.f);
        target.draw(highlight);

        // Bocca dell'urna (apertura superiore)
        sf::RectangleShape mouth(sf::Vector2f(6.f, 2.f));
        mouth.setFillColor(urnDark);
        mouth.setOutlineThickness(0.5f); mouth.setOutlineColor(outlineUrn);
        mouth.setPosition(cx - 3.f, cy - 8.f);
        target.draw(mouth);
        // Bordo della bocca (cornicetta)
        sf::RectangleShape rim(sf::Vector2f(8.f, 1.5f));
        rim.setFillColor(urnLight);
        rim.setOutlineThickness(0.5f); rim.setOutlineColor(outlineUrn);
        rim.setPosition(cx - 4.f, cy - 9.f);
        target.draw(rim);

        // Decoro centrale (striscia orizzontale colorata)
        sf::RectangleShape decor(sf::Vector2f(10.f, 1.5f));
        decor.setFillColor(urnDecor);
        decor.setPosition(cx - 5.f, cy - 1.f);
        target.draw(decor);
        // Piccolo simbolo centrale (rombo)
        sf::ConvexShape symbol; symbol.setPointCount(4);
        symbol.setFillColor(urnDecor);
        symbol.setPoint(0, sf::Vector2f(cx, cy - 1.f));
        symbol.setPoint(1, sf::Vector2f(cx + 2.f, cy + 0.5f));
        symbol.setPoint(2, sf::Vector2f(cx, cy + 2.f));
        symbol.setPoint(3, sf::Vector2f(cx - 2.f, cy + 0.5f));
        target.draw(symbol);
    };

    // Posiziona urne in celle vuote selezionate deterministicamente (~2.5%)
    for (int c = 1; c < MAZE_COLS - 1; ++c) {
        for (int r = 1; r < MAZE_ROWS - 1; ++r) {
            if (grid[c][r].type != CELL_EMPTY) continue;
            // Esclude celle adiacenti alla posizione di partenza del player
            // (cella 1,1) per non ostacolare visivamente l'inizio.
            if (c <= 2 && r <= 2) continue;
            // 2.5% delle celle vuote
            if (cellHash(c + 5000, r + 6000) > 0.025f) continue;
            float cx = c * TILE_SIZE + TILE_SIZE / 2.f;
            float cy = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            drawUrn(cx, cy);
        }
    }
}
