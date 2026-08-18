#include "Player.h"
#include <iostream>
#include <algorithm>
#include <cmath>

// ===========================================================================
// Player.cpp - Implementazione del giocatore.
//
// Note importanti:
//   * Tutti i timer sono in "ms simulati": ogni frame a 60 FPS vengono
//     decrementati di 16. Questo approccio semplifica il ragionamento
//     ("1000 ms di invulnerabilita'" invece di "60 frame").
//   * Il salto ha due effetti: visivo (jumpOffset tramite sin()) e logico
//     (isJumping() ritorna true e blocca i danni).
//   * In modalita' labirinto il movimento e' "snap to grid": ci si allinea
//     al centro della cella prima di poter girare. In modalita' boss il
//     movimento e' libero in pixel.
// ===========================================================================

Player::Player() { reset(); }

// Reset completo (nuova partita): oltre alla posizione, resetta vite,
// energia, punteggio, soglia prossima vita e arma iniziale (pistola).
void Player::reset() {
    resetPosition();
    lives = 3; maxEnergy = 5; energy = maxEnergy;
    score = 0; nextLifeThreshold = 100000;   // 1 vita extra ogni 100k punti
    currentWeapon = Weapon::generate(WPN_PISTOL);
    projectiles.clear();
}

// Reset solo posizione/stato movimento (mantiene punteggio/vite). Usato
// all'inizio di ogni livello e dopo aver perso una vita.
void Player::resetPosition() {
    // Posizione iniziale: centro della cella (1,1) del labirinto.
    pos.x = 1 * TILE_SIZE + TILE_SIZE / 2.0f;
    pos.y = 1 * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
    dx = 0; dy = 0; nextDx = 0; nextDy = 0; lastDx = 1; lastDy = 0;
    speed = 2; jumpTimer = 0; maxJumpTime = 0; damageTimer = 0; shootCooldown = 0;
    shootAnimTimer = 0;
    animTime = 0;
    speedBoostTimer = 0;
    jumpOffset = 0.0f;
}

// loadSprite: carica sprite principale + 4 frame camminata + 1 salto.
bool Player::loadSprite(const std::string& basePath) {
    bool mainOk = sprite.load(basePath);
    for(int i = 0; i < 4; i++) {
        walkSprites[i].load(basePath + "_walk" + std::to_string(i));
    }
    jumpSprite.load(basePath + "_jump");
    return mainOk;
}

// Imposta posizione assoluta e ferma il movimento (usato in modalita' boss).
void Player::setPosition(float newX, float newY) {
    pos.x = newX; pos.y = newY; dx = 0; dy = 0; nextDx = 0; nextDy = 0;
}

