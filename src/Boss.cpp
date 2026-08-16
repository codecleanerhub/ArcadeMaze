#include "Boss.h"
#include "Weapon.h"
#include <cstdlib>
#include <cmath>
#include <fstream>

// ===========================================================================
// Boss.cpp - Implementazione dei boss.
//
// Il boss si muove sempre diagonalmente e rimbalza sui bordi della stanza.
// Per lo sparo usa un pattern a ventaglio (3 colpi) piu' un eventuale
// colpo "bomba" (piu' lento ma danno doppio). Tutti i boss hanno la stessa
// logica di gioco; il rendering e' personalizzato per tipo.
//
// Le animazioni sono basate su `animTime` (incrementato di ~16 ms per frame):
// questo crea movimenti fluidi di ali, braccia, bocche, occhi, ecc.
//
// Rendering: ogni tipo ha uno sprite associato (mappa BossType -> ID file).
// Se il PNG e' caricato (loadAllSprites), viene usato lo SpriteSheet;
// altrimenti fallback a renderPrimitives (vecchio disegno a primitive).
// ===========================================================================

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// --- Membri statici ---
std::map<BossType, SpriteSheet> Boss::sprites;
bool Boss::spritesLoaded = false;

// ---------------------------------------------------------------------------
// getSpriteId: mappa BossType -> ID file bestiary.
//
// Tutti i 17 tipi hanno match diretto col bestiary fantasy horror:
//   BOSS_GHOUL_LORD         -> boss_021 (Signore dei Ghoul)
//   BOSS_SPECTRAL_ALPHA     -> boss_023 (Lupo Alpha Spettrale)
//   BOSS_CULT_HERALD        -> boss_024 (Araldo del Culto)
//   BOSS_COLOSSAL_MIMIC     -> boss_025 (Mimic Colossale)
//   BOSS_RAT_KING           -> boss_026 (Re dei Topi)
//   BOSS_SUPREME_WITCH      -> boss_027 (Strega Suprema delle Paludi)
//   BOSS_TWILIGHT_KNIGHT    -> boss_028 (Cavaliere del Crepuscolo)
//   BOSS_VAMPIRE            -> boss_029 (Vescovo Vampiro)
//   BOSS_KRAKEN             -> boss_030 (Guardiano delle Profondita')
//
// I 7 tipi originali senza match diretto nel file bestiary (GOLEM, LICH,
// DEMON, ABOMINATION, DRAGON, WRAITH_LORD, BEHOLDER) sono stati rimappati
// sui 7 nuovi tipi del file per allineamento totale:
//   BOSS_GOLEM         -> boss_021 (Signore dei Ghoul, golem-like)
//   BOSS_LICH          -> boss_024 (Araldo del Culto, caster undead)
//   BOSS_DEMON         -> boss_025 (Mimic Colossale, big monster)
//   BOSS_ABOMINATION   -> boss_026 (Re dei Topi, abomination-like)
//   BOSS_DRAGON        -> boss_023 (Lupo Alpha, beast)
//   BOSS_WRAITH_LORD   -> boss_028 (Cavaliere del Crepuscolo, wraith-like)
//   BOSS_BEHOLDER      -> boss_027 (Strega Suprema, multi-eye caster)
// ---------------------------------------------------------------------------
std::string Boss::getSpriteId(BossType t) {
    switch(t) {
        // 10 tipi originali - rimappati sui 7 nuovi + 3 esistenti
        case BOSS_GOLEM:         return "boss_021";
        case BOSS_LICH:          return "boss_024";
        case BOSS_DEMON:         return "boss_025";
        case BOSS_SPIDER:        return "boss_022";
        case BOSS_ABOMINATION:   return "boss_026";
        case BOSS_KRAKEN:        return "boss_030";
        case BOSS_DRAGON:        return "boss_023";
        case BOSS_WRAITH_LORD:   return "boss_028";
        case BOSS_VAMPIRE:       return "boss_029";
        case BOSS_BEHOLDER:      return "boss_027";
        // 7 nuovi tipi (mappati 1:1 sul file)
        case BOSS_GHOUL_LORD:        return "boss_021";
        case BOSS_SPECTRAL_ALPHA:    return "boss_023";
        case BOSS_CULT_HERALD:       return "boss_024";
        case BOSS_COLOSSAL_MIMIC:    return "boss_025";
        case BOSS_RAT_KING:          return "boss_026";
        case BOSS_SUPREME_WITCH:     return "boss_027";
        case BOSS_TWILIGHT_KNIGHT:   return "boss_028";
    }
    return "";
}

// ---------------------------------------------------------------------------
// loadAllSprites: carica tutti gli sprite dei boss dalla cartella `basePath`.
// Per ogni tipo (tutti i 17), prova a caricare `<basePath>/<id>`. I file
// mancanti vengono saltati silenziosamente.
// ---------------------------------------------------------------------------
bool Boss::loadAllSprites(const std::string& basePath) {
    spritesLoaded = false;
    BossType allTypes[] = {
        BOSS_GOLEM, BOSS_LICH, BOSS_DEMON, BOSS_SPIDER,
        BOSS_ABOMINATION, BOSS_KRAKEN, BOSS_DRAGON,
        BOSS_WRAITH_LORD, BOSS_VAMPIRE, BOSS_BEHOLDER,
        BOSS_GHOUL_LORD, BOSS_SPECTRAL_ALPHA, BOSS_CULT_HERALD,
        BOSS_COLOSSAL_MIMIC, BOSS_RAT_KING, BOSS_SUPREME_WITCH,
        BOSS_TWILIGHT_KNIGHT
    };
    bool any = false;
    for (BossType t : allTypes) {
        std::string id = getSpriteId(t);
        if (id.empty()) continue;
        std::string path = basePath + "/" + id;
        if (sprites[t].load(path)) {
            any = true;
        }
    }
    spritesLoaded = any;
    return any;
}

void Boss::unloadAllSprites() {
    sprites.clear();
    spritesLoaded = false;
}

