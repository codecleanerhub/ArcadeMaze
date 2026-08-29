#include "SpriteSheet.h"
#include <fstream>
#include <sstream>
#include <iostream>
#include <cstdlib>
#include <cstring>

// ===========================================================================
// SpriteSheet.cpp - Implementazione.
//
// Parsing JSON minimale a mano: il file e' generato da script Python ed ha
// struttura nota e semplice. Evitiamo dipendenze esterne (nlohmann/json).
// Se il parsing fallisce, si usano i default.
// ===========================================================================

// Helper multipiattaforma per leggere una variabile d'ambiente.
// Usa std::getenv su Linux/macOS e _dupenv_s su MSVC (per evitare il
// warning C4996 "getenv unsafe" su Windows).
static std::string getEnvVar(const char* name) {
    if (name == nullptr || name[0] == '\0') return "";
#if defined(_MSC_VER)
    // MSVC: usa _dupenv_s (sicura, non deprecata)
    char* value = nullptr;
    size_t len = 0;
    if (_dupenv_s(&value, &len, name) == 0 && value != nullptr) {
        std::string result(value);
        free(value);
        return result;
    }
    return "";
#else
    // Linux/macOS: usa std::getenv (thread-safe con un mutex interno in C11+)
    const char* value = std::getenv(name);
    return (value != nullptr) ? std::string(value) : std::string();
#endif
}

// Helper: attiva log diagnostico se la variabile d'ambiente
// ARCADE_DEBUG_SPRITES=1 e' impostata. Utile per diagnosticare problemi
// di caricamento sprite.
static bool debugSpritesEnabled() {
    static bool checked = false;
    static bool enabled = false;
    if (!checked) {
        std::string v = getEnvVar("ARCADE_DEBUG_SPRITES");
        enabled = (v == "1");
        checked = true;
    }
    return enabled;
}

#define SPRITE_LOG(msg) do { if (debugSpritesEnabled()) std::cerr << "[SPRITE] " << msg << std::endl; } while(0)

SpriteSheet::SpriteSheet() : frameW(64), frameH(64), columns(6), rows(4), loaded(false) {
    // Animazioni di default (corrispondono a quelle degli script Python).
    animations["idle"]   = {0, 4, 200};
    animations["walk"]   = {1, 6, 100};
    animations["attack"] = {2, 6, 100};
    animations["death"]  = {3, 6, 120};
}

