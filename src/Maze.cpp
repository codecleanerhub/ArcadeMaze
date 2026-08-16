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
                // --- Muro 3D roccioso (pietra compatta, non porosa) ---
                // Lo stile e' "roccia massiccia": superficie piu' solida possibile
                // con poche variazioni, banda superiore chiara (illuminazione
                // dall'alto), banda inferiore scura (fessura col pavimento) e
                // al massimo UN piccolo ciottolo di colore uniforme per cella.
                // Niente crepe multiple ne' macchie chiare sparse: la roccia
                // deve sembrare compatta, non "buchi porosi".

                // Colore base = wallColor scurito (effetto ombra profonda)
                sf::Color baseCol = sf::Color(
                    (sf::Uint8)std::max(0,   wallColor.r - 18),
                    (sf::Uint8)std::max(0,   wallColor.g - 18),
                    (sf::Uint8)std::max(0,   wallColor.b - 18));
                rect.setFillColor(baseCol);
                target.draw(rect);

                // Banda superiore piu' chiara (illuminazione calda da torcia)
                rect.setSize(sf::Vector2f(TILE_SIZE, 8.f));
                rect.setFillColor(sf::Color(
                    (sf::Uint8)std::min(255, wallColor.r + 30),
                    (sf::Uint8)std::min(255, wallColor.g + 24),
                    (sf::Uint8)std::min(255, wallColor.b + 18)));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);

                // Sottile striscia di luce ancora piu' chiara sul bordo superiore
                // (effetto "taglio di luce" che evidenzia il top del muro)
                rect.setSize(sf::Vector2f(TILE_SIZE, 2.f));
                rect.setFillColor(sf::Color(
                    (sf::Uint8)std::min(255, wallColor.r + 55),
                    (sf::Uint8)std::min(255, wallColor.g + 45),
                    (sf::Uint8)std::min(255, wallColor.b + 35)));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);

                // Banda inferiore molto scura (ombra / fessura col pavimento)
                rect.setSize(sf::Vector2f(TILE_SIZE, 5.f));
                rect.setFillColor(sf::Color(12, 8, 6));
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT + TILE_SIZE - 5);
                target.draw(rect);

                // Piccola variazione di tonalita' sulla superficie (deterministica):
                // UN solo "ciottolo" per cella, grande e molto sfumato, per dare
                // l'impressione di una pietra leggermente irregolare senza
                // buchi porosi.
                {
                    float h1 = cellHash(c * 7 + 1, r * 3 + 1);
                    float h2 = cellHash(c * 13 + 1, r * 5 + 7);
                    float px = c * TILE_SIZE + 8.f + h1 * (TILE_SIZE - 16.f);
                    float py = r * TILE_SIZE + UI_HEIGHT + 14.f + h2 * (TILE_SIZE - 24.f);
                    float radius = 4.f;  // fisso, niente variazioni estreme
                    sf::Uint8 cr = (sf::Uint8)std::min(255, wallColor.r + 8);
                    sf::Uint8 cg = (sf::Uint8)std::min(255, wallColor.g + 6);
                    sf::Uint8 cb = (sf::Uint8)std::min(255, wallColor.b + 4);
                    sf::CircleShape pebble(radius);
                    pebble.setFillColor(sf::Color(cr, cg, cb, 180));
                    pebble.setPosition(px - radius, py - radius);
                    target.draw(pebble);
                    // Highlight leggero (effetto volumetrico morbido)
                    sf::CircleShape highlight(radius * 0.5f);
                    highlight.setFillColor(sf::Color(
                        (sf::Uint8)std::min(255, (int)cr + 20),
                        (sf::Uint8)std::min(255, (int)cg + 18),
                        (sf::Uint8)std::min(255, (int)cb + 14), 200));
                    highlight.setPosition(px - radius * 0.6f, py - radius * 0.6f);
                    target.draw(highlight);
                }

                // Singola crepa rara (~12% delle celle muro), sottile e corta:
                // sufficiente per dare carattere senza sembrare "poroso".
                if (cellHash(c + 99, r + 17) > 0.88f) {
                    float h1 = cellHash(c * 5 + 31, r * 7 + 19);
                    float cx = c * TILE_SIZE + 8.f + h1 * (TILE_SIZE - 16.f);
                    float cy = r * TILE_SIZE + UI_HEIGHT + 18.f;
                    float ang = (h1 - 0.5f) * 60.f;
                    sf::RectangleShape crack(sf::Vector2f(1.2f, 6.f));
                    crack.setFillColor(sf::Color(5, 5, 5, 180));
                    crack.setOrigin(0.6f, crack.getSize().y * 0.5f);
                    crack.setPosition(cx, cy);
                    crack.rotate(ang);
                    target.draw(crack);
                }

                // Muschio verde molto raro (~3% delle celle muro) per variazione
                // cromatica: solo alla base del muro (effetto umidita' di fondo).
                if (cellHash(c + 555, r + 333) > 0.97f) {
                    float mx = c * TILE_SIZE + 6.f + cellHash(c, r) * (TILE_SIZE - 12.f);
                    float my = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE - 6.f;
                    sf::CircleShape moss(2.5f);
                    moss.setFillColor(sf::Color(50, 90, 40, 200));
                    moss.setPosition(mx - 2.5f, my - 2.5f);
                    target.draw(moss);
                }

                // Ripristina dimensione del rettangolo base per il prossimo tile
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE));
            } else {
                // --- Pavimento terriccio da dungeon ---
                // Colore base terriccio scuro (terra battuta bruna) con
                // variazione deterministica di tonalita' per evitare piattezza.
                // Rispetto al vecchio pavimento: tinta piu' calda (marrone
                // terroso invece di grigio scuro), texture piu' omogenea.
                float v = cellHash(c + 1, r + 1);
                // Base terriccio: R alto, G medio, B basso (marrone caldo)
                sf::Uint8 fr = (sf::Uint8)std::max(0, std::min(255, (int)(45 + (v - 0.5f) * 14.f)));
                sf::Uint8 fg = (sf::Uint8)std::max(0, std::min(255, (int)(30 + (v - 0.5f) * 10.f)));
                sf::Uint8 fb = (sf::Uint8)std::max(0, std::min(255, (int)(20 + (v - 0.5f) *  7.f)));
                rect.setFillColor(sf::Color(fr, fg, fb));
                target.draw(rect);

                // Piccole crepe di terra (terriccio seccato): 1-2 sottilissime
                // linee scure per cella, posizioni deterministiche. Danno
                // l'idea di terra battuta senza diventare "buche".
                int numFloorCracks = 1 + (int)(cellHash(c + 50, r + 25) * 2.f);
                for (int i = 0; i < numFloorCracks; i++) {
                    float h1 = cellHash(c * 17 + i + 100, r * 3 + i + 50);
                    float h2 = cellHash(c * 7 + i + 200, r * 13 + i + 70);
                    float px = c * TILE_SIZE + 6.f + h1 * (TILE_SIZE - 12.f);
                    float py = r * TILE_SIZE + UI_HEIGHT + 6.f + h2 * (TILE_SIZE - 12.f);
                    float ang = (h1 - 0.5f) * 40.f;
                    sf::RectangleShape crack(sf::Vector2f(0.8f, 5.f + h2 * 4.f));
                    crack.setFillColor(sf::Color(15, 8, 4, 160));
                    crack.setOrigin(0.4f, crack.getSize().y * 0.5f);
                    crack.setPosition(px, py);
                    crack.rotate(ang);
                    target.draw(crack);
                }

                // Piccoli sassolini sparsi sul terriccio (~1-2 per cella)
                int numFloorPebbles = 1 + (int)(cellHash(c + 200, r + 100) * 2.f);
                for (int i = 0; i < numFloorPebbles; i++) {
                    float h1 = cellHash(c * 17 + i + 100, r * 3 + i + 50);
                    float h2 = cellHash(c * 7 + i + 200, r * 13 + i + 70);
                    float h3 = cellHash(c * 23 + i + 1,   r * 11 + i + 13);
                    float px = c * TILE_SIZE + 4.f + h1 * (TILE_SIZE - 8.f);
                    float py = r * TILE_SIZE + UI_HEIGHT + 4.f + h2 * (TILE_SIZE - 8.f);
                    float radius = 1.2f + h3 * 1.2f;
                    // Colore grigio-marrone chiaro (sassolini)
                    sf::Uint8 pr = (sf::Uint8)(95 + h3 * 30);
                    sf::Uint8 pg = (sf::Uint8)(80 + h3 * 25);
                    sf::Uint8 pb = (sf::Uint8)(60 + h3 * 18);
                    sf::CircleShape pebble(radius);
                    pebble.setFillColor(sf::Color(pr, pg, pb));
                    pebble.setPosition(px - radius, py - radius);
                    target.draw(pebble);
                }

                // Macchie di terra piu' scura (~12% delle celle pavimento):
                // piccoli avvallamenti che sembrano umidita' / terriccio
                // accumulato, non buchi profondi.
                if (cellHash(c + 700, r + 350) > 0.88f) {
                    float h1 = cellHash(c + 800, r + 400);
                    float h2 = cellHash(c + 900, r + 500);
                    float sx = c * TILE_SIZE + 8.f + h1 * (TILE_SIZE - 24.f);
                    float sy = r * TILE_SIZE + UI_HEIGHT + 8.f + h2 * (TILE_SIZE - 24.f);
                    sf::CircleShape stain(3.f + h1 * 2.f);
                    stain.setFillColor(sf::Color(20, 12, 6, 140));
                    stain.setPosition(sx - 3.f, sy - 3.f);
                    target.draw(stain);
                }

                // Centro del tile (usato per tesori/oggetti)
                float cx = c * TILE_SIZE + TILE_SIZE/2.f;
                float cy = r * TILE_SIZE + TILE_SIZE/2.f + UI_HEIGHT;

                if (grid[c][r].type == CELL_TREASURE) {
                    // --- Pedistallo di pietra elaborato (altare) ---
                    // Piastra ovale scura ai piedi del tesoro + cornicetta dorata
                    // decorativa che evidenzia il tesoro come oggetto prezioso.
                    // Ombra morbida a terra
                    sf::CircleShape shadow(18.f);
                    shadow.setFillColor(sf::Color(0, 0, 0, 100));
                    shadow.setPosition(cx - 18.f, cy + 6.f);
                    target.draw(shadow);
                    // Piastra di base (rettangolare, pietra scura)
                    sf::RectangleShape pedestalBase(sf::Vector2f(30.f, 4.f));
                    pedestalBase.setFillColor(sf::Color(60, 50, 40));
                    pedestalBase.setOutlineThickness(0.8f);
                    pedestalBase.setOutlineColor(sf::Color(20, 15, 10));
                    pedestalBase.setPosition(cx - 15.f, cy + 10.f);
                    target.draw(pedestalBase);
                    // Decorazione dorata del piedistallo (cornicetta)
                    sf::RectangleShape pedestalTrim(sf::Vector2f(32.f, 1.5f));
                    pedestalTrim.setFillColor(sf::Color(200, 160, 60));
                    pedestalTrim.setPosition(cx - 16.f, cy + 9.f);
                    target.draw(pedestalTrim);

                    if (grid[c][r].treasure == TRES_CROWN) {
                        // === Corona reale dettagliata (piu' grande) ===
                        // Sotto-corpo (basamento della corona)
                        sf::RectangleShape crownBase(sf::Vector2f(34.f, 8.f));
                        crownBase.setFillColor(sf::Color(180, 130, 30));
                        crownBase.setOutlineThickness(1.5f); crownBase.setOutlineColor(outline);
                        crownBase.setPosition(cx - 17.f, cy + 2.f);
                        target.draw(crownBase);
                        // Strato dorato superiore della base (riflesso)
                        sf::RectangleShape crownTop(sf::Vector2f(34.f, 4.f));
                        crownTop.setFillColor(sf::Color(255, 215, 0));
                        crownTop.setOutlineThickness(1.f); crownTop.setOutlineColor(outline);
                        crownTop.setPosition(cx - 17.f, cy + 2.f);
                        target.draw(crownTop);
                        // Riflesso cromatico superiore (striscia chiara)
                        sf::RectangleShape crownRef(sf::Vector2f(28.f, 1.2f));
                        crownRef.setFillColor(sf::Color(255, 245, 150));
                        crownRef.setPosition(cx - 14.f, cy + 2.5f);
                        target.draw(crownRef);

                        // 5 punte della corona (rette, non coniche per non sforare)
                        // Posizionate lungo il bordo superiore della base
                        float tipPositions[5] = {-15.f, -7.f, 0.f, 7.f, 15.f};
                        float tipHeights[5] = {8.f, 11.f, 13.f, 11.f, 8.f};
                        for (int i = 0; i < 5; i++) {
                            sf::ConvexShape tip; tip.setPointCount(3);
                            tip.setFillColor(sf::Color(255, 215, 0));
                            tip.setOutlineThickness(1.f); tip.setOutlineColor(outline);
                            tip.setPoint(0, sf::Vector2f(cx + tipPositions[i] - 3.f, cy + 2.f));
                            tip.setPoint(1, sf::Vector2f(cx + tipPositions[i] + 3.f, cy + 2.f));
                            tip.setPoint(2, sf::Vector2f(cx + tipPositions[i], cy + 2.f - tipHeights[i]));
                            target.draw(tip);
                            // Riflesso sulla punta
                            sf::ConvexShape tipRef; tipRef.setPointCount(3);
                            tipRef.setFillColor(sf::Color(255, 245, 150));
                            tipRef.setPoint(0, sf::Vector2f(cx + tipPositions[i] - 1.5f, cy + 1.f));
                            tipRef.setPoint(1, sf::Vector2f(cx + tipPositions[i] - 0.5f, cy + 1.f));
                            tipRef.setPoint(2, sf::Vector2f(cx + tipPositions[i] - 0.5f, cy + 2.f - tipHeights[i] * 0.8f));
                            target.draw(tipRef);
                            // Sfera dorata sulla punta della punta
                            sf::CircleShape tipBall(1.5f);
                            tipBall.setFillColor(sf::Color(255, 235, 80));
                            tipBall.setOutlineThickness(0.5f); tipBall.setOutlineColor(outline);
                            tipBall.setPosition(cx + tipPositions[i] - 1.5f, cy + 2.f - tipHeights[i] - 1.5f);
                            target.draw(tipBall);
                        }

                        // Gemme incastonate sulla base (5 piccole)
                        sf::Color gemColors[5] = {
                            sf::Color(220, 30, 30),    // rosso
                            sf::Color(30, 180, 80),    // verde
                            sf::Color(80, 80, 220),    // blu
                            sf::Color(220, 200, 30),   // giallo
                            sf::Color(180, 30, 220)    // viola
                        };
                        for (int i = 0; i < 5; i++) {
                            sf::CircleShape gem(1.8f);
                            gem.setFillColor(gemColors[i]);
                            gem.setOutlineThickness(0.5f); gem.setOutlineColor(outline);
                            gem.setPosition(cx - 14.f + i * 7.f, cy + 5.f);
                            target.draw(gem);
                            // Riflesso luminoso sulla gemma
                            sf::CircleShape gemRef(0.6f);
                            gemRef.setFillColor(sf::Color(255, 255, 255, 200));
                            gemRef.setPosition(cx - 13.5f + i * 7.f, cy + 5.5f);
                            target.draw(gemRef);
                        }
                    }
                    else if (grid[c][r].treasure == TRES_GEM) {
                        // === Gemma preziosa dettagliata (piu' grande) ===
                        // Triplo alone luminoso per dare profondita'
                        sf::CircleShape glow3(20.f);
                        glow3.setFillColor(sf::Color(0, 255, 255, 25));
                        glow3.setPosition(cx - 20.f, cy - 20.f);
                        target.draw(glow3);
                        sf::CircleShape glow2(15.f);
                        glow2.setFillColor(sf::Color(80, 220, 255, 45));
                        glow2.setPosition(cx - 15.f, cy - 15.f);
                        target.draw(glow2);
                        sf::CircleShape glow1(11.f);
                        glow1.setFillColor(sf::Color(150, 240, 255, 65));
                        glow1.setPosition(cx - 11.f, cy - 11.f);
                        target.draw(glow1);

                        // Gemma taglio a diamante (8 facce)
                        sf::ConvexShape gem; gem.setPointCount(8);
                        gem.setFillColor(sf::Color(0, 220, 220));
                        gem.setOutlineThickness(1.5f); gem.setOutlineColor(outline);
                        // Otto punti a forma di diamante stellato
                        for (int i = 0; i < 8; i++) {
                            float ang = i * (float)M_PI / 4.f;
                            float r = (i % 2 == 0) ? 14.f : 7.f;  // alterna raggio (stella)
                            gem.setPoint(i, sf::Vector2f(cx + cos(ang) * r, cy + sin(ang) * r));
                        }
                        target.draw(gem);

                        // Facce interne piu' chiare (effetto rifrazione)
                        sf::ConvexShape gemFacets; gemFacets.setPointCount(4);
                        gemFacets.setFillColor(sf::Color(150, 255, 255, 180));
                        gemFacets.setPoint(0, sf::Vector2f(cx, cy - 6.f));
                        gemFacets.setPoint(1, sf::Vector2f(cx + 4.f, cy));
                        gemFacets.setPoint(2, sf::Vector2f(cx, cy + 6.f));
                        gemFacets.setPoint(3, sf::Vector2f(cx - 4.f, cy));
                        target.draw(gemFacets);

                        // Riflesso bianco (piccolo triangolo)
                        sf::ConvexShape gleam; gleam.setPointCount(3);
                        gleam.setFillColor(sf::Color(255, 255, 255, 230));
                        gleam.setPoint(0, sf::Vector2f(cx - 3.f, cy - 5.f));
                        gleam.setPoint(1, sf::Vector2f(cx - 0.5f, cy - 8.f));
                        gleam.setPoint(2, sf::Vector2f(cx - 5.f, cy - 1.f));
                        target.draw(gleam);

                        // Piccola scintilla luminosa (punto bianco brillante)
                        sf::CircleShape spark(0.8f);
                        spark.setFillColor(sf::Color(255, 255, 255));
                        spark.setPosition(cx + 2.f, cy - 4.f);
                        target.draw(spark);
                    }
                    else if (grid[c][r].treasure == TRES_CHEST) {
                        // === Forziere del tesoro dettagliato (piu' grande) ===
                        // 4 piedini (piccoli blocchi scuri)
                        for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
                            sf::RectangleShape foot(sf::Vector2f(3.f, 2.f));
                            foot.setFillColor(sf::Color(40, 25, 10));
                            foot.setOutlineThickness(0.5f); foot.setOutlineColor(outline);
                            foot.setPosition(cx - 14.f + i * 25.f, cy + 12.f);
                            target.draw(foot);
                        }

                        // Corpo del forziere (3 strati per dar volume)
                        // Strato base scuro
                        sf::RectangleShape body(sf::Vector2f(34.f, 18.f));
                        body.setFillColor(sf::Color(110, 65, 25));
                        body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
                        body.setPosition(cx - 17.f, cy - 4.f);
                        target.draw(body);
                        // Strato mediano (legno piu' chiaro, effetto volume)
                        sf::RectangleShape bodyMid(sf::Vector2f(34.f, 4.f));
                        bodyMid.setFillColor(sf::Color(140, 85, 35));
                        bodyMid.setPosition(cx - 17.f, cy - 4.f);
                        target.draw(bodyMid);
                        // Venature del legno (3 linee)
                        for (int i = 0; i < 3; i++) {
                            sf::RectangleShape vein(sf::Vector2f(32.f, 0.6f));
                            vein.setFillColor(sf::Color(80, 50, 20));
                            vein.setPosition(cx - 16.f, cy + 2.f + i * 4.f);
                            target.draw(vein);
                        }

                        // Coperchio (forma arrotondata con ConvexShape)
                        sf::ConvexShape lid; lid.setPointCount(6);
                        lid.setFillColor(sf::Color(90, 55, 20));
                        lid.setOutlineThickness(1.5f); lid.setOutlineColor(outline);
                        lid.setPoint(0, sf::Vector2f(cx - 17.f, cy - 4.f));
                        lid.setPoint(1, sf::Vector2f(cx + 17.f, cy - 4.f));
                        lid.setPoint(2, sf::Vector2f(cx + 15.f, cy - 10.f));
                        lid.setPoint(3, sf::Vector2f(cx + 10.f, cy - 13.f));
                        lid.setPoint(4, sf::Vector2f(cx - 10.f, cy - 13.f));
                        lid.setPoint(5, sf::Vector2f(cx - 15.f, cy - 10.f));
                        target.draw(lid);
                        // Highlight del coperchio
                        sf::ConvexShape lidHigh; lidHigh.setPointCount(6);
                        lidHigh.setFillColor(sf::Color(130, 80, 30));
                        lidHigh.setPoint(0, sf::Vector2f(cx - 16.f, cy - 4.5f));
                        lidHigh.setPoint(1, sf::Vector2f(cx - 14.f, cy - 9.f));
                        lidHigh.setPoint(2, sf::Vector2f(cx - 9.f, cy - 12.f));
                        lidHigh.setPoint(3, sf::Vector2f(cx - 4.f, cy - 12.5f));
                        lidHigh.setPoint(4, sf::Vector2f(cx - 6.f, cy - 10.f));
                        lidHigh.setPoint(5, sf::Vector2f(cx - 13.f, cy - 5.f));
                        target.draw(lidHigh);

                        // 2 bande metalliche verticali (rinforzo)
                        for (int i = 0; i < 2; i++) {
                            float bx = cx - 8.f + i * 16.f;
                            sf::RectangleShape band(sf::Vector2f(3.f, 18.f));
                            band.setFillColor(sf::Color(180, 180, 180));
                            band.setOutlineThickness(0.8f); band.setOutlineColor(outline);
                            band.setPosition(bx, cy - 4.f);
                            target.draw(band);
                            // Riflesso della banda (striscia chiara)
                            sf::RectangleShape bandRef(sf::Vector2f(0.8f, 16.f));
                            bandRef.setFillColor(sf::Color(240, 240, 240));
                            bandRef.setPosition(bx + 0.5f, cy - 3.f);
                            target.draw(bandRef);
                            // Rivetto sulla banda
                            sf::CircleShape rivet(1.f);
                            rivet.setFillColor(sf::Color(220, 180, 60));
                            rivet.setPosition(bx + 0.5f, cy + 4.f);
                            target.draw(rivet);
                        }

                        // Lucchetto dorato (con dettaglio della serratura)
                        sf::RectangleShape lock(sf::Vector2f(8.f, 7.f));
                        lock.setFillColor(sf::Color(255, 215, 0));
                        lock.setOutlineThickness(1.f); lock.setOutlineColor(outline);
                        lock.setPosition(cx - 4.f, cy - 2.f);
                        target.draw(lock);
                        // Riflesso del lucchetto
                        sf::RectangleShape lockRef(sf::Vector2f(6.f, 1.f));
                        lockRef.setFillColor(sf::Color(255, 245, 150));
                        lockRef.setPosition(cx - 3.f, cy - 1.5f);
                        target.draw(lockRef);
                        // Foro della serratura (piccolo cerchio nero)
                        sf::CircleShape keyhole(0.8f);
                        keyhole.setFillColor(sf::Color(20, 15, 5));
                        keyhole.setPosition(cx - 0.8f, cy + 0.5f);
                        target.draw(keyhole);

                        // Lingotti d'oro che sporgono dal forziere (effetto "pieno")
                        sf::RectangleShape ingot1(sf::Vector2f(6.f, 3.f));
                        ingot1.setFillColor(sf::Color(255, 215, 0));
                        ingot1.setOutlineThickness(0.5f); ingot1.setOutlineColor(outline);
                        ingot1.setPosition(cx - 8.f, cy - 11.f);
                        target.draw(ingot1);
                        sf::RectangleShape ingot2(sf::Vector2f(6.f, 3.f));
                        ingot2.setFillColor(sf::Color(255, 235, 50));
                        ingot2.setOutlineThickness(0.5f); ingot2.setOutlineColor(outline);
                        ingot2.setPosition(cx + 2.f, cy - 12.f);
                        target.draw(ingot2);
                    }
                    else if (grid[c][r].treasure == TRES_CUP) {
                        // === Coppa / calice reale dettagliata (piu' grande) ===
                        // Base allargata (3 strati)
                        sf::RectangleShape baseBottom(sf::Vector2f(20.f, 4.f));
                        baseBottom.setFillColor(sf::Color(180, 130, 30));
                        baseBottom.setOutlineThickness(1.f); baseBottom.setOutlineColor(outline);
                        baseBottom.setPosition(cx - 10.f, cy + 10.f);
                        target.draw(baseBottom);
                        sf::RectangleShape baseTop(sf::Vector2f(20.f, 2.f));
                        baseTop.setFillColor(sf::Color(255, 215, 0));
                        baseTop.setPosition(cx - 10.f, cy + 10.f);
                        target.draw(baseTop);
                        // Decorazione della base (puntini dorati)
                        for (int i = 0; i < 4; i++) {
                            sf::CircleShape dot(0.8f);
                            dot.setFillColor(sf::Color(255, 245, 150));
                            dot.setPosition(cx - 8.f + i * 5.f, cy + 11.f);
                            target.draw(dot);
                        }

                        // Stelo (colonna con fregio centrale)
                        sf::RectangleShape stem(sf::Vector2f(4.f, 8.f));
                        stem.setFillColor(sf::Color(220, 170, 30));
                        stem.setOutlineThickness(0.8f); stem.setOutlineColor(outline);
                        stem.setPosition(cx - 2.f, cy + 2.f);
                        target.draw(stem);
                        // Nodo centrale dello stelo (sfera dorata)
                        sf::CircleShape node(2.5f);
                        node.setFillColor(sf::Color(255, 215, 0));
                        node.setOutlineThickness(0.8f); node.setOutlineColor(outline);
                        node.setPosition(cx - 2.5f, cy + 4.f);
                        target.draw(node);
                        // Riflesso del nodo
                        sf::CircleShape nodeRef(0.8f);
                        nodeRef.setFillColor(sf::Color(255, 245, 150));
                        nodeRef.setPosition(cx - 1.8f, cy + 4.5f);
                        target.draw(nodeRef);

                        // Calice (la coppa vera e propria, forma trapezoidale)
                        sf::ConvexShape cup; cup.setPointCount(4);
                        cup.setFillColor(sf::Color(255, 215, 0));
                        cup.setOutlineThickness(1.5f); cup.setOutlineColor(outline);
                        cup.setPoint(0, sf::Vector2f(cx - 10.f, cy - 8.f));
                        cup.setPoint(1, sf::Vector2f(cx + 10.f, cy - 8.f));
                        cup.setPoint(2, sf::Vector2f(cx + 6.f, cy + 2.f));
                        cup.setPoint(3, sf::Vector2f(cx - 6.f, cy + 2.f));
                        target.draw(cup);
                        // Riflesso cromatico del calice (striscia chiara verticale)
                        sf::ConvexShape cupRef; cupRef.setPointCount(4);
                        cupRef.setFillColor(sf::Color(255, 245, 150));
                        cupRef.setPoint(0, sf::Vector2f(cx - 8.f, cy - 7.f));
                        cupRef.setPoint(1, sf::Vector2f(cx - 6.f, cy - 7.f));
                        cupRef.setPoint(2, sf::Vector2f(cx - 4.f, cy + 1.f));
                        cupRef.setPoint(3, sf::Vector2f(cx - 5.f, cy + 1.f));
                        target.draw(cupRef);

                        // Bordo superiore del calice (cornicetta dorata)
                        sf::RectangleShape rim(sf::Vector2f(22.f, 2.f));
                        rim.setFillColor(sf::Color(220, 170, 30));
                        rim.setOutlineThickness(0.8f); rim.setOutlineColor(outline);
                        rim.setPosition(cx - 11.f, cy - 9.f);
                        target.draw(rim);

                        // Gemma rossa centrale sul calice
                        sf::CircleShape gem(2.5f);
                        gem.setFillColor(sf::Color(220, 30, 30));
                        gem.setOutlineThickness(0.8f); gem.setOutlineColor(outline);
                        gem.setPosition(cx - 2.5f, cy - 5.f);
                        target.draw(gem);
                        // Riflesso della gemma
                        sf::CircleShape gemRef(0.8f);
                        gemRef.setFillColor(sf::Color(255, 200, 200));
                        gemRef.setPosition(cx - 1.8f, cy - 4.5f);
                        target.draw(gemRef);
                    }
                    else if (grid[c][r].treasure == TRES_GOLD) {
                        // === Pila di monete d'oro dettagliata (piu' grande) ===
                        // Strato 1: 3 monete di base
                        for (int i = 0; i < 3; i++) {
                            sf::CircleShape coin(7.f);
                            coin.setFillColor(sf::Color(255, 215, 0));
                            coin.setOutlineThickness(1.f); coin.setOutlineColor(outline);
                            coin.setPosition(cx - 13.f + i * 9.f, cy + 6.f);
                            target.draw(coin);
                            // Striscia di riflesso sul bordo superiore
                            sf::RectangleShape ref(sf::Vector2f(10.f, 1.2f));
                            ref.setFillColor(sf::Color(255, 245, 150));
                            ref.setPosition(cx - 12.f + i * 9.f, cy + 5.f);
                            target.draw(ref);
                            // Simbolo centrale della moneta (piccolo rombo)
                            sf::ConvexShape sym; sym.setPointCount(4);
                            sym.setFillColor(sf::Color(180, 130, 30));
                            sym.setPoint(0, sf::Vector2f(cx - 6.f + i * 9.f, cy + 7.f));
                            sym.setPoint(1, sf::Vector2f(cx - 4.f + i * 9.f, cy + 9.f));
                            sym.setPoint(2, sf::Vector2f(cx - 6.f + i * 9.f, cy + 11.f));
                            sym.setPoint(3, sf::Vector2f(cx - 8.f + i * 9.f, cy + 9.f));
                            target.draw(sym);
                        }
                        // Strato 2: 2 monete sopra (sfalsate)
                        for (int i = 0; i < 2; i++) {
                            sf::CircleShape coin(7.f);
                            coin.setFillColor(sf::Color(255, 235, 50));
                            coin.setOutlineThickness(1.f); coin.setOutlineColor(outline);
                            coin.setPosition(cx - 9.f + i * 11.f, cy - 1.f);
                            target.draw(coin);
                            // Riflesso
                            sf::RectangleShape ref(sf::Vector2f(10.f, 1.2f));
                            ref.setFillColor(sf::Color(255, 245, 180));
                            ref.setPosition(cx - 8.f + i * 11.f, cy - 2.f);
                            target.draw(ref);
                            // Simbolo
                            sf::ConvexShape sym; sym.setPointCount(4);
                            sym.setFillColor(sf::Color(180, 130, 30));
                            sym.setPoint(0, sf::Vector2f(cx - 2.f + i * 11.f, cy));
                            sym.setPoint(1, sf::Vector2f(cx + 0.f + i * 11.f, cy + 2.f));
                            sym.setPoint(2, sf::Vector2f(cx - 2.f + i * 11.f, cy + 4.f));
                            sym.setPoint(3, sf::Vector2f(cx - 4.f + i * 11.f, cy + 2.f));
                            target.draw(sym);
                        }
                        // Strato 3: 1 moneta in cima (apice)
                        sf::CircleShape coin3(8.f);
                        coin3.setFillColor(sf::Color(255, 255, 100));
                        coin3.setOutlineThickness(1.f); coin3.setOutlineColor(outline);
                        coin3.setPosition(cx - 8.f, cy - 9.f);
                        target.draw(coin3);
                        // Riflesso della moneta apicale
                        sf::RectangleShape ref3(sf::Vector2f(12.f, 1.5f));
                        ref3.setFillColor(sf::Color(255, 250, 200));
                        ref3.setPosition(cx - 6.f, cy - 10.f);
                        target.draw(ref3);
                        // Simbolo della moneta apicale (stella a 5 punte)
                        sf::ConvexShape star; star.setPointCount(10);
                        star.setFillColor(sf::Color(180, 130, 30));
                        for (int i = 0; i < 10; i++) {
                            float ang = i * (float)M_PI / 5.f - (float)M_PI / 2.f;
                            float r = (i % 2 == 0) ? 3.f : 1.2f;
                            star.setPoint(i, sf::Vector2f(cx + cos(ang) * r, cy - 5.f + sin(ang) * r));
                        }
                        target.draw(star);

                        // Piccoli raggi luminosi attorno alla pila (effetto scintillio)
                        for (int i = 0; i < 4; i++) {
                            float ang = i * (float)M_PI / 2.f + (float)M_PI / 4.f;
                            float sx = cx + cos(ang) * 14.f;
                            float sy = cy - 4.f + sin(ang) * 10.f;
                            sf::RectangleShape ray(sf::Vector2f(1.f, 3.f));
                            ray.setFillColor(sf::Color(255, 240, 150, 180));
                            ray.setOrigin(0.5f, 1.5f);
                            ray.setPosition(sx, sy);
                            ray.rotate(ang * 180.f / (float)M_PI);
                            target.draw(ray);
                        }
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
