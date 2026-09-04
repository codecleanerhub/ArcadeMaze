#ifndef DEFORMABLE_SPRITE_H
#define DEFORMABLE_SPRITE_H

// ===========================================================================
// DeformableSprite.h - Animazione di uno sprite statico tramite mesh
// deformation nativa SFML (sf::VertexArray).
//
// Invece di generare 4 frame AI separati (che risultano troppo diversi tra
// loro - effetto "gif disconnessa"), questa classe prende 1 sola immagine
// e la anima deformando una griglia di vertici in tempo reale.
//
// Animazioni disponibili:
//   * IDLE: respirazione (scale Y sinusoidale) + dondolio (rotazione leggera)
//   * WALK: oscillazione gambe (shift vertici inferiori) + bob verticale
//   * ATTACK: pulse orizzontale (scale X rapido)
//
// La griglia e' configurabile (default 8x8 = 64 quad). Ogni quad ha 4
// vertici con position (schermo) e texCoords (texture). Deformando le
// position nel tempo si crea l'animazione.
//
// Vantaggi:
//   - Zero dipendenze esterne (usa solo sf::VertexArray nativo SFML)
//   - 1 sola immagine AI per entita' (invece di 4)
//   - Animazione fluida e coerente (mai "gif disconnessa")
//   - Animazioni codice, non visive: pieno controllo programmatico
// ===========================================================================

#include <SFML/Graphics.hpp>
#include <cmath>

class DeformableSprite {
public:
    enum AnimMode { IDLE, WALK, ATTACK };

    DeformableSprite();

    // Carica la texture da file. Restituisce true se successo.
    bool load(const std::string& path);

    // Imposta la griglia (default 8x8). Piu' alta = piu' fluida ma piu' CPU.
    void setGridSize(int w, int h) { gridW = w; gridH = h; rebuildMesh(); }

    // Aggiorna l'animazione. `time` e' in secondi (cumulativo).
    // `mode` determina quale animazione applicare.
    // `scale` e' lo scale factor finale (es. size/64 per i boss).
    // `flipped` specchia orizzontalmente.
    void update(float time, AnimMode mode, float scale = 1.0f, bool flipped = false);

    // Disegna lo sprite deformato sul target.
    void render(sf::RenderTarget& target, float x, float y);

    bool isLoaded() const { return loaded; }

private:
    sf::Texture texture;
    sf::VertexArray mesh;
    bool loaded;

    int gridW, gridH;       // dimensioni griglia (default 8x8)
    int texW, texH;         // dimensioni texture originale

    // Posizioni base dei vertici (prima della deformazione)
    // Grida di (gridW+1) x (gridH+1) vertici
    std::vector<sf::Vector2f> basePositions;
    std::vector<sf::Vector2f> baseTexCoords;

    // Stato corrente
    float currentScale;
    bool currentFlipped;
    sf::Vector2f currentOffset;  // offset di disegno (x, y dal chiamante)

    // Ricostruisce la griglia base (chiamato quando cambia gridSize o texture)
    void rebuildMesh();

    // Applica la deformazione in base alla modalita'
    void applyDeformation(float time, AnimMode mode);

    // Aggiorna le position dei vertici nel VertexArray
    void updateMeshPositions(float x, float y);
};

#endif // DEFORMABLE_SPRITE_H