// ---------------------------------------------------------------------------
// load: carica PNG + JSON. Prova piu' pattern di nome file:
//   1. <basePath>.png + <basePath>.json
//   2. <basePath>_sheet.png + <basePath>_meta.json  (formato generato dagli script)
// Se nessuno dei due funziona, resta unloaded.
// ---------------------------------------------------------------------------
bool SpriteSheet::load(const std::string& basePath) {
    SPRITE_LOG("load(\"" << basePath << "\")");
    // Pattern 1: <basePath>.png + <basePath>.json
    std::string pngPath = basePath + ".png";
    std::string jsonPath = basePath + ".json";

    if (!texture.loadFromFile(pngPath)) {
        // Pattern 2: <basePath>_sheet.png + <basePath>_meta.json
        pngPath = basePath + "_sheet.png";
        jsonPath = basePath + "_meta.json";
        if (!texture.loadFromFile(pngPath)) {
            SPRITE_LOG("  FAIL: nessun PNG trovato ne' come " << basePath << ".png ne' come " << basePath << "_sheet.png");
            loaded = false;
            return false;
        }
    }
    SPRITE_LOG("  PNG caricato: " << pngPath);
    // Disattiva smoothing per pixel art: mantiene i pixel netti anche quando
    // lo sprite viene scalato (es. x4 per schermo).
    texture.setSmooth(false);

    // Carica PRIMA i metadati (columns, rows, frameWidth, frameHeight, animazioni)
    // dal file JSON. Questo aggiorna columns/rows dai valori di default (6,4)
    // ai valori reali dello spritesheet (es. 4,1 per i nostri sheet 256x64).
    loadMetaOrDefault(jsonPath);
    SPRITE_LOG("  Meta caricato da " << jsonPath << ": columns=" << columns << ", rows=" << rows);

    // DOPO aver caricato i metadati, ricalcola frameW/frameH in base alle
    // dimensioni reali della texture e ai nuovi columns/rows.
    // IMPORTANTE: questo calcolo DEVE essere fatto dopo loadMetaOrDefault,
    // altrimenti userebbe i valori di default (columns=6, rows=4) e
    // calcolerebbe frameW=256/6=42, frameH=64/4=16 -> SBAGLIATO.
    // Con columns=4 dal JSON, frameW=256/4=64, frameH=64/1=64 -> CORRETTO.
    sf::Vector2u texSize = texture.getSize();
    if (texSize.x > 0 && texSize.y > 0 && columns > 0 && rows > 0) {
        // Ricalcola sempre da texture/columns/rows. Se il JSON specificava
        // frameWidth/frameHeight diversi, li rispettiamo solo se sono
        // coerenti con la griglia (texSize.x / columns == frameWidth).
        // Altrimenti usiamo il calcolo dalla texture (piu' affidabile).
        unsigned int calcFrameW = texSize.x / columns;
        unsigned int calcFrameH = texSize.y / rows;
        // Override dei valori dal JSON solo se sono 0 (default) o
        // inconsistenti con la texture
        frameW = (int)calcFrameW;
        frameH = (int)calcFrameH;
    }
    SPRITE_LOG("  Texture size: " << texSize.x << "x" << texSize.y << ", frameW=" << frameW << ", frameH=" << frameH);
    // Log animazioni caricate
    for (const auto& kv : animations) {
        SPRITE_LOG("  Anim '" << kv.first << "': row=" << kv.second.row << ", frames=" << kv.second.frames << ", dur=" << kv.second.frameDuration);
    }
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

// ---------------------------------------------------------------------------
// render (overload con scaling): come render() ma applica uno scale factor
// al frame. Usato per i boss che hanno `size` variabile ma sprite 64x64.
// L'ancora dei piedi (32, 56) viene scalata proporzionalmente.
// ---------------------------------------------------------------------------
void SpriteSheet::render(sf::RenderTarget& target, const std::string& animName,
                          int frameIdx, float x, float y, float scale,
                          bool flipped) const {
    if (!loaded) return;
    auto it = animations.find(animName);
    if (it == animations.end()) return;
    const AnimInfo& info = it->second;

    int idx = frameIdx;
    if (info.frames > 0) idx = ((idx % info.frames) + info.frames) % info.frames;

    int sx = idx * frameW;
    int sy = info.row * frameH;
    sf::IntRect rect(sx, sy, frameW, frameH);

    sf::Sprite sprite(texture, rect);
    // Anchor a coordinate frame (32, 56).
    // Per flip corretto: se flipped, anchor speculare (frameW - centerX).
    float ox = frameW * 0.5f;
    float oy = frameH * (56.f / 64.f);
    if (flipped) ox = frameW - ox;
    sprite.setOrigin(ox, oy);
    sprite.setPosition(x, y);
    float scaleX = flipped ? -scale : scale;
    sprite.setScale(scaleX, scale);
    target.draw(sprite);
}

// ---------------------------------------------------------------------------
// render (overload con tint color): come render(scale) ma applica anche un
// tint color moltiplicativo. Usato per distinguere P1 da P2 quando scelgono
// lo stesso personaggio: P2 viene tinto di un colore diverso.
// ---------------------------------------------------------------------------
void SpriteSheet::render(sf::RenderTarget& target, const std::string& animName,
                          int frameIdx, float x, float y, float scale,
                          bool flipped, const sf::Color& tint) const {
    if (!loaded) return;
    auto it = animations.find(animName);
    if (it == animations.end()) return;
    const AnimInfo& info = it->second;

    int idx = frameIdx;
    if (info.frames > 0) idx = ((idx % info.frames) + info.frames) % info.frames;

    int sx = idx * frameW;
    int sy = info.row * frameH;
    sf::IntRect rect(sx, sy, frameW, frameH);

    sf::Sprite sprite(texture, rect);
    // Anchor a coordinate frame (32, 56) - NON dividere per scale.
    // L'anchor e' il punto del frame che coincide con (x, y).
    // Per flip corretto: se flipped, l'anchor X deve essere specchiato
    // rispetto al centro del frame (frameW - 32 invece di 32).
    float ox = frameW * 0.5f;
    float oy = frameH * (56.f / 64.f);
    if (flipped) {
        // Quando flippiamo, l'anchor speculare e' (frameW - centerX).
        // In modalita' coordinate frame, e' (frameW - ox).
        ox = frameW - ox;
    }
    sprite.setOrigin(ox, oy);
    sprite.setPosition(x, y);
    // Scale combinato: se flipped, scaleX = -scale, altrimenti +scale
    float scaleX = flipped ? -scale : scale;
    sprite.setScale(scaleX, scale);
    sprite.setColor(tint);
    target.draw(sprite);
}
