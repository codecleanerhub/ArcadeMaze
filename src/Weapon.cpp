#include "Weapon.h"
#include "Utils.h"
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
    float cx = x + TILE_SIZE / 2.f;
    float cy = y + TILE_SIZE / 2.f;
    sf::Color outline(20, 20, 20, 255);

    // --- Ombra a terra morbida (cerchio grande sfumato) ---
    sf::CircleShape shadow(22.f);
    shadow.setFillColor(sf::Color(0, 0, 0, 130));
    shadow.setPosition(cx - 22.f, cy + 10.f);
    target.draw(shadow);

    // --- Aura colorata sottile (identifica l'arma a distanza) ---
    sf::Color auraCol;
    switch (type) {
        case WPN_PISTOL:  auraCol = sf::Color(220, 220, 220, 25); break;
        case WPN_SHOTGUN: auraCol = sf::Color(220, 130, 60, 30);  break;
        case WPN_ROCKET:  auraCol = sf::Color(220, 50, 50, 30);   break;
        case WPN_LASER:   auraCol = sf::Color(80, 220, 255, 50);  break;
    }
    sf::CircleShape aura(24.f);
    aura.setFillColor(auraCol);
    aura.setPosition(cx - 24.f, cy - 18.f);
    target.draw(aura);

    if (type == WPN_PISTOL) {
        // ============ PISTOLA dettagliata ============
        // Impugnatura in legno scuro scolpito (3 strati per dar volume)
        // Strato base (legno piu' scuro)
        sf::RectangleShape gripBase(sf::Vector2f(10.f, 18.f));
        gripBase.setFillColor(sf::Color(50, 25, 12));
        gripBase.setOutlineThickness(1.2f); gripBase.setOutlineColor(outline);
        gripBase.setPosition(cx - 7.f, cy + 1.f);
        target.draw(gripBase);
        // Strato mediano (legno piu' chiaro, effetto venatura)
        sf::RectangleShape gripMid(sf::Vector2f(8.f, 18.f));
        gripMid.setFillColor(sf::Color(85, 50, 25));
        gripMid.setPosition(cx - 6.f, cy + 1.f);
        target.draw(gripMid);
        // Venatura (linea verticale chiara)
        sf::RectangleShape gripVein(sf::Vector2f(1.f, 16.f));
        gripVein.setFillColor(sf::Color(140, 90, 50));
        gripVein.setPosition(cx - 3.f, cy + 2.f);
        target.draw(gripVein);
        // Rivetto in fondo all'impugnatura
        sf::CircleShape rivet(1.5f);
        rivet.setFillColor(sf::Color(200, 180, 100));
        rivet.setPosition(cx - 1.5f, cy + 15.f);
        target.draw(rivet);

        // Guardia del grilletto (arco metallico)
        sf::RectangleShape triggerGuard(sf::Vector2f(8.f, 5.f));
        triggerGuard.setFillColor(sf::Color(60, 60, 70));
        triggerGuard.setOutlineThickness(1.f); triggerGuard.setOutlineColor(outline);
        triggerGuard.setPosition(cx - 1.f, cy + 4.f);
        target.draw(triggerGuard);
        // Grilletto vero e proprio (piccolo triangolo)
        sf::ConvexShape trigger; trigger.setPointCount(3);
        trigger.setFillColor(sf::Color(80, 80, 90));
        trigger.setPoint(0, sf::Vector2f(cx + 1.f, cy + 5.f));
        trigger.setPoint(1, sf::Vector2f(cx + 4.f, cy + 5.f));
        trigger.setPoint(2, sf::Vector2f(cx + 2.f, cy + 8.f));
        target.draw(trigger);

        // Corpo metallico a strati (slide + frame)
        // Frame (strato scuro)
        sf::RectangleShape frame(sf::Vector2f(22.f, 13.f));
        frame.setFillColor(sf::Color(45, 45, 55));
        frame.setOutlineThickness(1.f); frame.setOutlineColor(outline);
        frame.setPosition(cx - 11.f, cy - 11.f);
        target.draw(frame);
        // Slide (strato superiore piu' chiaro, effetto riflettente)
        sf::RectangleShape slide(sf::Vector2f(22.f, 7.f));
        slide.setFillColor(sf::Color(95, 95, 105));
        slide.setOutlineThickness(0.8f); slide.setOutlineColor(outline);
        slide.setPosition(cx - 11.f, cy - 11.f);
        target.draw(slide);
        // Riflesso cromatico (striscia chiara in alto)
        sf::RectangleShape reflection1(sf::Vector2f(18.f, 1.5f));
        reflection1.setFillColor(sf::Color(200, 200, 220));
        reflection1.setPosition(cx - 9.f, cy - 10.f);
        target.draw(reflection1);
        // Marrone / dorato per la finitura (piccolo inserto)
        sf::RectangleShape insert(sf::Vector2f(3.f, 4.f));
        insert.setFillColor(sf::Color(180, 140, 60));
        insert.setPosition(cx - 8.f, cy - 9.f);
        target.draw(insert);

        // Canna (cilindro metallico)
        sf::RectangleShape barrel(sf::Vector2f(14.f, 7.f));
        barrel.setFillColor(sf::Color(75, 75, 85));
        barrel.setOutlineThickness(1.f); barrel.setOutlineColor(outline);
        barrel.setPosition(cx + 8.f, cy - 7.f);
        target.draw(barrel);
        // Bocca della canna (cerchio nero)
        sf::CircleShape muzzle(2.5f);
        muzzle.setFillColor(sf::Color(15, 15, 15));
        muzzle.setOutlineThickness(0.8f); muzzle.setOutlineColor(sf::Color(60, 60, 60));
        muzzle.setPosition(cx + 19.f, cy - 5.f);
        target.draw(muzzle);
        // Mirino sopra la canna (piccolo cilindro verticale)
        sf::RectangleShape sight(sf::Vector2f(1.5f, 3.f));
        sight.setFillColor(sf::Color(40, 40, 40));
        sight.setPosition(cx + 14.f, cy - 10.f);
        target.draw(sight);
    }
    else if (type == WPN_SHOTGUN) {
        // ============ FUCILE a pompa dettagliato ============
        // Calciatura in legno scolpito (3 strati per volume)
        // Strato base
        sf::RectangleShape stockBase(sf::Vector2f(20.f, 16.f));
        stockBase.setFillColor(sf::Color(70, 40, 18));
        stockBase.setOutlineThickness(1.2f); stockBase.setOutlineColor(outline);
        stockBase.setPosition(cx - 14.f, cy + 3.f);
        target.draw(stockBase);
        // Strato superiore piu' chiaro
        sf::RectangleShape stockTop(sf::Vector2f(20.f, 8.f));
        stockTop.setFillColor(sf::Color(130, 80, 35));
        stockTop.setOutlineThickness(0.8f); stockTop.setOutlineColor(outline);
        stockTop.setPosition(cx - 14.f, cy + 3.f);
        target.draw(stockTop);
        // Venatura del legno (3 linee sottili)
        for (int i = 0; i < 3; i++) {
            sf::RectangleShape vein(sf::Vector2f(18.f, 0.8f));
            vein.setFillColor(sf::Color(160, 110, 60));
            vein.setPosition(cx - 13.f, cy + 5.f + i * 3.f);
            target.draw(vein);
        }
        // Ghiera metallica tra calciatura e corpo
        sf::RectangleShape collar(sf::Vector2f(3.f, 16.f));
        collar.setFillColor(sf::Color(180, 180, 180));
        collar.setOutlineThickness(0.8f); collar.setOutlineColor(outline);
        collar.setPosition(cx + 5.f, cy + 3.f);
        target.draw(collar);

        // Corpo metallico che collega alla canna
        sf::RectangleShape receiver(sf::Vector2f(14.f, 12.f));
        receiver.setFillColor(sf::Color(70, 70, 78));
        receiver.setOutlineThickness(1.f); receiver.setOutlineColor(outline);
        receiver.setPosition(cx - 5.f, cy - 4.f);
        target.draw(receiver);
        // Levetta di caricamento (piccola protuberanza)
        sf::RectangleShape lever(sf::Vector2f(4.f, 3.f));
        lever.setFillColor(sf::Color(100, 100, 110));
        lever.setOutlineThickness(0.5f); lever.setOutlineColor(outline);
        lever.setPosition(cx + 2.f, cy + 8.f);
        target.draw(lever);

        // Doppia canna (2 cilindri sovrapposti)
        // Canna superiore
        sf::RectangleShape barrelTop(sf::Vector2f(28.f, 6.f));
        barrelTop.setFillColor(sf::Color(55, 55, 60));
        barrelTop.setOutlineThickness(1.f); barrelTop.setOutlineColor(outline);
        barrelTop.setPosition(cx - 10.f, cy - 12.f);
        target.draw(barrelTop);
        // Riflesso superiore (striscia chiara)
        sf::RectangleShape barrelRef1(sf::Vector2f(26.f, 1.2f));
        barrelRef1.setFillColor(sf::Color(180, 180, 190));
        barrelRef1.setPosition(cx - 9.f, cy - 11.f);
        target.draw(barrelRef1);
        // Canna inferiore
        sf::RectangleShape barrelBot(sf::Vector2f(28.f, 5.f));
        barrelBot.setFillColor(sf::Color(50, 50, 55));
        barrelBot.setOutlineThickness(1.f); barrelBot.setOutlineColor(outline);
        barrelBot.setPosition(cx - 10.f, cy - 6.f);
        target.draw(barrelBot);
        // Ghiera all'estremita' della canna (anello)
        sf::RectangleShape muzzleBand(sf::Vector2f(3.f, 12.f));
        muzzleBand.setFillColor(sf::Color(180, 180, 180));
        muzzleBand.setOutlineThickness(0.8f); muzzleBand.setOutlineColor(outline);
        muzzleBand.setPosition(cx + 14.f, cy - 12.f);
        target.draw(muzzleBand);
        // Doppia bocca (due cerchi neri)
        sf::CircleShape muzzle1(1.5f);
        muzzle1.setFillColor(sf::Color(10, 10, 10));
        muzzle1.setPosition(cx + 17.f, cy - 11.f);
        target.draw(muzzle1);
        muzzle1.setPosition(cx + 17.f, cy - 5.f);
        target.draw(muzzle1);

        // Pompa scanalata (sotto la canna)
        sf::RectangleShape pump(sf::Vector2f(12.f, 6.f));
        pump.setFillColor(sf::Color(140, 90, 45));
        pump.setOutlineThickness(1.f); pump.setOutlineColor(outline);
        pump.setPosition(cx - 6.f, cy + 2.f);
        target.draw(pump);
        // Scanalature della pompa (3 linee verticali)
        for (int i = 0; i < 3; i++) {
            sf::RectangleShape groove(sf::Vector2f(0.8f, 5.f));
            groove.setFillColor(sf::Color(60, 35, 15));
            groove.setPosition(cx - 4.f + i * 3.5f, cy + 2.5f);
            target.draw(groove);
        }
        // Grilletto (triangolo metallico)
        sf::ConvexShape trigger; trigger.setPointCount(3);
        trigger.setFillColor(sf::Color(80, 80, 90));
        trigger.setPoint(0, sf::Vector2f(cx - 3.f, cy + 8.f));
        trigger.setPoint(1, sf::Vector2f(cx + 1.f, cy + 8.f));
        trigger.setPoint(2, sf::Vector2f(cx - 1.f, cy + 12.f));
        target.draw(trigger);
    }
    else if (type == WPN_ROCKET) {
        // ============ LANCIARAZZI dettagliato ============
        // Tubo lanciarazzi (corpo cilindrico con bande)
        sf::RectangleShape tube(sf::Vector2f(28.f, 14.f));
        tube.setFillColor(sf::Color(60, 90, 50));
        tube.setOutlineThickness(1.2f); tube.setOutlineColor(outline);
        tube.setPosition(cx - 14.f, cy - 7.f);
        target.draw(tube);
        // Strato superiore ( riflesso piu' chiaro)
        sf::RectangleShape tubeTop(sf::Vector2f(28.f, 4.f));
        tubeTop.setFillColor(sf::Color(100, 140, 80));
        tubeTop.setPosition(cx - 14.f, cy - 7.f);
        target.draw(tubeTop);
        // 2 bande metalliche di rinforzo
        for (int i = 0; i < 2; i++) {
            sf::RectangleShape band(sf::Vector2f(2.5f, 14.f));
            band.setFillColor(sf::Color(180, 180, 180));
            band.setOutlineThickness(0.8f); band.setOutlineColor(outline);
            band.setPosition(cx - 8.f + i * 12.f, cy - 7.f);
            target.draw(band);
        }
        // Avvertimento "DANGER" - piccola striscia giallo/nera
        for (int i = 0; i < 4; i++) {
            sf::RectangleShape stripe(sf::Vector2f(2.f, 14.f));
            stripe.setFillColor((i % 2 == 0) ? sf::Color(255, 200, 0) : sf::Color(20, 20, 20));
            stripe.setPosition(cx - 2.f + i * 2.f, cy - 7.f);
            target.draw(stripe);
        }
        // Ugello di scarico posteriore (cono tronco)
        sf::ConvexShape nozzle; nozzle.setPointCount(4);
        nozzle.setFillColor(sf::Color(40, 40, 50));
        nozzle.setOutlineThickness(1.f); nozzle.setOutlineColor(outline);
        nozzle.setPoint(0, sf::Vector2f(cx - 14.f, cy - 7.f));
        nozzle.setPoint(1, sf::Vector2f(cx - 14.f, cy + 7.f));
        nozzle.setPoint(2, sf::Vector2f(cx - 22.f, cy + 5.f));
        nozzle.setPoint(3, sf::Vector2f(cx - 22.f, cy - 5.f));
        target.draw(nozzle);
        // Bordo anteriore dell'ugello (anello metallico)
        sf::RectangleShape nozzleRing(sf::Vector2f(2.f, 14.f));
        nozzleRing.setFillColor(sf::Color(150, 150, 160));
        nozzleRing.setPosition(cx - 14.f, cy - 7.f);
        target.draw(nozzleRing);

        // Razzo in vista (sporge dalla parte anteriore)
        // Corpo del razzo
        sf::RectangleShape rocketBody(sf::Vector2f(12.f, 8.f));
        rocketBody.setFillColor(sf::Color(180, 50, 50));
        rocketBody.setOutlineThickness(0.8f); rocketBody.setOutlineColor(outline);
        rocketBody.setPosition(cx + 8.f, cy - 4.f);
        target.draw(rocketBody);
        // Riflesso superiore del razzo
        sf::RectangleShape rocketRef(sf::Vector2f(12.f, 1.5f));
        rocketRef.setFillColor(sf::Color(240, 180, 180));
        rocketRef.setPosition(cx + 8.f, cy - 4.f);
        target.draw(rocketRef);
        // Punta conica del razzo
        sf::ConvexShape rocketTip; rocketTip.setPointCount(3);
        rocketTip.setFillColor(sf::Color(220, 80, 80));
        rocketTip.setOutlineThickness(0.8f); rocketTip.setOutlineColor(outline);
        rocketTip.setPoint(0, sf::Vector2f(cx + 20.f, cy - 4.f));
        rocketTip.setPoint(1, sf::Vector2f(cx + 20.f, cy + 4.f));
        rocketTip.setPoint(2, sf::Vector2f(cx + 26.f, cy));
        target.draw(rocketTip);
        // 3 alette stabilizzatrici di coda (1 sopra, 2 laterali)
        sf::ConvexShape finTop; finTop.setPointCount(3);
        finTop.setFillColor(sf::Color(140, 30, 30));
        finTop.setOutlineThickness(0.5f); finTop.setOutlineColor(outline);
        finTop.setPoint(0, sf::Vector2f(cx + 8.f, cy - 4.f));
        finTop.setPoint(1, sf::Vector2f(cx + 12.f, cy - 4.f));
        finTop.setPoint(2, sf::Vector2f(cx + 10.f, cy - 9.f));
        target.draw(finTop);
        sf::ConvexShape finBot; finBot.setPointCount(3);
        finBot.setFillColor(sf::Color(140, 30, 30));
        finBot.setOutlineThickness(0.5f); finBot.setOutlineColor(outline);
        finBot.setPoint(0, sf::Vector2f(cx + 8.f, cy + 4.f));
        finBot.setPoint(1, sf::Vector2f(cx + 12.f, cy + 4.f));
        finBot.setPoint(2, sf::Vector2f(cx + 10.f, cy + 9.f));
        target.draw(finBot);
        // Miccia/conduttore elettrico (filo dorato)
        sf::RectangleShape wire(sf::Vector2f(6.f, 1.f));
        wire.setFillColor(sf::Color(255, 200, 60));
        wire.setPosition(cx + 4.f, cy + 1.f);
        target.draw(wire);

        // Mirino telescopico sopra il tubo
        sf::RectangleShape scope(sf::Vector2f(8.f, 3.f));
        scope.setFillColor(sf::Color(30, 30, 40));
        scope.setOutlineThickness(0.8f); scope.setOutlineColor(outline);
        scope.setPosition(cx - 4.f, cy - 11.f);
        target.draw(scope);
        // Lente del mirino (piccolo cerchio azzurro)
        sf::CircleShape lens(1.5f);
        lens.setFillColor(sf::Color(80, 180, 220));
        lens.setPosition(cx - 4.f, cy - 10.f);
        target.draw(lens);

        // Impugnatura anatomica (sotto il tubo)
        sf::ConvexShape grip; grip.setPointCount(4);
        grip.setFillColor(sf::Color(40, 40, 50));
        grip.setOutlineThickness(1.f); grip.setOutlineColor(outline);
        grip.setPoint(0, sf::Vector2f(cx - 2.f, cy + 7.f));
        grip.setPoint(1, sf::Vector2f(cx + 4.f, cy + 7.f));
        grip.setPoint(2, sf::Vector2f(cx + 6.f, cy + 15.f));
        grip.setPoint(3, sf::Vector2f(cx - 4.f, cy + 15.f));
        target.draw(grip);
        // Grilletto
        sf::ConvexShape trigger; trigger.setPointCount(3);
        trigger.setFillColor(sf::Color(80, 80, 90));
        trigger.setPoint(0, sf::Vector2f(cx - 1.f, cy + 8.f));
        trigger.setPoint(1, sf::Vector2f(cx + 2.f, cy + 8.f));
        trigger.setPoint(2, sf::Vector2f(cx + 0.5f, cy + 11.f));
        target.draw(trigger);
    }
    else if (type == WPN_LASER) {
        // ============ LASER dettagliato ============
        // Glow pulsante attorno al nucleo (effetto energia)
        sf::CircleShape outerGlow(20.f);
        outerGlow.setFillColor(sf::Color(80, 200, 255, 35));
        outerGlow.setPosition(cx - 20.f, cy - 18.f);
        target.draw(outerGlow);
        sf::CircleShape innerGlow(15.f);
        innerGlow.setFillColor(sf::Color(120, 230, 255, 50));
        innerGlow.setPosition(cx - 15.f, cy - 13.f);
        target.draw(innerGlow);

        // Impugnatura anatomica scura (3 strati per volume)
        sf::ConvexShape gripBase; gripBase.setPointCount(4);
        gripBase.setFillColor(sf::Color(20, 20, 35));
        gripBase.setOutlineThickness(1.2f); gripBase.setOutlineColor(outline);
        gripBase.setPoint(0, sf::Vector2f(cx - 6.f, cy + 4.f));
        gripBase.setPoint(1, sf::Vector2f(cx + 4.f, cy + 4.f));
        gripBase.setPoint(2, sf::Vector2f(cx + 6.f, cy + 16.f));
        gripBase.setPoint(3, sf::Vector2f(cx - 8.f, cy + 16.f));
        target.draw(gripBase);
        // Strato mediano (leggermente piu' chiaro)
        sf::ConvexShape gripMid; gripMid.setPointCount(4);
        gripMid.setFillColor(sf::Color(35, 35, 55));
        gripMid.setPoint(0, sf::Vector2f(cx - 5.f, cy + 5.f));
        gripMid.setPoint(1, sf::Vector2f(cx + 3.f, cy + 5.f));
        gripMid.setPoint(2, sf::Vector2f(cx + 5.f, cy + 15.f));
        gripMid.setPoint(3, sf::Vector2f(cx - 7.f, cy + 15.f));
        target.draw(gripMid);
        // Inserto dorsale (gomma antiscivolo)
        sf::RectangleShape gripInsert(sf::Vector2f(2.f, 9.f));
        gripInsert.setFillColor(sf::Color(15, 15, 25));
        gripInsert.setPosition(cx - 1.f, cy + 6.f);
        target.draw(gripInsert);
        // Grilletto (piccolo triangolo bluastro)
        sf::ConvexShape trigger; trigger.setPointCount(3);
        trigger.setFillColor(sf::Color(60, 80, 120));
        trigger.setPoint(0, sf::Vector2f(cx + 3.f, cy + 5.f));
        trigger.setPoint(1, sf::Vector2f(cx + 6.f, cy + 5.f));
        trigger.setPoint(2, sf::Vector2f(cx + 4.f, cy + 9.f));
        target.draw(trigger);

        // Corpo principale (arma a energia)
        // Strato base scuro
        sf::RectangleShape bodyBase(sf::Vector2f(26.f, 14.f));
        bodyBase.setFillColor(sf::Color(50, 55, 80));
        bodyBase.setOutlineThickness(1.2f); bodyBase.setOutlineColor(outline);
        bodyBase.setPosition(cx - 13.f, cy - 11.f);
        target.draw(bodyBase);
        // Strato superiore metallico (riflettente)
        sf::RectangleShape bodyTop(sf::Vector2f(26.f, 5.f));
        bodyTop.setFillColor(sf::Color(100, 110, 150));
        bodyTop.setPosition(cx - 13.f, cy - 11.f);
        target.draw(bodyTop);
        // Riflesso cromatico
        sf::RectangleShape bodyRef(sf::Vector2f(22.f, 1.5f));
        bodyRef.setFillColor(sf::Color(200, 220, 255));
        bodyRef.setPosition(cx - 11.f, cy - 10.f);
        target.draw(bodyRef);
        // Pannello laterale con viti (effetto industriale)
        sf::RectangleShape panel(sf::Vector2f(8.f, 8.f));
        panel.setFillColor(sf::Color(40, 45, 70));
        panel.setOutlineThickness(0.8f); panel.setOutlineColor(outline);
        panel.setPosition(cx - 10.f, cy - 7.f);
        target.draw(panel);
        // 2 viti sul pannello
        for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
            sf::CircleShape screw(0.8f);
            screw.setFillColor(sf::Color(180, 180, 200));
            screw.setPosition(cx - 9.f + i * 5.f, cy - 6.f + j * 4.f);
            target.draw(screw);
        }

        // Cella energetica (sopra il corpo, cilindro verde-blu)
        sf::RectangleShape cell(sf::Vector2f(8.f, 4.f));
        cell.setFillColor(sf::Color(80, 220, 200));
        cell.setOutlineThickness(0.8f); cell.setOutlineColor(outline);
        cell.setPosition(cx - 4.f, cy - 14.f);
        target.draw(cell);
        // Emissione della cella (striscia luminosa)
        sf::RectangleShape cellGlow(sf::Vector2f(6.f, 1.5f));
        cellGlow.setFillColor(sf::Color(180, 255, 240));
        cellGlow.setPosition(cx - 3.f, cy - 13.5f);
        target.draw(cellGlow);

        // Nucleo dell'arma (cuore luminoso pulsante)
        // Strato esterno (azzurro)
        sf::CircleShape coreOuter(7.f);
        coreOuter.setFillColor(sf::Color(100, 200, 255, 220));
        coreOuter.setOutlineThickness(1.f); coreOuter.setOutlineColor(sf::Color(50, 100, 180));
        coreOuter.setPosition(cx - 7.f, cy - 7.f);
        target.draw(coreOuter);
        // Strato medio (ciano chiaro)
        sf::CircleShape coreMid(5.f);
        coreMid.setFillColor(sf::Color(180, 240, 255, 240));
        coreMid.setPosition(cx - 5.f, cy - 5.f);
        target.draw(coreMid);
        // Strato interno (bianco quasi puro)
        sf::CircleShape coreInner(2.5f);
        coreInner.setFillColor(sf::Color(255, 255, 255, 250));
        coreInner.setPosition(cx - 2.5f, cy - 2.5f);
        target.draw(coreInner);

        // Canna emettitrice (davanti al corpo)
        sf::RectangleShape emitter(sf::Vector2f(10.f, 6.f));
        emitter.setFillColor(sf::Color(70, 80, 110));
        emitter.setOutlineThickness(1.f); emitter.setOutlineColor(outline);
        emitter.setPosition(cx + 12.f, cy - 5.f);
        target.draw(emitter);
        // Anello luminoso all'estremita' della canna (dove esce il laser)
        sf::CircleShape emitterRing(2.5f);
        emitterRing.setFillColor(sf::Color(150, 255, 255, 200));
        emitterRing.setOutlineThickness(0.8f); emitterRing.setOutlineColor(sf::Color(50, 150, 200));
        emitterRing.setPosition(cx + 19.f, cy - 2.5f);
        target.draw(emitterRing);
        // Fulmine a energia davanti alla canna (piccolo sprazzo)
        sf::CircleShape spark(1.5f);
        spark.setFillColor(sf::Color(255, 255, 255, 220));
        spark.setPosition(cx + 22.f, cy - 0.5f);
        target.draw(spark);
    }
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
