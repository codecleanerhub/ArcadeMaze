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
    jumpOffset = 0.0f;
}

// loadSprite: carica lo sprite del giocatore da basePath.png + basePath.json.
// Restituisce true se il caricamento ha avuto successo.
bool Player::loadSprite(const std::string& basePath) {
    return sprite.load(basePath);
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

    if (freeMovement) {
        // --- Modalita' stanza del boss: movimento libero ---
        if (nextDx != 0 || nextDy != 0) {
            dx = nextDx; dy = nextDy; lastDx = dx; lastDy = dy; nextDx = 0; nextDy = 0;
        }
        pos.x += dx * speed; pos.y += dy * speed;
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
        if (fabs(pos.x - centerX) < speed && fabs(pos.y - centerY) < speed) {
            pos.x = centerX; pos.y = centerY;
            // Applica direzione richiesta (se fattibile).
            if (nextDx != 0 || nextDy != 0) { tryMove(nextDx, nextDy, maze); nextDx = 0; nextDy = 0; }
            // Se davanti c'e' muro, ferma il movimento.
            if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
        }
        pos.x += dx * speed; pos.y += dy * speed;

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
    drawTextCentered(target, currentWeapon.getName(), px, pos.y - 45, 2, sf::Color(255, 255, 0));

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
        // Disegna lo sprite con bob effect + leg movement simulato
        // Scale 1.0: sprite 64x64 nativo (cella labirinto 48x48)
        float bobY = 0.f;
        if (animName == "walk" && (dx != 0 || dy != 0)) {
            bobY = sin(animTime * 0.012f) * 2.f;
        } else if (animName == "idle") {
            bobY = sin(animTime * 0.004f) * 1.f;
        }
        // Leg movement simulato: piccolo offset orizzontale alternato
        // (simula il peso che si sposta da una gamba all'altra)
        float offsetX = (animName == "walk" && (dx != 0 || dy != 0)) ?
                        sin(animTime * 0.024f) * 1.f : 0.f;  // +/- 1px
        sprite.render(target, animName, frame, px + offsetX, pos.y + 8.f + bobY, 1.0f, flipped);
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
// Forma diversa per tipo di arma: pistol = pallottola gialla, laser = raggio
// ciano, shotgun/rocket = palla rossa.
// ---------------------------------------------------------------------------
void Player::drawProjectiles(sf::RenderTarget& target) {
    for (const auto& p : projectiles) {
        if (p.active) {
            if (p.type == WPN_PISTOL) {
                // Pallottola piccola gialla (3px raggio)
                sf::CircleShape proj(3.f); proj.setFillColor(sf::Color(255, 220, 80));
                proj.setOutlineThickness(1.f); proj.setOutlineColor(sf::Color(120, 80, 0));
                proj.setPosition(p.pos.x - 3.f, p.pos.y - 3.f); target.draw(proj);
            } else if (p.type == WPN_LASER) {
                // Raggio laser ciano sottile (12x3)
                sf::RectangleShape beam(sf::Vector2f(12.f, 3.f)); beam.setFillColor(sf::Color(80, 220, 255));
                beam.setOutlineThickness(1.f); beam.setOutlineColor(sf::Color(20, 100, 180));
                beam.setPosition(p.pos.x - 6.f, p.pos.y - 1.5f); target.draw(beam);
            } else if (p.type == WPN_SHOTGUN) {
                // ShotGun: 3 pallini rossi piccoli (2px)
                for(int i = -2; i <= 2; i += 2) {
                    sf::CircleShape proj(2.f); proj.setFillColor(sf::Color(255, 100, 50));
                    proj.setPosition(p.pos.x - 2.f + i, p.pos.y - 2.f); target.draw(proj);
                }
            } else { // WPN_ROCKET
                // Razzo: corpo + punta + scia
                sf::RectangleShape body(sf::Vector2f(8.f, 4.f)); body.setFillColor(sf::Color(120, 120, 130));
                body.setOutlineThickness(1.f); body.setOutlineColor(sf::Color(40, 40, 50));
                body.setPosition(p.pos.x - 4.f, p.pos.y - 2.f); target.draw(body);
                sf::CircleShape tip(2.f); tip.setFillColor(sf::Color(220, 60, 40));
                tip.setPosition(p.pos.x + 2.f, p.pos.y - 2.f); target.draw(tip);
                // Scia arancione dietro
                sf::RectangleShape trail(sf::Vector2f(4.f, 2.f)); trail.setFillColor(sf::Color(255, 150, 0, 180));
                trail.setPosition(p.pos.x - 8.f, p.pos.y - 1.f); target.draw(trail);
            }
        }
    }
}
