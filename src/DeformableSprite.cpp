#include "DeformableSprite.h"
#include <iostream>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ===========================================================================
// DeformableSprite.cpp - Implementazione mesh deformation nativo SFML.
//
// Usa sf::VertexArray con sf::Quads per deformare una singola texture.
// La griglia di vertici viene animata in tempo reale con funzioni
// sinusoidali per creare respirazione, camminata, e attacco.
// ===========================================================================

DeformableSprite::DeformableSprite()
    : loaded(false), gridW(8), gridH(8), texW(0), texH(0),
      currentScale(1.0f), currentFlipped(false) {
}

bool DeformableSprite::load(const std::string& path) {
    if (!texture.loadFromFile(path)) {
        loaded = false;
        return false;
    }
    texture.setSmooth(false);
    sf::Vector2u size = texture.getSize();
    texW = (int)size.x;
    texH = (int)size.y;
    if (texW <= 0 || texH <= 0) {
        loaded = false;
        return false;
    }
    rebuildMesh();
    loaded = true;
    return true;
}

void DeformableSprite::rebuildMesh() {
    if (texW <= 0 || texH <= 0) return;

    // Crea (gridW+1) x (gridH+1) vertici base
    int nVerts = (gridW + 1) * (gridH + 1);
    basePositions.resize(nVerts);
    baseTexCoords.resize(nVerts);

    for (int gy = 0; gy <= gridH; gy++) {
        for (int gx = 0; gx <= gridW; gx++) {
            int idx = gy * (gridW + 1) + gx;
            // Position base: 0..texW, 0..texH
            float px = (float)gx / (float)gridW * (float)texW;
            float py = (float)gy / (float)gridH * (float)texH;
            basePositions[idx] = sf::Vector2f(px, py);
            // TexCoord: stessa griglia sulla texture
            baseTexCoords[idx] = sf::Vector2f(px, py);
        }
    }

    // Crea il VertexArray con Quads: gridW * gridH quad, ognuno con 4 vertici
    mesh.setPrimitiveType(sf::Quads);
    mesh.resize(gridW * gridH * 4);
}

void DeformableSprite::applyDeformation(float time, AnimMode mode) {
    if (!loaded || basePositions.empty()) return;

    // Array di offset per ogni vertice (deformazione)
    int nVerts = (gridW + 1) * (gridH + 1);
    std::vector<sf::Vector2f> offsets(nVerts, sf::Vector2f(0.f, 0.f));

    if (mode == IDLE) {
        // Respirazione: i vertici oscillano in Y (scala verticale sinusoidale)
        // La deformazione e' maggiore al centro e nulla ai bordi
        for (int gy = 0; gy <= gridH; gy++) {
            for (int gx = 0; gx <= gridW; gx++) {
                int idx = gy * (gridW + 1) + gx;
                // Peso: 0 ai bordi, 1 al centro (curva coseno)
                float wx = sinf((float)gx / (float)gridW * (float)M_PI);
                float wy = sinf((float)gy / (float)gridH * (float)M_PI);
                float weight = wx * wy;
                // Respirazione: oscillazione Y lenta
                float breath = sinf(time * 2.0f) * 1.5f * weight;
                // Leggero dondolio X
                float sway = sinf(time * 1.5f) * 0.8f * weight;
                offsets[idx] = sf::Vector2f(sway, breath);
            }
        }
    } else if (mode == WALK) {
        // Camminata: oscillazione delle gambe (parte bassa) + bob verticale
        // La meta' inferiore (gy > gridH/2) si muove in modo alternato
        float bobY = sinf(time * 8.0f) * 1.5f;  // bob verticale
        for (int gy = 0; gy <= gridH; gy++) {
            for (int gx = 0; gx <= gridW; gx++) {
                int idx = gy * (gridW + 1) + gx;
                // Peso verticale: 0 in alto, 1 in basso
                float vertWeight = (float)gy / (float)gridH;
                vertWeight = vertWeight * vertWeight;  // esagera verso il basso

                // Bob verticale (tutto il corpo)
                float yOff = bobY * 0.5f;

                // Oscillazione gambe: la meta' inferiore oscilla in X
                float legSway = 0.f;
                if (gy > gridH / 2) {
                    // Sway alternato: sinistra e destra
                    float side = (gx < gridW / 2) ? -1.f : 1.f;
                    legSway = sinf(time * 8.0f) * 2.0f * side * vertWeight;
                }

                // Leggera respirazione anche durante camminata
                float wx = sinf((float)gx / (float)gridW * (float)M_PI);
                float breath = sinf(time * 2.0f) * 0.8f * wx * (1.f - vertWeight);

                offsets[idx] = sf::Vector2f(legSway, yOff + breath);
            }
        }
    } else if (mode == ATTACK) {
        // Attacco: pulse orizzontale rapido
        float pulse = sinf(time * 15.0f) * 2.0f;
        for (int gy = 0; gy <= gridH; gy++) {
            for (int gx = 0; gx <= gridW; gx++) {
                int idx = gy * (gridW + 1) + gx;
                // Peso: maggiore al centro
                float wx = sinf((float)gx / (float)gridW * (float)M_PI);
                float weight = wx * (1.f - (float)gy / (float)gridH * 0.3f);
                float xOff = pulse * weight;
                // Respirazione durante l'attacco
                float breath = sinf(time * 2.0f) * 0.5f * wx;
                offsets[idx] = sf::Vector2f(xOff, breath);
            }
        }
    }

    // Applica gli offset alle posizioni base e scrivi nel VertexArray
    for (int gy = 0; gy < gridH; gy++) {
        for (int gx = 0; gx < gridW; gx++) {
            // Indici dei 4 vertici del quad
            int v00 = gy * (gridW + 1) + gx;
            int v10 = gy * (gridW + 1) + (gx + 1);
            int v01 = (gy + 1) * (gridW + 1) + gx;
            int v11 = (gy + 1) * (gridW + 1) + (gx + 1);
            int quadIdx = (gy * gridW + gx) * 4;

            // Positioni deformate = base + offset, scalate
            auto transformVertex = [&](int vIdx) -> sf::Vector2f {
                sf::Vector2f pos = basePositions[vIdx] + offsets[vIdx];
                // Applica scale
                pos.x *= currentScale;
                pos.y *= currentScale;
                // Flip orizzontale
                if (currentFlipped) {
                    pos.x = (float)texW * currentScale - pos.x;
                }
                return pos;
            };

            mesh[quadIdx + 0].position = transformVertex(v00);
            mesh[quadIdx + 1].position = transformVertex(v10);
            mesh[quadIdx + 2].position = transformVertex(v11);
            mesh[quadIdx + 3].position = transformVertex(v01);

            // TexCoords ( fisse, non deformate)
            mesh[quadIdx + 0].texCoords = baseTexCoords[v00];
            mesh[quadIdx + 1].texCoords = baseTexCoords[v10];
            mesh[quadIdx + 2].texCoords = baseTexCoords[v11];
            mesh[quadIdx + 3].texCoords = baseTexCoords[v01];
        }
    }
}

void DeformableSprite::update(float time, AnimMode mode, float scale, bool flipped) {
    currentScale = scale;
    currentFlipped = flipped;
    applyDeformation(time, mode);
}

void DeformableSprite::render(sf::RenderTarget& target, float x, float y) {
    if (!loaded) return;

    // Trasla tutti i vertici di (x, y) usando sf::Transform
    // (piu' efficiente: usa renderStates con transform)
    sf::RenderStates states;
    states.texture = &texture;
    sf::Transform transform;
    transform.translate(x, y);
    states.transform = transform;
    target.draw(mesh, states);
}
