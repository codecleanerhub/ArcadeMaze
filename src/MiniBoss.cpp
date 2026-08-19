#include "MiniBoss.h"
#include <cmath>
#include <cstdlib>
#include <queue>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ===========================================================================
// MiniBoss.cpp - Implementazione dei mini-boss dei labirinti.
//
// I mini-boss sono renderizzati con primitive SFML (nessuno sprite esterno)
// in stile "boss" ma con dimensioni piccole (32-40px). Ogni tipo ha una
// grafica unica ispirata a LOTR/D&D: forma del corpo, colore, arma, animazione.
//
// AI: insegue il player con BFS pathfinding (come i nemici "pensanti").
// Attacco: meele a distanza ravvicinata (attackRange) con cooldown.
// ===========================================================================

// --- Costruttore ---
MiniBoss::MiniBoss(MiniBossType t, int level, int startCol, int startRow)
    : pos(), dx(0), dy(0), speed(0), health(0), maxHealth(0),
      type(t), weapon(getWeaponForType(t)),
      pathUpdateTimer(0), attackCooldown(0), attackingTimer(0), dyingTimer(0),
      animTime(0.f), size(0), spriteLoaded(false) {
    pos.x = startCol * TILE_SIZE + TILE_SIZE / 2.f;
    pos.y = startRow * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
    maxHealth = getBaseHealth(t) + (level - 1) * 3;  // scala col livello
    health = maxHealth;
    speed = getBaseSpeed(t);
    size = getBaseSize(t);
    dx = (rand() % 2) ? 1 : -1;
    dy = (rand() % 2) ? 1 : -1;
    // Carica lo sprite PNG (assets/sprites/miniboss_XX_sheet.png)
    loadSprite();
}

// --- Caricamento sprite ---
// Restituisce l'ID del file sprite associato al tipo (miniboss_01..17).
std::string MiniBoss::getSpriteId(MiniBossType t) {
    static const char* ids[MINIBOSS_TYPE_COUNT] = {
        "miniboss_01",  // MB_GOBLIN_CHIEFTAIN
        "miniboss_02",  // MB_CAVE_TROLL
        "miniboss_03",  // MB_ORC_BERSERKER
        "miniboss_04",  // MB_WARG_RIDER
        "miniboss_05",  // MB_URUK_HAI
        "miniboss_06",  // MB_NAZGUL
        "miniboss_07",  // MB_OGRE_BRUTE
        "miniboss_08",  // MB_GNOLL_PACKLORD
        "miniboss_09",  // MB_BUGBEAR_CHIEF
        "miniboss_10",  // MB_MINOTAUR
        "miniboss_11",  // MB_WIGHT_LORD
        "miniboss_12",  // MB_CAVE_GIANT
        "miniboss_13",  // MB_DEATH_KNIGHT
        "miniboss_14",  // MB_ILLITHID
        "miniboss_15",  // MB_ETTIN
        "miniboss_16",  // MB_FOMORIAN
        "miniboss_17",  // MB_BALROG_CULTIST
    };
    int idx = (int)t;
    if (idx < 0 || idx >= MINIBOSS_TYPE_COUNT) return "miniboss_01";
    return ids[idx];
}

void MiniBoss::loadSprite() {
    std::string basePath = "assets/sprites/" + getSpriteId(type);
    spriteLoaded = sprite.load(basePath);
}

// --- Statistiche per tipo ---
// HP: tra nemico normale (3-8) e boss (50-250). Qui 18-35.
MiniBossWeapon MiniBoss::getWeaponForType(MiniBossType t) {
    switch (t) {
        case MB_GOBLIN_CHIEFTAIN: return MBW_AXE;
        case MB_CAVE_TROLL:       return MBW_CLUB;
        case MB_ORC_BERSERKER:    return MBW_AXE;
        case MB_WARG_RIDER:       return MBW_SWORD;
        case MB_URUK_HAI:         return MBW_SWORD;
        case MB_NAZGUL:           return MBW_DAGGER;
        case MB_OGRE_BRUTE:       return MBW_MACE;
        case MB_GNOLL_PACKLORD:   return MBW_AXE;
        case MB_BUGBEAR_CHIEF:    return MBW_CHAIN;
        case MB_MINOTAUR:         return MBW_AXE;
        case MB_WIGHT_LORD:       return MBW_SWORD;
        case MB_CAVE_GIANT:       return MBW_CLUB;
        case MB_DEATH_KNIGHT:     return MBW_SWORD;
        case MB_ILLITHID:         return MBW_TENTACLES;
        case MB_ETTIN:            return MBW_MACE;
        case MB_FOMORIAN:         return MBW_CLUB;
        case MB_BALROG_CULTIST:   return MBW_WHIP;
    }
    return MBW_AXE;
}

