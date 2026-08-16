#include "Weapon.h"
#include <cstdlib>
#include "Utils.h"

// ===========================================================================
// Weapon.cpp - Implementazione di armi e proiettili.
//
// Tutti i disegni delle armi sono costruiti con primitive SFML (rettangoli,
// cerchi, poligoni) senza usare texture esterne: in questo modo il gioco e'
// completamente autonomo e l'estetica resta coerente col look "arcade".
// ===========================================================================

// Factory: sceglie una delle 4 armi in modo casuale.
// Il cast da int (0..3) a WeaponType e' sicuro perche' l'enum ha esattamente
// 4 valori consecutivi a partire da 0.
Weapon Weapon::generateRandom() { return generate(static_cast<WeaponType>(rand() % 4)); }

// Factory: crea un'arma del tipo richiesto con statistiche bilanciate.
// Le munizioni e il potere sono scelti in modo che armi piu' forti abbiano
// meno colpi (compromesso gameplay: il razzo fa molto danno ma ha 3 colpi).
Weapon Weapon::generate(WeaponType t) {
    Weapon w; w.type = t;
    if (t == WPN_PISTOL)      { w.power = 1; w.ammo = 15; }
    else if (t == WPN_SHOTGUN){ w.power = 2; w.ammo = 8;  }
    else if (t == WPN_ROCKET) { w.power = 4; w.ammo = 3;  }
    else if (t == WPN_LASER)  { w.power = 3; w.ammo = 10; }
    return w;
}

// Restituisce il nome testuale usato nell'UI in alto (etichetta "WPN").
std::string Weapon::getName() const {
    switch(type) {
        case WPN_PISTOL:  return "PISTOL";
        case WPN_SHOTGUN: return "SHOTGUN";
        case WPN_ROCKET:  return "ROCKET";
        case WPN_LASER:   return "LASER";
    }
    return "";
}

// Colore associato all'arma (usato per il testo del nome nell'UI).
sf::Color Weapon::getColor() const {
    switch(type) {
        case WPN_PISTOL:  return sf::Color(200, 200, 200);
        case WPN_SHOTGUN: return sf::Color(200, 100, 50);
        case WPN_ROCKET:  return sf::Color(100, 200, 50);
        case WPN_LASER:   return sf::Color(50, 200, 255);
    }
    return sf::Color::White;
}

