#include "Enemy.h"
#include <cstdlib>
#include <cmath>
#include <fstream>

// ===========================================================================
// Enemy.cpp - Implementazione dei nemici.
//
// I nemici sono mossi in modo "snap-to-grid" come il giocatore (si allineano
// al centro della cella prima di poter cambiare direzione). La scelta della
// prossima direzione dipende dal tipo: alcuni usano BFS (cammino minimo),
// altri usano greedy (euristica distanza).
//
// Rendering: ogni tipo ha uno sprite associato (mappa EnemyType -> ID file).
// Se il PNG e' stato caricato (loadAllSprites), viene usato lo SpriteSheet;
// altrimenti si fa fallback al disegno a primitive SFML (renderPrimitives).
// ===========================================================================

// --- Membri statici della classe ---
std::map<EnemyType, SpriteSheet> Enemy::sprites;
bool Enemy::spritesLoaded = false;

// ---------------------------------------------------------------------------
// getSpriteId: tabella di mapping EnemyType -> ID del file bestiary.
//
// Restituisce l'ID (es. "monster_001") se il tipo e' mappato sul bestiary
// fantasy horror, oppure stringa vuota se non ha sprite associato (es.
// ENEMY_BAT, ENEMY_SLIME, ENEMY_DEMON non hanno controparte nel file).
//
// Mappatura (15 tipi originali + 13 nuovi = 28):
//   ENEMY_GHOUL          -> monster_001 (Sghignazzante Ghoul)
//   ENEMY_SPIDER         -> monster_002 (Ragno Abissale)
//   ENEMY_WOLF           -> monster_003 (Lupo Spettrale)
//   ENEMY_CULTIST        -> monster_004 (Cultista Corrotto)
//   ENEMY_MIMIC          -> monster_005 (Mimic Borsa)
//   ENEMY_RAT            -> monster_006 (Ratto Gigante)
//   ENEMY_WITCH          -> monster_007 (Strega delle Paludi)
//   ENEMY_SKELETON       -> monster_008 (Scheletro Lanciere)
//   ENEMY_GHOST          -> monster_009 (Ombra Strisciante)
//   ENEMY_BONE_GOLEM     -> monster_010 (Golem di Ossa)
//   ENEMY_ASH_SERPENT    -> monster_011 (Serpente di Cenere)
//   ENEMY_DAMNED_KNIGHT  -> monster_012 (Cavaliere Dannato)
//   ENEMY_MAD_WIZARD     -> monster_013 (Mago Folle)
//   ENEMY_DEMONIC_CROW   -> monster_015 (Corvo Demoniaco)
//   ENEMY_TENTACLE       -> monster_016 (Tentacolo Sotterraneo)
//   ENEMY_GARGOYLE       -> monster_017 (Gargoyle Vegliante)
//   ENEMY_WELL_SPIRIT    -> monster_018 (Spirito del Pozzo)
//   ENEMY_CURSED_BOAR    -> monster_019 (Cinghiale Maledetto)
//   ENEMY_PREDATOR_FUNGUS-> monster_020 (Fungo Predatore)
//
// Non mappati (nessuno sprite nel bestiary, usano primitive):
//   ENEMY_ZOMBIE, ENEMY_BAT, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
//   ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_IMP
// ---------------------------------------------------------------------------
std::string Enemy::getSpriteId(EnemyType t) {
    switch(t) {
        case ENEMY_GHOUL:           return "monster_001";
        case ENEMY_SPIDER:          return "monster_002";
        case ENEMY_WOLF:            return "monster_003";
        case ENEMY_CULTIST:         return "monster_004";
        case ENEMY_MIMIC:           return "monster_005";
        case ENEMY_RAT:             return "monster_006";
        case ENEMY_WITCH:           return "monster_007";
        case ENEMY_SKELETON:        return "monster_008";
        case ENEMY_GHOST:           return "monster_009";
        case ENEMY_BONE_GOLEM:      return "monster_010";
        case ENEMY_ASH_SERPENT:     return "monster_011";
        case ENEMY_DAMNED_KNIGHT:   return "monster_012";
        case ENEMY_MAD_WIZARD:      return "monster_013";
        case ENEMY_DEMONIC_CROW:    return "monster_015";
        case ENEMY_TENTACLE:        return "monster_016";
        case ENEMY_GARGOYLE:        return "monster_017";
        case ENEMY_WELL_SPIRIT:     return "monster_018";
        case ENEMY_CURSED_BOAR:     return "monster_019";
        case ENEMY_PREDATOR_FUNGUS: return "monster_020";
        default: return "";  // ENEMY_ZOMBIE, BAT, SLIME, DEMON, ROBOT,
                             // GOBLIN, ORC, WRAITH, IMP -> nessuno sprite
    }
}

// True se il tipo usa BFS per l'AI di movimento; false se usa greedy.
// Tipi "pensanti" (lenti ma determinati): robot/slime/demon/orc originali
// + nuovi tipi coriacei (bone_golem, damned_knight, gargoyle).
bool Enemy::usesBFS(EnemyType t) {
    switch(t) {
        case ENEMY_ROBOT:
        case ENEMY_SLIME:
        case ENEMY_DEMON:
        case ENEMY_ORC:
        case ENEMY_BONE_GOLEM:
        case ENEMY_DAMNED_KNIGHT:
        case ENEMY_GARGOYLE:
            return true;
        default:
            return false;
    }
}

// True se il tipo puo' sparare al giocatore (a distanza, non corpo a corpo).
// Tipi "a distanza": skeleton/cultist/demon/wraith/robot originali + nuovi
// caster (witch, mad_wizard).
bool Enemy::canShoot(EnemyType t) {
    switch(t) {
        case ENEMY_SKELETON:
        case ENEMY_CULTIST:
        case ENEMY_DEMON:
        case ENEMY_WRAITH:
        case ENEMY_ROBOT:
        case ENEMY_WITCH:
        case ENEMY_MAD_WIZARD:
            return true;
        default:
            return false;
    }
}