int MiniBoss::getBaseHealth(MiniBossType t) {
    // 18-35 HP (nemici normali: 3-8, boss: 50-250)
    switch (t) {
        case MB_GOBLIN_CHIEFTAIN: return 18;
        case MB_CAVE_TROLL:       return 35;  // troll: molto tanky
        case MB_ORC_BERSERKER:    return 22;
        case MB_WARG_RIDER:       return 20;
        case MB_URUK_HAI:         return 25;
        case MB_NAZGUL:           return 24;
        case MB_OGRE_BRUTE:       return 32;
        case MB_GNOLL_PACKLORD:   return 22;
        case MB_BUGBEAR_CHIEF:    return 26;
        case MB_MINOTAUR:         return 30;
        case MB_WIGHT_LORD:       return 28;
        case MB_CAVE_GIANT:       return 35;
        case MB_DEATH_KNIGHT:     return 30;
        case MB_ILLITHID:         return 26;
        case MB_ETTIN:            return 34;
        case MB_FOMORIAN:         return 33;
        case MB_BALROG_CULTIST:   return 28;
    }
    return 22;
}

// Velocita': PIU' LENTA del player (player=2.5px/frame circa).
// Mini-boss: 0.8-1.5 px/frame (lenti, ma inesorabili).
int MiniBoss::getBaseSpeed(MiniBossType t) {
    switch (t) {
        case MB_GOBLIN_CHIEFTAIN: return 1;  // veloce (per un goblin)
        case MB_CAVE_TROLL:       return 0;  // molto lento
        case MB_ORC_BERSERKER:    return 1;  // veloce quando insegue
        case MB_WARG_RIDER:       return 1;  // warg e' veloce
        case MB_URUK_HAI:         return 1;
        case MB_NAZGUL:           return 1;
        case MB_OGRE_BRUTE:       return 0;  // lento
        case MB_GNOLL_PACKLORD:   return 1;
        case MB_BUGBEAR_CHIEF:    return 1;
        case MB_MINOTAUR:          return 1;
        case MB_WIGHT_LORD:        return 1;
        case MB_CAVE_GIANT:        return 0;  // gigante lento
        case MB_DEATH_KNIGHT:      return 1;
        case MB_ILLITHID:          return 1;
        case MB_ETTIN:             return 0;  // lento ma potente
        case MB_FOMORIAN:          return 0;
        case MB_BALROG_CULTIST:    return 1;
    }
    return 1;
}

// Dimensioni: 32-40px (TILE_SIZE=48, deve passare nei corridoi).
int MiniBoss::getBaseSize(MiniBossType t) {
    switch (t) {
        case MB_GOBLIN_CHIEFTAIN: return 32;  // piccolo
        case MB_CAVE_TROLL:       return 40;  // grosso
        case MB_ORC_BERSERKER:    return 34;
        case MB_WARG_RIDER:       return 36;
        case MB_URUK_HAI:         return 34;
        case MB_NAZGUL:           return 36;  // ammantellato
        case MB_OGRE_BRUTE:       return 38;
        case MB_GNOLL_PACKLORD:   return 32;
        case MB_BUGBEAR_CHIEF:    return 36;
        case MB_MINOTAUR:         return 38;
        case MB_WIGHT_LORD:       return 36;
        case MB_CAVE_GIANT:       return 40;
        case MB_DEATH_KNIGHT:     return 36;
        case MB_ILLITHID:         return 34;
        case MB_ETTIN:            return 40;  // due teste
        case MB_FOMORIAN:         return 40;
        case MB_BALROG_CULTIST:   return 36;
    }
    return 34;
}

int MiniBoss::getAttackDamage() const {
    // Danno meele: 10-25 HP (player ha 100 HP, 4-10 colpi per ucciderlo)
    switch (weapon) {
        case MBW_AXE:       return 18;  // tagliente, medio
        case MBW_MACE:     return 22;   // contundente, alto
        case MBW_SWORD:    return 16;   // tagliente, medio
        case MBW_DAGGER:   return 12;   // veloce ma basso
        case MBW_CHAIN:    return 20;   // contundente, raggio lungo
        case MBW_CLUB:     return 25;   // molto alto, lento
        case MBW_WHIP:     return 15;   // raggio lunghissimo
        case MBW_TENTACLES: return 14; // danno mente, medio
    }
    return 15;
}

