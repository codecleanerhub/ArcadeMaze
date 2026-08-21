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
// `level` (1-based) seleziona la palette cromatica del livello (8 palette
// che ciclano: caverna grigia, dungeon blu, cripta viola, ecc.).
// ---------------------------------------------------------------------------
void Maze::generate(int level) {
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

    // 4) Posiziona tesori e armi in celle vuote, DISTANTI tra loro.
    //    Raccogliamo tutte le celle vuote, poi posizioniamo tesori e armi
    //    scegliendo posizioni che abbiano una distanza minima (Manhattan)
    //    da tutti gli altri tesori/armi gia' posizionati. Questo evita
    //    che tesori o armi siano ammassati in una zona del labirinto.
    std::vector<Vec2> emptyCells;
    for (int c = 1; c < MAZE_COLS - 1; ++c)
        for (int r = 1; r < MAZE_ROWS - 1; ++r)
            if (grid[c][r].type == CELL_EMPTY) emptyCells.push_back({c, r});

    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(emptyCells.begin(), emptyCells.end(), g);

    // Distanza minima tra tesori/armi (in celle Manhattan)
    const int MIN_DIST_TREASURE = 4;  // tesori distanti almeno 4 celle tra loro
    const int MIN_DIST_WEAPON = 5;    // armi distanti almeno 5 celle tra loro
    const int MIN_DIST_TW = 3;        // tesori vs armi: almeno 3 celle

    std::vector<Vec2> placedItems;  // posizioni gia' occupate da tesori/armi
    std::vector<Vec2> placedTreasures;  // solo tesori (per distanza tesori-armi)

    // Funzione lambda: verifica se una cella e' abbastanza lontana
    // da TUTTE le posizioni in un vettore dato (distanza Manhattan).
    auto isFarEnoughFrom = [](const Vec2& candidate,
                              const std::vector<Vec2>& positions,
                              int minDist) -> bool {
        for (const auto& p : positions) {
            if (abs(p.x - candidate.x) + abs(p.y - candidate.y) < minDist)
                return false;
        }
        return true;
    };
    // Compatibilita' con il vecchio nome (controlla placedItems).
    auto isFarEnough = [&](const Vec2& candidate, int minDist) -> bool {
        return isFarEnoughFrom(candidate, placedItems, minDist);
    };

    // 8 tesori distribuiti e distanti
    int treasuresPlaced = 0;
    for (const auto& cell : emptyCells) {
        if (treasuresPlaced >= 8) break;
        if (isFarEnough(cell, MIN_DIST_TREASURE)) {
            grid[cell.x][cell.y].type = CELL_TREASURE;
            grid[cell.x][cell.y].treasure = static_cast<TreasureType>(rand() % 5);
            placedItems.push_back(cell);
            placedTreasures.push_back(cell);
            treasuresPlaced++;
        }
    }

    // 5 armi distribuite e distanti da tesori (MIN_DIST_TW) e tra loro
    // (MIN_DIST_WEAPON). Questo implementa davvero la distanza tesori-armi
    // che prima era solo dichiarata nel commento ma non applicata.
    int weaponsPlaced = 0;
    for (const auto& cell : emptyCells) {
        if (weaponsPlaced >= 5) break;
        if (grid[cell.x][cell.y].type != CELL_EMPTY) continue;
        // Distanza da altri tesori (almeno MIN_DIST_TW celle)
        if (!isFarEnoughFrom(cell, placedTreasures, MIN_DIST_TW)) continue;
        // Distanza da altre armi (almeno MIN_DIST_WEAPON celle)
        if (isFarEnough(cell, MIN_DIST_WEAPON)) {
            grid[cell.x][cell.y].type = CELL_WEAPON;
            grid[cell.x][cell.y].weapon = Weapon::generateRandom();
            placedItems.push_back(cell);
            weaponsPlaced++;
        }
    }

    // 5) Colori: ogni livello ha una palette tematica diversa per dare
    //    carattere distintivo al dungeon. Sono state definite 8 palette
    //    che ciclano: caverna grigia, dungeon blu notturno, cripta viola
    //    necrotica, caverne rocciose rosse, ossario giallo-osso, palude
    //    verde, sale infernali rosso scuro, abisso turchese.
    //    Inoltre il pavimento (`bgColor`) e' scelto in armonia cromatica
    //    col muro per dare coerenza al "tema" del livello.
    {
        int palIdx = (level - 1) % 8;  // 8 palette disponibili (level e' 1-based)
        switch (palIdx) {
            case 0: // Caverna grigia (palette classica)
                wallColor = sf::Color(75, 70, 65);
                bgColor  = sf::Color(28, 22, 18);
                break;
            case 1: // Dungeon blu notturno (illuminazione fredda)
                wallColor = sf::Color(55, 70, 90);
                bgColor  = sf::Color(18, 22, 35);
                break;
            case 2: // Cripta viola necrotica
                wallColor = sf::Color(85, 60, 90);
                bgColor  = sf::Color(28, 18, 30);
                break;
            case 3: // Caverne rocciose rosse (terra bruciata)
                wallColor = sf::Color(95, 60, 50);
                bgColor  = sf::Color(35, 20, 15);
                break;
            case 4: // Ossario giallo-osso (polvere di ossa)
                wallColor = sf::Color(95, 85, 60);
                bgColor  = sf::Color(32, 28, 18);
                break;
            case 5: // Palude verde (muffa e muschio)
                wallColor = sf::Color(60, 80, 55);
                bgColor  = sf::Color(18, 28, 18);
                break;
            case 6: // Sale infernali (rosso scuro fuoco)
                wallColor = sf::Color(95, 50, 45);
                bgColor  = sf::Color(35, 15, 12);
                break;
            case 7: // Abisso turchese (grotta sottomarina)
                wallColor = sf::Color(45, 85, 85);
                bgColor  = sf::Color(15, 28, 30);
                break;
        }
    }
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
                // --- Muro 3D roccioso con gradiente verticale pulito ---
                // La roccia e' resa con un gradiente verticale a 5 strisce
                // sovrapposte: molto chiara in alto (illuminazione da torcia),
                // via via piu' scura verso il basso (ombra e umidita' di fondo).
                // Questo da' al muro un aspetto "pietra massiccia" senza usare
                // texture esterne, e varieta' cromatica tra livelli (palette).
                //
                // Niente ciottoli, niente puntini, niente highlights puntiformi:
                // la superficie deve essere pulita, solo gradiente. Le vecchie
                // macchie chiare sparse venivano percepite come "stelline" e
                // rovinavano l'effetto material.
                //
                // Strati (dall'alto al basso):
                //   1. cima: luce intensa (wallColor + 50, tonalita' calda)
                //   2. alto-sopra: luce media (wallColor + 22)
                //   3. centro: tono base (wallColor - 5, leggermente piu' scuro)
                //   4. basso-sotto: ombra (wallColor - 25)
                //   5. fondo: ombra profonda (wallColor - 55)

                // Strato 5 (fondo, ombra profonda): copre tutta la cella
                sf::Color colBottom = sf::Color(
                    (sf::Uint8)std::max(0, wallColor.r - 55),
                    (sf::Uint8)std::max(0, wallColor.g - 50),
                    (sf::Uint8)std::max(0, wallColor.b - 45));
                rect.setFillColor(colBottom);
                target.draw(rect);

                // Strato 4 (basso-sotto, ombra media): 60% del tile dal basso
                sf::Color colLowShadow = sf::Color(
                    (sf::Uint8)std::max(0, wallColor.r - 25),
                    (sf::Uint8)std::max(0, wallColor.g - 22),
                    (sf::Uint8)std::max(0, wallColor.b - 20));
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE * 0.75f));
                rect.setFillColor(colLowShadow);
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT + TILE_SIZE * 0.25f);
                target.draw(rect);

                // Strato 3 (centro, tono base): 55% del tile dal centro in su
                sf::Color colMid = sf::Color(
                    (sf::Uint8)std::max(0, wallColor.r - 5),
                    (sf::Uint8)std::max(0, wallColor.g - 5),
                    (sf::Uint8)std::max(0, wallColor.b - 5));
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE * 0.55f));
                rect.setFillColor(colMid);
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);

                // Strato 2 (alto-sopra, luce media): 30% del tile dall'alto
                sf::Color colHigh = sf::Color(
                    (sf::Uint8)std::min(255, wallColor.r + 22),
                    (sf::Uint8)std::min(255, wallColor.g + 18),
                    (sf::Uint8)std::min(255, wallColor.b + 14));
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE * 0.30f));
                rect.setFillColor(colHigh);
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);

                // Strato 1 (cima, luce intensa): 10% del tile dal bordo superiore
                sf::Color colTop = sf::Color(
                    (sf::Uint8)std::min(255, wallColor.r + 48),
                    (sf::Uint8)std::min(255, wallColor.g + 40),
                    (sf::Uint8)std::min(255, wallColor.b + 32));
                rect.setSize(sf::Vector2f(TILE_SIZE, TILE_SIZE * 0.10f));
                rect.setFillColor(colTop);
                rect.setPosition(c * TILE_SIZE, r * TILE_SIZE + UI_HEIGHT);
                target.draw(rect);

                // Singola crepa rara (~10% delle celle muro), sottile e corta.
                // Le crepe NON sono "puntini": sono linee sottili scure che danno
                // carattere di roccia erosa senza rovinare il gradiente.
                if (cellHash(c + 99, r + 17) > 0.90f) {
                    float h1 = cellHash(c * 5 + 31, r * 7 + 19);
                    float cx = c * TILE_SIZE + 8.f + h1 * (TILE_SIZE - 16.f);
                    float cy = r * TILE_SIZE + UI_HEIGHT + 18.f;
                    float ang = (h1 - 0.5f) * 60.f;
                    sf::RectangleShape crack(sf::Vector2f(1.2f, 6.f));
                    crack.setFillColor(sf::Color(5, 5, 5, 130));
                    crack.setOrigin(0.6f, crack.getSize().y * 0.5f);
                    crack.setPosition(cx, cy);
                    crack.rotate(ang);
                    target.draw(crack);
                }

                // Muschio verde molto raro (~3% delle celle muro) per variazione
                // cromatica: solo alla base del muro (effetto umidita' di fondo).
                // Piccolo e non invadente, non e' un "puntino" sparso.
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
                // --- Pavimento terriccio con gradiente radiale morbido ---
                // Il pavimento ha un gradiente "radiale": leggermente piu'
                // scuro ai bordi della cella (transizione col muro) e piu'
                // chiaro al centro (come se la luce venisse dall'alto).
                // Questo da' l'effetto di un pavimento di dungeon battuto,
                // non piatto ne' "bucato".

                // Base: terriccio scuro (colorato in armonia col bgColor del
                // livello, leggermente variato per cella per evitare piattezza)
                float v = cellHash(c + 1, r + 1);
                sf::Uint8 fr = (sf::Uint8)std::max(0, std::min(255, (int)(bgColor.r + 18 + (v - 0.5f) * 10.f)));
                sf::Uint8 fg = (sf::Uint8)std::max(0, std::min(255, (int)(bgColor.g + 12 + (v - 0.5f) *  8.f)));
                sf::Uint8 fb = (sf::Uint8)std::max(0, std::min(255, (int)(bgColor.b +  6 + (v - 0.5f) *  6.f)));
                rect.setFillColor(sf::Color(fr, fg, fb));
                target.draw(rect);

                // Macchia chiara centrale (gradiente radiale morbido):
                // un cerchio piu' chiaro al centro del tile che simula la luce
                // che cade dall'alto. Solo su ~50% delle celle (alternanza)
                // per dare ritmo visivo senza appesantire.
                if (cellHash(c + 33, r + 22) > 0.5f) {
                    float h1 = cellHash(c + 11, r + 7);
                    float cx2 = c * TILE_SIZE + TILE_SIZE / 2.f + (h1 - 0.5f) * 8.f;
                    float cy2 = r * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f + (cellHash(c+5, r+9) - 0.5f) * 8.f;
                    sf::CircleShape lightSpot(14.f);
                    lightSpot.setFillColor(sf::Color(
                        (sf::Uint8)std::min(255, fr + 12),
                        (sf::Uint8)std::min(255, fg + 10),
                        (sf::Uint8)std::min(255, fb + 8), 90));
                    lightSpot.setPosition(cx2 - 14.f, cy2 - 14.f);
                    target.draw(lightSpot);
                }

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
                    crack.setFillColor(sf::Color(15, 8, 4, 140));
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
                    stain.setFillColor(sf::Color(15, 8, 4, 130));
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
                            float radius = (i % 2 == 0) ? 14.f : 7.f;  // alterna raggio (stella)
                            gem.setPoint(i, sf::Vector2f(cx + cos(ang) * radius, cy + sin(ang) * radius));
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
                            float starR = (i % 2 == 0) ? 3.f : 1.2f;  // FIX -Wshadow: rinominato r -> starR
                            star.setPoint(i, sf::Vector2f(cx + cos(ang) * starR, cy - 5.f + sin(ang) * starR));
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

    // --- Torce lungo i muri (massimo 3 per tipo di orientamento) ---
    // Per evitare troppe torci nel labirinto, vengono selezionate al piu'
    // 3 celle muro per ciascun orientamento (openDown / openUp / openRight /
    // openLeft). Le celle candidato sono prima raccolte in 4 vettori, poi
    // ordinate per "hash" (funzione cellHash deterministica) e prelevate
    // le migliori 3. Questo garantisce:
    //   - distribuzione uniforme delle torce (non concentrate in un'area)
    //   - stabilita' tra frame (le torce non appaiono/scompaiono a caso)
    //   - massimo 12 torce totali (3 x 4 orientamenti)
    //
    // Le torce vengono posizionate sul lato del muro verso la cella vuota
    // adiacente, come prima.
    {
        // 4 vettori per i 4 orientamenti, contenenti (col, row) dei candidati
        std::vector<Vec2> candDown, candUp, candRight, candLeft;
        for (int c = 1; c < MAZE_COLS - 1; ++c) {
            for (int r = 1; r < MAZE_ROWS - 1; ++r) {
                if (grid[c][r].type != CELL_WALL) continue;
                bool openUp    = (grid[c][r-1].type != CELL_WALL);
                bool openDown  = (grid[c][r+1].type != CELL_WALL);
                bool openLeft  = (grid[c-1][r].type != CELL_WALL);
                bool openRight = (grid[c+1][r].type != CELL_WALL);
                if (!openUp && !openDown && !openLeft && !openRight) continue;
                // Inserisce il candidato in TUTTI gli orientamenti aperti:
                // sara' poi la selezione per hash a decidere quali vincono.
                // (In pratica ogni cella finisce in 1-2 vettori al massimo,
                // dato che un muro con 3+ lati aperti e' raro.)
                if (openDown)  candDown.push_back({c, r});
                if (openUp)    candUp.push_back({c, r});
                if (openRight) candRight.push_back({c, r});
                if (openLeft)  candLeft.push_back({c, r});
            }
        }

        // Funzione: seleziona le migliori 3 celle dal vettore candidato.
        // La selezione e' basata sull'hash della cella: ordiniamo per hash
        // decrescente e prendiamo le prime 3. Inoltre, per distribuire bene
        // le torce nello spazio, saltiamo i candidati troppo vicini (>1 cella
        // di distanza) a uno gia' selezionato.
        auto selectTorches = [&](std::vector<Vec2>& candidates,
                                 std::vector<Vec2>& out) {
            // Ordina per hash decrescente (le migliori hash vincono)
            std::sort(candidates.begin(), candidates.end(),
                [](const Vec2& a, const Vec2& b) {
                    return cellHash(a.x + 1111, a.y + 2222) >
                           cellHash(b.x + 1111, b.y + 2222);
                });
            // Seleziona mantenendo distanza minima di 3 celle tra le
            // torce scelte, per evitare raggruppamenti.
            const int minDist = 8;
            for (const Vec2& cand : candidates) {
                if ((int)out.size() >= 2) break;
                bool tooClose = false;
                for (const Vec2& s : out) {
                    int dx = std::abs(cand.x - s.x);
                    int dy = std::abs(cand.y - s.y);
                    if (dx + dy < minDist) { tooClose = true; break; }
                }
                if (!tooClose) out.push_back(cand);
            }
        };

        std::vector<Vec2> torchesDown, torchesUp, torchesRight, torchesLeft;
        selectTorches(candDown,  torchesDown);
        selectTorches(candUp,    torchesUp);
        selectTorches(candRight, torchesRight);
        selectTorches(candLeft,  torchesLeft);

        // Disegna le torce selezionate per ogni orientamento
        for (const Vec2& t : torchesDown) {
            float mcx = t.x * TILE_SIZE + TILE_SIZE / 2.f;
            float yBase = t.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE + 4.f;
            drawTorch(mcx, yBase, animTime);
        }
        for (const Vec2& t : torchesUp) {
            float mcx = t.x * TILE_SIZE + TILE_SIZE / 2.f;
            float yBase = t.y * TILE_SIZE + UI_HEIGHT - 4.f;
            drawTorch(mcx, yBase, animTime);
        }
        for (const Vec2& t : torchesRight) {
            float x = (t.x + 1) * TILE_SIZE + 4.f;
            float yBase = t.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            drawTorch(x, yBase, animTime);
        }
        for (const Vec2& t : torchesLeft) {
            float x = t.x * TILE_SIZE - 4.f;
            float yBase = t.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            drawTorch(x, yBase, animTime);
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

    // --- Aure luminose attorno alle torce (effetto atmosfera) ---
    // Per ogni cella muro che ha una torcia (le stesse selezionate prima),
    // disegna un grande cerchio semitrasparente caldo attorno alla posizione
    // della torcia, simulando la luce che si diffonde. Poiche' le posizioni
    // delle torce sono deterministiche (selezionate tramite selectTorches),
    // ricalcoliamo qui le stesse posizioni mantenendo coerenza col disegno
    // delle torce fatto prima.
    //
    // Costo: massimo 12 aure (3 per orientamento x 4), ogni una 1 draw.
    // Trascurabile rispetto al resto del render.
    {
        // Ricalcola le posizioni delle torce selezionate per poterci
        // disegnare l'aura attorno. Usa la stessa logica di selectTorches.
        std::vector<Vec2> torchPositions;
        auto collectTorchCandidates = [&](std::vector<Vec2>& out, int sideFlag) {
            for (int c = 1; c < MAZE_COLS - 1; ++c) {
                for (int r = 1; r < MAZE_ROWS - 1; ++r) {
                    if (grid[c][r].type != CELL_WALL) continue;
                    bool openUp = (grid[c][r-1].type != CELL_WALL);
                    bool openDown = (grid[c][r+1].type != CELL_WALL);
                    bool openLeft = (grid[c-1][r].type != CELL_WALL);
                    bool openRight = (grid[c+1][r].type != CELL_WALL);
                    bool open = false;
                    switch (sideFlag) {
                        case 0: open = openDown; break;
                        case 1: open = openUp; break;
                        case 2: open = openRight; break;
                        case 3: open = openLeft; break;
                    }
                    if (!open) continue;
                    if (openUp || openDown || openLeft || openRight)
                        out.push_back({c, r});
                }
            }
        };
        auto selectTop3 = [](std::vector<Vec2>& in, std::vector<Vec2>& out) {
            std::sort(in.begin(), in.end(),
                [](const Vec2& a, const Vec2& b) {
                    return cellHash(a.x + 1111, a.y + 2222) >
                           cellHash(b.x + 1111, b.y + 2222);
                });
            const int minDist = 8;
            for (const Vec2& cand : in) {
                if ((int)out.size() >= 2) break;
                bool tooClose = false;
                for (const Vec2& s : out) {
                    if (std::abs(cand.x - s.x) + std::abs(cand.y - s.y) < minDist) {
                        tooClose = true; break;
                    }
                }
                if (!tooClose) out.push_back(cand);
            }
        };
        // Raccogli e seleziona per ogni orientamento
        for (int side = 0; side < 4; side++) {
            std::vector<Vec2> cand;
            collectTorchCandidates(cand, side);
            std::vector<Vec2> selected;
            selectTop3(cand, selected);
            // Calcola posizione pixel della torcia per ogni cella selezionata
            for (const Vec2& t : selected) {
                float mcx = t.x * TILE_SIZE + TILE_SIZE / 2.f;
                float mcy;
                switch (side) {
                    case 0: mcy = t.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE + 4.f; break;
                    case 1: mcy = t.y * TILE_SIZE + UI_HEIGHT - 4.f; break;
                    case 2: mcx = (t.x + 1) * TILE_SIZE + 4.f;
                            mcy = t.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f; break;
                    case 3: mcx = t.x * TILE_SIZE - 4.f;
                            mcy = t.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f; break;
                }
                torchPositions.push_back({(int)mcx, (int)mcy});
            }
        }
        // Disegna l'aura per ogni torcia
        for (const Vec2& tp : torchPositions) {
            float tx = (float)tp.x;
            float ty = (float)tp.y;
            // Aura grande calda
            sf::CircleShape tAura(36.f);
            tAura.setFillColor(sf::Color(255, 180, 80, 25));
            tAura.setPosition(tx - 36.f, ty - 50.f);
            target.draw(tAura);
            // Aura media più intensa
            sf::CircleShape tAura2(22.f);
            tAura2.setFillColor(sf::Color(255, 200, 100, 40));
            tAura2.setPosition(tx - 22.f, ty - 38.f);
            target.draw(tAura2);
        }
    }

    // --- Particelle di polvere fluttuanti (effetto atmosfera) ---
    // Piccoli punti chiari semitrasparenti che fluttuano lentamente,
    // come polvere illuminata dalla luce delle torce. Posizioni deterministiche
    // (hash) per stabilita', con animazione sinusoidale.
    {
        srand(13);  // seed fisso per layout stabile delle particelle
        for (int i = 0; i < 24; i++) {
            // Posizione base deterministica su tutto il labirinto
            float baseX = (float)(rand() % (MAZE_COLS * TILE_SIZE));
            float baseY = (float)(rand() % (MAZE_ROWS * TILE_SIZE)) + UI_HEIGHT;
            // Animazione sinusoidale (fluttuazione lenta)
            float t = animTime + i * 0.5f;
            float dx = sin(t * 0.8f) * 6.f;
            float dy = cos(t * 0.6f + i) * 4.f;
            float px = baseX + dx;
            float py = baseY + dy;
            // Pulsazione alpha (lampeggio lento)
            float alphaPulse = (sin(t * 1.5f + i) + 1.f) * 0.5f;  // 0..1
            sf::Uint8 pAlpha = (sf::Uint8)(40 + alphaPulse * 60);
            // Particella (piccolo punto chiaro)
            sf::CircleShape dust(1.f);
            dust.setFillColor(sf::Color(255, 240, 200, pAlpha));
            dust.setPosition(px - 1.f, py - 1.f);
            target.draw(dust);
        }
        srand(time(NULL));  // ripristina seed
    }
}
