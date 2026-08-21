#include "Weapon.h"
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ===========================================================================
// Weapon.cpp - Implementazione delle armi
// ===========================================================================

Weapon Weapon::generateRandom() { return generate(static_cast<WeaponType>(rand() % 4)); }

Weapon Weapon::generate(WeaponType t) {
    Weapon w;
    w.type = t;
    switch (t) {
        case WPN_PISTOL:  w.power = 1; w.ammo = 15; break;
        case WPN_SHOTGUN: w.power = 3; w.ammo = 8;  break;
        case WPN_LASER:   w.power = 2; w.ammo = 20; break;
        case WPN_ROCKET:  w.power = 5; w.ammo = 4;  break;
    }
    return w;
}

std::string Weapon::getName() const {
    switch (type) {
        case WPN_PISTOL:  return "PISTOL";
        case WPN_SHOTGUN: return "SHOTGUN";
        case WPN_LASER:   return "LASER";
        case WPN_ROCKET:  return "ROCKET";
    }
    return "?";
}

sf::Color Weapon::getColor() const {
    switch (type) {
        case WPN_PISTOL:  return sf::Color(200, 200, 50);
        case WPN_SHOTGUN: return sf::Color(200, 100, 50);
        case WPN_LASER:   return sf::Color(80, 200, 255);
        case WPN_ROCKET:  return sf::Color(200, 50, 50);
    }
    return sf::Color::White;
}

// Helper: disegna un rettangolo. posX e' l'angolo superiore sinistro.
// Se flip, specchia orizzontalmente rispetto al centro x.
static void drawRect(sf::RenderTarget& target, float x, float y,
                      float rectX, float rectY, float w, float h,
                      const sf::Color& fill,
                      const sf::Color& outline = sf::Color::Transparent,
                      float outlineThick = 0.f, bool flip = false) {
    sf::RectangleShape shape(sf::Vector2f(w, h));
    shape.setFillColor(fill);
    if (outlineThick > 0.f) {
        shape.setOutlineThickness(outlineThick);
        shape.setOutlineColor(outline);
    }
    float drawX = flip ? (x - (rectX - x) - w) : rectX;
    shape.setPosition(drawX, rectY);
    target.draw(shape);
}

// Helper: disegna un cerchio.
static void drawCircle(sf::RenderTarget& target, float x, float y,
                        float circX, float circY, float r,
                        const sf::Color& fill, bool flip = false) {
    sf::CircleShape shape(r);
    shape.setFillColor(fill);
    float drawX = flip ? (x - (circX - x) - r * 2.f) : circX;
    shape.setPosition(drawX, circY);
    target.draw(shape);
}

void Weapon::render(sf::RenderTarget& target, float x, float y) const {
    sf::RectangleShape body(sf::Vector2f(20.f, 8.f));
    body.setFillColor(getColor());
    body.setPosition(x - 10.f, y - 4.f);
    target.draw(body);
}

