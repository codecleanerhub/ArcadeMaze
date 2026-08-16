#ifndef WEAPON_H
#define WEAPON_H

// ===========================================================================
// Weapon.h - Definizione di armi e proiettili.
//
// Il gioco ha 4 tipi di arma (pistola, fucile a pompa, razzo, laser) con
// poteri e munizioni diversi. Le stesse struct `Weapon` e `Projectile` sono
// riusate sia dal giocatore sia dai nemici/boss: in `Projectile` il campo
// `type` identifica l'aspetto visivo del proiettile (cerchio, raggio, ecc.).
// ===========================================================================

#include <SFML/Graphics.hpp>
#include <string>

// Tipo di arma. L'ordine e' significativo: e' usato come indice nei switch
// di rendering e audio. NON modificare l'ordine senza aggiornare tutti gli
// switch associati.
enum WeaponType { WPN_PISTOL, WPN_SHOTGUN, WPN_ROCKET, WPN_LASER };

// Tipo di proiettile sparato dal boss. Ogni tipo ha un aspetto visivo
// (forma/colore) e un comportamento diversi. Il rendering specifico e'
// in Game.cpp; il comportamento (homing, sinusoidale, ecc.) e' gestito
// in Game::update() per i boss e usa i campi aggiuntivi di Projectile
// (homingTimer, age, ecc.).
enum BossProjKind {
    BP_NORMAL,         // proiettile generico (fallback)
    BP_BOULDER,        // GOLEM: masso pesante lento
    BP_NECRO_BOLT,     // LICH: saetta necrotica verde
    BP_FIREBALL,       // DEMON: palla di fuoco arancione
    BP_WEBSHOT,        // SPIDER: piccola ragnatela appiccicosa
    BP_FLESH_CHUNK,    // ABOMINATION: brandello di carne
    BP_INK_SPRAY,      // KRAKEN: getto d'inchiostro
    BP_DRAGON_BREATH,  // DRAGON: piccolo soffio di fuoco
    BP_GHOST_BOLT,     // WRAITH_LORD: saetta spettrale ciano
    BP_BLOOD_BOLT,     // VAMPIRE: dardo di sangue rosso scuro
    BP_EYE_RAY,        // BEHOLDER: raggio energetico colorato
    BP_GHOUL_CLAW,     // GHOUL_LORD: artiglio osseo
    BP_SPECTRAL_FANG,  // SPECTRAL_ALPHA: zanna spettrale
    BP_CULT_ORB,       // CULT_HERALD: sfera magica viola
    BP_MIMIC_GOO,      // COLOSSAL_MIMIC: bava appiccicosa
    BP_RAT_SWARM,      // RAT_KING: piccolo ratto proiettile
    BP_WITCH_HEX,      // SUPREME_WITCH: maledizione viola homing
    BP_TWILIGHT_BLADE  // TWILIGHT_KNIGHT: lama d'ombra
};

// Proiettile generico. Rappresenta uno "shot" in volo, sia del giocatore
// sia di nemici/boss. Lo stato `active=false` lo marca per la rimozione.
struct Projectile {
    sf::Vector2f pos;       // posizione corrente in pixel
    sf::Vector2f dir;       // vettore di spostamento per frame (già scalato)
    int power;              // danno inflitto quando colpisce il bersaglio
    bool active;            // false = da rimuovere (fuori schermo o impattato)
    WeaponType type;        // usato per il rendering (forma/colore del colpo)

    // --- Campi per i proiettili dei boss (ignorati dai proiettili player) ---
    BossProjKind bpKind = BP_NORMAL;  // tipo di proiettile boss (rendering + comportamento)
    int homingTimer = 0;              // >0 = proiettile homing che insegue il player (ms residui)
    uint32_t age = 0;                 // eta' del proiettile in ms (per comportamenti temporali)
    uint8_t variant = 0;              // variante visiva (0..n) per pattern come eye-ray colori
};

// Struct arma: non e' una classe polimorfica, ma un semplice contenitore.
// Le factory statiche `generateRandom()` e `generate(t)` restituiscono
// armi gia' configurate con potenza/munizioni bilanciate.
struct Weapon {
    WeaponType type;
    int power;      // danno per colpo
    int ammo;       // colpi residui (0 = arma scarica, da sostituire)

    // Factory: arma casuale fra le 4 disponibili.
    static Weapon generateRandom();
    // Factory: arma specifica con statistiche predefinite.
    static Weapon generate(WeaponType t);

    std::string getName() const;        // etichetta UI (es. "PISTOL")
    sf::Color getColor() const;         // colore associato all'arma (UI)

    // Disegna l'arma appoggiata a terra (grande, con ombra).
    void render(sf::RenderTarget& target, float x, float y) const;
    // Disegna l'arma equipaggiata in mano al giocatore (piu' piccola).
    void renderEquipped(sf::RenderTarget& target, float x, float y) const;
};

#endif
