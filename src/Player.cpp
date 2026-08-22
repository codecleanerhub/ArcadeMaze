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
//   * Il salto ha due effetti: visivo (jumpOffset tramite sinf()) e logico
//     (isJumping() ritorna true e blocca i danni).
//   * In modalita' labirinto il movimento e' "snap to grid": ci si allinea
//     al centro della cella prima di poter girare. In modalita' boss il
//     movimento e' libero in pixel.
// ===========================================================================

Player::Player() : characterType(CHAR_HERO_M), playerNum(1), tint(255, 255, 255) { reset(); }

// --- Funzioni helper per CharacterType ---

// Restituisce il path base dello sprite per il personaggio.
// I file sono: assets/sprites/<base>_sheet.png + <base>_walk0..3_sheet.png
std::string getCharacterSpriteBase(CharacterType ct) {
    switch (ct) {
        case CHAR_HERO_M:   return "assets/sprites/player1";      // esiste gia'
        case CHAR_HERO_F:   return "assets/sprites/player2";      // esiste gia'
        case CHAR_MAGE:     return "assets/sprites/char_mage";
        case CHAR_ORC:      return "assets/sprites/char_orc";
        case CHAR_ELF:      return "assets/sprites/char_elf";
        case CHAR_KNIGHT:   return "assets/sprites/char_knight";
        case CHAR_GOLEM:   return "assets/sprites/char_golem";
        case CHAR_DRAGON:  return "assets/sprites/char_dragon";
        case CHAR_VAMPIRE: return "assets/sprites/char_vampire";
    }
    return "assets/sprites/player1";
}

// Restituisce il nome descrittivo del personaggio (per UI menu selezione).
std::string getCharacterName(CharacterType ct) {
    switch (ct) {
        case CHAR_HERO_M:   return "HERO";
        case CHAR_HERO_F:   return "HEROINE";
        case CHAR_MAGE:     return "MAGE";
        case CHAR_ORC:      return "ORC";
        case CHAR_ELF:      return "ELF";
        case CHAR_KNIGHT:   return "KNIGHT";
        case CHAR_GOLEM:   return "GOLEM";
        case CHAR_DRAGON:  return "DRAGON";
        case CHAR_VAMPIRE: return "VAMPIRE";
    }
    return "HERO";
}

// Restituisce il color tint per distinguere P1 da P2 quando stesso personaggio.
// P1 = bianco (nessun tint), P2 = bluastro (200, 200, 255).
sf::Color getPlayerTint(int playerNum) {
    if (playerNum == 2) {
        // P2: tint bluastro leggero per distinguere
        return sf::Color(200, 200, 255);
    }
    // P1: nessun tint (bianco = moltiplica per 1)
    return sf::Color(255, 255, 255);
}

// Restituisce true se lo sprite di default del personaggio e' rivolto verso
// DESTRA. Questo decide la logica di flip:
//   * default RIGHT (true):  flipped = (lastDx < 0) -> specchia quando muove LEFT
//   * default LEFT  (false): flipped = (lastDx > 0) -> specchia quando muove RIGHT
//
// Mappatura determinata combinando:
//   1. VLM (vision model) su confronti side-by-side originale vs specchiato
//   2. Feedback utente: HERO_M (player1) e' RIGHT-default (test reale ha
//      confermato che con flipped=(lastDx>0) si girava al contrario)
//
// Le sprite "originali" (player1, player2) e i char_* (nuovi personaggi)
// hanno orientamenti INCONSISTENTI tra loro, da qui la necessita' di
// questa tabella per-character.
bool spriteDefaultFacesRight(CharacterType ct) {
    switch (ct) {
        case CHAR_HERO_M:   return true;   // user-verified: default RIGHT
        case CHAR_HERO_F:   return false;  // VLM: default LEFT
        case CHAR_MAGE:     return true;   // VLM: default RIGHT
        case CHAR_ORC:      return false;  // VLM: default LEFT
        case CHAR_ELF:      return false;  // VLM: default LEFT
        case CHAR_KNIGHT:   return false;  // VLM: default LEFT
        case CHAR_GOLEM:    return false;  // VLM: default LEFT
        case CHAR_DRAGON:   return true;   // VLM: default RIGHT
        case CHAR_VAMPIRE:  return true;   // VLM: default RIGHT
    }
    return true;
}