float MiniBoss::getAttackRange() const {
    // Raggio di attacco meele in pixel.
    switch (weapon) {
        case MBW_AXE:       return 36.f;
        case MBW_MACE:     return 34.f;
        case MBW_SWORD:    return 38.f;
        case MBW_DAGGER:   return 30.f;
        case MBW_CHAIN:    return 48.f;   // catena: raggio lungo
        case MBW_CLUB:     return 36.f;
        case MBW_WHIP:     return 56.f;   // frusta: raggio lunghissimo
        case MBW_TENTACLES: return 42.f;
    }
    return 34.f;
}

int MiniBoss::getScoreReward() const {
    // Score alto per aver sconfitto un mini-boss (5000-10000)
    return 5000 + (int)type * 300;  // aumenta col tipo
}

// --- BFS pathfinding (come Enemy::bfsPath) ---
bool MiniBoss::bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep) {
    if (start.x == target.x && start.y == target.y) return false;
    std::queue<std::vector<Vec2>> q;
    q.push({start});
    std::vector<Vec2> visited = {start};
    int dirs[4][2] = {{0,1},{0,-1},{1,0},{-1,0}};
    int maxIter = 200;  // limita la ricerca per performance
    while (!q.empty() && maxIter-- > 0) {
        std::vector<Vec2> path = q.front(); q.pop();
        Vec2 cur = path.back();
        if (cur.x == target.x && cur.y == target.y) {
            if (path.size() >= 2) { nextStep = path[1]; return true; }
            return false;
        }
        for (int d = 0; d < 4; d++) {
            Vec2 next{cur.x + dirs[d][0], cur.y + dirs[d][1]};
            if (next.x < 0 || next.x >= MAZE_COLS || next.y < 0 || next.y >= MAZE_ROWS) continue;
            if (maze.isWall(next.x, next.y)) continue;
            bool vis = false;
            for (const auto& v : visited) if (v.x == next.x && v.y == next.y) { vis = true; break; }
            if (vis) continue;
            visited.push_back(next);
            std::vector<Vec2> newPath = path;
            newPath.push_back(next);
            q.push(newPath);
        }
    }
    return false;
}

void MiniBoss::moveGreedy(Maze& maze, const Vec2& target) {
    // Sceglie la cella adiacente che minimizza la distanza Manhattan.
    int dirs[4][2] = {{0,1},{0,-1},{1,0},{-1,0}};
    int bestDist = abs(target.x - (int)(pos.x / TILE_SIZE)) +
                   abs(target.y - (int)((pos.y - UI_HEIGHT) / TILE_SIZE));
    int bestDx = 0, bestDy = 0;
    for (int d = 0; d < 4; d++) {
        int nc = (int)(pos.x / TILE_SIZE) + dirs[d][0];
        int nr = (int)((pos.y - UI_HEIGHT) / TILE_SIZE) + dirs[d][1];
        if (nc < 0 || nc >= MAZE_COLS || nr < 0 || nr >= MAZE_ROWS) continue;
        if (maze.isWall(nc, nr)) continue;
        int dist = abs(target.x - nc) + abs(target.y - nr);
        if (dist < bestDist) {
            bestDist = dist;
            bestDx = dirs[d][0];
            bestDy = dirs[d][1];
        }
    }
    pos.x += bestDx * (float)speed;
    pos.y += bestDy * (float)speed;
}

// --- Update ---
void MiniBoss::update(Maze& maze, const Vec2& playerGridPos,
                       const sf::Vector2f& playerPixelPos,
                       std::vector<Particle>& particles) {
    animTime += 0.016f;

    if (isDead()) {
        if (dyingTimer > 0) dyingTimer -= 16;
        else dyingTimer = 0;
        return;
    }

    // --- AI inseguitamento (BFS) ---
    // Ricalcola il path ogni ~300ms per performance.
    if (pathUpdateTimer > 0) pathUpdateTimer -= 16;
    else {
        pathUpdateTimer = 300;
        Vec2 myGrid{ (int)(pos.x / TILE_SIZE), (int)((pos.y - UI_HEIGHT) / TILE_SIZE) };
        Vec2 nextStep;
        if (bfsPath(maze, myGrid, playerGridPos, nextStep)) {
            // Muovi verso nextStep
            float targetX = nextStep.x * TILE_SIZE + TILE_SIZE / 2.f;
            float targetY = nextStep.y * TILE_SIZE + UI_HEIGHT + TILE_SIZE / 2.f;
            float dx = targetX - pos.x;
            float dy = targetY - pos.y;
            float dist = sqrtf(dx*dx + dy*dy);
            if (dist > 0.1f) {
                pos.x += (dx / dist) * (float)speed;
                pos.y += (dy / dist) * (float)speed;
            }
        } else {
            moveGreedy(maze, playerGridPos);
        }
    }

    // --- Attacco meele ---
    if (attackCooldown > 0) attackCooldown -= 16;
    if (attackingTimer > 0) attackingTimer -= 16;

    float dx = playerPixelPos.x - pos.x;
    float dy = playerPixelPos.y - pos.y;
    float dist = sqrtf(dx*dx + dy*dy);
    if (dist < getAttackRange() && attackCooldown == 0) {
        // Inizia attacco
        attackingTimer = 400;   // 400ms di animazione attacco
        attackCooldown = 1200;  // 1.2s tra attacchi
        // Genera particelle di "swung" dell'arma (scintille)
        for (int i = 0; i < 5; i++) {
            float ang = (rand() % 360) * (float)M_PI / 180.f;
            particles.push_back(makeParticle(
                sf::Vector2f(pos.x + cos(ang) * 20.f, pos.y + sin(ang) * 20.f),
                sf::Vector2f(cos(ang) * 2.f, sin(ang) * 2.f - 1.f),
                sf::Color(220, 160, 40),  // oro
                20, 20, 3.f, 0));
        }
    }
}

