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

// Proiettile generico. Rappresenta uno "shot" in volo, sia del giocatore
// sia di nemici/boss. Lo stato `active=false` lo marca per la rimozione.
struct Projectile {
    sf::Vector2f pos;       // posizione corrente in pixel
    sf::Vector2f dir;       // vettore di spostamento per frame (già scalato)
    int power;              // danno inflitto quando colpisce il bersaglio
    bool active;            // false = da rimuovere (fuori schermo o impattato)
    WeaponType type;        // usato per il rendering (forma/colore del colpo)
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
