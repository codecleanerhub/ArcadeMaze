#ifndef SPRITESHEET_H
#define SPRITESHEET_H

// ===========================================================================
// SpriteSheet.h - Caricamento e rendering di spritesheet animati.
//
// Uno SpriteSheet e' un'immagine PNG che contiene una griglia di frame
// (default 6 colonne x 4 righe). Ogni riga corrisponde a un'animazione
// (idle, walk, attack, death) e ogni colonna a un frame di quell'animazione.
//
// I metadati (dimensioni frame, numero di frame per animazione, durata) sono
// letti da un file JSON associato. Se il JSON non esiste si usano valori
// di default coerenti con gli script di generazione.
//
// Fallback: se il PNG non esiste o non carica, isLoaded() ritorna false e
// il chiamante puo' disegnare con primitive SFML (vecchio comportamento).
// Il gioco e' sempre giocabile anche senza asset.
// ===========================================================================

#include <SFML/Graphics.hpp>
#include <string>
#include <map>

class SpriteSheet {
public:
    SpriteSheet();

    // Carica PNG + JSON. Restituisce true se il PNG e' stato caricato.
    // Se il JSON manca si usano default (6x4, 4 animazioni standard).
    // `basePath` e' il percorso senza estensione: la funzione prova a
    // caricare `<basePath>.png` e `<basePath>.json`.
    bool load(const std::string& basePath);

    // Disegna il frame `frameIdx` dell'animazione `animName` centrato su (x, y).
    // `flipped` capovolge orizzontalmente (utile per movimento sinistra).
    // Se lo sprite non e' caricato, non fa nulla (il chiamante deve gestire
    // il fallback).
    void render(sf::RenderTarget& target, const std::string& animName,
                int frameIdx, float x, float y, bool flipped = false) const;

    // Overload con scaling: disegna lo sprite scalato di `scale` rispetto
    // alle dimensioni native del frame (default 64x64). Utile per i boss
    // che hanno `size` variabile (160+ px) ma sprite a 64x64.
    void render(sf::RenderTarget& target, const std::string& animName,
                int frameIdx, float x, float y, float scale,
                bool flipped) const;

    // True se il PNG e' stato caricato con successo.
    bool isLoaded() const { return loaded; }

    // Numero di frame di un'animazione (0 se l'animazione non esiste).
    int getFrameCount(const std::string& animName) const;

    // Dimensioni del frame (per scaling/centratura).
    int getFrameWidth() const { return frameW; }
    int getFrameHeight() const { return frameH; }

private:
    sf::Texture texture;
    int frameW, frameH;
    int columns, rows;

    struct AnimInfo {
        int row;            // riga nello spritesheet (0-based)
        int frames;         // numero di frame dell'animazione
        int frameDuration;  // durata di un frame in ms (informativo)
    };
    std::map<std::string, AnimInfo> animations;
    bool loaded;

    // Parsa il file JSON dei metadati. Se manca o e' malformato, usa i
    // default (6x4 con idle=0/4, walk=1/6, attack=2/6, death=3/6).
    void loadMetaOrDefault(const std::string& jsonPath);
};

#endif