// ---------------------------------------------------------------------------
// Costruttore: configura il boss per il livello.
//   * size: cresce col livello (160 + lvl*10)
//   * speed: cresce lentamente (1 + lvl/2)
//   * health: 50 + lvl*20 (il boss del livello 10 ha 250 HP)
//   * dx/dy: direzione iniziale (alternata in base alla parita' del livello)
//   * type: ciclo sui 17 tipi (1->GOLEM, ..., 17->TWILIGHT_KNIGHT)
//   * attackingTimer: inizializzato a 0 (nessun attacco in corso)
// ---------------------------------------------------------------------------
Boss::Boss(int lvl, int w, int h) : shootTimer(0), animTime(0.0f), attackingTimer(0) {
    level = lvl; screenWidth = w; screenHeight = h;
    size = 160 + lvl * 10;
    // Posizione iniziale: centro orizzontale, sotto la UI
    pos.x = w / 2.0f; pos.y = UI_HEIGHT + 120.0f + size;
    // Direzione iniziale alternata per evitare pattern sempre uguali
    dx = (lvl % 2 == 0) ? 2 : -2; dy = (lvl % 3 == 0) ? 1 : -1;
    speed = 1 + lvl / 2;
    health = 50 + lvl * 20; maxHealth = health;
    // Tipo ciclico sui 17 tipi disponibili
    type = static_cast<BossType>((lvl - 1) % BOSS_TYPE_COUNT);
}

// ---------------------------------------------------------------------------
// update: muove il boss e gestisce lo sparo.
//
// Movimento:
//   * Aggiorna animTime.
//   * Sposta in diagonale; inverte dx/dy quando tocca i bordi della stanza.
// Sparo:
//   * Ogni (1500 - level*100) ms spara un ventaglio di 3 colpi verso il
//     giocatore (angolo base + -0.3 rad).
//   * Con probabilita' 1/3 aggiunge un colpo "bomba" (WPN_ROCKET) piu'
//     lento (velocita' 2) ma con danno 2 e direzione leggermente random.
//   * Man mano che il livello aumenta, il cooldown diminuisce (spara piu'
//     spesso), ma non scende sotto ~500 ms (1500-10*100).
// ---------------------------------------------------------------------------
void Boss::update(float playerX, float playerY, std::vector<Projectile>& bossProjectiles) {
    animTime += 0.016f;  // ~16 ms per frame a 60 FPS
    // Decrementa attackingTimer (16 ms per frame a 60 FPS)
    if (attackingTimer > 16) attackingTimer -= 16; else attackingTimer = 0;
    pos.x += dx * speed; pos.y += dy * speed;
    // Rimbalzo sui bordi orizzontali
    if (pos.x < size/2 || pos.x > screenWidth - size/2) dx = -dx;
    // Rimbalzo sui bordi verticali (sotto la UI, sopra il fondo finestra)
    if (pos.y < UI_HEIGHT + size/2 || pos.y > screenHeight - size/2) dy = -dy;
    shootTimer += 16;

    // Sparo a ventaglio: il cooldown diminuisce col livello (min ~500 ms).
    // Cast a uint32_t per evitare -Wsign-compare fra shootTimer (unsigned) e
    // l'espressione (1500 - level*100) che e' int firmato.
    if (shootTimer > (uint32_t)(1500 - level * 100)) {
        shootTimer = 0;
        // Triggera animazione di attacco per ~500 ms dopo lo sparo
        attackingTimer = 500;
        float dxp = playerX - pos.x, dyp = playerY - pos.y;
        float dist = sqrt(dxp*dxp + dyp*dyp);
        if (dist > 0) {
            float baseAngle = atan2(dyp, dxp);
            // 3 colpi a ventaglio con passo 0.3 rad (~17°)
            for(int i = -1; i <= 1; i++) {
                float angle = baseAngle + i * 0.3f;
                bossProjectiles.push_back({pos, sf::Vector2f(cos(angle)*5.0f, sin(angle)*5.0f), 1, true, WPN_PISTOL});
            }
            // Bomba: 1/3 di probabilita', danno 2, piu' lenta
            if (rand() % 3 == 0) {
                float bombAngle = baseAngle + (rand()%60 - 30) * (M_PI/180.0f);
                bossProjectiles.push_back({pos, sf::Vector2f(cos(bombAngle)*2.0f, sin(bombAngle)*2.0f), 2, true, WPN_ROCKET});
            }
        }
    }
}

void Boss::takeDamage(int dmg) { health -= dmg; }

// ---------------------------------------------------------------------------
// render: disegna il boss. Per ognuno dei 10 tipi c'e' uno sprite specifico
// con animazioni guidate da `animTime`:
//   * BOSS_GOLEM: braccia che oscillano, occhi che pulsano
//   * BOSS_LICH: mantello che ondeggia
//   * BOSS_DEMON: ali che sbattono
//   * BOSS_SPIDER: zampe che si muovono
//   * BOSS_ABOMINATION: braccia che oscillano, occhi spenti
//   * BOSS_KRAKEN: tentacoli ondeggianti
//   * BOSS_DRAGON: ali e collo animati
//   * BOSS_WRAITH_LORD: mantello con onde multiple
//   * BOSS_VAMPIRE: mantello che ondeggia
//   * BOSS_BEHOLDER: corpo pulsante, pupilla che si muove, 10 occhi satellite
//
// In comune: ombra a terra, bocca con denti (tranne BEHOLDER/LICH che hanno
// gestioni custom), e barra HP rossa sopra la testa.
// ---------------------------------------------------------------------------
void Boss::render(sf::RenderTarget& target) const {
    float px = pos.x;
    float py = pos.y;

    // Ombra ellittica a terra (cerchio piatto piu' basso del boss)
    sf::CircleShape shadow(size/2.0f);
    shadow.setFillColor(sf::Color(0, 0, 0, 150));
    shadow.setPosition(px - size/2.0f, py + size/4.0f);
    target.draw(shadow);

    // Tentativo di rendering con sprite.
    // Lo sprite del boss e' 64x64 ma il boss ha `size` variabile (160+).
    // Applichiamo uno scaling = size/64 per far coincidere l'hitbox con
    // lo sprite visibile.
    // Animazioni: usa "attack" se attackingTimer>0, altrimenti "idle".
    auto it = sprites.find(type);
    if (it != sprites.end() && it->second.isLoaded()) {
        // Selezione animazione: attack > idle (walk non usato per i boss)
        std::string animName = "idle";
        int frameCount = it->second.getFrameCount(animName);
        int frameDuration = 200;
        bool isAttacking = (attackingTimer > 0)
                           && (it->second.getFrameCount("attack") > 0);
        if (isAttacking) {
            animName = "attack";
            frameCount = it->second.getFrameCount(animName);
            frameDuration = 80;  // ~480 ms totali per 6 frame
        }
        if (frameCount > 0) {
            int frame = ((int)(animTime * 1000.0f / frameDuration)) % frameCount;
            if (frame < 0) frame += frameCount;
            // Scale: size/64 per far coincidere l'hitbox con lo sprite.
            // Il boss ha size 160-260px, sprite 64px -> scale 2.5-4.0 naturale.
            float scale = (float)size / 64.0f;
            float drawX = px;
            float drawY = py - size * 0.25f;
            it->second.render(target, animName, frame, drawX, drawY, scale, false);
            // Barra HP sopra la testa
            sf::RectangleShape hbBg(sf::Vector2f(size, 15.0f)); hbBg.setFillColor(sf::Color(50, 0, 0));
            hbBg.setPosition(px - size/2, py - size/2 - 30); target.draw(hbBg);
            sf::RectangleShape hbFg(sf::Vector2f(size * health / maxHealth, 15.0f)); hbFg.setFillColor(sf::Color(255, 50, 50));
            hbFg.setPosition(px - size/2, py - size/2 - 30); target.draw(hbFg);
            return;
        }
    }

    // Fallback: rendering a primitive (codice originale)
    renderPrimitives(target);
}