// ---------------------------------------------------------------------------
// tryMove: tenta di impostare la direzione di movimento verso (tDx, tDy).
// Restituisce true se la cella adiacente non e' muro. Aggiorna anche
// lastDx/lastDy per orientare correttamente l'arma quando ci si ferma.
// ---------------------------------------------------------------------------
bool Player::tryMove(int tDx, int tDy, Maze& maze) {
    int col = (int)(pos.x / TILE_SIZE);
    int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
    if (!maze.isWall(col + tDx, row + tDy)) {
        dx = tDx; dy = tDy; lastDx = tDx; lastDy = tDy;
        return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// update: aggiorna tutti gli aspetti del giocatore.
//
//  1. Salto: calcola l'offset verticale visivo tramite mezza sinusoide
//     (0 -> max -> 0 in `maxJumpTime` frame).
//  2. Decrementa timer di invulnerabilita' e cooldown sparo (16 ms/frame).
//  3. Movimento:
//     - Modalita' boss (freeMovement=true): movimento libero in pixel, con
//       limiti ai bordi della finestra.
//     - Modalita' labirinto: align-to-grid. Quando ci si trova vicino al
//       centro di una cella (entro `speed`), si scatta al centro esatto e
//       si valuta se cambiare direzione; se davanti c'e' muro, ci si ferma.
//  4. Collisioni con tesori/armi della cella corrente.
//  5. Avanzamento dei proiettili con rimozione di quelli inattivi.
// ---------------------------------------------------------------------------
void Player::update(Maze& maze, bool freeMovement, std::vector<Particle>& particles) {
    // 1) Aggiornamento salto: l'offset visivo segue sin(x*pi) per dare un
    //    arco naturale (partenza morbida, picco a meta', atterraggio morbido).
    if (jumpTimer > 0) {
        jumpTimer--;
        float progress = 1.0f - (float)jumpTimer / (float)maxJumpTime;
        jumpOffset = sin(progress * M_PI) * 25.0f; // Altezza massima salto: 25 px
    } else {
        jumpOffset = 0.0f;
    }

    // 2) Decrementa i timer (16 ms per frame a 60 FPS). Usiamo una soglia
    //    per evitare che il valore resti bloccato a 1..15.
    if (damageTimer > 16) damageTimer -= 16; else damageTimer = 0;
    if (shootCooldown > 16) shootCooldown -= 16; else shootCooldown = 0;
    if (shootAnimTimer > 16) shootAnimTimer -= 16; else shootAnimTimer = 0;
    // Incrementa animTime per le animazioni idle/walk
    animTime += 16;
    // Decrementa speed boost timer
    if (speedBoostTimer > 16) speedBoostTimer -= 16; else speedBoostTimer = 0;

    // Speed effettivo: base 2, con boost diventa 3
    int effectiveSpeed = (speedBoostTimer > 0) ? (speed + 1) : speed;

    if (freeMovement) {
        // --- Modalita' stanza del boss: movimento libero ---
        if (nextDx != 0 || nextDy != 0) {
            dx = nextDx; dy = nextDy; lastDx = dx; lastDy = dy; nextDx = 0; nextDy = 0;
        }
        pos.x += dx * effectiveSpeed; pos.y += dy * effectiveSpeed;
        // Limiti di finestra (margine di 16 px per non uscire con meta' sprite)
        if (pos.x < 16) pos.x = 16;
        if (pos.x > WINDOW_WIDTH - 16) pos.x = WINDOW_WIDTH - 16;
        if (pos.y < UI_HEIGHT + 16) pos.y = UI_HEIGHT + 16;
        if (pos.y > WINDOW_HEIGHT - 16) pos.y = WINDOW_HEIGHT - 16;
    } else {
        // --- Modalita' labirinto: snap-to-grid ---
        int col = (int)(pos.x / TILE_SIZE);
        int row = (int)((pos.y - UI_HEIGHT) / TILE_SIZE);
        float centerX = col * TILE_SIZE + TILE_SIZE / 2.0f;
        float centerY = row * TILE_SIZE + TILE_SIZE / 2.0f + UI_HEIGHT;
        // Quando si e' abbastanza vicini al centro si può cambiare direzione.
        if (fabs(pos.x - centerX) < effectiveSpeed && fabs(pos.y - centerY) < effectiveSpeed) {
            pos.x = centerX; pos.y = centerY;
            // Applica direzione richiesta (se fattibile).
            if (nextDx != 0 || nextDy != 0) { tryMove(nextDx, nextDy, maze); nextDx = 0; nextDy = 0; }
            // Se davanti c'e' muro, ferma il movimento.
            if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
        }
        pos.x += dx * effectiveSpeed; pos.y += dy * effectiveSpeed;

        // Raccolta tesori/armi della cella corrente.
        if (maze.getCellType(col, row) == CELL_TREASURE) {
            maze.collectTreasure(col, row);
            addScore(10000);
            // Effetto particellare: scintille dorate.
            for(int i=0; i<15; i++) {
                particles.push_back({pos, {(float)(rand()%6-3), (float)(rand()%6-3)}, sf::Color(255, 215, 0), 40, 40});
            }
        } else if (maze.getCellType(col, row) == CELL_WEAPON) {
            Weapon w = maze.collectWeapon(col, row);
            collectWeapon(w);
            // Effetto particellare per raccolta arma: scintille dorate
            for(int i=0; i<15; i++) {
                particles.push_back({pos, {(float)(rand()%8-4), (float)(rand()%8-4)}, sf::Color(255, 215, 0), 35, 35});
            }
        }
    }

    // 5) Aggiornamento proiettili: si muovono a 8 px/frame. In modalita'
    //    labirinto vengono disattivati se colpiscono un muro. In ogni caso
    //    vengono disattivati se escono dai bordi dell'area di gioco.
    for (auto& p : projectiles) {
        if (!p.active) continue;
        if (!freeMovement) {
            int pCol = (int)(p.pos.x / TILE_SIZE);
            int pRow = (int)((p.pos.y - UI_HEIGHT) / TILE_SIZE);
            if (maze.isWall(pCol, pRow)) { p.active = false; continue; }
        }
        p.pos.x += p.dir.x * 8.f; p.pos.y += p.dir.y * 8.f;
        if (p.pos.x < 0 || p.pos.x > WINDOW_WIDTH || p.pos.y < UI_HEIGHT || p.pos.y > WINDOW_HEIGHT) p.active = false;
    }
    // Rimuove i proiettili inattivi (erase-remove idiom).
    projectiles.erase(std::remove_if(projectiles.begin(), projectiles.end(), [](const Projectile& p) { return !p.active; }), projectiles.end());
}

// ---------------------------------------------------------------------------
// shoot: crea un proiettile nella direzione di movimento corrente. Se il
// giocatore e' fermo, usa l'ultima direzione valida (lastDx/lastDy). Se
// anche quelle sono zero (caso limite iniziale), spara verso destra.
// Consuma 1 munizione; se ammo==0 non fa nulla.
// ---------------------------------------------------------------------------
void Player::shoot() {
    if (currentWeapon.ammo > 0) {
        int shootDx = (dx != 0) ? dx : lastDx;
        int shootDy = (dy != 0) ? dy : lastDy;

        if (shootDx == 0 && shootDy == 0) shootDx = 1; // Fallback se fermo

        projectiles.push_back({pos, sf::Vector2f((float)shootDx, (float)shootDy), currentWeapon.power, true, currentWeapon.type});
        currentWeapon.ammo--;
        // Triggera animazione di attacco per ~300 ms
        shootAnimTimer = 300;
    }
}

// ---------------------------------------------------------------------------
// takeDamage: applica 1 punto di danno energia. Il danno e' ignorato se:
//   * il giocatore sta saltando (jumpTimer>0): il salto e' un "dodge"
//   * e' ancora invulnerabile (damageTimer>0): ha appena preso un colpo
// Quando l'energia arriva a 0 si perde una vita: l'energia viene ripristinata
// e il giocatore torna alla posizione di partenza del livello.
// ---------------------------------------------------------------------------
void Player::takeDamage() {
    if (!isJumping() && damageTimer == 0) {
        energy--;
        damageTimer = 1000;  // ~1 secondo di invulnerabilita'
        if (energy <= 0) {
            lives--;
            energy = maxEnergy;
            resetPosition();  // respawn
        }
    }
}

// Sostituisce l'arma corrente con quella raccolta (vecchia arma scartata).
void Player::collectWeapon(Weapon w) { currentWeapon = w; }

// addScore: aggiunge punti e, se si supera la soglia, dà una vita extra.
// La soglia viene incrementata di 100000 ogni volta (vita a 100k, 200k, ...).
void Player::addScore(int points) {
    score += points;
    if (score >= nextLifeThreshold) { lives++; nextLifeThreshold += 100000; }
}

// Posizione di griglia calcolata dalla posizione in pixel.
Vec2 Player::getGridPos() const { return { (int)(pos.x / TILE_SIZE), (int)((pos.y - UI_HEIGHT) / TILE_SIZE) }; }

// ---------------------------------------------------------------------------
// render: disegna il personaggio stile "esploratore con Fedora" (simile a
// Indiana Jones). Tutte le proporzioni sono esplicite e basate su (px, py),
// dove py tiene conto dell'offset visivo del salto (il personaggio si
// "alza" quando salta). Vengono disegnati:
//   * Nome dell'arma sopra la testa
//   * Gambe (posizione diversa se si salta)
//   * Corpo (camicia + giubbotto laterale)
//   * Braccia
//   * Testa + cappello Fedora
//   * Frusta sul fianco
//   * Arma in mano (orientata in base a lastDx)
//   * Proiettili con forma diversa per tipo (laser = raggio, altri = palla)
// ---------------------------------------------------------------------------
void Player::render(sf::RenderTarget& target) {
    float px = pos.x;
    float py = pos.y - jumpOffset; // Applica offset visivo del salto

    // Etichetta arma sopra la testa
    drawTextCentered(target, currentWeapon.getName(), px, pos.y - 60, 2, sf::Color(255, 255, 0));

    // Tentativo di rendering con sprite.
    // Animazioni: attack (se shootAnimTimer>0) > walk > idle.
    // Lo sprite e' 64x64 con anchor piedi a (32, 56); posizioniamo a (px, py+8)
    // per allineare i piedi al suolo della cella.
    if (sprite.isLoaded()) {
        // Selezione animazione
        std::string animName = "idle";
        int frameDuration = 200;
        int frame = 0;
        bool flipped = (lastDx < 0);
        if (shootAnimTimer > 0 && sprite.getFrameCount("attack") > 0) {
            animName = "attack";
            frameDuration = 50;  // 6 frame in 300 ms
            int elapsed = 300 - (int)shootAnimTimer;
            int frameCount = sprite.getFrameCount("attack");
            frame = elapsed / frameDuration;
            if (frame >= frameCount) frame = frameCount - 1;
        } else if ((dx != 0 || dy != 0) && sprite.getFrameCount("walk") > 0) {
            animName = "walk";
            frameDuration = 100;
            int frameCount = sprite.getFrameCount("walk");
            frame = (animTime / (uint32_t)frameDuration) % frameCount;
        } else if (sprite.getFrameCount("idle") > 0) {
            animName = "idle";
            frameDuration = 200;
            int frameCount = sprite.getFrameCount("idle");
            frame = (animTime / (uint32_t)frameDuration) % frameCount;
        }
        // Disegna lo sprite con bob effect
        float bobY = 0.f;
        bool isWalking = (animName == "walk" && (dx != 0 || dy != 0));
        bool isJumping = (jumpTimer > 0);
        if (isWalking) {
            bobY = sin(animTime * 0.012f) * 2.f;
        } else if (animName == "idle") {
            bobY = sin(animTime * 0.004f) * 1.f;
        }

        // --- Salto: usa lo sprite idle con effetto zoom-in-alto ---
        // Invece di uno sprite jump separato, scaliamo leggermente in alto
        // e solleviamo lo sprite per simulare il salto.
        if (isJumping) {
            // Progresso del salto: 0 (inizio) -> 1 (apice) -> 0 (fine)
            float jumpProgress = 1.0f - (float)jumpTimer / (float)maxJumpTime;
            // jumpOffset e' gia' calcolato in update (sin curve, max 25px)
            // Effetto zoom: comprime leggermente in orizzontale (0.9x)
            // per simulare lo stretching del salto
            float scaleX = 0.9f + sin(jumpProgress * M_PI) * 0.1f;  // 0.9 -> 1.0 -> 0.9
            // Disegna lo sprite idle con scale modificato e sollevato
            sprite.render(target, "idle", 0, px, pos.y + 8.f - jumpOffset, scaleX, flipped);
        }
        // Se sta camminando e abbiamo 4 frame, cicla walk0->walk1->walk2->walk3
        else if (isWalking && walkSprites[0].isLoaded() && walkSprites[1].isLoaded()) {
            int stepFrame = (animTime / 80) % 4;
            int availableFrames = 0;
            for (int i = 0; i < 4; i++) {
                if (walkSprites[i].isLoaded()) availableFrames++;
            }
            if (availableFrames >= 2) {
                stepFrame = stepFrame % availableFrames;
                walkSprites[stepFrame].render(target, "idle", 0, px, pos.y + 8.f + bobY, 1.0f, flipped);
            } else {
                sprite.render(target, animName, frame, px, pos.y + 8.f + bobY, 1.0f, flipped);
            }
        }
        // Altrimenti usa sprite principale (idle o attack)
        else {
            sprite.render(target, animName, frame, px, pos.y + 8.f + bobY, 1.0f, flipped);
        }

        // Speed boost: effetto discreto (piccoli pixel gialli ai piedi, non cerchio)
        if (speedBoostTimer > 0) {
            sf::Color sparkColor(255, 220, 80, 200);
            for (int i = 0; i < 3; i++) {
                float sparkX = px + (rand() % 12 - 6);
                float sparkY = pos.y + 18.f + (rand() % 4);
                sf::RectangleShape spark(sf::Vector2f(2.f, 2.f));
                spark.setFillColor(sparkColor);
                spark.setPosition(sparkX, sparkY);
                target.draw(spark);
            }
        }

        drawProjectiles(target);
        return;
    }

    // Fallback: rendering a primitive (Indiana Jones)
    sf::Color skin(210, 180, 140);
    sf::Color shirt(200, 200, 200);
    sf::Color jacket(139, 69, 19);
    sf::Color pants(50, 50, 50);
    sf::Color hat(80, 50, 20);
    sf::Color outline(10, 10, 10);

    // Gambe: se sta saltando, sono piu' corte e divaricate (postura "in aria")
    if (isJumping()) {
        sf::RectangleShape leg1(sf::Vector2f(8.f, 16.f)); leg1.setFillColor(pants); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 12.f, py + 4.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(8.f, 16.f)); leg2.setFillColor(pants); leg2.setOutlineThickness(1.f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 4.f, py + 4.f); target.draw(leg2);
    } else {
        sf::RectangleShape leg1(sf::Vector2f(8.f, 20.f)); leg1.setFillColor(pants); leg1.setOutlineThickness(1.f); leg1.setOutlineColor(outline);
        leg1.setPosition(px - 6.f, py + 4.f); target.draw(leg1);
        sf::RectangleShape leg2(sf::Vector2f(8.f, 20.f)); leg2.setFillColor(pants); leg2.setOutlineThickness(1.f); leg2.setOutlineColor(outline);
        leg2.setPosition(px + 2.f, py + 4.f); target.draw(leg2);
    }

    // Corpo (camicia chiara)
    sf::RectangleShape body(sf::Vector2f(24.f, 20.f)); body.setFillColor(shirt); body.setOutlineThickness(1.f); body.setOutlineColor(outline);
    body.setPosition(px - 12.f, py - 8.f); target.draw(body);
    // Giubbotto di pelle ai lati del corpo
    sf::RectangleShape jacket1(sf::Vector2f(6.f, 20.f)); jacket1.setFillColor(jacket); jacket1.setOutlineThickness(1.f); jacket1.setOutlineColor(outline);
    jacket1.setPosition(px - 12.f, py - 8.f); target.draw(jacket1);
    sf::RectangleShape jacket2(sf::Vector2f(6.f, 20.f)); jacket2.setFillColor(jacket); jacket2.setOutlineThickness(1.f); jacket2.setOutlineColor(outline);
    jacket2.setPosition(px + 6.f, py - 8.f); target.draw(jacket2);

    // Braccia
    sf::RectangleShape arm1(sf::Vector2f(6.f, 16.f)); arm1.setFillColor(shirt); arm1.setOutlineThickness(1.f); arm1.setOutlineColor(outline);
    arm1.setPosition(px - 14.f, py - 6.f); target.draw(arm1);
    sf::RectangleShape arm2(sf::Vector2f(6.f, 16.f)); arm2.setFillColor(shirt); arm2.setOutlineThickness(1.f); arm2.setOutlineColor(outline);
    arm2.setPosition(px + 8.f, py - 6.f); target.draw(arm2);

    // Testa (cerchio)
    sf::CircleShape head(8.f); head.setFillColor(skin); head.setOutlineThickness(1.f); head.setOutlineColor(outline);
    head.setPosition(px - 8.f, py - 22.f); target.draw(head);

    // Cappello Fedora: parte superiore + tesa
    sf::RectangleShape top(sf::Vector2f(14.f, 6.f)); top.setFillColor(hat); top.setOutlineThickness(1.f); top.setOutlineColor(outline);
    top.setPosition(px - 7.f, py - 28.f); target.draw(top);
    sf::RectangleShape brim(sf::Vector2f(24.f, 4.f)); brim.setFillColor(hat); brim.setOutlineThickness(1.f); brim.setOutlineColor(outline);
    brim.setPosition(px - 12.f, py - 24.f); target.draw(brim);

    // Frusta arrotolata sul fianco destro
    sf::RectangleShape whip(sf::Vector2f(2.f, 12.f)); whip.setFillColor(sf::Color(100, 50, 10));
    whip.setPosition(px + 10.f, py - 4.f); target.draw(whip);

    // Arma equipaggiata: viene posizionata davanti al personaggio nella
    // direzione di orientamento (lastDx). Su y resta all'altezza del corpo.
    currentWeapon.renderEquipped(target, px + (lastDx * 16), py);

    // Proiettili (comune a sprite e primitive)
    drawProjectiles(target);
}

// ---------------------------------------------------------------------------
// drawProjectiles: disegna i proiettili sparati dal giocatore.
//
// Forma diversa per tipo di arma:
//   * PISTOL  : pallottola rotonda gialla (la rotazione e' visivamente
//               ininfluente sulle forme circolari, ma la posizione e' OK).
//   * LASER   : raggio ciano allungato (14x3) ruotato in modo da allinearsi
//               alla direzione di volo. Se il proiettile si muove in
//               verticale, il raggio risulta verticale (non orizzontale).
//   * SHOTGUN : 3 pallini rossi disposti PERPENDICOLARMENTE alla direzione
//               di volo (pattern a "ventaglio stretto").
//   * ROCKET  : corpo allungato (10x4) + punta conica rossa sul fronte +
//               scia dietro. Tutto ruotato in base alla direzione di volo:
//               un missile sparato verso il basso ha la punta verso il
//               basso e scende in verticale.
//
// La rotazione e' calcolata da `p.dir` tramite atan2(dy, dx). Per le forme
// allungate (laser, rocket) viene impostato l'origine al centro del corpo e
// la rotazione viene applicata con setRotation. Per i pallini rotondi
// (pistol) la rotazione non e' visibile ma la posizione e' corretta.
// ---------------------------------------------------------------------------
void Player::drawProjectiles(sf::RenderTarget& target) {
    for (const auto& p : projectiles) {
        if (!p.active) continue;

        // Angolo di rotazione in gradi, derivato dalla direzione del proiettile.
        // atan2 ritorna 0 per (1,0) [destra], 90 per (0,1) [basso], ecc.
        // Default 0 = puntato verso destra (come da disegno delle forme).
        float angleDeg = 0.f;
        float dlen = std::sqrt(p.dir.x * p.dir.x + p.dir.y * p.dir.y);
        if (dlen > 0.0001f) {
            angleDeg = std::atan2(p.dir.y, p.dir.x) * 180.f / static_cast<float>(M_PI);
        }
        // Coseno/seno precalcolati per posizionare elementi "offset" (punta,
        // scia, pallini satellite) lungo la direzione di volo.
        float rad = angleDeg * static_cast<float>(M_PI) / 180.f;
        float cosA = std::cos(rad);
        float sinA = std::sin(rad);

        if (p.type == WPN_PISTOL) {
            // Pallottola piccola gialla (3px raggio). Essendo circolare,
            // la rotazione non e' visibile ma la posizione rimane corretta.
            sf::CircleShape proj(3.f); proj.setFillColor(sf::Color(255, 220, 80));
            proj.setOutlineThickness(1.f); proj.setOutlineColor(sf::Color(120, 80, 0));
            proj.setPosition(p.pos.x - 3.f, p.pos.y - 3.f); target.draw(proj);
        } else if (p.type == WPN_LASER) {
            // Raggio laser ciano allungato (14x3), ruotato in base alla
            // direzione di volo. setOrigin al centro per rotazione corretta.
            sf::RectangleShape beam(sf::Vector2f(14.f, 3.f));
            beam.setFillColor(sf::Color(80, 220, 255));
            beam.setOutlineThickness(1.f); beam.setOutlineColor(sf::Color(20, 100, 180));
            beam.setOrigin(7.f, 1.5f);  // centro del raggio
            beam.setPosition(p.pos.x, p.pos.y);
            beam.setRotation(angleDeg);
            target.draw(beam);
            // Glow centrale (piccolo cerchio luminoso sopra il raggio)
            sf::CircleShape glow(2.f); glow.setFillColor(sf::Color(200, 250, 255, 200));
            glow.setPosition(p.pos.x - 2.f, p.pos.y - 2.f);
            target.draw(glow);
        } else if (p.type == WPN_SHOTGUN) {
            // ShotGun: 3 pallini rossi piccoli (2px raggio) allineati
            // PERPENDICOLARMENTE alla direzione di volo. L'offset dei pallini
            // e' lungo il vettore perpendicolare (-sinA, cosA).
            float perpX = -sinA;
            float perpY = cosA;
            for (int i = -2; i <= 2; i += 2) {
                sf::CircleShape proj(2.f); proj.setFillColor(sf::Color(255, 100, 50));
                // Offset i/2 lungo il perpendicolare (i = -2, 0, 2 -> -1, 0, 1 px)
                float ox = perpX * (i * 0.5f);
                float oy = perpY * (i * 0.5f);
                proj.setPosition(p.pos.x - 2.f + ox, p.pos.y - 2.f + oy);
                target.draw(proj);
            }
        } else { // WPN_ROCKET
            // Razzo composto da corpo + punta + scia, tutti ruotati in base
            // alla direzione di volo. La punta va sul "fronte" (lato verso
            // cui il missile si muove), la scia sul retro (lato opposto).
            //
            // Corpo: rettangolo 10x4, origine al centro, ruotato.
            sf::RectangleShape body(sf::Vector2f(10.f, 4.f));
            body.setFillColor(sf::Color(120, 120, 130));
            body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(40, 40, 50));
            body.setOrigin(5.f, 2.f);  // centro del corpo
            body.setPosition(p.pos.x, p.pos.y);
            body.setRotation(angleDeg);
            target.draw(body);

            // Punta: cerchio 2px posizionato sul fronte del missile (offset
            // +5 px lungo la direzione di volo dal centro del corpo).
            float tipX = p.pos.x + cosA * 5.f;
            float tipY = p.pos.y + sinA * 5.f;
            sf::CircleShape tip(2.f); tip.setFillColor(sf::Color(220, 60, 40));
            tip.setPosition(tipX - 2.f, tipY - 2.f);
            target.draw(tip);

            // Scia arancione dietro al missile (offset -7 px lungo la
            // direzione opposta al volo). Anche la scia e' ruotata.
            float trailX = p.pos.x - cosA * 7.f;
            float trailY = p.pos.y - sinA * 7.f;
            sf::RectangleShape trail(sf::Vector2f(6.f, 2.f));
            trail.setFillColor(sf::Color(255, 150, 0, 180));
            trail.setOrigin(3.f, 1.f);  // centro
            trail.setPosition(trailX, trailY);
            trail.setRotation(angleDeg);
            target.draw(trail);
        }
    }
}
