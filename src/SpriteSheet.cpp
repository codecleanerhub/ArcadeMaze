#include "SpriteSheet.h"
#include <fstream>
#include <sstream>
#include <iostream>

// ===========================================================================
// SpriteSheet.cpp - Implementazione.
//
// Parsing JSON minimale a mano: il file e' generato da script Python ed ha
// struttura nota e semplice. Evitiamo dipendenze esterne (nlohmann/json).
// Se il parsing fallisce, si usano i default.
// ===========================================================================

SpriteSheet::SpriteSheet() : frameW(64), frameH(64), columns(6), rows(4), loaded(false) {
    // Animazioni di default (corrispondono a quelle degli script Python).
    animations["idle"]   = {0, 4, 200};
    animations["walk"]   = {1, 6, 100};
    animations["attack"] = {2, 6, 100};
    animations["death"]  = {3, 6, 120};
}

// ---------------------------------------------------------------------------
// load: carica PNG + JSON. `basePath` senza estensione.
//   1. Prova a caricare <basePath>.png con sf::Texture::loadFromFile.
//   2. Se OK, prova a leggere <basePath>.json per i metadati.
//   3. Se il JSON manca o e' malformato, mantiene i default (va bene lo stesso
//      perche' i default combaciano con gli script di generazione).
//   4. Se il PNG manca, resta unloaded: il chiamante fa fallback.
// ---------------------------------------------------------------------------
bool SpriteSheet::load(const std::string& basePath) {
    std::string pngPath = basePath + ".png";
    std::string jsonPath = basePath + ".json";

    if (!texture.loadFromFile(pngPath)) {
        loaded = false;
        return false;
    }
    // PNG caricato: aggiorna le dimensioni effettive della texture.
    sf::Vector2u texSize = texture.getSize();
    if (texSize.x > 0 && texSize.y > 0 && columns > 0 && rows > 0) {
        // Ricalcola le dimensioni del frame in base alla texture reale
        // (potrebbe essere diversa dal default 64x64 se lo script e' stato
        // configurato diversamente).
        frameW = texSize.x / columns;
        frameH = texSize.y / rows;
    }

    loadMetaOrDefault(jsonPath);
    loaded = true;
    return true;
}

// ---------------------------------------------------------------------------
// loadMetaOrDefault: parser JSON minimale per il file metadata.
//
// Cerchiamo le chiavi:
//   "frameWidth", "frameHeight", "columns", "rows"
//   "animations": { "idle": {"row":0,"frames":4,"frameDuration":200}, ... }
//
// Implementazione volutamente semplice: legge il file, cerca le sottostringhe
// `"chiave":valore` e le parsa. Funziona per il formato generato dai nostri
// script Python. Per JSON arbitrari usare una libreria vera.
// ---------------------------------------------------------------------------
void SpriteSheet::loadMetaOrDefault(const std::string& jsonPath) {
    std::ifstream file(jsonPath);
    if (!file.is_open()) return;  // mantieni default

    std::stringstream ss;
    ss << file.rdbuf();
    std::string content = ss.str();

    // Helper: trova il valore intero dopo una chiave data.
    auto getInt = [&](const std::string& key, int& out) {
        size_t pos = content.find("\"" + key + "\"");
        if (pos == std::string::npos) return false;
        pos = content.find(':', pos);
        if (pos == std::string::npos) return false;
        pos++;
        while (pos < content.size() && (content[pos] == ' ' || content[pos] == '\t')) pos++;
        int val = 0;
        bool any = false;
        while (pos < content.size() && content[pos] >= '0' && content[pos] <= '9') {
            val = val * 10 + (content[pos] - '0');
            pos++;
            any = true;
        }
        if (any) { out = val; return true; }
        return false;
    };

    getInt("frameWidth", frameW);
    getInt("frameHeight", frameH);
    getInt("columns", columns);
    getInt("rows", rows);

    // Per ogni animazione nota, aggiorna row/frames/duration se presenti
    // nel blocco "animations": {...}.
    for (auto& kv : animations) {
        const std::string& name = kv.first;
        AnimInfo& info = kv.second;
        // Cerca "<name>": { ... "row":N ... "frames":N ... "frameDuration":N ... }
        size_t pos = content.find("\"" + name + "\"");
        if (pos == std::string::npos) continue;
        // Trova la parentesi graffa di chiusura del blocco animazione.
        size_t braceStart = content.find('{', pos);
        if (braceStart == std::string::npos) continue;
        size_t braceEnd = content.find('}', braceStart);
        if (braceEnd == std::string::npos) continue;
        std::string block = content.substr(braceStart, braceEnd - braceStart + 1);

        // Helper locale per il blocco
        auto getIntBlock = [&](const std::string& key, int& out) {
            size_t p = block.find("\"" + key + "\"");
            if (p == std::string::npos) return false;
            p = block.find(':', p);
            if (p == std::string::npos) return false;
            p++;
            while (p < block.size() && (block[p] == ' ' || block[p] == '\t')) p++;
            int val = 0; bool any = false;
            while (p < block.size() && block[p] >= '0' && block[p] <= '9') {
                val = val * 10 + (block[p] - '0');
                p++; any = true;
            }
            if (any) { out = val; return true; }
            return false;
        };
        getIntBlock("row", info.row);
        getIntBlock("frames", info.frames);
        getIntBlock("frameDuration", info.frameDuration);
    }
}

// ---------------------------------------------------------------------------
// render: disegna il frame specifico dell'animazione.
//
//  1. Verifica che lo sprite sia caricato e che l'animazione esista.
//  2. Calcola il rettangolo sorgente (subRect) nella texture.
//  3. Modula il frameIdx con il numero di frame (wrap-around sicuro).
//  4. Disegna uno sf::Sprite con centratura su (x, y): l'ancora del frame
//     e' il punto (32, 56) secondo le specifiche (piedi del personaggio).
// ---------------------------------------------------------------------------
void SpriteSheet::render(sf::RenderTarget& target, const std::string& animName,
                          int frameIdx, float x, float y, bool flipped) const {
    if (!loaded) return;
    auto it = animations.find(animName);
    if (it == animations.end()) return;
    const AnimInfo& info = it->second;

    // Wrap-around sicuro: se frameIdx e' fuori range, si usa modulo.
    int idx = frameIdx;
    if (info.frames > 0) idx = ((idx % info.frames) + info.frames) % info.frames;

    // Sub-rectangle nella texture
    int sx = idx * frameW;
    int sy = info.row * frameH;
    sf::IntRect rect(sx, sy, frameW, frameH);

    sf::Sprite sprite(texture, rect);
    // Centratura: anchor a (32, 56) -> offset (-32, -56)
    float ox = 32.f;
    float oy = 56.f;
    if (frameW > 0 && frameH > 0) {
        // Se le dimensioni del frame sono diverse dal default 64x64,
        // scaliamo l'ancora proporzionalmente.
        ox = frameW * 0.5f;
        oy = frameH * (56.f / 64.f);
    }
    sprite.setOrigin(ox, oy);
    sprite.setPosition(x, y);
    if (flipped) {
        // Capovolgi orizzontalmente: scale(-1, 1)
        sprite.scale(-1.f, 1.f);
    }
    target.draw(sprite);
}

// Restituisce il numero di frame di un'animazione (0 se non esiste).
int SpriteSheet::getFrameCount(const std::string& animName) const {
    auto it = animations.find(animName);
    if (it == animations.end()) return 0;
    return it->second.frames;
}