// ---------------------------------------------------------------------------
// renderPrimitives: disegna il boss con rettangoli/cerchi/poligoni.
// Codice originale mantenuto intatto come fallback quando gli sprite PNG
// non sono disponibili.
// ---------------------------------------------------------------------------
void Boss::renderPrimitives(sf::RenderTarget& target) const {
    float px = pos.x;
    float py = pos.y;
    sf::Color outline(10, 10, 10);

    // Animazione bocca: oscillazione sinusoidale
    float mouthOpen = (sin(animTime * 4.0f) + 1.0f) / 2.0f;  // 0..1
    float mouthHeight = size/6.0f + mouthOpen * size/6.0f;   // size/6 .. size/3

    if (type == BOSS_GOLEM) {
        // Golem di pietra: corpo massiccio, braccia che oscillano, occhi verdi
        sf::Color rock(100, 100, 110);
        sf::RectangleShape body(sf::Vector2f(size, size*4/5));
        body.setFillColor(rock); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.0f, py - size*2/5); target.draw(body);

        // Braccia che oscillano in controfase
        float armOffset = sin(animTime * 3.0f) * 10.0f;
        sf::RectangleShape arm1(sf::Vector2f(size*3/10, size*3/5));
        arm1.setFillColor(sf::Color(60, 60, 70)); arm1.setOutlineThickness(3.0f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*4/5, py - size/5 + armOffset); target.draw(arm1);
        arm1.setPosition(px + size/2, py - size/5 - armOffset); target.draw(arm1);

        sf::RectangleShape head(sf::Vector2f(size/2, size/2));
        head.setFillColor(rock); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/4, py - size*4/5); target.draw(head);

        // Occhi verdi pulsanti
        sf::Uint8 eyeBright = 150 + sin(animTime * 10.0f) * 105;
        sf::CircleShape eye(size/12.0f); eye.setFillColor(sf::Color(0, eyeBright, 50));
        eye.setPosition(px - size/4 - size/12, py - size*3/5); target.draw(eye);
        eye.setPosition(px + size/4 - size/12, py - size*3/5); target.draw(eye);
    }
    else if (type == BOSS_LICH) {
        // Lich: teschio e mantello viola che ondeggia
        sf::ConvexShape robe; robe.setPointCount(5);
        robe.setFillColor(sf::Color(40, 20, 60)); robe.setOutlineThickness(4.0f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py - size/2.0f));
        float wave1 = sin(animTime * 3.0f) * 10.0f;
        robe.setPoint(1, sf::Vector2f(px + size/2.0f + wave1, py));
        robe.setPoint(2, sf::Vector2f(px + size/3.0f, py + size/2.0f));
        robe.setPoint(3, sf::Vector2f(px - size/3.0f, py + size/2.0f));
        robe.setPoint(4, sf::Vector2f(px - size/2.0f - wave1, py));
        target.draw(robe);

        sf::CircleShape skull(size/3.0f); skull.setFillColor(sf::Color(220, 220, 200)); skull.setOutlineThickness(3.0f); skull.setOutlineColor(outline);
        skull.setPosition(px - size/3.0f, py - size/2.0f); target.draw(skull);

        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px - size/5, py - size/3); target.draw(eye);
        eye.setPosition(px + size/10, py - size/3); target.draw(eye);

        // Bocca: meta' altezza per il Lich (look "sottile")
        sf::RectangleShape mouth(sf::Vector2f(size*2/5, mouthHeight/2));
        mouth.setFillColor(sf::Color::Black);
        mouth.setPosition(px - size/5, py + size/8); target.draw(mouth);
    }
    else if (type == BOSS_DEMON) {
        // Demone: corpo rosso, ali sbattono, corna
        float wingFlap = sin(animTime * 8.0f) * 0.4f + 0.8f;  // ampiezza ala
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(80, 10, 10)); wing.setOutlineThickness(3.0f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px - size/3, py - size/4));
        wing.setPoint(1, sf::Vector2f(px - size*6/5, py - size/2 * wingFlap));
        wing.setPoint(2, sf::Vector2f(px - size*11/10, py + size/4 * wingFlap));
        wing.setPoint(3, sf::Vector2f(px - size/3, py + size/6));
        target.draw(wing);
        // Ala destra: specchiata
        wing.scale(-1.0f, 1.0f); wing.setPosition(px + size/3, py - size/4); target.draw(wing);

        sf::CircleShape body(size/2.0f); body.setFillColor(sf::Color(150, 30, 30)); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.0f, py - size/2.0f); target.draw(body);

        // Corna laterali
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(outline);
        horn.setPoint(0, sf::Vector2f(px - size/3, py - size/2));
        horn.setPoint(1, sf::Vector2f(px - size/2, py - size*4/5));
        horn.setPoint(2, sf::Vector2f(px - size/4, py - size*7/10));
        target.draw(horn);

        horn.setPoint(0, sf::Vector2f(px + size/3, py - size/2));
        horn.setPoint(1, sf::Vector2f(px + size/2, py - size*4/5));
        horn.setPoint(2, sf::Vector2f(px + size/4, py - size*7/10));
        target.draw(horn);

        sf::CircleShape eye(size/10.0f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - size/4 - size/10, py - size/6); target.draw(eye);
        eye.setPosition(px + size/4 - size/10, py - size/6); target.draw(eye);
    }
    else if (type == BOSS_SPIDER) {
        // Ragno gigante: 8 zampe che si muovono, addome viola
        sf::Color carapace(40, 0, 50);
        for(int i=0; i<4; i++) {
            float angle1 = (45 + i*20) * M_PI / 180.0f;
            float angle2 = (-45 - i*20) * M_PI / 180.0f;
            float legMove = sin(animTime * 6.0f + i) * 10.0f;

            sf::RectangleShape leg1(sf::Vector2f(size/2.0f, size/16.0f));
            leg1.setFillColor(carapace); leg1.setOutlineThickness(2.0f); leg1.setOutlineColor(outline);
            leg1.rotate(angle1 * 180 / M_PI); leg1.setPosition(px - size/4, py + legMove); target.draw(leg1);

            sf::RectangleShape leg2(sf::Vector2f(size/2.0f, size/16.0f));
            leg2.setFillColor(carapace); leg2.setOutlineThickness(2.0f); leg2.setOutlineColor(outline);
            leg2.rotate(angle2 * 180 / M_PI); leg2.setPosition(px + size/4, py - legMove); target.draw(leg2);
        }
        sf::CircleShape abdomen(size/2.0f); abdomen.setFillColor(carapace); abdomen.setOutlineThickness(4.0f); abdomen.setOutlineColor(outline);
        abdomen.setPosition(px - size/2.0f, py - size/4); target.draw(abdomen);
        sf::CircleShape head(size/4.0f); head.setFillColor(sf::Color(60, 0, 70)); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/8, py - size*2/3); target.draw(head);

        // Occhi rossi pulsanti
        sf::Uint8 eyeBright = 150 + sin(animTime * 8.0f) * 105;
        sf::CircleShape eye(size/20.0f); eye.setFillColor(sf::Color(eyeBright, 0, 0));
        eye.setPosition(px - size/6, py - size*5/8); target.draw(eye);
        eye.setPosition(px + size/12, py - size*5/8); target.draw(eye);
    }
    else if (type == BOSS_ABOMINATION) {
        // Abominazione: corpo carnoso, braccia asimmetriche, bulloni sul collo
        sf::Color flesh(140, 160, 120);
        sf::RectangleShape body(sf::Vector2f(size*4/5, size));
        body.setFillColor(flesh); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size*2/5, py - size/2.0f); target.draw(body);

        // Braccia che oscillano in controfase
        float armWave = sin(animTime * 2.0f) * 15.0f;
        sf::RectangleShape arm1(sf::Vector2f(size*3/10, size*7/10));
        arm1.setFillColor(flesh); arm1.setOutlineThickness(3.0f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*7/10, py - size/3 + armWave); target.draw(arm1);
        arm1.setPosition(px + size*2/5, py - size/3 - armWave); target.draw(arm1);

        sf::RectangleShape head(sf::Vector2f(size*2/5, size*2/5));
        head.setFillColor(flesh); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/5, py - size*9/10); target.draw(head);

        // Bulloni metallici laterali sul collo (stile Frankenstein)
        sf::RectangleShape bolt1(sf::Vector2f(size/10, size/10)); bolt1.setFillColor(sf::Color(180, 180, 180));
        bolt1.setPosition(px - size*3/10, py - size*4/5); target.draw(bolt1);
        bolt1.setPosition(px + size/5, py - size*4/5); target.draw(bolt1);

        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(50, 50, 50));
        eye.setPosition(px - size/5, py - size*3/4); target.draw(eye);
        eye.setPosition(px + size/10, py - size*3/4); target.draw(eye);
    }
    else if (type == BOSS_KRAKEN) {
        // Kraken: 8 tentacoli ondeggianti, corpo centrale
        sf::Color skin(0, 100, 100);
        for(int i=0; i<8; i++) {
            // Ogni tentacolo ha un'angolazione che oscilla leggermente
            float angle = i * (M_PI / 4) + sin(animTime * 2.0f + i) * 0.2f;
            sf::ConvexShape tent; tent.setPointCount(4);
            tent.setFillColor(skin); tent.setOutlineThickness(2.0f); tent.setOutlineColor(outline);
            tent.setPoint(0, sf::Vector2f(px, py));
            tent.setPoint(1, sf::Vector2f(px + cos(angle)*size/3, py + sin(angle)*size/3));
            tent.setPoint(2, sf::Vector2f(px + cos(angle)*size/2 + 10, py + sin(angle)*size/2 + 10));
            tent.setPoint(3, sf::Vector2f(px + cos(angle)*size/2 - 10, py + sin(angle)*size/2 - 10));
            target.draw(tent);
        }
        sf::CircleShape body(size/2.0f); body.setFillColor(skin); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2.0f, py - size/2.0f); target.draw(body);
        sf::CircleShape eye(size/10.0f); eye.setFillColor(sf::Color(255, 255, 0));
        eye.setPosition(px - size/4 - size/10, py - size/4); target.draw(eye);
        eye.setPosition(px + size/4 - size/10, py - size/4); target.draw(eye);
    }
    else if (type == BOSS_DRAGON) {
        // Drago scheletro: ali, collo lungo, testa
        sf::Color bone(200, 200, 180);
        float wingFlap = sin(animTime * 6.0f) * 0.3f + 0.8f;
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(50, 50, 50)); wing.setOutlineThickness(3.0f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px - size/4, py - size/3));
        wing.setPoint(1, sf::Vector2f(px - size, py - size/2 * wingFlap));
        wing.setPoint(2, sf::Vector2f(px - size*9/10, py + size/6 * wingFlap));
        wing.setPoint(3, sf::Vector2f(px - size/4, py));
        target.draw(wing);
        wing.scale(-1.0f, 1.0f); wing.setPosition(px + size/4, py - size/3); target.draw(wing);

        // Collo che ondeggia (rotazione oscillante)
        float neckWave = sin(animTime * 2.0f) * 20.0f;
        sf::RectangleShape neck(sf::Vector2f(size/5, size*4/5));
        neck.setFillColor(bone); neck.rotate(-30 + neckWave); neck.setOutlineThickness(3.0f); neck.setOutlineColor(outline);
        neck.setPosition(px - size/10, py - size/10); target.draw(neck);

        // Testa in alto a sinistra
        sf::ConvexShape head; head.setPointCount(4);
        head.setFillColor(bone); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPoint(0, sf::Vector2f(px - size/2, py - size));
        head.setPoint(1, sf::Vector2f(px - size/4, py - size*11/10));
        head.setPoint(2, sf::Vector2f(px - size/4, py - size*9/10));
        head.setPoint(3, sf::Vector2f(px - size/2, py - size*9/10));
        target.draw(head);

        sf::CircleShape eye(size/20.0f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - size/2 + size/20, py - size + size/20); target.draw(eye);

        sf::RectangleShape body(sf::Vector2f(size*3/5, size*3/5));
        body.setFillColor(bone); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size*3/10, py - size/5); target.draw(body);
    }
    else if (type == BOSS_WRAITH_LORD) {
        // Signore dei Wraith: mantello con pieghe animate, elmo con corna
        sf::Color armor(100, 100, 150);
        sf::ConvexShape cloak; cloak.setPointCount(6);
        cloak.setFillColor(sf::Color(20, 20, 40, 220)); cloak.setOutlineThickness(4.0f); cloak.setOutlineColor(outline);
        // Le pieghe del mantello oscillano in modo differenziato
        float wave1 = sin(animTime * 4.0f) * 15.0f;
        cloak.setPoint(0, sf::Vector2f(px - size/2, py - size/3));
        cloak.setPoint(1, sf::Vector2f(px + size/2, py - size/3));
        cloak.setPoint(2, sf::Vector2f(px + size/3 + wave1, py + size/2));
        cloak.setPoint(3, sf::Vector2f(px + size/6, py + size/3 - wave1/2));
        cloak.setPoint(4, sf::Vector2f(px - size/6, py + size/2));
        cloak.setPoint(5, sf::Vector2f(px - size/3 - wave1, py + size/3 + wave1/2));
        target.draw(cloak);

        sf::RectangleShape helm(sf::Vector2f(size*2/5, size/2));
        helm.setFillColor(armor); helm.setOutlineThickness(3.0f); helm.setOutlineColor(outline);
        helm.setPosition(px - size/5, py - size*3/5); target.draw(helm);

        // Corna dell'elmo
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(armor);
        horn.setPoint(0, sf::Vector2f(px - size/5, py - size*3/5));
        horn.setPoint(1, sf::Vector2f(px - size*2/5, py - size*4/5));
        horn.setPoint(2, sf::Vector2f(px - size/5, py - size/2));
        target.draw(horn);

        horn.setPoint(0, sf::Vector2f(px + size/5, py - size*3/5));
        horn.setPoint(1, sf::Vector2f(px + size*2/5, py - size*4/5));
        horn.setPoint(2, sf::Vector2f(px + size/5, py - size/2));
        target.draw(horn);

        // Occhi ciano pulsanti
        sf::Uint8 eyeBright = 150 + sin(animTime * 5.0f) * 105;
        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(0, eyeBright, eyeBright, 200));
        eye.setPosition(px - size/5, py - size*9/20); target.draw(eye);
        eye.setPosition(px + size/10, py - size*9/20); target.draw(eye);
    }
    else if (type == BOSS_VAMPIRE) {
        // Vampiro: mantello rosso, carnagione pallida
        sf::Color skin(230, 230, 250);
        sf::ConvexShape cloak; cloak.setPointCount(4);
        cloak.setFillColor(sf::Color(120, 0, 0)); cloak.setOutlineThickness(4.0f); cloak.setOutlineColor(outline);
        float wave1 = sin(animTime * 3.0f) * 10.0f;
        cloak.setPoint(0, sf::Vector2f(px - size/2, py - size/4));
        cloak.setPoint(1, sf::Vector2f(px + size/2, py - size/4));
        cloak.setPoint(2, sf::Vector2f(px + size/3 + wave1, py + size/2));
        cloak.setPoint(3, sf::Vector2f(px - size/3 - wave1, py + size/2));
        target.draw(cloak);

        // Colletto bianco
        sf::RectangleShape collar(sf::Vector2f(size*3/10, size/10));
        collar.setFillColor(sf::Color(255, 255, 255)); collar.setOutlineThickness(2.0f); collar.setOutlineColor(outline);
        collar.setPosition(px - size*3/20, py - size*3/10); target.draw(collar);

        sf::CircleShape head(size/3.0f); head.setFillColor(skin); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/3, py - size/2); target.draw(head);

        // Capelli neri
        sf::RectangleShape hair(sf::Vector2f(size*3/5, size/5)); hair.setFillColor(sf::Color::Black);
        hair.setPosition(px - size*3/10, py - size/2); target.draw(hair);

        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px - size/5, py - size/3); target.draw(eye);
        eye.setPosition(px + size/10, py - size/3); target.draw(eye);
    }
    else if (type == BOSS_BEHOLDER) {
        // Beholder: corpo sferico pulsante, grande occhio centrale, 10 occhi
        // satellite in cima a steli che si muovono.
        sf::Color bodyCol(100, 50, 50);
        // Pulsazione del corpo (raggio +/- 10%)
        float pulse = 1.0f + sin(animTime * 4.0f) * 0.1f;
        sf::CircleShape body(size/2.0f * pulse);
        body.setFillColor(bodyCol); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - (size/2.0f * pulse), py - (size/2.0f * pulse)); target.draw(body);

        // Occhio centrale: sclera bianca + pupilla che si muove in cerchio
        sf::CircleShape eye(size/4.0f); eye.setFillColor(sf::Color::White); eye.setOutlineThickness(2.0f); eye.setOutlineColor(outline);
        eye.setPosition(px - size/4, py - size/4); target.draw(eye);

        float pupilX = px - size/8 + cos(animTime * 2.0f) * (size/20);
        float pupilY = py - size/8 + sin(animTime * 2.0f) * (size/20);
        sf::CircleShape pupil(size/8.0f); pupil.setFillColor(sf::Color::Black);
        pupil.setPosition(pupilX - size/8, pupilY - size/8); target.draw(pupil);

        // Iride rossa dentro la pupilla
        sf::CircleShape iris(size/16.0f); iris.setFillColor(sf::Color(255, 0, 0));
        iris.setPosition(pupilX - size/16, pupilY - size/16); target.draw(iris);

        // 8 occhi satellite su steli che ruotano attorno al corpo
        for(int i=0; i<8; i++) {
            float angle = i * (M_PI / 4) + sin(animTime * 3.0f + i) * 0.3f;
            float tx = px + cos(angle) * size/2;
            float ty = py + sin(angle) * size/2;
            // Stelo
            sf::RectangleShape stalk(sf::Vector2f(size/8, size/3));
            stalk.setFillColor(bodyCol); stalk.setOutlineThickness(2.0f); stalk.setOutlineColor(outline);
            stalk.rotate(angle * 180 / M_PI + 90); stalk.setPosition(tx, ty); target.draw(stalk);

            // Occhio satellite (bianco + pupilla nera)
            sf::CircleShape sEye(size/12.0f); sEye.setFillColor(sf::Color::White); sEye.setOutlineThickness(1.0f); sEye.setOutlineColor(outline);
            sEye.setPosition(tx - size/12, ty - size/12); target.draw(sEye);

            sf::CircleShape sPupil(size/24.0f); sPupil.setFillColor(sf::Color::Black);
            sPupil.setPosition(tx - size/24, ty - size/24); target.draw(sPupil);
        }
    }
    // === 7 nuovi tipi dal bestiary ===
    else if (type == BOSS_GHOUL_LORD) {
        // Signore dei Ghoul: corpo scheletrico + corona d'osso + aura necromantica
        sf::Color bone(220, 220, 200);
        sf::CircleShape aura(size/2.0f + 10.f);
        aura.setFillColor(sf::Color(80, 255, 80, 40));
        aura.setPosition(px - size/2.0f - 10.f, py - size/2.0f - 10.f);
        target.draw(aura);
        sf::RectangleShape body(sf::Vector2f(size*4/5, size));
        body.setFillColor(bone); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size*2/5, py - size/2.0f); target.draw(body);
        float armWave = sin(animTime * 2.0f) * 15.0f;
        sf::RectangleShape arm1(sf::Vector2f(size/5, size*3/5));
        arm1.setFillColor(bone); arm1.setOutlineThickness(3.0f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - size*3/5, py - size/4 + armWave); target.draw(arm1);
        arm1.setPosition(px + size*2/5, py - size/4 - armWave); target.draw(arm1);
        sf::CircleShape head(size/3.0f); head.setFillColor(bone); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px - size/3.0f, py - size*4/5); target.draw(head);
        for(int i=0; i<5; i++) {
            sf::ConvexShape spike; spike.setPointCount(3);
            spike.setFillColor(sf::Color(240, 240, 220));
            float sx = px - size/3.0f + i * (size*2/3.0f)/4;
            spike.setPoint(0, sf::Vector2f(sx, py - size*4/5));
            spike.setPoint(1, sf::Vector2f(sx + size/12, py - size*4/5));
            spike.setPoint(2, sf::Vector2f(sx + size/24, py - size*4/5 - size/8));
            target.draw(spike);
        }
        sf::CircleShape eye(size/14.0f); eye.setFillColor(sf::Color(255, 50, 50));
        eye.setPosition(px - size/5, py - size*3/5); target.draw(eye);
        eye.setPosition(px + size/10, py - size*3/5); target.draw(eye);
    }
    else if (type == BOSS_SPECTRAL_ALPHA) {
        // Lupo Alpha Spettrale: piu' grande, criniera di fumo
        sf::Color smoke(120, 120, 140, 200);
        for(int i=0; i<6; i++) {
            float a = i * (M_PI / 3.0f) + animTime;
            sf::CircleShape puff(size/4.0f);
            puff.setFillColor(smoke);
            puff.setPosition(px - size/2 + cos(a)*size/3, py - size/3 + sin(a)*size/4);
            target.draw(puff);
        }
        sf::ConvexShape body; body.setPointCount(5);
        body.setFillColor(sf::Color(90, 90, 110, 230)); body.setOutlineThickness(3.0f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-size/2, py+size/4)); body.setPoint(1, sf::Vector2f(px-size/3, py-size/4));
        body.setPoint(2, sf::Vector2f(px+size/4, py-size/4)); body.setPoint(3, sf::Vector2f(px+size/2, py));
        body.setPoint(4, sf::Vector2f(px+size/3, py+size/4));
        target.draw(body);
        sf::CircleShape head(size/4.0f); head.setFillColor(sf::Color(110, 110, 130, 230)); head.setOutlineThickness(3.0f); head.setOutlineColor(outline);
        head.setPosition(px + size/4, py - size/3); target.draw(head);
        sf::ConvexShape ear; ear.setPointCount(3); ear.setFillColor(sf::Color(90, 90, 110, 230));
        ear.setPoint(0, sf::Vector2f(px+size/4, py-size/3)); ear.setPoint(1, sf::Vector2f(px+size/5, py-size/2)); ear.setPoint(2, sf::Vector2f(px+size/3, py-size/3));
        target.draw(ear);
        sf::CircleShape eye(size/20.0f); eye.setFillColor(sf::Color(150, 255, 150));
        eye.setPosition(px + size/3, py - size/4); target.draw(eye);
    }
    else if (type == BOSS_CULT_HERALD) {
        // Araldo del Culto: tunica sontuosa + bastone + sigilli
        sf::ConvexShape robe; robe.setPointCount(6);
        robe.setFillColor(sf::Color(60, 0, 80)); robe.setOutlineThickness(4.0f); robe.setOutlineColor(outline);
        float wave = sin(animTime * 3.0f) * 15.0f;
        robe.setPoint(0, sf::Vector2f(px - size/2, py - size/3));
        robe.setPoint(1, sf::Vector2f(px + size/2, py - size/3));
        robe.setPoint(2, sf::Vector2f(px + size/3 + wave, py + size/2));
        robe.setPoint(3, sf::Vector2f(px + size/6, py + size/3));
        robe.setPoint(4, sf::Vector2f(px - size/6, py + size/2));
        robe.setPoint(5, sf::Vector2f(px - size/3 - wave, py + size/3));
        target.draw(robe);
        sf::CircleShape hood(size/3.0f); hood.setFillColor(sf::Color(40, 0, 60)); hood.setOutlineThickness(3.0f); hood.setOutlineColor(outline);
        hood.setPosition(px - size/3, py - size*4/5); target.draw(hood);
        sf::CircleShape face(size/6.0f); face.setFillColor(sf::Color::Black);
        face.setPosition(px - size/6, py - size*2/3); target.draw(face);
        sf::CircleShape eye(size/24.0f); eye.setFillColor(sf::Color(255, 215, 0));
        eye.setPosition(px - size/12, py - size*7/12); target.draw(eye);
        eye.setPosition(px + size/24, py - size*7/12); target.draw(eye);
        sf::RectangleShape staff(sf::Vector2f(size/12, size*4/5));
        staff.setFillColor(sf::Color(120, 80, 40)); staff.setOutlineThickness(2.0f); staff.setOutlineColor(outline);
        staff.setPosition(px + size*2/5, py - size/3); target.draw(staff);
        sf::CircleShape sigil(size/10.0f); sigil.setFillColor(sf::Color(180, 50, 220, 200));
        sigil.setPosition(px + size*2/5 - size/30, py - size/3 - size/10); target.draw(sigil);
    }
    else if (type == BOSS_COLOSSAL_MIMIC) {
        // Mimic Colossale: forziere gigante con bocca spalancata
        sf::Color wood(110, 70, 30);
        sf::RectangleShape body(sf::Vector2f(size, size*4/5));
        body.setFillColor(wood); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size/2, py - size/3); target.draw(body);
        sf::ConvexShape lid; lid.setPointCount(4);
        lid.setFillColor(sf::Color(80, 50, 20)); lid.setOutlineThickness(3.0f); lid.setOutlineColor(outline);
        lid.setPoint(0, sf::Vector2f(px - size/2, py - size/3));
        lid.setPoint(1, sf::Vector2f(px + size/2, py - size/3));
        lid.setPoint(2, sf::Vector2f(px + size/3, py - size*4/5));
        lid.setPoint(3, sf::Vector2f(px - size/3, py - size*4/5));
        target.draw(lid);
        sf::RectangleShape maw(sf::Vector2f(size*4/5, size/4));
        maw.setFillColor(sf::Color::Black);
        maw.setPosition(px - size*2/5, py - size/8); target.draw(maw);
        for(int i=0; i<8; i++) {
            sf::ConvexShape tooth; tooth.setPointCount(3);
            tooth.setFillColor(sf::Color(255, 255, 220));
            float tw = (size*4/5) / 8;
            tooth.setPoint(0, sf::Vector2f(px - size*2/5 + i*tw, py - size/8));
            tooth.setPoint(1, sf::Vector2f(px - size*2/5 + (i+1)*tw, py - size/8));
            tooth.setPoint(2, sf::Vector2f(px - size*2/5 + i*tw + tw/2, py));
            target.draw(tooth);
        }
        sf::ConvexShape tongue; tongue.setPointCount(4);
        tongue.setFillColor(sf::Color(220, 80, 120));
        tongue.setPoint(0, sf::Vector2f(px - size/8, py));
        tongue.setPoint(1, sf::Vector2f(px + size/8, py));
        tongue.setPoint(2, sf::Vector2f(px + size/12, py + size/6));
        tongue.setPoint(3, sf::Vector2f(px - size/12, py + size/6));
        target.draw(tongue);
        sf::RectangleShape band1(sf::Vector2f(size/12, size*4/5));
        band1.setFillColor(sf::Color(200, 200, 200));
        band1.setPosition(px - size/3, py - size/3); target.draw(band1);
        band1.setPosition(px + size/4, py - size/3); target.draw(band1);
    }
    else if (type == BOSS_RAT_KING) {
        // Re dei Topi: groviglio di ratti con corona d'osso
        sf::Color fur(80, 70, 60);
        for(int i=0; i<5; i++) {
            float a = i * (2*M_PI/5) + animTime * 0.5f;
            sf::CircleShape body(size/5.0f);
            body.setFillColor(fur); body.setOutlineThickness(2.0f); body.setOutlineColor(outline);
            body.setPosition(px + cos(a)*size/3 - size/5, py + sin(a)*size/3 - size/5);
            target.draw(body);
            sf::CircleShape eye(size/30.0f); eye.setFillColor(sf::Color(255, 0, 0));
            eye.setPosition(px + cos(a)*size/3 - size/15, py + sin(a)*size/3 - size/15);
            target.draw(eye);
        }
        sf::CircleShape mainBody(size/3.0f); mainBody.setFillColor(sf::Color(60, 50, 40)); mainBody.setOutlineThickness(3.0f); mainBody.setOutlineColor(outline);
        mainBody.setPosition(px - size/3, py - size/3); target.draw(mainBody);
        for(int i=0; i<5; i++) {
            sf::ConvexShape spike; spike.setPointCount(3);
            spike.setFillColor(sf::Color(240, 240, 220));
            float sx = px - size/4 + i * size/8;
            spike.setPoint(0, sf::Vector2f(sx, py - size/3));
            spike.setPoint(1, sf::Vector2f(sx + size/12, py - size/3));
            spike.setPoint(2, sf::Vector2f(sx + size/24, py - size/2));
            target.draw(spike);
        }
        sf::CircleShape eye(size/16.0f); eye.setFillColor(sf::Color(255, 30, 30));
        eye.setPosition(px - size/8, py - size/6); target.draw(eye);
        eye.setPosition(px + size/16, py - size/6); target.draw(eye);
    }
    else if (type == BOSS_SUPREME_WITCH) {
        // Strega Suprema: cappello grande + tunica + viti animate
        sf::Color robe(40, 80, 40);
        for(int i=0; i<6; i++) {
            float a = i * (M_PI / 3.0f) + animTime;
            sf::RectangleShape vine(sf::Vector2f(size/12, size/3));
            vine.setFillColor(sf::Color(60, 120, 60));
            vine.setOutlineThickness(1.5f); vine.setOutlineColor(outline);
            vine.rotate(a * 180 / M_PI);
            vine.setPosition(px + cos(a)*size/3, py + sin(a)*size/3);
            target.draw(vine);
        }
        sf::ConvexShape robeShape; robeShape.setPointCount(5);
        robeShape.setFillColor(robe); robeShape.setOutlineThickness(4.0f); robeShape.setOutlineColor(outline);
        float wave = sin(animTime * 2.0f) * 12.0f;
        robeShape.setPoint(0, sf::Vector2f(px, py - size/3));
        robeShape.setPoint(1, sf::Vector2f(px + size/2 + wave, py));
        robeShape.setPoint(2, sf::Vector2f(px + size/3, py + size/2));
        robeShape.setPoint(3, sf::Vector2f(px - size/3, py + size/2));
        robeShape.setPoint(4, sf::Vector2f(px - size/2 - wave, py));
        target.draw(robeShape);
        sf::CircleShape face(size/4.0f); face.setFillColor(sf::Color(150, 200, 120)); face.setOutlineThickness(3.0f); face.setOutlineColor(outline);
        face.setPosition(px - size/4, py - size/2); target.draw(face);
        sf::ConvexShape hat; hat.setPointCount(3); hat.setFillColor(sf::Color(20, 20, 20));
        hat.setPoint(0, sf::Vector2f(px - size/3, py - size/2));
        hat.setPoint(1, sf::Vector2f(px + size/3, py - size/2));
        hat.setPoint(2, sf::Vector2f(px + size/12, py - size));
        target.draw(hat);
        sf::CircleShape eye(size/24.0f); eye.setFillColor(sf::Color(255, 255, 100));
        eye.setPosition(px - size/10, py - size*5/12); target.draw(eye);
        eye.setPosition(px + size/30, py - size*5/12); target.draw(eye);
    }
    else if (type == BOSS_TWILIGHT_KNIGHT) {
        // Cavaliere del Crepuscolo: armatura che assorbe luce + scudo + lancia
        sf::Color armor(20, 20, 35);
        sf::RectangleShape body(sf::Vector2f(size*3/4, size*3/4));
        body.setFillColor(armor); body.setOutlineThickness(4.0f); body.setOutlineColor(outline);
        body.setPosition(px - size*3/8, py - size*3/8); target.draw(body);
        float pulse = 1.0f + sin(animTime * 3.0f) * 0.1f;
        sf::CircleShape aura(size/2.0f * pulse);
        aura.setFillColor(sf::Color(0, 0, 30, 100));
        aura.setPosition(px - size/2 * pulse, py - size/2 * pulse);
        target.draw(aura);
        sf::RectangleShape chest(sf::Vector2f(size/2, size/3));
        chest.setFillColor(sf::Color(40, 40, 60)); chest.setOutlineThickness(2.0f); chest.setOutlineColor(outline);
        chest.setPosition(px - size/4, py - size/6); target.draw(chest);
        sf::RectangleShape helm(sf::Vector2f(size/2, size*2/5));
        helm.setFillColor(armor); helm.setOutlineThickness(3.0f); helm.setOutlineColor(outline);
        helm.setPosition(px - size/4, py - size*4/5); target.draw(helm);
        sf::RectangleShape visor(sf::Vector2f(size/3, size/16));
        visor.setFillColor(sf::Color(150, 50, 220));
        visor.setPosition(px - size/6, py - size*11/20); target.draw(visor);
        sf::CircleShape shield(size/4.0f);
        shield.setFillColor(sf::Color(30, 30, 50)); shield.setOutlineThickness(3.0f); shield.setOutlineColor(sf::Color(100, 100, 150));
        shield.setPosition(px - size/2, py); target.draw(shield);
        sf::RectangleShape lance(sf::Vector2f(size/12, size));
        lance.setFillColor(sf::Color(180, 180, 200)); lance.setOutlineThickness(2.0f); lance.setOutlineColor(outline);
        lance.setPosition(px + size/3, py - size/2); target.draw(lance);
        sf::ConvexShape tip; tip.setPointCount(3); tip.setFillColor(sf::Color(220, 220, 240));
        tip.setPoint(0, sf::Vector2f(px + size/3, py - size/2));
        tip.setPoint(1, sf::Vector2f(px + size/3 + size/12, py - size/2));
        tip.setPoint(2, sf::Vector2f(px + size/3 + size/24, py - size*5/8));
        target.draw(tip);
    }

    // Bocca con denti (per i tipi che non hanno design custom senza bocca).
    if(type != BOSS_BEHOLDER && type != BOSS_LICH
       && type != BOSS_CULT_HERALD && type != BOSS_COLOSSAL_MIMIC
       && type != BOSS_SUPREME_WITCH && type != BOSS_TWILIGHT_KNIGHT) {
        sf::RectangleShape mouth(sf::Vector2f(size*3/5, mouthHeight));
        mouth.setFillColor(sf::Color::Black);
        mouth.setPosition(px - size*3/10, py + size/6);
        target.draw(mouth);

        // Denti: 6 triangoli bianchi allineati sulla bocca
        int numTeeth = 6;
        for(int i=0; i<numTeeth; i++) {
            float toothW = (size*3/5) / numTeeth;
            sf::ConvexShape tooth; tooth.setPointCount(3);
            tooth.setFillColor(sf::Color::White); tooth.setOutlineThickness(1.5f); tooth.setOutlineColor(outline);
            tooth.setPoint(0, sf::Vector2f(px - size*3/10 + i * toothW, py + size/6));
            tooth.setPoint(1, sf::Vector2f(px - size*3/10 + (i+1) * toothW, py + size/6));
            tooth.setPoint(2, sf::Vector2f(px - size*3/10 + i * toothW + toothW/2, py + size/6 + mouthHeight * 4/5));
            target.draw(tooth);
        }
    }

    // Barra HP sopra la testa
    sf::RectangleShape hbBg(sf::Vector2f(size, 15.0f)); hbBg.setFillColor(sf::Color(50, 0, 0));
    hbBg.setPosition(px - size/2, py - size/2 - 30); target.draw(hbBg);
    sf::RectangleShape hbFg(sf::Vector2f(size * health / maxHealth, 15.0f)); hbFg.setFillColor(sf::Color(255, 50, 50));
    hbFg.setPosition(px - size/2, py - size/2 - 30); target.draw(hbFg);
}