// ---------------------------------------------------------------------------
// renderEquipped: arma impugnata dal player
//
// FIX: per specchiare correttamente l'arma a sinistra, usiamo un approccio
// basato sulla posizione. Disegniamo l'arma con orientamento naturale (destra)
// usando coordinate relative al punto (x, y). Per il flip (sinistra),
// specchiamo ogni coordinata X rispetto a x: newX = 2*x - oldX - width.
//
// Questo garantisce che forme asimmetriche (punta conica del razzo, aletta)
// vengano specchiate correttamente senza glitch.
// ---------------------------------------------------------------------------
void Weapon::renderEquipped(sf::RenderTarget& target, float x, float y, bool facingRight) const {
    // Se ammo == 0, non disegnare l'arma
    if (ammo <= 0) return;

    // Funzione helper per specchiare una coordinata X rispetto al centro x
    auto flipX = [x](float px, float w) -> float {
        return 2.f * x - px - w;
    };

    if (type == WPN_PISTOL) {
        // Impugnatura in legno (2 strati)
        {
            sf::RectangleShape gripBase(sf::Vector2f(6.f, 11.f));
            gripBase.setFillColor(sf::Color(50, 25, 12));
            float gx = x - 3.f;
            if (!facingRight) gx = flipX(gx, 6.f);
            gripBase.setPosition(gx, y + 1.f);
            target.draw(gripBase);
        }
        {
            sf::RectangleShape gripMid(sf::Vector2f(5.f, 11.f));
            gripMid.setFillColor(sf::Color(85, 50, 25));
            float gx = x - 2.5f;
            if (!facingRight) gx = flipX(gx, 5.f);
            gripMid.setPosition(gx, y + 1.f);
            target.draw(gripMid);
        }
        // Corpo metallico
        {
            sf::RectangleShape body(sf::Vector2f(13.f, 9.f));
            body.setFillColor(sf::Color(70, 70, 80));
            body.setOutlineThickness(0.5f); body.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x - 4.f;
            if (!facingRight) gx = flipX(gx, 13.f);
            body.setPosition(gx, y - 7.f);
            target.draw(body);
        }
        // Slide superiore
        {
            sf::RectangleShape slide(sf::Vector2f(13.f, 3.f));
            slide.setFillColor(sf::Color(120, 120, 130));
            float gx = x - 4.f;
            if (!facingRight) gx = flipX(gx, 13.f);
            slide.setPosition(gx, y - 7.f);
            target.draw(slide);
        }
        // Inserto dorato
        {
            sf::RectangleShape insert(sf::Vector2f(2.f, 3.f));
            insert.setFillColor(sf::Color(180, 140, 60));
            float gx = x - 3.f;
            if (!facingRight) gx = flipX(gx, 2.f);
            insert.setPosition(gx, y - 6.f);
            target.draw(insert);
        }
        // Canna
        {
            sf::RectangleShape barrel(sf::Vector2f(8.f, 5.f));
            barrel.setFillColor(sf::Color(85, 85, 95));
            float gx = x + 8.f;
            if (!facingRight) gx = flipX(gx, 8.f);
            barrel.setPosition(gx, y - 5.f);
            target.draw(barrel);
        }
        // Bocca
        {
            sf::CircleShape muzzle(1.5f);
            muzzle.setFillColor(sf::Color(15, 15, 15));
            float gx = x + 14.5f;
            if (!facingRight) gx = flipX(gx, 3.f);  // 3 = raggio*2
            muzzle.setPosition(gx, y - 3.5f);
            target.draw(muzzle);
        }
    }
    else if (type == WPN_SHOTGUN) {
        // Calciatura in legno (2 strati)
        {
            sf::RectangleShape stockBase(sf::Vector2f(14.f, 10.f));
            stockBase.setFillColor(sf::Color(70, 40, 18));
            float gx = x - 7.f;
            if (!facingRight) gx = flipX(gx, 14.f);
            stockBase.setPosition(gx, y + 3.f);
            target.draw(stockBase);
        }
        {
            sf::RectangleShape stockTop(sf::Vector2f(14.f, 5.f));
            stockTop.setFillColor(sf::Color(130, 80, 35));
            float gx = x - 7.f;
            if (!facingRight) gx = flipX(gx, 14.f);
            stockTop.setPosition(gx, y + 3.f);
            target.draw(stockTop);
        }
        // Doppia canna
        {
            sf::RectangleShape barrelTop(sf::Vector2f(20.f, 4.f));
            barrelTop.setFillColor(sf::Color(55, 55, 60));
            barrelTop.setOutlineThickness(0.5f); barrelTop.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x - 6.f;
            if (!facingRight) gx = flipX(gx, 20.f);
            barrelTop.setPosition(gx, y - 6.f);
            target.draw(barrelTop);
        }
        {
            sf::RectangleShape barrelBot(sf::Vector2f(20.f, 4.f));
            barrelBot.setFillColor(sf::Color(50, 50, 55));
            barrelBot.setOutlineThickness(0.5f); barrelBot.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x - 6.f;
            if (!facingRight) gx = flipX(gx, 20.f);
            barrelBot.setPosition(gx, y - 1.f);
            target.draw(barrelBot);
        }
        // Riflesso canna
        {
            sf::RectangleShape barrelRef(sf::Vector2f(18.f, 1.f));
            barrelRef.setFillColor(sf::Color(180, 180, 190));
            float gx = x - 5.f;
            if (!facingRight) gx = flipX(gx, 18.f);
            barrelRef.setPosition(gx, y - 5.5f);
            target.draw(barrelRef);
        }
        // Pompa
        {
            sf::RectangleShape pump(sf::Vector2f(8.f, 5.f));
            pump.setFillColor(sf::Color(140, 90, 45));
            pump.setOutlineThickness(0.5f); pump.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x + 1.f;
            if (!facingRight) gx = flipX(gx, 8.f);
            pump.setPosition(gx, y + 4.f);
            target.draw(pump);
        }
        // Scanalatura
        {
            sf::RectangleShape groove(sf::Vector2f(0.8f, 4.f));
            groove.setFillColor(sf::Color(60, 35, 15));
            float gx = x + 4.f;
            if (!facingRight) gx = flipX(gx, 0.8f);
            groove.setPosition(gx, y + 4.5f);
            target.draw(groove);
        }
    }
    else if (type == WPN_ROCKET) {
        // Tubo lanciarazzi
        {
            sf::RectangleShape tube(sf::Vector2f(18.f, 9.f));
            tube.setFillColor(sf::Color(60, 90, 50));
            tube.setOutlineThickness(0.8f); tube.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x - 9.f;
            if (!facingRight) gx = flipX(gx, 18.f);
            tube.setPosition(gx, y - 4.f);
            target.draw(tube);
        }
        // Strato superiore
        {
            sf::RectangleShape tubeTop(sf::Vector2f(18.f, 3.f));
            tubeTop.setFillColor(sf::Color(100, 140, 80));
            float gx = x - 9.f;
            if (!facingRight) gx = flipX(gx, 18.f);
            tubeTop.setPosition(gx, y - 4.f);
            target.draw(tubeTop);
        }
        // Banda metallica
        {
            sf::RectangleShape band(sf::Vector2f(1.5f, 9.f));
            band.setFillColor(sf::Color(180, 180, 180));
            float gx = x - 2.f;
            if (!facingRight) gx = flipX(gx, 1.5f);
            band.setPosition(gx, y - 4.f);
            target.draw(band);
        }
        // Razzo
        {
            sf::RectangleShape rocketBody(sf::Vector2f(8.f, 5.f));
            rocketBody.setFillColor(sf::Color(180, 50, 50));
            rocketBody.setOutlineThickness(0.5f); rocketBody.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x + 5.f;
            if (!facingRight) gx = flipX(gx, 8.f);
            rocketBody.setPosition(gx, y - 2.5f);
            target.draw(rocketBody);
        }
        // Punta conica
        {
            sf::ConvexShape tip; tip.setPointCount(3);
            tip.setFillColor(sf::Color(220, 80, 80));
            if (facingRight) {
                tip.setPoint(0, sf::Vector2f(x + 13.f, y - 2.5f));
                tip.setPoint(1, sf::Vector2f(x + 13.f, y + 2.5f));
                tip.setPoint(2, sf::Vector2f(x + 17.f, y));
            } else {
                // Specchiata: punta a sinistra
                tip.setPoint(0, sf::Vector2f(x - 13.f, y - 2.5f));
                tip.setPoint(1, sf::Vector2f(x - 13.f, y + 2.5f));
                tip.setPoint(2, sf::Vector2f(x - 17.f, y));
            }
            target.draw(tip);
        }
        // Aletta
        {
            sf::ConvexShape fin; fin.setPointCount(3);
            fin.setFillColor(sf::Color(140, 30, 30));
            if (facingRight) {
                fin.setPoint(0, sf::Vector2f(x + 5.f, y - 2.5f));
                fin.setPoint(1, sf::Vector2f(x + 8.f, y - 2.5f));
                fin.setPoint(2, sf::Vector2f(x + 6.5f, y - 5.f));
            } else {
                // Specchiata
                fin.setPoint(0, sf::Vector2f(x - 5.f, y - 2.5f));
                fin.setPoint(1, sf::Vector2f(x - 8.f, y - 2.5f));
                fin.setPoint(2, sf::Vector2f(x - 6.5f, y - 5.f));
            }
            target.draw(fin);
        }
        // Mirino
        {
            sf::RectangleShape scope(sf::Vector2f(6.f, 2.f));
            scope.setFillColor(sf::Color(30, 30, 40));
            float gx = x - 3.f;
            if (!facingRight) gx = flipX(gx, 6.f);
            scope.setPosition(gx, y - 7.f);
            target.draw(scope);
        }
    }
    else if (type == WPN_LASER) {
        // Glow
        {
            sf::CircleShape glow(8.f);
            glow.setFillColor(sf::Color(80, 220, 255, 60));
            float gx = x - 8.f;
            if (!facingRight) gx = flipX(gx, 16.f);
            glow.setPosition(gx, y - 6.f);
            target.draw(glow);
        }
        // Corpo
        {
            sf::RectangleShape body(sf::Vector2f(16.f, 9.f));
            body.setFillColor(sf::Color(50, 55, 80));
            body.setOutlineThickness(0.5f); body.setOutlineColor(sf::Color(20, 20, 20));
            float gx = x - 5.f;
            if (!facingRight) gx = flipX(gx, 16.f);
            body.setPosition(gx, y - 4.f);
            target.draw(body);
        }
        // Strato superiore
        {
            sf::RectangleShape bodyTop(sf::Vector2f(16.f, 3.f));
            bodyTop.setFillColor(sf::Color(100, 110, 150));
            float gx = x - 5.f;
            if (!facingRight) gx = flipX(gx, 16.f);
            bodyTop.setPosition(gx, y - 4.f);
            target.draw(bodyTop);
        }
        // Nucleo luminoso
        {
            sf::CircleShape coreOut(4.f);
            coreOut.setFillColor(sf::Color(100, 200, 255, 220));
            float gx = x - 4.f;
            if (!facingRight) gx = flipX(gx, 8.f);
            coreOut.setPosition(gx, y - 4.f);
            target.draw(coreOut);
        }
        {
            sf::CircleShape coreMid(2.5f);
            coreMid.setFillColor(sf::Color(180, 240, 255, 240));
            float gx = x - 2.5f;
            if (!facingRight) gx = flipX(gx, 5.f);
            coreMid.setPosition(gx, y - 2.5f);
            target.draw(coreMid);
        }
        {
            sf::CircleShape coreIn(1.2f);
            coreIn.setFillColor(sf::Color(255, 255, 255, 250));
            float gx = x - 1.2f;
            if (!facingRight) gx = flipX(gx, 2.4f);
            coreIn.setPosition(gx, y - 1.2f);
            target.draw(coreIn);
        }
        // Canna emettitrice
        {
            sf::RectangleShape emitter(sf::Vector2f(7.f, 5.f));
            emitter.setFillColor(sf::Color(70, 80, 110));
            float gx = x + 8.f;
            if (!facingRight) gx = flipX(gx, 7.f);
            emitter.setPosition(gx, y - 3.f);
            target.draw(emitter);
        }
        // Anello luminoso
        {
            sf::CircleShape ring(2.f);
            ring.setFillColor(sf::Color(150, 255, 255, 220));
            float gx = x + 13.f;
            if (!facingRight) gx = flipX(gx, 4.f);
            ring.setPosition(gx, y - 2.f);
            target.draw(ring);
        }
    }
}
