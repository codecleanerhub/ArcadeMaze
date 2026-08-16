#ifndef MAZE_H
#define MAZE_H

// ===========================================================================
// Maze.h - Generazione e gestione del labirinto.
//
// Il labirinto e' una griglia MAZE_COLS x MAZE_ROWS (21 x 19) di `Cell`.
// Ogni cella puo' essere:
//   * CELL_EMPTY   - pavimento percorribile
//   * CELL_WALL    - muro (blocca movimento e proiettili)
//   * CELL_TREASURE- tesoro da raccogliere per attivare il boss
//   * CELL_WEAPON  - arma casuale che il giocatore puo' raccogliere
//
// La generazione usa DFS iterativo ("recursive backtracker"); in coda
// vengono aggiunti passaggi extra e posizionati tesori/armi casuali.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include <vector>
#include "Utils.h"
#include "Weapon.h"

// Tipo di contenuto di una cella del labirinto.
enum CellType { CELL_EMPTY, CELL_WALL, CELL_TREASURE, CELL_WEAPON };

// Tipo di tesoro (puramente estetico: il valore in punti e' fisso a 10000).
enum TreasureType { TRES_CROWN, TRES_GOLD, TRES_CHEST, TRES_GEM, TRES_CUP };

// Singola cella della griglia. Quando type==CELL_WEAPON il campo `weapon`
// contiene l'arma casuale generata; quando type==CELL_TREASURE il campo
// `treasure` contiene il sottotipo (corona, gemma, ecc.).
struct Cell {
    CellType type;
    Weapon weapon;
    TreasureType treasure;
};

class Maze {
public:
    Maze();

    // Rigenera casualmente l'intero labirinto: muri, tesori, armi e colori.
    // Va chiamato all'inizio di ogni livello.
    void generate();

    // Disegna l'intero labirinto (muri 3D, tesori, armi) sul target.
    void render(sf::RenderTarget& target);

    // Restituisce true se la cella (col, row) e' un muro o fuori griglia.
    bool isWall(int col, int row);

    // Restituisce il tipo di cella (per controllare tesori/armi sotto il
    // giocatore). Le celle fuori griglia sono trattate come CELL_WALL.
    CellType getCellType(int col, int row);

    // Raccoglie l'arma presente nella cella e la trasforma in CELL_EMPTY.
    // Attenzione: chiama questo metodo solo se getCellType == CELL_WEAPON.
    Weapon collectWeapon(int col, int row);

    // Raccoglie il tesoro nella cella (lo trasforma in CELL_EMPTY).
    void collectTreasure(int col, int row);

    // Conta i tesori ancora presenti: quando arriva a 0, parte il boss.
    int getRemainingTreasures();

    // Colori generati casualmente per ogni livello (usati dal rendering).
    sf::Color getWallColor() const { return wallColor; }
    sf::Color getBgColor() const { return bgColor; }
private:
    // Griglia bidimensionale [col][row] di celle.
    std::vector<std::vector<Cell>> grid;
    sf::Color wallColor;   // colore muri (varia per livello)
    sf::Color bgColor;     // colore pavimento (fisso scuro)

    // Conta i muri tra le 4 celle ortogonalmente adiacenti a (c, r).
    // Usato per ammorbidire il labirinto aprendo muri con 2 soli vicini.
    int countNeighboringWalls(int c, int r);
};

#endif