// Reset completo (nuova partita): oltre alla posizione, resetta vite,
// energia, punteggio, soglia prossima vita e arma iniziale (pistola).
void Player::reset() {
    resetPosition();
    lives = 3; maxEnergy = 5; energy = maxEnergy;
    score = 0; nextLifeThreshold = 100000;   // 1 vita extra ogni 100k punti
    currentWeapon = Weapon::generate(WPN_PISTOL);
    projectiles.clear();
    pickedWeaponThisFrame = false;
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

// --- Character selection ---
// Imposta il tipo di personaggio e il numero giocatore, poi carica lo sprite.
// Se il file PNG non esiste, lo sprite resta non caricato e il render()
// usera' il fallback procedurale (renderCharacterFallback).
// FIX -Wshadow: parametro rinominato da 'playerNum' a 'pNum' per evitare
// shadowing del membro omonimo Player::playerNum.
void Player::setCharacter(CharacterType ct, int pNum) {
    characterType = ct;
    this->playerNum = pNum;
    tint = getPlayerTint(pNum);
    loadCharacterSprite();
}

// Carica lo sprite associato al characterType corrente.
void Player::loadCharacterSprite() {
    std::string basePath = getCharacterSpriteBase(characterType);
    loadSprite(basePath);
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
    // FIX: se la direzione richiesta e' bloccata da un muro, aggiorna
    // comunque lastDx/lastDy (per orientare sprite e arma) e ferma
    // il movimento. Prima restituiva false senza toccare dx/dy, il che
    // causava il blocco permanente del player (dx/dy rimanevano ai
    // valori precedenti e al frame successivo il muro fermava di nuovo).
    lastDx = tDx; lastDy = tDy;
    dx = 0; dy = 0;
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
    // 1) Aggiornamento salto: l'offset visivo segue sinf(x*pi) per dare un
    //    arco naturale (partenza morbida, picco a meta', atterraggio morbido).
    if (jumpTimer > 0) {
        jumpTimer--;
        float progress = 1.0f - (float)jumpTimer / (float)maxJumpTime;
        jumpOffset = sinf(progress * (float)M_PI) * 25.0f; // Altezza massima salto: 25 px
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
            if (nextDx != 0 || nextDy != 0) {
                tryMove(nextDx, nextDy, maze);
                nextDx = 0; nextDy = 0;
            }
            // FIX: se davanti c'e' muro, ferma il movimento (dx/dy a 0).
            // Non usare else-if perche' tryMove potrebbe aver impostato dx/dy
            // a 0 se la direzione era bloccata, e questo check e' ridondante
            // ma sicuro: controlla se la direzione corrente porta a un muro.
            if (dx != 0 || dy != 0) {
                if (maze.isWall(col + dx, row + dy)) { dx = 0; dy = 0; }
            }
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
            pickedWeaponThisFrame = true;
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

        // FIX: il proiettile parte dall'estremita' dell'arma, non dal centro
        // del player. L'arma e' posizionata a pos.y - 12 (centro corpo) e
        // spostata di 14px nella direzione orizzontale. La canna dell'arma
        // e' circa 18px oltre il centro dell'arma.
        // Calcoliamo il punto di partenza del proiettile:
        //   - Orizzontale: pos.x + shootDx * 18 (18 = metà arma + canna)
        //   - Verticale:   pos.y - 12 (altezza del centro corpo dove sta l'arma)
        //                  + shootDy * 14 (spostamento verticale dell'arma)
        sf::Vector2f shootPos;
        if (shootDx != 0) {
            // Sparo orizzontale: parti dalla canna a destra/sinistra
            shootPos.x = pos.x + (float)shootDx * 20.f;  // 20 = arma + canna
            shootPos.y = pos.y - 12.f;  // centro corpo dove sta l'arma
        } else {
            // Sparo verticale: parti dall'arma a destra del player
            shootPos.x = pos.x + 4.f;   // arma leggermente a destra
            shootPos.y = pos.y - 12.f + (float)shootDy * 16.f;  // canna su/giu
        }

        projectiles.push_back({shootPos, sf::Vector2f((float)shootDx, (float)shootDy), currentWeapon.power, true, currentWeapon.type});
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
    // py non piu' usato dopo la refactoring del fallback procedurale

    // Etichetta arma sopra la testa.
    // FIX: mostra il nome dell'arma SOLO se ci sono ancora munizioni.
    // Se ammo=0, il player ha finito i colpi e l'arma e' di fatto scarica:
    // non ha senso mostrare ancora il nome (es. "LASER") come se la avesse.
    if (currentWeapon.ammo > 0) {
        drawTextCentered(target, currentWeapon.getName(), (int)px, (int)(pos.y - 60), 2, sf::Color(255, 255, 0));
    }

    // Tentativo di rendering con sprite.
    // Animazioni: attack (se shootAnimTimer>0) > walk > idle.
    // Lo sprite e' 64x64 con anchor piedi a (32, 56); posizioniamo a (px, py+8)
    // per allineare i piedi al suolo della cella.
    if (sprite.isLoaded()) {
        // Selezione animazione
        std::string animName = "idle";
        int frameDuration = 200;
        int frame = 0;
        // FIX: logica di flip per-character. Gli sprite PNG dei personaggi
        // hanno orientamenti INCONSISTENTI tra loro (alcuni guardano a destra
        // di default, altri a sinistra). spriteDefaultFacesRight() restituisce
        // la direzione di default per il characterType corrente:
        //   * default RIGHT: flipped = (lastDx < 0) -> specchia quando muove LEFT
        //   * default LEFT:  flipped = (lastDx > 0) -> specchia quando muove RIGHT
        // In questo modo il personaggio si gira SEMPRE nella direzione di
        // movimento, indipendentemente dall'orientamento di default dello sprite.
        bool defaultRight = spriteDefaultFacesRight(characterType);
        bool flipped = defaultRight ? (lastDx < 0) : (lastDx > 0);
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
            bobY = sinf(animTime * 0.012f) * 2.f;
        } else if (animName == "idle") {
            bobY = sinf(animTime * 0.004f) * 1.f;
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
            float scaleX = 0.9f + sinf(jumpProgress * (float)M_PI) * 0.1f;  // 0.9 -> 1.0 -> 0.9
            // Disegna lo sprite idle con scale modificato e sollevato (+ tint)
            sprite.render(target, "idle", 0, px, pos.y + 8.f - jumpOffset, scaleX, flipped, tint);
        }
        // --- Camminata: usa SEMPRE lo sprite idle con bob effect ---
        // NON usiamo walkSprites[0..3] perche' i frame walk dei nuovi personaggi
        // sono immagini AI indipendenti (non coordinate) - l'effetto sarebbe
        // una "gif animata con immagini slegate". Invece usiamo lo sprite idle
        // (1 sola immagine coerente) con un effetto bob verticale per simulare
        // la camminata. Questo da un risultato fluido e coordinato per tutti
        // i personaggi (originali e nuovi).
        else if (isWalking) {
            // Bob effect piu' pronunciato quando cammina (effetto passo)
            float walkBob = sinf(animTime * 0.012f) * 3.f;
            // Leggera inclinazione orizzontale per simulare il dondolio
            float scaleX = 1.0f + sinf(animTime * 0.024f) * 0.05f;
            sprite.render(target, "idle", 0, px, pos.y + 8.f + walkBob, scaleX, flipped, tint);
        }
        // Altrimenti usa sprite principale (idle o attack)
        else {
            sprite.render(target, animName, frame, px, pos.y + 8.f + bobY, 1.0f, flipped, tint);
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

        // --- Arma equipaggiata visibile (ramo sprite PNG) ---
        // L'arma viene posizionata DAVANTI al player, all'altezza del
        // centro del corpo (come se fosse imbracciata).
        // Lo sprite e' 64px con anchor piedi a (32,56), quindi il centro
        // del corpo e' circa a pos.y + 8 - 24 = pos.y - 16.
        // Usiamo pos.y - 12 come altezza "imbracciata".
        float weaponX = px;
        float weaponY = pos.y - 12.f;  // centro corpo (era pos.y + 4, ai piedi)
        bool weaponFacingRight = true;  // direzione in cui punta l'arma
        if (lastDx > 0) { weaponX = px + 14.f; weaponFacingRight = true; }
        else if (lastDx < 0) { weaponX = px - 14.f; weaponFacingRight = false; }
        else if (lastDy > 0) { weaponY = pos.y - 12.f; weaponX = px + 4.f; }
        else if (lastDy < 0) { weaponY = pos.y - 12.f; weaponX = px + 4.f; }
        if (isJumping) weaponY -= jumpOffset;
        currentWeapon.renderEquipped(target, weaponX, weaponY, weaponFacingRight);

        drawProjectiles(target);
        return;
    }

    // --- Fallback: rendering procedurale per personaggi senza sprite PNG ---
    // Disegna il personaggio con primitive SFML in base a characterType.
    // Questo permette di avere 8 personaggi giocabili anche senza sprite PNG
    // dedicati per ognuno (i 2 originali hanno sprite, gli altri 6 usano
    // questo fallback che li disegna in stile coerente).
    {
        // FIX: stessa logica di flip per-character dello sprite PNG (vedi sopra).
        bool defaultRight = spriteDefaultFacesRight(characterType);
        bool flipped = defaultRight ? (lastDx < 0) : (lastDx > 0);
        bool walking = (dx != 0 || dy != 0);
        float bobY = 0.f;
        if (walking) {
            bobY = sinf(animTime * 0.012f) * 2.f;
        } else {
            bobY = sinf(animTime * 0.004f) * 1.f;
        }
        renderCharacterFallback(target, px, pos.y + 8.f - jumpOffset + bobY,
                                  flipped, walking, bobY);

        // Speed boost (stesso del ramo sprite)
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
    }
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
        float cosA = std::cosf(rad);
        float sinA = std::sinf(rad);

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

// ---------------------------------------------------------------------------
// renderCharacterFallback: rendering procedurale per i personaggi senza
// sprite PNG dedicati. Disegna il personaggio con primitive SFML in base
// a characterType. Stile coerente con gli sprite esistenti (64px alto,
// palette 16 colori, anchor piedi in basso).
//
// Ogni personaggio ha:
//   * Corpo (rettangolo con colori specifici)
//   * Testa (cerchio)
//   * Dettagli unici (cappello, mantello, orecchie, armatura, scaglie, ecc.)
//   * Arma equipaggiata (chiamata a currentWeapon.renderEquipped)
//   * Tint color applicato a tutte le forme (per P2 se stesso personaggio)
//
// Parametri:
//   x, y = posizione centro personaggio (piedi)
//   flipped = true se rivolto a sinistra
//   walking = true se in movimento (bob effect piu' pronunciato)
//   bobY = offset verticale animazione camminata
// ---------------------------------------------------------------------------
void Player::renderCharacterFallback(sf::RenderTarget& target, float x, float y,
                                       bool flipped, bool walking, float bobY) const {
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
    const sf::Color COL_BLUE_D   (48, 40, 36);  // ri-usa dark per blu scuro
    const sf::Color COL_BLUE_L   (80, 160, 220);  // azzurro
    const sf::Color COL_WHITE    (240, 240, 240);
    const sf::Color COL_PURPLE   (160, 120, 200);
    const sf::Color COL_CYAN     (120, 200, 200);

    // Tint applicato a tutti i colori (P1 = bianco, P2 = bluastro)
    // Moltiplichiamo i componenti RGB per il tint normalizzato.
    auto tintColor = [&](const sf::Color& c) -> sf::Color {
        return sf::Color(
            (sf::Uint8)(c.r * tint.r / 255),
            (sf::Uint8)(c.g * tint.g / 255),
            (sf::Uint8)(c.b * tint.b / 255),
            c.a);
    };

    // Colori del personaggio in base al tipo
    sf::Color skin, body, accent, headColor;
    switch (characterType) {
        case CHAR_HERO_M:   // eroe maschio
            skin = COL_PALE; body = COL_MID; accent = COL_GOLD; headColor = COL_PALE;
            break;
        case CHAR_HERO_F:   // eroina femmina
            skin = COL_PALE; body = COL_RED_L; accent = COL_GOLD; headColor = COL_PALE;
            break;
        case CHAR_MAGE:     // mago
            skin = COL_PALE; body = COL_BLUE_L; accent = COL_GOLD; headColor = COL_PALE;
            break;
        case CHAR_ORC:      // orco
            skin = COL_GREEN_L; body = COL_DARK; accent = COL_RED; headColor = COL_GREEN_L;
            break;
        case CHAR_ELF:      // elfo
            skin = COL_PALE; body = COL_GREEN_L; accent = COL_GOLD; headColor = COL_PALE;
            break;
        case CHAR_KNIGHT:   // cavaliere
            skin = COL_MID; body = COL_LIT; accent = COL_GOLD; headColor = COL_MID;
            break;
        case CHAR_GOLEM:   // golem
            skin = COL_MID; body = COL_DARK; accent = COL_CYAN; headColor = COL_MID;
            break;
        case CHAR_DRAGON:  // uomo drago
            skin = COL_RED_L; body = COL_RED; accent = COL_GOLD; headColor = COL_RED_L;
            break;
        case CHAR_VAMPIRE: // vampiro
            skin = COL_PALE; body = COL_BLACK; accent = COL_RED; headColor = COL_PALE;
            break;
        default:
            skin = COL_PALE; body = COL_MID; accent = COL_GOLD; headColor = COL_PALE;
    }

    // Applica tint a tutti i colori
    skin = tintColor(skin);
    body = tintColor(body);
    accent = tintColor(accent);
    headColor = tintColor(headColor);

    float px = x;
    float py = y;

    // --- Ombra sul pavimento ---
    sf::CircleShape shadow(8.f);
    shadow.setFillColor(sf::Color(COL_BLACK.r, COL_BLACK.g, COL_BLACK.b, 80));
    shadow.setScale(1.5f, 0.4f);
    shadow.setPosition(px - 8.f, py + 18.f);
    target.draw(shadow);

    // --- Gambe ---
    // Se sta camminando, alternanza delle gambe (effetto passo)
    float legOffset = walking ? sinf(animTime * 0.024f) * 3.f : 0.f;
    sf::RectangleShape leg1(sf::Vector2f(7.f, 18.f));
    leg1.setFillColor(tintColor(COL_DARK));
    leg1.setOutlineThickness(0.5f);
    leg1.setOutlineColor(tintColor(COL_BLACK));
    leg1.setPosition(px - 7.f, py + 2.f + legOffset);
    target.draw(leg1);
    sf::RectangleShape leg2(sf::Vector2f(7.f, 18.f));
    leg2.setFillColor(tintColor(COL_DARK));
    leg2.setOutlineThickness(0.5f);
    leg2.setOutlineColor(tintColor(COL_BLACK));
    leg2.setPosition(px + 1.f, py + 2.f - legOffset);
    target.draw(leg2);

    // --- Corpo ---
    sf::RectangleShape bodyShape(sf::Vector2f(20.f, 22.f));
    bodyShape.setFillColor(body);
    bodyShape.setOutlineThickness(1.f);
    bodyShape.setOutlineColor(tintColor(COL_BLACK));
    bodyShape.setPosition(px - 10.f, py - 8.f + bobY);
    target.draw(bodyShape);

    // --- Braccia ---
    sf::RectangleShape arm1(sf::Vector2f(5.f, 16.f));
    arm1.setFillColor(body);
    arm1.setOutlineThickness(0.5f);
    arm1.setOutlineColor(tintColor(COL_BLACK));
    arm1.setPosition(px - 13.f, py - 6.f + bobY);
    target.draw(arm1);
    sf::RectangleShape arm2(sf::Vector2f(5.f, 16.f));
    arm2.setFillColor(body);
    arm2.setOutlineThickness(0.5f);
    arm2.setOutlineColor(tintColor(COL_BLACK));
    arm2.setPosition(px + 8.f, py - 6.f + bobY);
    target.draw(arm2);

    // --- Testa ---
    float headR = 7.f;
    sf::CircleShape head(headR);
    head.setFillColor(headColor);
    head.setOutlineThickness(1.f);
    head.setOutlineColor(tintColor(COL_BLACK));
    head.setPosition(px - headR, py - 22.f + bobY);
    target.draw(head);

    // --- Occhi ---
    float eyeY = py - 22.f + bobY + 2.f;
    sf::CircleShape eye1(1.f);
    eye1.setFillColor(tintColor(COL_BLACK));
    eye1.setPosition(px - 3.f, eyeY);
    target.draw(eye1);
    sf::CircleShape eye2(1.f);
    eye2.setFillColor(tintColor(COL_BLACK));
    eye2.setPosition(px + 2.f, eyeY);
    target.draw(eye2);

    // --- Dettagli specifici per tipo di personaggio ---
    switch (characterType) {
        case CHAR_HERO_M: {
            // Cappello da esploratore (fedora)
            sf::RectangleShape hatBrim(sf::Vector2f(18.f, 2.f));
            hatBrim.setFillColor(tintColor(COL_DARK));
            hatBrim.setPosition(px - 9.f, py - 26.f + bobY);
            target.draw(hatBrim);
            sf::RectangleShape hatTop(sf::Vector2f(10.f, 5.f));
            hatTop.setFillColor(tintColor(COL_DARK));
            hatTop.setPosition(px - 5.f, py - 31.f + bobY);
            target.draw(hatTop);
            break;
        }
        case CHAR_HERO_F: {
            // Capelli lunghi (rettili laterali)
            sf::RectangleShape hair1(sf::Vector2f(3.f, 12.f));
            hair1.setFillColor(tintColor(COL_GOLD));
            hair1.setPosition(px - 8.f, py - 22.f + bobY);
            target.draw(hair1);
            sf::RectangleShape hair2(sf::Vector2f(3.f, 12.f));
            hair2.setFillColor(tintColor(COL_GOLD));
            hair2.setPosition(px + 5.f, py - 22.f + bobY);
            target.draw(hair2);
            break;
        }
        case CHAR_MAGE: {
            // Cappello a cono (mago)
            sf::ConvexShape hat;
            hat.setPointCount(3);
            hat.setFillColor(tintColor(COL_BLUE_L));
            hat.setOutlineThickness(0.5f);
            hat.setOutlineColor(tintColor(COL_BLACK));
            hat.setPoint(0, sf::Vector2f(px - 7.f, py - 26.f + bobY));
            hat.setPoint(1, sf::Vector2f(px + 7.f, py - 26.f + bobY));
            hat.setPoint(2, sf::Vector2f(px, py - 38.f + bobY));
            target.draw(hat);
            // Stella sul cappello
            sf::CircleShape star(1.5f);
            star.setFillColor(tintColor(COL_GOLD));
            star.setPosition(px - 1.5f, py - 32.f + bobY);
            target.draw(star);
            // Mantello dietro
            sf::ConvexShape cloak;
            cloak.setPointCount(3);
            cloak.setFillColor(sf::Color(tintColor(COL_BLUE_L).r,
                                          tintColor(COL_BLUE_L).g,
                                          tintColor(COL_BLUE_L).b, 180));
            cloak.setPoint(0, sf::Vector2f(px, py - 8.f + bobY));
            cloak.setPoint(1, sf::Vector2f(px - 12.f, py + 16.f));
            cloak.setPoint(2, sf::Vector2f(px + 12.f, py + 16.f));
            target.draw(cloak);
            break;
        }
        case CHAR_ORC: {
            // Zanne (2 triangoli bianchi dalla bocca)
            for (int side = 0; side < 2; side++) {
                float dir = (side == 0) ? -1.f : 1.f;
                sf::ConvexShape fang;
                fang.setPointCount(3);
                fang.setFillColor(tintColor(COL_WHITE));
                fang.setPoint(0, sf::Vector2f(px + dir * 2.f, py - 16.f + bobY));
                fang.setPoint(1, sf::Vector2f(px + dir * 3.f, py - 12.f + bobY));
                fang.setPoint(2, sf::Vector2f(px + dir * 1.f, py - 12.f + bobY));
                target.draw(fang);
            }
            // Orecchie appuntite
            for (int side = 0; side < 2; side++) {
                float dir = (side == 0) ? -1.f : 1.f;
                sf::ConvexShape ear;
                ear.setPointCount(3);
                ear.setFillColor(headColor);
                ear.setPoint(0, sf::Vector2f(px + dir * (headR + 1.f), py - 22.f + bobY));
                ear.setPoint(1, sf::Vector2f(px + dir * (headR + 5.f), py - 24.f + bobY));
                ear.setPoint(2, sf::Vector2f(px + dir * (headR + 2.f), py - 19.f + bobY));
                target.draw(ear);
            }
            break;
        }
        case CHAR_ELF: {
            // Orecchie lunghe appuntite
            for (int side = 0; side < 2; side++) {
                float dir = (side == 0) ? -1.f : 1.f;
                sf::ConvexShape ear;
                ear.setPointCount(3);
                ear.setFillColor(headColor);
                ear.setOutlineThickness(0.5f);
                ear.setOutlineColor(tintColor(COL_BLACK));
                ear.setPoint(0, sf::Vector2f(px + dir * (headR + 1.f), py - 22.f + bobY));
                ear.setPoint(1, sf::Vector2f(px + dir * (headR + 6.f), py - 25.f + bobY));
                ear.setPoint(2, sf::Vector2f(px + dir * (headR + 3.f), py - 18.f + bobY));
                target.draw(ear);
            }
            // Cappuccio verde
            sf::ConvexShape hood;
            hood.setPointCount(3);
            hood.setFillColor(body);
            hood.setPoint(0, sf::Vector2f(px - 9.f, py - 24.f + bobY));
            hood.setPoint(1, sf::Vector2f(px + 9.f, py - 24.f + bobY));
            hood.setPoint(2, sf::Vector2f(px, py - 34.f + bobY));
            target.draw(hood);
            break;
        }
        case CHAR_KNIGHT: {
            // Elmo (rettangolo con visiera)
            sf::RectangleShape helmet(sf::Vector2f(14.f, 10.f));
            helmet.setFillColor(tintColor(COL_LIT));
            helmet.setOutlineThickness(1.f);
            helmet.setOutlineColor(tintColor(COL_BLACK));
            helmet.setPosition(px - 7.f, py - 28.f + bobY);
            target.draw(helmet);
            // Visiera (fessura)
            sf::RectangleShape visor(sf::Vector2f(10.f, 2.f));
            visor.setFillColor(tintColor(COL_BLACK));
            visor.setPosition(px - 5.f, py - 24.f + bobY);
            target.draw(visor);
            // Piumaggio rosso
            sf::RectangleShape plume(sf::Vector2f(2.f, 6.f));
            plume.setFillColor(tintColor(COL_RED));
            plume.setPosition(px - 1.f, py - 34.f + bobY);
            target.draw(plume);
            // Spalline
            sf::RectangleShape shoulder1(sf::Vector2f(6.f, 4.f));
            shoulder1.setFillColor(tintColor(COL_LIT));
            shoulder1.setOutlineThickness(0.5f);
            shoulder1.setOutlineColor(tintColor(COL_BLACK));
            shoulder1.setPosition(px - 14.f, py - 8.f + bobY);
            target.draw(shoulder1);
            sf::RectangleShape shoulder2(sf::Vector2f(6.f, 4.f));
            shoulder2.setFillColor(tintColor(COL_LIT));
            shoulder2.setOutlineThickness(0.5f);
            shoulder2.setOutlineColor(tintColor(COL_BLACK));
            shoulder2.setPosition(px + 8.f, py - 8.f + bobY);
            target.draw(shoulder2);
            break;
        }
        case CHAR_GOLEM: {
            // Crepe sul corpo (3 linee scure)
            for (int i = 0; i < 3; i++) {
                sf::RectangleShape crack(sf::Vector2f(1.f, 6.f));
                crack.setFillColor(tintColor(COL_BLACK));
                crack.setPosition(px - 6.f + i * 6.f, py - 6.f + bobY);
                crack.rotate((i % 2) * 20.f);
                target.draw(crack);
            }
            // Occhi glow (cyan)
            sf::CircleShape glow1(1.5f);
            glow1.setFillColor(tintColor(COL_CYAN));
            glow1.setPosition(px - 4.f, py - 20.f + bobY);
            target.draw(glow1);
            sf::CircleShape glow2(1.5f);
            glow2.setFillColor(tintColor(COL_CYAN));
            glow2.setPosition(px + 2.f, py - 20.f + bobY);
            target.draw(glow2);
            break;
        }
        case CHAR_DRAGON: {
            // Cresta sul capo (3 spuntoni)
            for (int i = 0; i < 3; i++) {
                sf::ConvexShape spike;
                spike.setPointCount(3);
                spike.setFillColor(tintColor(COL_RED));
                spike.setPoint(0, sf::Vector2f(px - 5.f + i * 4.f, py - 26.f + bobY));
                spike.setPoint(1, sf::Vector2f(px - 3.f + i * 4.f, py - 32.f + bobY));
                spike.setPoint(2, sf::Vector2f(px - 1.f + i * 4.f, py - 26.f + bobY));
                target.draw(spike);
            }
            // Ali (2 triangoli dietro)
            for (int side = 0; side < 2; side++) {
                float dir = (side == 0) ? -1.f : 1.f;
                sf::ConvexShape wing;
                wing.setPointCount(3);
                wing.setFillColor(sf::Color(tintColor(COL_RED).r,
                                             tintColor(COL_RED).g,
                                             tintColor(COL_RED).b, 200));
                wing.setPoint(0, sf::Vector2f(px + dir * 10.f, py - 6.f + bobY));
                wing.setPoint(1, sf::Vector2f(px + dir * 20.f, py - 12.f + bobY));
                wing.setPoint(2, sf::Vector2f(px + dir * 16.f, py + 4.f));
                target.draw(wing);
            }
            // Coda
            sf::ConvexShape tail;
            tail.setPointCount(3);
            tail.setFillColor(tintColor(COL_RED));
            tail.setPoint(0, sf::Vector2f(px - 3.f, py + 14.f));
            tail.setPoint(1, sf::Vector2f(px - 8.f, py + 20.f));
            tail.setPoint(2, sf::Vector2f(px + 2.f, py + 18.f));
            target.draw(tail);
            break;
        }
        case CHAR_VAMPIRE: {
            // Mantello nero (dietro)
            sf::ConvexShape cloak;
            cloak.setPointCount(3);
            cloak.setFillColor(tintColor(COL_BLACK));
            cloak.setPoint(0, sf::Vector2f(px, py - 8.f + bobY));
            cloak.setPoint(1, sf::Vector2f(px - 14.f, py + 18.f));
            cloak.setPoint(2, sf::Vector2f(px + 14.f, py + 18.f));
            target.draw(cloak);
            // Colletto rosso a V
            sf::ConvexShape collar;
            collar.setPointCount(3);
            collar.setFillColor(tintColor(COL_RED));
            collar.setPoint(0, sf::Vector2f(px - 5.f, py - 8.f + bobY));
            collar.setPoint(1, sf::Vector2f(px + 5.f, py - 8.f + bobY));
            collar.setPoint(2, sf::Vector2f(px, py - 2.f + bobY));
            target.draw(collar);
            // Canini (2 piccoli triangoli bianchi)
            for (int side = 0; side < 2; side++) {
                float dir = (side == 0) ? -1.f : 1.f;
                sf::ConvexShape fang;
                fang.setPointCount(3);
                fang.setFillColor(tintColor(COL_WHITE));
                fang.setPoint(0, sf::Vector2f(px + dir * 2.f, py - 16.f + bobY));
                fang.setPoint(1, sf::Vector2f(px + dir * 1.f, py - 12.f + bobY));
                fang.setPoint(2, sf::Vector2f(px + dir * 3.f, py - 12.f + bobY));
                target.draw(fang);
            }
            break;
        }
    }

    // --- Arma equipaggiata (fallback procedurale) ---
    // Stessa logica del ramo sprite: arma DAVANTI al player, all'altezza
    // del centro corpo (imbracciata, non ai piedi).
    {
        float wX = px;
        float wY = py - 12.f;
        bool wFacingRight = true;
        if (lastDx > 0) { wX = px + 14.f; wFacingRight = true; }
        else if (lastDx < 0) { wX = px - 14.f; wFacingRight = false; }
        else if (lastDy > 0) { wY = py - 12.f; wX = px + 4.f; }
        else if (lastDy < 0) { wY = py - 12.f; wX = px + 4.f; }
        currentWeapon.renderEquipped(target, wX, wY, wFacingRight);
    }
}