// ---------------------------------------------------------------------------
// render: disegna l'arma appoggiata a terra, versione dettagliata.
//
// Le coordinate (x, y) passate sono l'angolo in alto a sinistra del tile; il
// disegno e' centrato sul tile (cx, cy). Ogni arma ha un suo layout proprio
// ricco di dettagli (riflessi, gradienti, ornamenti) per dare un look piu'
// "curato" e fantasy:
//
//   * PISTOL:  impugnatura antropomorfa con texture legno + grilletto +
//              guardia metallica + corpo a strati + canna con bocca +
//              mirino + riflesso cromatico
//   * SHOTGUN: calciatura in legno scolpito + doppia canna con ghiera +
//              pompa scanalata + grilletto + levetta di caricamento
//   * ROCKET:  corpo verde militare con bande + testa rossa conica con
//              riflessi + 3 alette stabilizzatrici + ugello di scarico +
//              miccia a vista
//   * LASER:   nucleo di energia pulsante + impugnatura anatomica + corpo
//              metallico con venature + cella energetica + canna emettitrice
//
// Tutte le armi hanno:
//   * Ombra a terra morbida (cerchio sfumato)
//   * Aura sottile colorata (per identificarle a distanza)
//   * Outline scuro per definizione
// ---------------------------------------------------------------------------
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
// renderEquipped: versione ridotta del disegno, usata per mostrare l'arma
// in mano al giocatore. Le proporzioni sono piu' piccole e manca l'ombra
// (non serve: l'arma si muove col personaggio).
// Le coordinate (x, y) sono gia' la posizione in pixel del personaggio.
// Pur essendo piu' piccola, mantiene i dettagli chiave (riflessi, nucleo,
// inserti colorati) per riconoscibilita'.
// ---------------------------------------------------------------------------
void Weapon::renderEquipped(sf::RenderTarget& target, float x, float y) const {
    if (type == WPN_PISTOL) {
        // Impugnatura in legno (2 strati)
        sf::RectangleShape gripBase(sf::Vector2f(6.f, 11.f));
        gripBase.setFillColor(sf::Color(50, 25, 12));
        gripBase.setPosition(x - 3.f, y + 1.f);
        target.draw(gripBase);
        sf::RectangleShape gripMid(sf::Vector2f(5.f, 11.f));
        gripMid.setFillColor(sf::Color(85, 50, 25));
        gripMid.setPosition(x - 2.5f, y + 1.f);
        target.draw(gripMid);
        // Corpo metallico
        sf::RectangleShape body(sf::Vector2f(13.f, 9.f));
        body.setFillColor(sf::Color(70, 70, 80));
        body.setOutlineThickness(0.5f); body.setOutlineColor(sf::Color(20, 20, 20));
        body.setPosition(x - 4.f, y - 7.f);
        target.draw(body);
        // Slide superiore (riflesso)
        sf::RectangleShape slide(sf::Vector2f(13.f, 3.f));
        slide.setFillColor(sf::Color(120, 120, 130));
        slide.setPosition(x - 4.f, y - 7.f);
        target.draw(slide);
        // Inserto dorato
        sf::RectangleShape insert(sf::Vector2f(2.f, 3.f));
        insert.setFillColor(sf::Color(180, 140, 60));
        insert.setPosition(x - 3.f, y - 6.f);
        target.draw(insert);
        // Canna
        sf::RectangleShape barrel(sf::Vector2f(8.f, 5.f));
        barrel.setFillColor(sf::Color(85, 85, 95));
        barrel.setPosition(x + 8.f, y - 5.f);
        target.draw(barrel);
        // Bocca
        sf::CircleShape muzzle(1.5f);
        muzzle.setFillColor(sf::Color(15, 15, 15));
        muzzle.setPosition(x + 14.5f, y - 3.5f);
        target.draw(muzzle);
    }
    else if (type == WPN_SHOTGUN) {
        // Calciatura in legno (2 strati)
        sf::RectangleShape stockBase(sf::Vector2f(14.f, 10.f));
        stockBase.setFillColor(sf::Color(70, 40, 18));
        stockBase.setPosition(x - 7.f, y + 3.f);
        target.draw(stockBase);
        sf::RectangleShape stockTop(sf::Vector2f(14.f, 5.f));
        stockTop.setFillColor(sf::Color(130, 80, 35));
        stockTop.setPosition(x - 7.f, y + 3.f);
        target.draw(stockTop);
        // Doppia canna
        sf::RectangleShape barrelTop(sf::Vector2f(20.f, 4.f));
        barrelTop.setFillColor(sf::Color(55, 55, 60));
        barrelTop.setOutlineThickness(0.5f); barrelTop.setOutlineColor(sf::Color(20, 20, 20));
        barrelTop.setPosition(x - 6.f, y - 6.f);
        target.draw(barrelTop);
        sf::RectangleShape barrelBot(sf::Vector2f(20.f, 4.f));
        barrelBot.setFillColor(sf::Color(50, 50, 55));
        barrelBot.setOutlineThickness(0.5f); barrelBot.setOutlineColor(sf::Color(20, 20, 20));
        barrelBot.setPosition(x - 6.f, y - 1.f);
        target.draw(barrelBot);
        // Riflesso canna
        sf::RectangleShape barrelRef(sf::Vector2f(18.f, 1.f));
        barrelRef.setFillColor(sf::Color(180, 180, 190));
        barrelRef.setPosition(x - 5.f, y - 5.5f);
        target.draw(barrelRef);
        // Pompa
        sf::RectangleShape pump(sf::Vector2f(8.f, 5.f));
        pump.setFillColor(sf::Color(140, 90, 45));
        pump.setOutlineThickness(0.5f); pump.setOutlineColor(sf::Color(20, 20, 20));
        pump.setPosition(x + 1.f, y + 4.f);
        target.draw(pump);
        // Scanalatura
        sf::RectangleShape groove(sf::Vector2f(0.8f, 4.f));
        groove.setFillColor(sf::Color(60, 35, 15));
        groove.setPosition(x + 4.f, y + 4.5f);
        target.draw(groove);
    }
    else if (type == WPN_ROCKET) {
        // Tubo lanciarazzi
        sf::RectangleShape tube(sf::Vector2f(18.f, 9.f));
        tube.setFillColor(sf::Color(60, 90, 50));
        tube.setOutlineThickness(0.8f); tube.setOutlineColor(sf::Color(20, 20, 20));
        tube.setPosition(x - 9.f, y - 4.f);
        target.draw(tube);
        // Strato superiore (riflesso)
        sf::RectangleShape tubeTop(sf::Vector2f(18.f, 3.f));
        tubeTop.setFillColor(sf::Color(100, 140, 80));
        tubeTop.setPosition(x - 9.f, y - 4.f);
        target.draw(tubeTop);
        // Banda metallica
        sf::RectangleShape band(sf::Vector2f(1.5f, 9.f));
        band.setFillColor(sf::Color(180, 180, 180));
        band.setPosition(x - 2.f, y - 4.f);
        target.draw(band);
        // Razzo
        sf::RectangleShape rocketBody(sf::Vector2f(8.f, 5.f));
        rocketBody.setFillColor(sf::Color(180, 50, 50));
        rocketBody.setOutlineThickness(0.5f); rocketBody.setOutlineColor(sf::Color(20, 20, 20));
        rocketBody.setPosition(x + 5.f, y - 2.5f);
        target.draw(rocketBody);
        // Punta conica
        sf::ConvexShape tip; tip.setPointCount(3);
        tip.setFillColor(sf::Color(220, 80, 80));
        tip.setPoint(0, sf::Vector2f(x + 13.f, y - 2.5f));
        tip.setPoint(1, sf::Vector2f(x + 13.f, y + 2.5f));
        tip.setPoint(2, sf::Vector2f(x + 17.f, y));
        target.draw(tip);
        // Aletta
        sf::ConvexShape fin; fin.setPointCount(3);
        fin.setFillColor(sf::Color(140, 30, 30));
        fin.setPoint(0, sf::Vector2f(x + 5.f, y - 2.5f));
        fin.setPoint(1, sf::Vector2f(x + 8.f, y - 2.5f));
        fin.setPoint(2, sf::Vector2f(x + 6.5f, y - 5.f));
        target.draw(fin);
        // Mirino
        sf::RectangleShape scope(sf::Vector2f(6.f, 2.f));
        scope.setFillColor(sf::Color(30, 30, 40));
        scope.setPosition(x - 3.f, y - 7.f);
        target.draw(scope);
    }
    else if (type == WPN_LASER) {
        // Glow pulsante
        sf::CircleShape glow(8.f);
        glow.setFillColor(sf::Color(80, 220, 255, 60));
        glow.setPosition(x - 8.f, y - 6.f);
        target.draw(glow);
        // Corpo
        sf::RectangleShape body(sf::Vector2f(16.f, 9.f));
        body.setFillColor(sf::Color(50, 55, 80));
        body.setOutlineThickness(0.5f); body.setOutlineColor(sf::Color(20, 20, 20));
        body.setPosition(x - 5.f, y - 4.f);
        target.draw(body);
        // Strato superiore
        sf::RectangleShape bodyTop(sf::Vector2f(16.f, 3.f));
        bodyTop.setFillColor(sf::Color(100, 110, 150));
        bodyTop.setPosition(x - 5.f, y - 4.f);
        target.draw(bodyTop);
        // Nucleo luminoso (3 strati)
        sf::CircleShape coreOut(4.f);
        coreOut.setFillColor(sf::Color(100, 200, 255, 220));
        coreOut.setPosition(x - 4.f, y - 4.f);
        target.draw(coreOut);
        sf::CircleShape coreMid(2.5f);
        coreMid.setFillColor(sf::Color(180, 240, 255, 240));
        coreMid.setPosition(x - 2.5f, y - 2.5f);
        target.draw(coreMid);
        sf::CircleShape coreIn(1.2f);
        coreIn.setFillColor(sf::Color(255, 255, 255, 250));
        coreIn.setPosition(x - 1.2f, y - 1.2f);
        target.draw(coreIn);
        // Canna emettitrice
        sf::RectangleShape emitter(sf::Vector2f(7.f, 5.f));
        emitter.setFillColor(sf::Color(70, 80, 110));
        emitter.setPosition(x + 8.f, y - 3.f);
        target.draw(emitter);
        // Anello luminoso
        sf::CircleShape ring(2.f);
        ring.setFillColor(sf::Color(150, 255, 255, 220));
        ring.setPosition(x + 13.f, y - 2.f);
        target.draw(ring);
    }
}