// --- Render a primitive SFML (stile boss ma piccolo) ---
// Ogni tipo ha grafica unica ispirata a LOTR/D&D.
void MiniBoss::renderPrimitives(sf::RenderTarget& target) const {
    // Palette 16 colori OBBLIGATORIA
    const sf::Color COL_BLACK   (12, 12, 12);
    const sf::Color COL_DARK    (48, 40, 36);
    const sf::Color COL_MID     (96, 80, 72);
    const sf::Color COL_LIT     (160, 128, 112);
    const sf::Color COL_PALE    (200, 180, 160);
    const sf::Color COL_RED     (160, 40, 40);
    const sf::Color COL_RED_L   (200, 80, 80);
    const sf::Color COL_GOLD     (220, 160, 40);
    const sf::Color COL_GREEN_D  (40, 80, 60);
    const sf::Color COL_GREEN_L  (80, 120, 100);
    const sf::Color COL_BLUE_D   (40, 80, 60);
    const sf::Color COL_WHITE    (240, 240, 240);
    const sf::Color COL_PURPLE   (160, 120, 200);
    const sf::Color COL_CYAN     (120, 200, 200);

    float cx = pos.x;
    float cy = pos.y;
    float s = (float)size / 2.f;  // raggio approssimativo
    bool attacking = (attackingTimer > 0);
    // Animazione "respiro" (leggera pulsazione)
    float breath = sinf(animTime * 3.f) * 1.f;

    // --- Colore del corpo in base al tipo ---
    sf::Color bodyColor, accentColor;
    switch (type) {
        case MB_GOBLIN_CHIEFTAIN: bodyColor = COL_GREEN_D; accentColor = COL_GOLD; break;
        case MB_CAVE_TROLL:       bodyColor = COL_MID;      accentColor = COL_PALE; break;  // grigio-verde
        case MB_ORC_BERSERKER:    bodyColor = COL_GREEN_D; accentColor = COL_RED; break;
        case MB_WARG_RIDER:       bodyColor = COL_DARK;     accentColor = COL_PALE; break;
        case MB_URUK_HAI:         bodyColor = COL_DARK;     accentColor = COL_RED_L; break;  // nero-rosso
        case MB_NAZGUL:           bodyColor = COL_BLACK;    accentColor = COL_RED; break;     // nero
        case MB_OGRE_BRUTE:       bodyColor = COL_MID;      accentColor = COL_LIT; break;
        case MB_GNOLL_PACKLORD:   bodyColor = COL_LIT;      accentColor = COL_GOLD; break;  // marrone
        case MB_BUGBEAR_CHIEF:    bodyColor = COL_MID;      accentColor = COL_DARK; break;
        case MB_MINOTAUR:         bodyColor = COL_DARK;     accentColor = COL_GOLD; break;
        case MB_WIGHT_LORD:       bodyColor = COL_BLUE_D;  accentColor = COL_CYAN; break;   // bluastro
        case MB_CAVE_GIANT:       bodyColor = COL_MID;      accentColor = COL_PALE; break;
        case MB_DEATH_KNIGHT:     bodyColor = COL_BLACK;    accentColor = COL_CYAN; break;
        case MB_ILLITHID:         bodyColor = COL_PURPLE;  accentColor = COL_PALE; break;
        case MB_ETTIN:            bodyColor = COL_MID;      accentColor = COL_RED; break;
        case MB_FOMORIAN:         bodyColor = COL_MID;      accentColor = COL_DARK; break;
        case MB_BALROG_CULTIST:   bodyColor = COL_RED;   accentColor = COL_GOLD; break;
        default: bodyColor = COL_MID; accentColor = COL_GOLD;
    }

    // --- Aura del mini-boss (pulsante, colore accent) ---
    float auraR = s * 1.4f + sinf(animTime * 2.f) * 2.f;
    sf::CircleShape aura(auraR);
    aura.setFillColor(sf::Color(accentColor.r, accentColor.g, accentColor.b, 40));
    aura.setPosition(cx - auraR, cy - auraR);
    target.draw(aura);

    // --- Corpo (rettangolo arrotondato) ---
    float bodyW = (float)size * 0.7f;
    float bodyH = (float)size * 0.9f;
    sf::RectangleShape body(sf::Vector2f(bodyW, bodyH + breath));
    body.setFillColor(bodyColor);
    body.setOutlineThickness(1.f);
    body.setOutlineColor(COL_BLACK);
    body.setOrigin(bodyW / 2.f, bodyH / 2.f);
    body.setPosition(cx, cy + 2.f);
    target.draw(body);

    // --- Testa (cerchio sopra il corpo) ---
    float headR = (float)size * 0.25f;
    sf::CircleShape head(headR);
    head.setFillColor(bodyColor);
    head.setOutlineThickness(1.f);
    head.setOutlineColor(COL_BLACK);
    head.setPosition(cx - headR, cy - bodyH / 2.f - headR + 4.f);
    target.draw(head);

    // --- Occhi (due puntini color accent) ---
    float eyeRad = 1.5f;
    sf::CircleShape eyeL(eyeRad);
    eyeL.setFillColor(accentColor);
    eyeL.setPosition(cx - headR * 0.5f - eyeRad, cy - bodyH / 2.f - headR * 0.3f + 4.f);
    target.draw(eyeL);
    sf::CircleShape eyeRShape(eyeRad);
    eyeRShape.setFillColor(accentColor);
    eyeRShape.setPosition(cx + headR * 0.5f - eyeRad, cy - bodyH / 2.f - headR * 0.3f + 4.f);
    target.draw(eyeRShape);

    // --- Dettagli specifici per tipo ---
    // (corna, creste, mantelli, ecc. per distinguere i tipi)
    switch (type) {
        case MB_GOBLIN_CHIEFTAIN:
        case MB_ORC_BERSERKER:
        case MB_GNOLL_PACKLORD: {
            // Orecchie appuntite (2 triangoli)
            sf::ConvexShape ear;
            ear.setPointCount(3);
            ear.setFillColor(bodyColor);
            ear.setOutlineThickness(0.5f);
            ear.setOutlineColor(COL_BLACK);
            // SX
            ear.setPoint(0, sf::Vector2f(cx - headR - 4.f, cy - bodyH/2.f));
            ear.setPoint(1, sf::Vector2f(cx - headR + 1.f, cy - bodyH/2.f - 3.f));
            ear.setPoint(2, sf::Vector2f(cx - headR + 2.f, cy - bodyH/2.f + 4.f));
            target.draw(ear);
            // DX
            ear.setPoint(0, sf::Vector2f(cx + headR + 4.f, cy - bodyH/2.f));
            ear.setPoint(1, sf::Vector2f(cx + headR - 1.f, cy - bodyH/2.f - 3.f));
            ear.setPoint(2, sf::Vector2f(cx + headR - 2.f, cy - bodyH/2.f + 4.f));
            target.draw(ear);
            break;
        }
        case MB_CAVE_TROLL:
        case MB_OGRE_BRUTE:
        case MB_CAVE_GIANT:
        case MB_FOMORIAN: {
            // Corna (2 piccoli triangoli sulla testa)
            for (int side = 0; side < 2; side++) {
                float dir = (side == 0) ? -1.f : 1.f;
                sf::ConvexShape horn;
                horn.setPointCount(3);
                horn.setFillColor(COL_PALE);
                horn.setOutlineThickness(0.5f);
                horn.setOutlineColor(COL_BLACK);
                horn.setPoint(0, sf::Vector2f(cx + dir * headR * 0.5f, cy - bodyH/2.f - headR + 2.f));
                horn.setPoint(1, sf::Vector2f(cx + dir * (headR + 4.f), cy - bodyH/2.f - headR - 6.f));
                horn.setPoint(2, sf::Vector2f(cx + dir * (headR - 1.f), cy - bodyH/2.f - headR + 2.f));
                target.draw(horn);
            }
            break;
        }
        case MB_NAZGUL:
        case MB_WIGHT_LORD:
        case MB_DEATH_KNIGHT: {
            // Mantello (triangolo dietro)
            sf::ConvexShape cloak;
            cloak.setPointCount(3);
            cloak.setFillColor(sf::Color(bodyColor.r, bodyColor.g, bodyColor.b, 180));
            cloak.setPoint(0, sf::Vector2f(cx, cy - bodyH/2.f));
            cloak.setPoint(1, sf::Vector2f(cx - bodyW * 0.8f, cy + bodyH/2.f));
            cloak.setPoint(2, sf::Vector2f(cx + bodyW * 0.8f, cy + bodyH/2.f));
            target.draw(cloak);
            break;
        }
        case MB_URUK_HAI: {
            // Marchio bianco sulla fronte (linea)
            sf::RectangleShape mark(sf::Vector2f(1.f, 6.f));
            mark.setFillColor(COL_WHITE);
            mark.setPosition(cx - 0.5f, cy - bodyH/2.f - headR);
            target.draw(mark);
            break;
        }
        case MB_ILLITHID: {
            // Tentacoli (4 piccoli) attorno alla bocca
            for (int i = 0; i < 4; i++) {
                float ang = (i - 1.5f) * 0.4f;
                sf::ConvexShape tentacle;
                tentacle.setPointCount(3);
                tentacle.setFillColor(bodyColor);
                tentacle.setPoint(0, sf::Vector2f(cx + cosf(ang) * headR * 0.7f,
                                                    cy - bodyH/2.f + headR * 0.3f + 4.f));
                tentacle.setPoint(1, sf::Vector2f(cx + cosf(ang) * (headR + 5.f),
                                                    cy - bodyH/2.f + headR * 0.3f + 8.f));
                tentacle.setPoint(2, sf::Vector2f(cx + cosf(ang) * (headR + 2.f),
                                                    cy - bodyH/2.f + headR * 0.3f + 12.f));
                target.draw(tentacle);
            }
            break;
        }
        case MB_BALROG_CULTIST: {
            // Aura di fuoco attorno (particelle animate)
            for (int i = 0; i < 6; i++) {
                float ang = (i / 6.f) * 2.f * (float)M_PI + animTime * 2.f;
                float r = s * 1.1f + sinf(animTime * 4.f + i) * 3.f;
                sf::CircleShape flame(2.5f);
                flame.setFillColor(sf::Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 200));
                flame.setPosition(cx + cosf(ang) * r - 2.5f, cy + sinf(ang) * r - 2.5f);
                target.draw(flame);
            }
            break;
        }
        case MB_ETTIN: {
            // Seconda testa (a destra)
            sf::CircleShape head2(headR * 0.8f);
            head2.setFillColor(bodyColor);
            head2.setOutlineThickness(1.f);
            head2.setOutlineColor(COL_BLACK);
            head2.setPosition(cx + headR + 2.f, cy - bodyH/2.f - headR * 0.5f + 4.f);
            target.draw(head2);
            // Occhi seconda testa
            sf::CircleShape eye2(1.2f);
            eye2.setFillColor(accentColor);
            eye2.setPosition(cx + headR + 4.f, cy - bodyH/2.f - headR * 0.2f + 4.f);
            target.draw(eye2);
            break;
        }
        default: break;
    }

    // --- Arma in mano (in base a MiniBossWeapon) ---
    // Disegna l'arma solo se sta attaccando (animazione swing).
    if (attacking) {
        // Posizione arma: davanti al mini-boss (verso destra)
        float wx = cx + bodyW * 0.6f;
        float wy = cy;
        switch (weapon) {
            case MBW_AXE: {
                // Manico + lama triangolare
                sf::RectangleShape handle(sf::Vector2f(1.5f, 12.f));
                handle.setFillColor(COL_DARK);
                handle.setPosition(wx, wy - 6.f);
                target.draw(handle);
                sf::ConvexShape blade;
                blade.setPointCount(3);
                blade.setFillColor(COL_PALE);
                blade.setOutlineThickness(0.5f);
                blade.setOutlineColor(COL_BLACK);
                blade.setPoint(0, sf::Vector2f(wx, wy - 6.f));
                blade.setPoint(1, sf::Vector2f(wx + 8.f, wy - 4.f));
                blade.setPoint(2, sf::Vector2f(wx + 1.f, wy + 2.f));
                target.draw(blade);
                break;
            }
            case MBW_MACE:
            case MBW_CLUB: {
                // Manico + testa sferica con spuntoni
                sf::RectangleShape handle(sf::Vector2f(1.5f, 14.f));
                handle.setFillColor(COL_DARK);
                handle.setPosition(wx, wy - 7.f);
                target.draw(handle);
                sf::CircleShape head2(4.f);
                head2.setFillColor(COL_MID);
                head2.setOutlineThickness(1.f);
                head2.setOutlineColor(COL_BLACK);
                head2.setPosition(wx - 2.f, wy - 11.f);
                target.draw(head2);
                // Spuntoni
                for (int i = 0; i < 6; i++) {
                    float ang = i * (float)M_PI / 3.f;
                    sf::ConvexShape spike;
                    spike.setPointCount(3);
                    spike.setFillColor(COL_PALE);
                    spike.setPoint(0, sf::Vector2f(wx + cosf(ang) * 4.f, wy - 9.f + sinf(ang) * 4.f));
                    spike.setPoint(1, sf::Vector2f(wx + cosf(ang) * 6.f, wy - 9.f + sinf(ang) * 6.f));
                    spike.setPoint(2, sf::Vector2f(wx + cosf(ang) * 4.5f, wy - 9.f + sinf(ang) * 4.5f));
                    target.draw(spike);
                }
                break;
            }
            case MBW_SWORD: {
                // Lama dritta
                sf::RectangleShape blade(sf::Vector2f(1.5f, 14.f));
                blade.setFillColor(COL_PALE);
                blade.setOutlineThickness(0.4f);
                blade.setOutlineColor(COL_BLACK);
                blade.setPosition(wx, wy - 12.f);
                target.draw(blade);
                // Elsa
                sf::RectangleShape guard(sf::Vector2f(5.f, 1.5f));
                guard.setFillColor(COL_GOLD);
                guard.setPosition(wx - 1.75f, wy + 1.f);
                target.draw(guard);
                break;
            }
            case MBW_DAGGER: {
                // Pugnale corto
                sf::RectangleShape blade(sf::Vector2f(1.2f, 8.f));
                blade.setFillColor(COL_PALE);
                blade.setPosition(wx, wy - 6.f);
                target.draw(blade);
                sf::RectangleShape guard(sf::Vector2f(3.f, 1.f));
                guard.setFillColor(COL_GOLD);
                guard.setPosition(wx - 0.9f, wy + 1.f);
                target.draw(guard);
                break;
            }
            case MBW_CHAIN: {
                // Catena (3 cerchietti) + palla
                for (int i = 0; i < 3; i++) {
                    sf::CircleShape link(1.5f);
                    link.setFillColor(COL_DARK);
                    link.setPosition(wx + i * 4.f, wy - 6.f);
                    target.draw(link);
                }
                sf::CircleShape ball(3.5f);
                ball.setFillColor(COL_MID);
                ball.setOutlineThickness(1.f);
                ball.setOutlineColor(COL_BLACK);
                ball.setPosition(wx + 12.f, wy - 9.5f);
                target.draw(ball);
                break;
            }
            case MBW_WHIP: {
                // Frusta: linea curva (3 segmenti)
                for (int i = 0; i < 4; i++) {
                    float segY = wy - 8.f + i * 4.f;
                    sf::RectangleShape seg(sf::Vector2f(1.f, 4.f));
                    seg.setFillColor(COL_DARK);
                    seg.setPosition(wx + i * 2.f, segY);
                    seg.rotate(sinf(animTime * 10.f + i) * 20.f);
                    target.draw(seg);
                }
                break;
            }
            case MBW_TENTACLES: {
                // Tentacoli (già disegnati sopra come dettaglio tipo)
                break;
            }
        }
    }

    // --- Barra HP (sopra la testa) ---
    if (health < maxHealth) {
        float barW = (float)size * 0.8f;
        float barH = 3.f;
        float barY = cy - bodyH / 2.f - headR - 6.f;
        // Sfondo (nero)
        sf::RectangleShape bg(sf::Vector2f(barW, barH));
        bg.setFillColor(COL_BLACK);
        bg.setPosition(cx - barW / 2.f, barY);
        target.draw(bg);
        // HP (rosso -> verde in base alla percentuale)
        float hpRatio = (float)health / (float)maxHealth;
        sf::Color hpColor = (hpRatio > 0.5f) ? COL_GREEN_L :
                            (hpRatio > 0.25f) ? COL_GOLD : COL_RED;
        sf::RectangleShape hp(sf::Vector2f(barW * hpRatio, barH));
        hp.setFillColor(hpColor);
        hp.setPosition(cx - barW / 2.f, barY);
        target.draw(hp);
    }

    // --- Ombra sul pavimento ---
    sf::CircleShape shadow(s * 0.7f);
    shadow.setFillColor(sf::Color(COL_BLACK.r, COL_BLACK.g, COL_BLACK.b, 80));
    shadow.setScale(1.3f, 0.4f);
    shadow.setPosition(cx - s * 0.7f, cy + bodyH / 2.f);
    target.draw(shadow);
}