// ---------------------------------------------------------------------------
// loadAllSprites: carica tutti gli sprite dei nemici dalla cartella `basePath`.
// Per ogni tipo mappato (getSpriteId != ""), prova a caricare
// `<basePath>/<id>` (PNG + JSON). Se il caricamento fallisce (file mancante),
// lo sprite resta unloaded e il render fara' fallback alle primitive.
//
// Restituisce true se almeno uno sprite e' stato caricato.
// ---------------------------------------------------------------------------
bool Enemy::loadAllSprites(const std::string& basePath) {
    spritesLoaded = false;
    // Tutti i tipi dell'enum EnemyType
    EnemyType allTypes[] = {
        ENEMY_ZOMBIE, ENEMY_SKELETON, ENEMY_GHOST, ENEMY_BAT,
        ENEMY_SPIDER, ENEMY_SLIME, ENEMY_DEMON, ENEMY_ROBOT,
        ENEMY_GOBLIN, ENEMY_ORC, ENEMY_WRAITH, ENEMY_GHOUL,
        ENEMY_IMP, ENEMY_RAT, ENEMY_CULTIST,
        ENEMY_MIMIC, ENEMY_WOLF, ENEMY_WITCH, ENEMY_BONE_GOLEM,
        ENEMY_ASH_SERPENT, ENEMY_DAMNED_KNIGHT, ENEMY_MAD_WIZARD,
        ENEMY_DEMONIC_CROW, ENEMY_TENTACLE, ENEMY_GARGOYLE,
        ENEMY_WELL_SPIRIT, ENEMY_CURSED_BOAR, ENEMY_PREDATOR_FUNGUS
    };
    bool any = false;
    for (EnemyType t : allTypes) {
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

void Enemy::unloadAllSprites() {
    sprites.clear();
    spritesLoaded = false;
}

// ---------------------------------------------------------------------------
// Costruttore: inizializza posizione e statistiche del nemico.
//
// Tabella statistiche (bilanciamento indicativo):
//   * Nemici rapidi (BAT, IMP, RAT, WOLF, DEMONIC_CROW) hanno 1-2 HP e speed 3
//   * Nemici lenti ma coriacei (SLIME, ORC, ROBOT, BONE_GOLEM, DAMNED_KNIGHT,
//     GARGOYLE) hanno 5-6 HP e speed 1
//   * Nemici intermedi (SKELETON, SPIDER, GOBLIN, ...) hanno 2-3 HP e speed 2
//
// Il compromesso e': speed alta -> scappano via dalle pallottole e ti
// raggiungono presto; speed bassa + HP alti -> resistono molto ma puoi
// tenerli a distanza.
// ---------------------------------------------------------------------------
Enemy::Enemy(EnemyType t, int startCol, int startRow) : pathUpdateTimer(0), shootCooldown(0), attackingTimer(0), dyingTimer(0) {
    type = t;
    pos.x = startCol * TILE_SIZE + TILE_SIZE / 2.0f;
    pos.y = startRow * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0;

    // --- Statistiche per tipo ---
    // 15 tipi originali
    if (type == ENEMY_ZOMBIE)          { speed = 1; health = 4; maxHealth = 4; }
    else if (type == ENEMY_SKELETON)   { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_GHOST)      { speed = 2; health = 1; maxHealth = 1; }
    else if (type == ENEMY_BAT)        { speed = 3; health = 1; maxHealth = 1; }
    else if (type == ENEMY_SPIDER)     { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_SLIME)      { speed = 1; health = 5; maxHealth = 5; }
    else if (type == ENEMY_DEMON)      { speed = 1; health = 5; maxHealth = 5; }
    else if (type == ENEMY_ROBOT)      { speed = 1; health = 6; maxHealth = 6; }
    else if (type == ENEMY_GOBLIN)     { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_ORC)        { speed = 1; health = 6; maxHealth = 6; }
    else if (type == ENEMY_WRAITH)     { speed = 2; health = 3; maxHealth = 3; }
    else if (type == ENEMY_GHOUL)      { speed = 2; health = 3; maxHealth = 3; }
    else if (type == ENEMY_IMP)        { speed = 3; health = 1; maxHealth = 1; }
    else if (type == ENEMY_RAT)        { speed = 3; health = 2; maxHealth = 2; }
    else if (type == ENEMY_CULTIST)    { speed = 1; health = 3; maxHealth = 3; }
    // 13 nuovi tipi dal bestiary fantasy horror
    else if (type == ENEMY_MIMIC)          { speed = 1; health = 4; maxHealth = 4; }
    else if (type == ENEMY_WOLF)           { speed = 3; health = 2; maxHealth = 2; }
    else if (type == ENEMY_WITCH)          { speed = 1; health = 3; maxHealth = 3; }
    else if (type == ENEMY_BONE_GOLEM)     { speed = 1; health = 6; maxHealth = 6; }
    else if (type == ENEMY_ASH_SERPENT)    { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_DAMNED_KNIGHT)  { speed = 1; health = 5; maxHealth = 5; }
    else if (type == ENEMY_MAD_WIZARD)     { speed = 1; health = 3; maxHealth = 3; }
    else if (type == ENEMY_DEMONIC_CROW)   { speed = 3; health = 1; maxHealth = 1; }
    else if (type == ENEMY_TENTACLE)       { speed = 1; health = 3; maxHealth = 3; }
    else if (type == ENEMY_GARGOYLE)       { speed = 1; health = 5; maxHealth = 5; }
    else if (type == ENEMY_WELL_SPIRIT)    { speed = 2; health = 2; maxHealth = 2; }
    else if (type == ENEMY_CURSED_BOAR)    { speed = 2; health = 4; maxHealth = 4; }
    else if (type == ENEMY_PREDATOR_FUNGUS){ speed = 1; health = 3; maxHealth = 3; }
    else { speed = 1; health = 2; maxHealth = 2; }  // fallback sicuro
}

// bfsPath: BFS standard su griglia del labirinto (invariato rispetto all'originale).
bool Enemy::bfsPath(Maze& maze, Vec2 start, Vec2 target, Vec2& nextStep) {
    if (start.x == target.x && start.y == target.y) return false;
    std::queue<Vec2> q;
    std::vector<std::vector<bool>> visited(MAZE_COLS, std::vector<bool>(MAZE_ROWS, false));
    std::vector<std::vector<Vec2>> parent(MAZE_COLS, std::vector<Vec2>(MAZE_ROWS, {-1, -1}));
    q.push(start);
    visited[start.x][start.y] = true;
    int dc[] = {0, 1, 0, -1}, dr[] = {-1, 0, 1, 0};
    bool found = false;
    while (!q.empty()) {
        Vec2 curr = q.front(); q.pop();
        if (curr.x == target.x && curr.y == target.y) { found = true; break; }
        for (int i = 0; i < 4; ++i) {
            int nc = curr.x + dc[i], nr = curr.y + dr[i];
            if (nc >= 0 && nc < MAZE_COLS && nr >= 0 && nr < MAZE_ROWS && !visited[nc][nr] && !maze.isWall(nc, nr)) {
                visited[nc][nr] = true;
                parent[nc][nr] = curr;
                q.push({nc, nr});
            }
        }
    }
    if (found) {
        Vec2 curr = target;
        while (!(parent[curr.x][curr.y].x == start.x && parent[curr.x][curr.y].y == start.y)) curr = parent[curr.x][curr.y];
        nextStep = curr;
        return true;
    }
    return false;
}

// moveGreedy: euristica semplice (invariata rispetto all'originale).
void Enemy::moveGreedy(Maze& maze, const Vec2& target) {
    int col = (int)(pos.x / TILE_SIZE);
    int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
    int bestDx = 0, bestDy = 0;
    float minDist = 999999.0f;
    int dc[] = {0, 1, 0, -1}, dr[] = {-1, 0, 1, 0};
    for (int i = 0; i < 4; ++i) {
        int nc = col + dc[i], nr = row + dr[i];
        if (!maze.isWall(nc, nr)) {
            float dist = (nc - target.x) * (nc - target.x) + (nr - target.y) * (nr - target.y);
            if (dc[i] == -dx && dr[i] == -dy) dist += 10;
            if (dist < minDist) { minDist = dist; bestDx = dc[i]; bestDy = dr[i]; }
        }
    }
    dx = bestDx; dy = bestDy;
}

// ---------------------------------------------------------------------------
// update: aggiorna movimento e sparo del nemico.
// Logica movimento (snap-to-grid):
//   * Se vicino al centro cella, si allinea al centro esatto.
//   * Se usesBFS(type): ricalcola il path ogni ~250 ms.
//   * Altrimenti: greedy ad ogni centro cella.
//   * Se davanti c'e' muro, si ferma.
// Logica sparo:
//   * Solo tipi canShoot(type), con cooldown 1-2.5 sec.
//   * Sparano se il giocatore e' nel raggio di 500 px.
// ---------------------------------------------------------------------------
void Enemy::update(Maze& maze, const Vec2& playerGridPos, const sf::Vector2f& playerPixelPos, std::vector<Projectile>& enemyProjectiles) {
    // Decrementa i timer delle animazioni (16 ms per frame a 60 FPS)
    if (attackingTimer > 16) attackingTimer -= 16; else attackingTimer = 0;
    if (dyingTimer > 16) dyingTimer -= 16; else dyingTimer = 0;

    // Se il nemico sta morendo (animazione morte in corso), blocca movimento
    // e sparo: lascia solo scorrere il timer.
    if (dyingTimer > 0) return;

    int col = (int)(pos.x / TILE_SIZE);
    int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
    float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
    float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    pathUpdateTimer += 16;
    if (fabs(pos.x - centerX) < speed && fabs(pos.y - centerY) < speed) {
        pos.x = centerX; pos.y = centerY;

        if (usesBFS(type)) {
            if (pathUpdateTimer > 250) {
                pathUpdateTimer = 0;
                Vec2 nextStep;
                if (bfsPath(maze, {col, row}, playerGridPos, nextStep)) {
                    dx = nextStep.x - col; dy = nextStep.y - row;
                }
            }
        } else {
            moveGreedy(maze, playerGridPos);
        }
        if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
    }
    pos.x += dx * speed; pos.y += dy * speed;

    if (canShoot(type)) {
        if (shootCooldown > 0) shootCooldown -= 16;
        else {
            shootCooldown = 1000 + rand() % 1500;
            float dxp = playerPixelPos.x - pos.x;
            float dyp = playerPixelPos.y - pos.y;
            float dist = sqrt(dxp*dxp + dyp*dyp);
            if (dist > 0 && dist < 500) {
                // Triggera animazione di attacco per ~400 ms
                attackingTimer = 400;
                enemyProjectiles.push_back({pos, sf::Vector2f(dxp/dist * 3.f, dyp/dist * 3.f), 1, true, WPN_PISTOL});
            }
        }
    }
}

// takeDamage: riduce la salute e, se arriva a 0 o meno, triggera l'animazione
// di morte (dyingTimer = 600 ms ~= durata totale di 6 frame a 120 ms).
void Enemy::takeDamage(int dmg) {
    if (dyingTimer > 0) return;  // gia' in animazione morte, ignora ulteriori danni
    health -= dmg;
    if (health <= 0) {
        health = 0;
        dyingTimer = 600;  // ~600 ms di animazione death (6 frame x 120 ms)
    }
}

Vec2 Enemy::getGridPos() const { return { (int)(pos.x / TILE_SIZE), (int)((pos.y - UI_HEIGHT) / TILE_SIZE) }; }

// ---------------------------------------------------------------------------
// render: disegna il nemico.
//
//  1. Disegna sempre la barra HP (sopra la testa).
//  2. Se lo sprite e' caricato per questo tipo, usa SpriteSheet con
//     animazione "walk" + frame basato sul tempo (animazione semplice).
//  3. Altrimenti, fallback a renderPrimitives (disegno a primitive SFML).
// ---------------------------------------------------------------------------
void Enemy::render(sf::RenderTarget& target) const {
    float px = pos.x;
    float py = pos.y;
    sf::Color outline(20, 20, 20, 255);

    // Barra HP (nascosta durante l'animazione di morte)
    if (dyingTimer == 0) {
        sf::RectangleShape hbBg(sf::Vector2f(36.f, 4.f));
        hbBg.setFillColor(sf::Color(50, 0, 0, 200));
        hbBg.setPosition(px - 18.f, py - 36.f);
        target.draw(hbBg);
        sf::RectangleShape hbFg(sf::Vector2f(36.f * health / maxHealth, 4.f));
        hbFg.setFillColor(sf::Color(255, 50, 50));
        hbFg.setPosition(px - 18.f, py - 36.f);
        target.draw(hbFg);
    }

    // Tentativo di rendering con sprite.
    // Selezione animazione in base allo stato:
    //   - dyingTimer > 0           -> "death" (6 frame, 120 ms)
    //   - attackingTimer > 0        -> "attack" (6 frame, 100 ms)
    //   - dx != 0 || dy != 0        -> "walk" (6 frame, 100 ms)
    //   - altrimenti (fermo)        -> "idle" (4 frame, 200 ms)
    auto it = sprites.find(type);
    if (it != sprites.end() && it->second.isLoaded()) {
        std::string animName = "idle";
        int frameDuration = 200;
        // Priorita: death > attack > walk > idle
        if (dyingTimer > 0 && it->second.getFrameCount("death") > 0) {
            animName = "death";
            frameDuration = 120;
            int elapsed = 600 - (int)dyingTimer;
            int frameCount = it->second.getFrameCount("death");
            int frame = elapsed / frameDuration;
            if (frame >= frameCount) frame = frameCount - 1;
            bool flipped = (dx < 0);
            // Scale x4: 64x64 -> 256x256 (pixel art con smoothing off)
            it->second.render(target, animName, frame, px, py + 8.f, 4.0f, flipped);
            return;
        }
        if (attackingTimer > 0 && it->second.getFrameCount("attack") > 0) {
            animName = "attack";
            frameDuration = 100;
            int elapsed = 400 - (int)attackingTimer;
            int frameCount = it->second.getFrameCount("attack");
            int frame = elapsed / frameDuration;
            if (frame >= frameCount) frame = frameCount - 1;
            bool flipped = (dx < 0);
            it->second.render(target, animName, frame, px, py + 8.f, 4.0f, flipped);
            return;
        }
        if ((dx != 0 || dy != 0) && it->second.getFrameCount("walk") > 0) {
            animName = "walk";
            frameDuration = 100;
        } else if (it->second.getFrameCount("idle") > 0) {
            animName = "idle";
            frameDuration = 200;
        } else {
            animName = "walk";
            frameDuration = 100;
        }
        int frameCount = it->second.getFrameCount(animName);
        if (frameCount > 0) {
            int frame = (pathUpdateTimer / (uint32_t)frameDuration) % frameCount;
            bool flipped = (dx < 0);
            float bobY = 0.f;
            if (animName == "walk" && (dx != 0 || dy != 0)) {
                bobY = sin(pathUpdateTimer * 0.012f) * 2.f;
            } else if (animName == "idle") {
                bobY = sin(pathUpdateTimer * 0.004f) * 1.f;
            }
            it->second.render(target, animName, frame, px, py + 8.f + bobY, 4.0f, flipped);
            return;
        }
    }

    // Fallback: primitive SFML
    renderPrimitives(target);
}

// ---------------------------------------------------------------------------
// renderPrimitives: disegna il nemico con rettangoli/cerchi/poligoni.
// Implementa i 15 tipi originali + i 13 nuovi tipi del bestiary.
// Mantenuto come fallback quando lo sprite PNG non e' disponibile.
// ---------------------------------------------------------------------------
void Enemy::renderPrimitives(sf::RenderTarget& target) const {
    float px = pos.x;
    float py = pos.y;
    sf::Color outline(20, 20, 20, 255);

    if (type == ENEMY_ZOMBIE) {
        sf::RectangleShape arm1(sf::Vector2f(12.f, 8.f)); arm1.setFillColor(sf::Color(100, 150, 80)); arm1.setOutlineThickness(1.5f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - 18.f, py - 2.f); target.draw(arm1);
        sf::RectangleShape arm2(sf::Vector2f(12.f, 8.f)); arm2.setFillColor(sf::Color(100, 150, 80)); arm2.setOutlineThickness(1.5f); arm2.setOutlineColor(outline);
        arm2.setPosition(px + 6.f, py - 2.f); target.draw(arm2);
        sf::RectangleShape leg1(sf::Vector2f(8.f, 16.f)); leg1.setFillColor(sf::Color(60, 80, 40)); leg1.setOutlineThickness(1.5f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 8.f, py + 8.f); target.draw(leg1);
        sf::RectangleShape body(sf::Vector2f(20.f, 18.f)); body.setFillColor(sf::Color(80, 100, 60)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 10.f, py - 8.f); target.draw(body);
        sf::CircleShape head(10.f); head.setFillColor(sf::Color(150, 180, 120)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 10.f, py - 28.f); target.draw(head);
        sf::RectangleShape e1(sf::Vector2f(4.f, 4.f)); e1.setFillColor(sf::Color::Black);
        e1.setPosition(px - 6.f, py - 22.f); target.draw(e1);
        sf::RectangleShape e2(sf::Vector2f(4.f, 4.f)); e2.setFillColor(sf::Color::Black);
        e2.setPosition(px + 2.f, py - 22.f); target.draw(e2);
    }
    else if (type == ENEMY_SKELETON) {
        sf::RectangleShape skull(sf::Vector2f(16.f, 14.f)); skull.setFillColor(sf::Color(240, 240, 220)); skull.setOutlineThickness(1.5f); skull.setOutlineColor(outline);
        skull.setPosition(px - 8.f, py - 24.f); target.draw(skull);
        sf::RectangleShape body(sf::Vector2f(16.f, 16.f)); body.setFillColor(sf::Color(240, 240, 220)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        sf::RectangleShape leg1(sf::Vector2f(6.f, 14.f)); leg1.setFillColor(sf::Color(240, 240, 220)); leg1.setOutlineThickness(1.5f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 8.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(6.f, 14.f)); leg2.setFillColor(sf::Color(240, 240, 220)); leg2.setOutlineThickness(1.5f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 0.f, py + 8.f); target.draw(leg2);
        sf::RectangleShape e1(sf::Vector2f(4.f, 4.f)); e1.setFillColor(sf::Color::Black);
        e1.setPosition(px - 6.f, py - 22.f); target.draw(e1);
        sf::RectangleShape e2(sf::Vector2f(4.f, 4.f)); e2.setFillColor(sf::Color::Black);
        e2.setPosition(px + 2.f, py - 22.f); target.draw(e2);
        sf::ConvexShape bow; bow.setPointCount(4);
        bow.setFillColor(sf::Color(139, 69, 19));
        bow.setPoint(0, sf::Vector2f(px+8, py-8)); bow.setPoint(1, sf::Vector2f(px+14, py-4));
        bow.setPoint(2, sf::Vector2f(px+12, py+8)); bow.setPoint(3, sf::Vector2f(px+6, py+4));
        target.draw(bow);
    }
    else if (type == ENEMY_GOBLIN) {
        sf::RectangleShape body(sf::Vector2f(16.f, 14.f)); body.setFillColor(sf::Color(50, 150, 50)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 4.f); target.draw(body);
        sf::RectangleShape leg1(sf::Vector2f(5.f, 10.f)); leg1.setFillColor(sf::Color(40, 120, 40)); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 8.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(5.f, 10.f)); leg2.setFillColor(sf::Color(40, 120, 40)); leg2.setOutlineThickness(1.f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 1.f, py + 8.f); target.draw(leg2);
        sf::CircleShape head(8.f); head.setFillColor(sf::Color(70, 180, 70)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 8.f, py - 20.f); target.draw(head);
        sf::ConvexShape ear1; ear1.setPointCount(3); ear1.setFillColor(sf::Color(70, 180, 70));
        ear1.setPoint(0, sf::Vector2f(px-8, py-18)); ear1.setPoint(1, sf::Vector2f(px-16, py-16)); ear1.setPoint(2, sf::Vector2f(px-8, py-14));
        target.draw(ear1);
        sf::ConvexShape ear2; ear2.setPointCount(3); ear2.setFillColor(sf::Color(70, 180, 70));
        ear2.setPoint(0, sf::Vector2f(px+8, py-18)); ear2.setPoint(1, sf::Vector2f(px+16, py-16)); ear2.setPoint(2, sf::Vector2f(px+8, py-14));
        target.draw(ear2);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - 5.f, py - 16.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 16.f); target.draw(eye);
        sf::RectangleShape dagger(sf::Vector2f(2.f, 8.f)); dagger.setFillColor(sf::Color(200, 200, 200));
        dagger.setPosition(px + 8.f, py - 2.f); target.draw(dagger);
    }
    else if (type == ENEMY_ORC) {
        sf::RectangleShape arm1(sf::Vector2f(10.f, 14.f)); arm1.setFillColor(sf::Color(80, 120, 60)); arm1.setOutlineThickness(1.5f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - 16.f, py - 6.f); target.draw(arm1);
        sf::RectangleShape arm2(sf::Vector2f(10.f, 14.f)); arm2.setFillColor(sf::Color(80, 120, 60)); arm2.setOutlineThickness(1.5f); arm2.setOutlineColor(outline);
        arm2.setPosition(px + 6.f, py - 6.f); target.draw(arm2);
        sf::RectangleShape body(sf::Vector2f(24.f, 20.f)); body.setFillColor(sf::Color(100, 140, 80)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 12.f, py - 8.f); target.draw(body);
        sf::RectangleShape armor(sf::Vector2f(16.f, 8.f)); armor.setFillColor(sf::Color(100, 100, 100)); armor.setOutlineThickness(1.f); armor.setOutlineColor(outline);
        armor.setPosition(px - 8.f, py - 6.f); target.draw(armor);
        sf::RectangleShape leg1(sf::Vector2f(8.f, 12.f)); leg1.setFillColor(sf::Color(60, 100, 40)); leg1.setOutlineThickness(1.5f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 8.f, py + 10.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(8.f, 12.f)); leg2.setFillColor(sf::Color(60, 100, 40)); leg2.setOutlineThickness(1.5f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 0.f, py + 10.f); target.draw(leg2);
        sf::CircleShape head(12.f); head.setFillColor(sf::Color(120, 160, 100)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 12.f, py - 28.f); target.draw(head);
        sf::ConvexShape tusk1; tusk1.setPointCount(3); tusk1.setFillColor(sf::Color(255, 255, 200));
        tusk1.setPoint(0, sf::Vector2f(px-6, py-12)); tusk1.setPoint(1, sf::Vector2f(px-8, py-6)); tusk1.setPoint(2, sf::Vector2f(px-2, py-10));
        target.draw(tusk1);
        sf::ConvexShape tusk2; tusk2.setPointCount(3); tusk2.setFillColor(sf::Color(255, 255, 200));
        tusk2.setPoint(0, sf::Vector2f(px+6, py-12)); tusk2.setPoint(1, sf::Vector2f(px+8, py-6)); tusk2.setPoint(2, sf::Vector2f(px+2, py-10));
        target.draw(tusk2);
    }
    else if (type == ENEMY_WRAITH) {
        sf::ConvexShape cloak; cloak.setPointCount(5);
        cloak.setFillColor(sf::Color(40, 0, 60, 200)); cloak.setOutlineThickness(1.5f); cloak.setOutlineColor(sf::Color(100, 0, 150));
        cloak.setPoint(0, sf::Vector2f(px, py-24)); cloak.setPoint(1, sf::Vector2f(px+16, py-8));
        cloak.setPoint(2, sf::Vector2f(px+12, py+16)); cloak.setPoint(3, sf::Vector2f(px-12, py+16));
        cloak.setPoint(4, sf::Vector2f(px-16, py-8));
        target.draw(cloak);
        sf::CircleShape hood(10.f); hood.setFillColor(sf::Color(20, 0, 30, 255)); hood.setOutlineThickness(1.f); hood.setOutlineColor(outline);
        hood.setPosition(px - 10.f, py - 24.f); target.draw(hood);
        sf::CircleShape eye1(3.f); eye1.setFillColor(sf::Color(255, 0, 0));
        eye1.setPosition(px - 6.f, py - 18.f); target.draw(eye1);
        sf::CircleShape eye2(3.f); eye2.setFillColor(sf::Color(255, 0, 0));
        eye2.setPosition(px + 0.f, py - 18.f); target.draw(eye2);
    }
    else if (type == ENEMY_GHOUL) {
        sf::RectangleShape body(sf::Vector2f(18.f, 14.f)); body.setFillColor(sf::Color(150, 160, 140)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 9.f, py - 4.f); target.draw(body);
        sf::ConvexShape claw1; claw1.setPointCount(3); claw1.setFillColor(sf::Color(200, 200, 200));
        claw1.setPoint(0, sf::Vector2f(px-12, py-2)); claw1.setPoint(1, sf::Vector2f(px-18, py+2)); claw1.setPoint(2, sf::Vector2f(px-12, py+4));
        target.draw(claw1);
        sf::ConvexShape claw2; claw2.setPointCount(3); claw2.setFillColor(sf::Color(200, 200, 200));
        claw2.setPoint(0, sf::Vector2f(px+12, py-2)); claw2.setPoint(1, sf::Vector2f(px+18, py+2)); claw2.setPoint(2, sf::Vector2f(px+12, py+4));
        target.draw(claw2);
        sf::RectangleShape leg1(sf::Vector2f(6.f, 10.f)); leg1.setFillColor(sf::Color(120, 130, 110)); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 8.f); target.draw(leg1);
        sf::CircleShape head(8.f); head.setFillColor(sf::Color(180, 190, 170)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 8.f, py - 18.f); target.draw(head);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Black);
        eye.setPosition(px - 5.f, py - 14.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 14.f); target.draw(eye);
    }
    else if (type == ENEMY_IMP) {
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(120, 0, 0)); wing.setOutlineThickness(1.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px-2, py-4)); wing.setPoint(1, sf::Vector2f(px-16, py-12));
        wing.setPoint(2, sf::Vector2f(px-12, py-2)); wing.setPoint(3, sf::Vector2f(px-2, py+2));
        target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px+2, py-4); target.draw(wing);
        sf::CircleShape body(8.f); body.setFillColor(sf::Color(200, 50, 50)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        sf::ConvexShape horn; horn.setPointCount(3); horn.setFillColor(outline);
        horn.setPoint(0, sf::Vector2f(px-4, py-8)); horn.setPoint(1, sf::Vector2f(px-8, py-16)); horn.setPoint(2, sf::Vector2f(px-2, py-10));
        target.draw(horn);
        horn.setPoint(0, sf::Vector2f(px+4, py-8)); horn.setPoint(1, sf::Vector2f(px+8, py-16)); horn.setPoint(2, sf::Vector2f(px+2, py-10));
        target.draw(horn);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - 5.f, py - 4.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 4.f); target.draw(eye);
    }
    else if (type == ENEMY_RAT) {
        sf::ConvexShape body; body.setPointCount(4); body.setFillColor(sf::Color(80, 70, 60)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-12, py-4)); body.setPoint(1, sf::Vector2f(px+8, py-8));
        body.setPoint(2, sf::Vector2f(px+12, py+4)); body.setPoint(3, sf::Vector2f(px-10, py+8));
        target.draw(body);
        sf::RectangleShape tail(sf::Vector2f(16.f, 2.f)); tail.setFillColor(sf::Color(255, 200, 200));
        tail.rotate(45); tail.setPosition(px-12, py+2); target.draw(tail);
        sf::CircleShape head(6.f); head.setFillColor(sf::Color(100, 90, 80)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px + 6.f, py - 8.f); target.draw(head);
        sf::CircleShape ear(3.f); ear.setFillColor(sf::Color(100, 90, 80));
        ear.setPosition(px + 8.f, py - 14.f); target.draw(ear);
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px + 10.f, py - 6.f); target.draw(eye);
    }
    else if (type == ENEMY_CULTIST) {
        sf::ConvexShape robe; robe.setPointCount(5);
        robe.setFillColor(sf::Color(80, 0, 80)); robe.setOutlineThickness(1.5f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py-20)); robe.setPoint(1, sf::Vector2f(px+12, py-4));
        robe.setPoint(2, sf::Vector2f(px+8, py+16)); robe.setPoint(3, sf::Vector2f(px-8, py+16));
        robe.setPoint(4, sf::Vector2f(px-12, py-4));
        target.draw(robe);
        sf::CircleShape face(6.f); face.setFillColor(sf::Color::Black);
        face.setPosition(px - 6.f, py - 12.f); target.draw(face);
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 215, 0));
        eye.setPosition(px - 4.f, py - 8.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 8.f); target.draw(eye);
        sf::RectangleShape dagger(sf::Vector2f(2.f, 10.f)); dagger.setFillColor(sf::Color(200, 200, 200));
        dagger.setPosition(px + 8.f, py + 2.f); target.draw(dagger);
    }
    else if (type == ENEMY_GHOST) {
        sf::CircleShape top(12.f); top.setFillColor(sf::Color(150, 200, 255, 150));
        top.setPosition(px - 12.f, py - 16.f); target.draw(top);
        sf::RectangleShape body(sf::Vector2f(24.f, 16.f)); body.setFillColor(sf::Color(150, 200, 255, 150));
        body.setPosition(px - 12.f, py - 4.f); target.draw(body);
        sf::CircleShape eye1(3.f); eye1.setFillColor(sf::Color(100, 100, 255, 200));
        eye1.setPosition(px - 8.f, py - 8.f); target.draw(eye1);
        sf::CircleShape eye2(3.f); eye2.setFillColor(sf::Color(100, 100, 255, 200));
        eye2.setPosition(px + 2.f, py - 8.f); target.draw(eye2);
    }
    else if (type == ENEMY_BAT) {
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(80, 0, 80)); wing.setOutlineThickness(1.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(0, 0)); wing.setPoint(1, sf::Vector2f(-20, -8));
        wing.setPoint(2, sf::Vector2f(-16, 4)); wing.setPoint(3, sf::Vector2f(-4, 4));
        wing.setPosition(px, py); target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px, py); target.draw(wing);
        sf::CircleShape body(8.f); body.setFillColor(sf::Color(120, 0, 120)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - 3.f, py - 6.f); target.draw(eye);
    }
    else if (type == ENEMY_SPIDER) {
        sf::Color web(200, 200, 200);
        for(int i=0; i<4; i++) {
            sf::RectangleShape l1(sf::Vector2f(12.f, 2.f)); l1.setFillColor(web);
            l1.rotate(-30 + i*20); l1.setPosition(px - 8.f, py - 2 + i*3); target.draw(l1);
            sf::RectangleShape l2(sf::Vector2f(12.f, 2.f)); l2.setFillColor(web);
            l2.rotate(30 - i*20); l2.setPosition(px + 8.f, py - 2 + i*3); target.draw(l2);
        }
        sf::CircleShape body(10.f); body.setFillColor(sf::Color(30, 30, 30)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(px - 10.f, py - 4.f); target.draw(body);
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - 2.f, py - 6.f); target.draw(eye);
    }
    else if (type == ENEMY_SLIME) {
        sf::CircleShape body(14.f); body.setFillColor(sf::Color(50, 200, 50, 200)); body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(0, 100, 0));
        body.setPosition(px - 14.f, py - 6.f); target.draw(body);
        sf::CircleShape eye1(3.f); eye1.setFillColor(sf::Color::White);
        eye1.setPosition(px - 8.f, py - 2.f); target.draw(eye1);
        sf::CircleShape eye2(3.f); eye2.setFillColor(sf::Color::White);
        eye2.setPosition(px + 2.f, py - 2.f); target.draw(eye2);
        sf::CircleShape p1(1.5f); p1.setFillColor(sf::Color::Black);
        p1.setPosition(px - 5.f, py); target.draw(p1);
        sf::CircleShape p2(1.5f); p2.setFillColor(sf::Color::Black);
        p2.setPosition(px + 5.f, py); target.draw(p2);
    }
    else if (type == ENEMY_DEMON) {
        sf::RectangleShape body(sf::Vector2f(24.f, 20.f)); body.setFillColor(sf::Color(150, 0, 0)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 12.f, py - 8.f); target.draw(body);
        sf::CircleShape head(12.f); head.setFillColor(sf::Color(180, 0, 0)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 12.f, py - 28.f); target.draw(head);
        sf::ConvexShape horn1; horn1.setPointCount(3);
        horn1.setFillColor(sf::Color(80, 0, 0));
        horn1.setPoint(0, sf::Vector2f(0, 0)); horn1.setPoint(1, sf::Vector2f(-6, -10)); horn1.setPoint(2, sf::Vector2f(2, -10));
        horn1.setPosition(px - 8.f, py - 26.f); target.draw(horn1);
        horn1.setPosition(px + 8.f, py - 26.f); target.draw(horn1);
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(120, 0, 0));
        wing.setPoint(0, sf::Vector2f(0, 0)); wing.setPoint(1, sf::Vector2f(-20, -4));
        wing.setPoint(2, sf::Vector2f(-16, 12)); wing.setPoint(3, sf::Vector2f(-4, 10));
        wing.setPosition(px - 12.f, py - 4.f); target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px + 12.f, py - 4.f); target.draw(wing);
        sf::CircleShape eye(3.f); eye.setFillColor(sf::Color::Yellow);
        eye.setPosition(px - 8.f, py - 22.f); target.draw(eye);
        eye.setPosition(px + 2.f, py - 22.f); target.draw(eye);
    }
    else if (type == ENEMY_ROBOT) {
        sf::RectangleShape tracks(sf::Vector2f(32.f, 12.f)); tracks.setFillColor(sf::Color(30, 30, 30)); tracks.setOutlineThickness(1.f); tracks.setOutlineColor(outline);
        tracks.setPosition(px - 16.f, py + 8.f); target.draw(tracks);
        sf::RectangleShape body(sf::Vector2f(28.f, 20.f)); body.setFillColor(sf::Color(150, 150, 150)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 14.f, py - 12.f); target.draw(body);
        sf::RectangleShape head(sf::Vector2f(22.f, 16.f)); head.setFillColor(sf::Color(180, 180, 180)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 11.f, py - 28.f); target.draw(head);
        sf::RectangleShape ant(sf::Vector2f(2.f, 8.f)); ant.setFillColor(sf::Color(80, 80, 80));
        ant.setPosition(px - 1.f, py - 36.f); target.draw(ant);
        sf::CircleShape led(3.f); led.setFillColor(sf::Color(255, 50, 50));
        led.setPosition(px - 3.f, py - 39.f); target.draw(led);
        sf::CircleShape eye(5.f); eye.setFillColor(sf::Color::Red);
        eye.setPosition(px - 5.f, py - 18.f); target.draw(eye);
    }
    // === Nuovi tipi dal bestiary (13) ===
    else if (type == ENEMY_MIMIC) {
        // Forziere vivente: corpo legno + lingua + denti
        sf::RectangleShape body(sf::Vector2f(28.f, 20.f)); body.setFillColor(sf::Color(110, 70, 30)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 14.f, py - 4.f); target.draw(body);
        // Coperchio aperto con denti
        sf::RectangleShape top(sf::Vector2f(28.f, 6.f)); top.setFillColor(sf::Color(80, 50, 20)); top.setOutlineThickness(1.f); top.setOutlineColor(outline);
        top.setPosition(px - 14.f, py - 10.f); target.draw(top);
        // Denti
        for(int i=0; i<5; i++) {
            sf::ConvexShape tooth; tooth.setPointCount(3);
            tooth.setFillColor(sf::Color(255, 255, 220));
            float tx = px - 12.f + i * 6.f;
            tooth.setPoint(0, sf::Vector2f(tx, py - 4.f));
            tooth.setPoint(1, sf::Vector2f(tx + 4.f, py - 4.f));
            tooth.setPoint(2, sf::Vector2f(tx + 2.f, py + 2.f));
            target.draw(tooth);
        }
        // Lingua rosa
        sf::ConvexShape tongue; tongue.setPointCount(4);
        tongue.setFillColor(sf::Color(220, 80, 120));
        tongue.setPoint(0, sf::Vector2f(px-3, py-2)); tongue.setPoint(1, sf::Vector2f(px+3, py-2));
        tongue.setPoint(2, sf::Vector2f(px+2, py+8)); tongue.setPoint(3, sf::Vector2f(px-2, py+8));
        target.draw(tongue);
        // Occhio dorato
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color(255, 215, 0));
        eye.setPosition(px - 8.f, py - 8.f); target.draw(eye);
    }
    else if (type == ENEMY_WOLF) {
        // Lupo spettrale: corpo grigio-fumo, occhi verdi
        sf::ConvexShape body; body.setPointCount(5);
        body.setFillColor(sf::Color(80, 80, 90)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-14, py+2)); body.setPoint(1, sf::Vector2f(px-10, py-6));
        body.setPoint(2, sf::Vector2f(px+8, py-8)); body.setPoint(3, sf::Vector2f(px+14, py+2));
        body.setPoint(4, sf::Vector2f(px+4, py+8));
        target.draw(body);
        // Testa
        sf::CircleShape head(7.f); head.setFillColor(sf::Color(100, 100, 110)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px + 4.f, py - 14.f); target.draw(head);
        // Orecchie
        sf::ConvexShape ear1; ear1.setPointCount(3); ear1.setFillColor(sf::Color(80, 80, 90));
        ear1.setPoint(0, sf::Vector2f(px+6, py-14)); ear1.setPoint(1, sf::Vector2f(px+4, py-20)); ear1.setPoint(2, sf::Vector2f(px+10, py-16));
        target.draw(ear1);
        // Occhi verdi brillanti
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(100, 255, 100));
        eye.setPosition(px + 8.f, py - 10.f); target.draw(eye);
        // Zampe
        sf::RectangleShape leg1(sf::Vector2f(4.f, 8.f)); leg1.setFillColor(sf::Color(60, 60, 70));
        leg1.setPosition(px - 10.f, py + 6.f); target.draw(leg1);
        leg1.setPosition(px + 6.f, py + 6.f); target.draw(leg1);
        // Coda arruffata
        sf::ConvexShape tail; tail.setPointCount(4); tail.setFillColor(sf::Color(60, 60, 70));
        tail.setPoint(0, sf::Vector2f(px-14, py-2)); tail.setPoint(1, sf::Vector2f(px-22, py-8));
        tail.setPoint(2, sf::Vector2f(px-20, py+2)); tail.setPoint(3, sf::Vector2f(px-14, py+2));
        target.draw(tail);
    }
    else if (type == ENEMY_WITCH) {
        // Strega: cappello a punta + tunica + pozione
        sf::ConvexShape robe; robe.setPointCount(5);
        robe.setFillColor(sf::Color(40, 80, 40)); robe.setOutlineThickness(1.5f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py-18)); robe.setPoint(1, sf::Vector2f(px+12, py-4));
        robe.setPoint(2, sf::Vector2f(px+8, py+16)); robe.setPoint(3, sf::Vector2f(px-8, py+16));
        robe.setPoint(4, sf::Vector2f(px-12, py-4));
        target.draw(robe);
        // Pelle verde
        sf::CircleShape face(7.f); face.setFillColor(sf::Color(150, 200, 120)); face.setOutlineThickness(1.f); face.setOutlineColor(outline);
        face.setPosition(px - 7.f, py - 18.f); target.draw(face);
        // Cappello a punta
        sf::ConvexShape hat; hat.setPointCount(3); hat.setFillColor(sf::Color(20, 20, 20));
        hat.setPoint(0, sf::Vector2f(px-12, py-22)); hat.setPoint(1, sf::Vector2f(px+12, py-22));
        hat.setPoint(2, sf::Vector2f(px+2, py-40));
        target.draw(hat);
        // Occhi gialli
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 255, 100));
        eye.setPosition(px - 4.f, py - 14.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 14.f); target.draw(eye);
        // Boccetta di pozione
        sf::RectangleShape vial(sf::Vector2f(4.f, 8.f)); vial.setFillColor(sf::Color(100, 255, 100, 200));
        vial.setPosition(px + 8.f, py + 2.f); target.draw(vial);
    }
    else if (type == ENEMY_BONE_GOLEM) {
        // Golem di ossa: grossa gabbia toracica + teschio
        sf::RectangleShape body(sf::Vector2f(28.f, 24.f)); body.setFillColor(sf::Color(200, 200, 180)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 14.f, py - 8.f); target.draw(body);
        // Costole
        for(int i=0; i<3; i++) {
            sf::RectangleShape rib(sf::Vector2f(28.f, 2.f)); rib.setFillColor(sf::Color(120, 120, 100));
            rib.setPosition(px - 14.f, py - 4.f + i * 6.f); target.draw(rib);
        }
        // Teschio
        sf::RectangleShape skull(sf::Vector2f(18.f, 16.f)); skull.setFillColor(sf::Color(220, 220, 200)); skull.setOutlineThickness(1.5f); skull.setOutlineColor(outline);
        skull.setPosition(px - 9.f, py - 28.f); target.draw(skull);
        // Orbite
        sf::RectangleShape e1(sf::Vector2f(4.f, 4.f)); e1.setFillColor(sf::Color::Black);
        e1.setPosition(px - 6.f, py - 24.f); target.draw(e1);
        e1.setPosition(px + 2.f, py - 24.f); target.draw(e1);
        // Braccia ossute
        sf::RectangleShape arm1(sf::Vector2f(4.f, 18.f)); arm1.setFillColor(sf::Color(200, 200, 180)); arm1.setOutlineThickness(1.f); arm1.setOutlineColor(outline);
        arm1.setPosition(px - 18.f, py - 6.f); target.draw(arm1);
        arm1.setPosition(px + 14.f, py - 6.f); target.draw(arm1);
    }
    else if (type == ENEMY_ASH_SERPENT) {
        // Serpente sinuoso grigio-cenere
        sf::ConvexShape body; body.setPointCount(6);
        body.setFillColor(sf::Color(120, 110, 100)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-16, py+8)); body.setPoint(1, sf::Vector2f(px-8, py+2));
        body.setPoint(2, sf::Vector2f(px-2, py+8)); body.setPoint(3, sf::Vector2f(px+8, py+2));
        body.setPoint(4, sf::Vector2f(px+14, py+8)); body.setPoint(5, sf::Vector2f(px-2, py-2));
        target.draw(body);
        // Testa
        sf::CircleShape head(6.f); head.setFillColor(sf::Color(140, 130, 120)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px + 8.f, py - 8.f); target.draw(head);
        // Occhi brace
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 100, 0));
        eye.setPosition(px + 12.f, py - 6.f); target.draw(eye);
        // Lingua biforcuta
        sf::RectangleShape tongue(sf::Vector2f(6.f, 1.f)); tongue.setFillColor(sf::Color(255, 80, 80));
        tongue.setPosition(px + 14.f, py - 4.f); target.draw(tongue);
    }
    else if (type == ENEMY_DAMNED_KNIGHT) {
        // Cavaliere in armatura nera con crepe luminose
        sf::RectangleShape body(sf::Vector2f(22.f, 22.f)); body.setFillColor(sf::Color(40, 40, 50)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 11.f, py - 8.f); target.draw(body);
        // Corazza petto
        sf::RectangleShape armor(sf::Vector2f(16.f, 12.f)); armor.setFillColor(sf::Color(60, 60, 70)); armor.setOutlineThickness(1.f); armor.setOutlineColor(outline);
        armor.setPosition(px - 8.f, py - 6.f); target.draw(armor);
        // Crepe luminose arancioni
        sf::RectangleShape crack1(sf::Vector2f(2.f, 8.f)); crack1.setFillColor(sf::Color(255, 120, 0));
        crack1.setPosition(px - 4.f, py - 4.f); target.draw(crack1);
        crack1.setSize(sf::Vector2f(6.f, 2.f)); crack1.setPosition(px - 4.f, py + 2.f); target.draw(crack1);
        // Elmo
        sf::RectangleShape helm(sf::Vector2f(16.f, 14.f)); helm.setFillColor(sf::Color(30, 30, 40)); helm.setOutlineThickness(1.5f); helm.setOutlineColor(outline);
        helm.setPosition(px - 8.f, py - 26.f); target.draw(helm);
        // Fessura occhi
        sf::RectangleShape visor(sf::Vector2f(10.f, 2.f)); visor.setFillColor(sf::Color(255, 80, 0));
        visor.setPosition(px - 5.f, py - 20.f); target.draw(visor);
        // Spada
        sf::RectangleShape sword(sf::Vector2f(2.f, 18.f)); sword.setFillColor(sf::Color(180, 180, 180));
        sword.setPosition(px + 12.f, py - 12.f); target.draw(sword);
        // Gambe
        sf::RectangleShape leg1(sf::Vector2f(8.f, 12.f)); leg1.setFillColor(sf::Color(40, 40, 50)); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 8.f, py + 12.f); target.draw(leg1);
        leg1.setPosition(px + 0.f, py + 12.f); target.draw(leg1);
    }
    else if (type == ENEMY_MAD_WIZARD) {
        // Mago folle: tunica lacera + occhi brillanti + pergamene fluttuanti
        sf::ConvexShape robe; robe.setPointCount(6);
        robe.setFillColor(sf::Color(60, 30, 90)); robe.setOutlineThickness(1.5f); robe.setOutlineColor(outline);
        robe.setPoint(0, sf::Vector2f(px, py-20)); robe.setPoint(1, sf::Vector2f(px+14, py-8));
        robe.setPoint(2, sf::Vector2f(px+10, py+8)); robe.setPoint(3, sf::Vector2f(px+6, py+16));
        robe.setPoint(4, sf::Vector2f(px-6, py+16)); robe.setPoint(5, sf::Vector2f(px-10, py+8));
        robe.setPoint(5, sf::Vector2f(px-14, py-8));
        target.draw(robe);
        // Testa
        sf::CircleShape face(7.f); face.setFillColor(sf::Color(200, 180, 200)); face.setOutlineThickness(1.f); face.setOutlineColor(outline);
        face.setPosition(px - 7.f, py - 20.f); target.draw(face);
        // Cappello a punta con stella
        sf::ConvexShape hat; hat.setPointCount(3); hat.setFillColor(sf::Color(40, 20, 60));
        hat.setPoint(0, sf::Vector2f(px-10, py-24)); hat.setPoint(1, sf::Vector2f(px+10, py-24));
        hat.setPoint(2, sf::Vector2f(px+4, py-42));
        target.draw(hat);
        sf::CircleShape star(2.f); star.setFillColor(sf::Color(255, 255, 100));
        star.setPosition(px, py - 32.f); target.draw(star);
        // Occhi brillanti (pupille bianche)
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color(255, 255, 255));
        eye.setPosition(px - 4.f, py - 16.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 16.f); target.draw(eye);
        // Pergamene fluttuanti
        sf::RectangleShape scroll1(sf::Vector2f(6.f, 8.f)); scroll1.setFillColor(sf::Color(220, 200, 140));
        scroll1.setPosition(px - 18.f, py - 6.f); target.draw(scroll1);
        scroll1.setPosition(px + 12.f, py - 4.f); target.draw(scroll1);
    }
    else if (type == ENEMY_DEMONIC_CROW) {
        // Corvo nero con becco metallico e occhi rossi
        sf::ConvexShape wing; wing.setPointCount(4);
        wing.setFillColor(sf::Color(20, 20, 30)); wing.setOutlineThickness(1.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px-2, py-4)); wing.setPoint(1, sf::Vector2f(px-20, py-12));
        wing.setPoint(2, sf::Vector2f(px-16, py+4)); wing.setPoint(3, sf::Vector2f(px-2, py+4));
        target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px+2, py-4); target.draw(wing);
        // Corpo
        sf::CircleShape body(8.f); body.setFillColor(sf::Color(30, 30, 40)); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
        body.setPosition(px - 8.f, py - 8.f); target.draw(body);
        // Testa
        sf::CircleShape head(5.f); head.setFillColor(sf::Color(40, 40, 50)); head.setOutlineThickness(1.f); head.setOutlineColor(outline);
        head.setPosition(px + 2.f, py - 14.f); target.draw(head);
        // Becco metallico
        sf::ConvexShape beak; beak.setPointCount(3); beak.setFillColor(sf::Color(180, 180, 200));
        beak.setPoint(0, sf::Vector2f(px+8, py-12)); beak.setPoint(1, sf::Vector2f(px+14, py-10));
        beak.setPoint(2, sf::Vector2f(px+8, py-8));
        target.draw(beak);
        // Occhi rossi
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 0, 0));
        eye.setPosition(px + 4.f, py - 12.f); target.draw(eye);
    }
    else if (type == ENEMY_TENTACLE) {
        // Tentacolo emergente dal suolo con ventose
        sf::ConvexShape body; body.setPointCount(6);
        body.setFillColor(sf::Color(100, 80, 120)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-4, py+12)); body.setPoint(1, sf::Vector2f(px-10, py+4));
        body.setPoint(2, sf::Vector2f(px-6, py-8)); body.setPoint(3, sf::Vector2f(px+2, py-12));
        body.setPoint(4, sf::Vector2f(px+8, py-4)); body.setPoint(5, sf::Vector2f(px+6, py+12));
        target.draw(body);
        // Ventose
        for(int i=0; i<3; i++) {
            sf::CircleShape sucker(2.f); sucker.setFillColor(sf::Color(180, 150, 200));
            sucker.setPosition(px - 6.f + i*4.f, py - 4.f + i*4.f); target.draw(sucker);
        }
        // Occhi sparsi
        sf::CircleShape eye1(2.f); eye1.setFillColor(sf::Color(255, 240, 100));
        eye1.setPosition(px - 4.f, py - 4.f); target.draw(eye1);
        eye1.setPosition(px + 2.f, py - 8.f); target.draw(eye1);
        // Base del terreno
        sf::RectangleShape base(sf::Vector2f(20.f, 4.f)); base.setFillColor(sf::Color(60, 50, 70));
        base.setPosition(px - 10.f, py + 12.f); target.draw(base);
    }
    else if (type == ENEMY_GARGOYLE) {
        // Gargoyle di pietra con ali spezzate
        sf::RectangleShape body(sf::Vector2f(22.f, 22.f)); body.setFillColor(sf::Color(90, 90, 95)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPosition(px - 11.f, py - 8.f); target.draw(body);
        // Ali spezzate
        sf::ConvexShape wing; wing.setPointCount(5);
        wing.setFillColor(sf::Color(70, 70, 75)); wing.setOutlineThickness(1.f); wing.setOutlineColor(outline);
        wing.setPoint(0, sf::Vector2f(px-10, py-6)); wing.setPoint(1, sf::Vector2f(px-20, py-12));
        wing.setPoint(2, sf::Vector2f(px-22, py-4)); wing.setPoint(3, sf::Vector2f(px-18, py+2));
        wing.setPoint(4, sf::Vector2f(px-12, py-2));
        target.draw(wing);
        wing.scale(-1.f, 1.f); wing.setPosition(px+10, py-6); target.draw(wing);
        // Testa
        sf::RectangleShape head(sf::Vector2f(16.f, 14.f)); head.setFillColor(sf::Color(100, 100, 105)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px - 8.f, py - 24.f); target.draw(head);
        // Corna
        sf::ConvexShape horn1; horn1.setPointCount(3); horn1.setFillColor(sf::Color(80, 80, 85));
        horn1.setPoint(0, sf::Vector2f(px-8, py-24)); horn1.setPoint(1, sf::Vector2f(px-12, py-30)); horn1.setPoint(2, sf::Vector2f(px-6, py-26));
        target.draw(horn1);
        horn1.setPoint(0, sf::Vector2f(px+8, py-24)); horn1.setPoint(1, sf::Vector2f(px+12, py-30)); horn1.setPoint(2, sf::Vector2f(px+6, py-26));
        target.draw(horn1);
        // Occhi
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color(200, 50, 50));
        eye.setPosition(px - 5.f, py - 18.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 18.f); target.draw(eye);
    }
    else if (type == ENEMY_WELL_SPIRIT) {
        // Spirito acquatico: semitrasparente blu
        sf::CircleShape top(12.f); top.setFillColor(sf::Color(120, 200, 255, 130));
        top.setPosition(px - 12.f, py - 16.f); target.draw(top);
        sf::ConvexShape body; body.setPointCount(5);
        body.setFillColor(sf::Color(120, 200, 255, 130)); body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(80, 150, 200, 180));
        body.setPoint(0, sf::Vector2f(px, py-20)); body.setPoint(1, sf::Vector2f(px+12, py-8));
        body.setPoint(2, sf::Vector2f(px+10, py+10)); body.setPoint(3, sf::Vector2f(px-10, py+10));
        body.setPoint(4, sf::Vector2f(px-12, py-8));
        target.draw(body);
        // Volto
        sf::CircleShape face(6.f); face.setFillColor(sf::Color(150, 220, 255, 180));
        face.setPosition(px - 6.f, py - 14.f); target.draw(face);
        // Occhi
        sf::CircleShape eye(2.f); eye.setFillColor(sf::Color(80, 150, 200));
        eye.setPosition(px - 4.f, py - 10.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 10.f); target.draw(eye);
        // Bolle
        for(int i=0; i<3; i++) {
            sf::CircleShape bubble(1.f + (i%2)); bubble.setFillColor(sf::Color(200, 240, 255, 180));
            bubble.setPosition(px - 8.f + i*6.f, py + 4.f); target.draw(bubble);
        }
    }
    else if (type == ENEMY_CURSED_BOAR) {
        // Cinghiale maledetto: corpo tozzo + zanne
        sf::ConvexShape body; body.setPointCount(5);
        body.setFillColor(sf::Color(80, 60, 50)); body.setOutlineThickness(1.5f); body.setOutlineColor(outline);
        body.setPoint(0, sf::Vector2f(px-14, py+4)); body.setPoint(1, sf::Vector2f(px-12, py-8));
        body.setPoint(2, sf::Vector2f(px+10, py-10)); body.setPoint(3, sf::Vector2f(px+16, py-2));
        body.setPoint(4, sf::Vector2f(px+10, py+8));
        target.draw(body);
        // Fango sul dorso
        sf::RectangleShape mud(sf::Vector2f(20.f, 4.f)); mud.setFillColor(sf::Color(50, 40, 30));
        mud.setPosition(px - 10.f, py - 8.f); target.draw(mud);
        // Testa
        sf::CircleShape head(8.f); head.setFillColor(sf::Color(100, 80, 70)); head.setOutlineThickness(1.5f); head.setOutlineColor(outline);
        head.setPosition(px + 6.f, py - 12.f); target.draw(head);
        // Zanne incrostate
        sf::ConvexShape tusk1; tusk1.setPointCount(3); tusk1.setFillColor(sf::Color(200, 200, 180));
        tusk1.setPoint(0, sf::Vector2f(px+10, py-4)); tusk1.setPoint(1, sf::Vector2f(px+16, py-2));
        tusk1.setPoint(2, sf::Vector2f(px+10, py+2));
        target.draw(tusk1);
        // Occhio
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 100, 0));
        eye.setPosition(px + 10.f, py - 8.f); target.draw(eye);
        // Zampe
        for(int i=0; i<4; i++) {
            sf::RectangleShape leg(sf::Vector2f(4.f, 6.f)); leg.setFillColor(sf::Color(60, 45, 35));
            leg.setPosition(px - 12.f + i*8.f, py + 8.f); target.draw(leg);
        }
    }
    else if (type == ENEMY_PREDATOR_FUNGUS) {
        // Fungo predatore: cappuccio luminoso + gambo + spore
        // Gambo
        sf::RectangleShape stalk(sf::Vector2f(8.f, 14.f)); stalk.setFillColor(sf::Color(220, 200, 180)); stalk.setOutlineThickness(1.f); stalk.setOutlineColor(outline);
        stalk.setPosition(px - 4.f, py - 2.f); target.draw(stalk);
        // Cappuccio
        sf::ConvexShape cap; cap.setPointCount(5);
        cap.setFillColor(sf::Color(180, 80, 200)); cap.setOutlineThickness(1.5f); cap.setOutlineColor(outline);
        cap.setPoint(0, sf::Vector2f(px-16, py-2)); cap.setPoint(1, sf::Vector2f(px-12, py-14));
        cap.setPoint(2, sf::Vector2f(px, py-18)); cap.setPoint(3, sf::Vector2f(px+12, py-14));
        cap.setPoint(4, sf::Vector2f(px+16, py-2));
        target.draw(cap);
        // Macchie luminose sul cappuccio
        for(int i=0; i<3; i++) {
            sf::CircleShape spot(2.f); spot.setFillColor(sf::Color(255, 220, 100));
            spot.setPosition(px - 8.f + i*6.f, py - 12.f); target.draw(spot);
        }
        // Occhi
        sf::CircleShape eye(1.5f); eye.setFillColor(sf::Color(255, 50, 50));
        eye.setPosition(px - 4.f, py - 4.f); target.draw(eye);
        eye.setPosition(px + 1.f, py - 4.f); target.draw(eye);
        // Spore fluttuanti
        for(int i=0; i<4; i++) {
            sf::CircleShape spore(1.f); spore.setFillColor(sf::Color(200, 150, 220, 200));
            spore.setPosition(px - 14.f + i*8.f, py - 22.f + (i%2)*4.f); target.draw(spore);
        }
    }
    // (altri tipi gia' gestiti sopra; se si arriva qui con un tipo non
    // riconosciuto, non si disegna nulla oltre la barra HP)
}