// --- render ---
void MiniBoss::render(sf::RenderTarget& target) const {
    // Se lo sprite PNG e' caricato, usalo (stile boss/nemici, dettagliato).
    // Altrimenti fallback a primitive SFML (renderPrimitives).
    if (spriteLoaded && sprite.isLoaded()) {
        // Scala lo sprite 64x64 alla dimensione del mini-boss (32-40px).
        // size e' la dimensione target; lo sprite e' 64x64 con anchor (32,56).
        float scale = (float)size / 64.f;
        // Bob effect leggero per dare "vita"
        float bobY = sinf(animTime * 3.f) * 1.f;
        // Flipped se rivolto a sinistra (dx < 0)
        bool flipped = (dx < 0);
        sprite.render(target, "idle", 0, pos.x, pos.y + 8.f + bobY, scale, flipped);

        // --- Aura pulsante (colore accent in base al tipo) ---
        const sf::Color COL_GOLD(220, 160, 40);
        const sf::Color COL_RED(160, 40, 40);
        const sf::Color COL_CYAN(120, 200, 200);
        const sf::Color COL_PURPLE(160, 120, 200);
        sf::Color accentColor;
        switch (type) {
            case MB_GOBLIN_CHIEFTAIN: accentColor = COL_GOLD; break;
            case MB_CAVE_TROLL:       accentColor = sf::Color(200, 180, 160); break;
            case MB_ORC_BERSERKER:    accentColor = COL_RED; break;
            case MB_WARG_RIDER:       accentColor = sf::Color(200, 180, 160); break;
            case MB_URUK_HAI:         accentColor = sf::Color(200, 80, 80); break;
            case MB_NAZGUL:           accentColor = COL_RED; break;
            case MB_OGRE_BRUTE:       accentColor = sf::Color(160, 128, 112); break;
            case MB_GNOLL_PACKLORD:   accentColor = COL_GOLD; break;
            case MB_BUGBEAR_CHIEF:    accentColor = sf::Color(48, 40, 36); break;
            case MB_MINOTAUR:         accentColor = COL_GOLD; break;
            case MB_WIGHT_LORD:       accentColor = COL_CYAN; break;
            case MB_CAVE_GIANT:       accentColor = sf::Color(200, 180, 160); break;
            case MB_DEATH_KNIGHT:     accentColor = COL_CYAN; break;
            case MB_ILLITHID:         accentColor = COL_PURPLE; break;
            case MB_ETTIN:            accentColor = COL_RED; break;
            case MB_FOMORIAN:         accentColor = sf::Color(48, 40, 36); break;
            case MB_BALROG_CULTIST:   accentColor = COL_GOLD; break;
            default: accentColor = COL_GOLD;
        }
        float auraR = (float)size * 0.7f + sinf(animTime * 2.f) * 2.f;
        sf::CircleShape aura(auraR);
        aura.setFillColor(sf::Color(accentColor.r, accentColor.g, accentColor.b, 40));
        aura.setPosition(pos.x - auraR, pos.y - auraR);
        target.draw(aura);

        // --- Barra HP (sopra la testa) ---
        if (health < maxHealth) {
            float barW = (float)size * 0.8f;
            float barH = 3.f;
            float barY = pos.y - (float)size / 2.f - 8.f;
            sf::RectangleShape bg(sf::Vector2f(barW, barH));
            bg.setFillColor(sf::Color(12, 12, 12));
            bg.setPosition(pos.x - barW / 2.f, barY);
            target.draw(bg);
            float hpRatio = (float)health / (float)maxHealth;
            sf::Color hpColor = (hpRatio > 0.5f) ? sf::Color(80, 120, 100) :
                                (hpRatio > 0.25f) ? sf::Color(220, 160, 40) :
                                                    sf::Color(160, 40, 40);
            sf::RectangleShape hp(sf::Vector2f(barW * hpRatio, barH));
            hp.setFillColor(hpColor);
            hp.setPosition(pos.x - barW / 2.f, barY);
            target.draw(hp);
        }

        // --- Ombra sul pavimento ---
        sf::CircleShape shadow((float)size * 0.4f);
        shadow.setFillColor(sf::Color(12, 12, 12, 80));
        shadow.setScale(1.3f, 0.4f);
        shadow.setPosition(pos.x - (float)size * 0.4f, pos.y + (float)size / 2.f);
        target.draw(shadow);
    } else {
        // Fallback: rendering procedurale (se sprite non caricato)
        renderPrimitives(target);
    }
}
