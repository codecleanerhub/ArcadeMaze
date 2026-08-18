#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H

// ===========================================================================
// AudioManager.h - Audio chiptune generato proceduralmente (NES/SNES/C64 style)
//
// Tutti i suoni e le musiche sono sintetizzati a runtime in PCM 16-bit mono
// 44100 Hz. Nessun file esterno: il gioco e' completamente autonomo.
//
// Palette sonora limitata (stile chip audio vintage):
//   * Pulse wave (onda quadra con duty cycle) -> melodie lead
//   * Triangle wave -> bassi
//   * Sawtooth wave -> pad/armonici
//   * Noise -> percussioni (kick/snare/hihat) e effetti
//
// Contenuto:
//   * 16 effetti sonori (SoundType) - chiptune brevi e secchi
//   * 5 tracce musicali (4 livelli + 1 boss), loop perfetto
//     - Livelli: drammatici, oscuri, misteriosi, atmosfera dungeon
//     - Boss: epici, aggressivi, ritmo veloce, battaglia finale
// ===========================================================================

#include <SFML/Audio.hpp>
#include <vector>

// Identificatori degli effetti sonori. Usati come indice nel vettore
// `buffers`: NON modificare l'ordine senza sincronizzare il codice chiamante.
enum SoundType {
    // Armi (4)
    SOUND_PISTOL, SOUND_SHOTGUN, SOUND_ROCKET, SOUND_LASER,
    // Gameplay (5)
    SOUND_TREASURE, SOUND_ENEMY_DEATH, SOUND_LOSE_LIFE, SOUND_WIN,
    SOUND_BOSS_HIT, SOUND_BOSS_DEATH,
    // Nuovi SFX retro (5)
    SOUND_JUMP,          // salto del giocatore
    SOUND_DOOR_OPEN,     // apertura porta
    SOUND_TRAP,          // attivazione trappola
    SOUND_MENU_SELECT,   // selezione nel menu (spostamento cursore)
    SOUND_MENU_CONFIRM,  // conferma nel menu (invio)
    // Gameplay effects (6)
    SOUND_PORTAL_OPEN,   // apertura portale magico (epico ascendente)
    SOUND_PORTAL_CLOSE,  // chiusura portale (discendente)
    SOUND_WEAPON_PICKUP, // raccolta arma (caricamento fucile)
    SOUND_ENEMY_EXPLODE, // esplosione nemico (boom + debris)
    SOUND_BLOOD_SPLAT,   // sangue che schizza (wet impact)
    SOUND_MINE_BOUNCE,   // rimbalzo mina (boing metallico)
    SOUND_POTION_DRINK   // ingestione pozione (glug-glug)
};

// Numero totale di SFX (usato per dimensionare i buffer).
constexpr int SOUND_TYPE_COUNT = 23;

class AudioManager {
public:
    AudioManager();

    // Sintetizza e riproduce un effetto sonoro chiptune.
    void playSound(SoundType type);

    // Avvia la musica di sottofondo corrente (se non sta gia' suonando).
    void startMusic();
    // Ferma la musica corrente.
    void stopMusic();
    // Cambia la traccia in base al livello (1+) e se e' la stanza del boss.
    // Livelli normali: cicla su 4 tracce (0..3).
    // Boss: usa la traccia 4 (piu' aggressiva e veloce).
    void playLevelMusic(int level, bool isBoss);

    // True se la musica e' in riproduzione.
    bool isMusicPlaying() { return music.getStatus() == sf::Sound::Playing; }
private:
    // Pool di buffer per effetti sonori.
    std::vector<sf::SoundBuffer> buffers;
    // Pool di istanze sf::Sound per riproduzione polifonica (20 voci).
    std::vector<sf::Sound> sounds;

    // 6 tracce musicali pre-generate: indici 0..3 = livelli, 4 = boss, 5 = portale.
    sf::SoundBuffer musicBuffers[6];
    sf::Sound music;

    // Trova uno slot audio libero (o il primo se tutti occupati).
    int findFreeSound();
    // Pre-sintetizza un suono nel buffer (chiamato dal costruttore).
    void preGenerateSound(SoundType type);
    // Sintetizza una traccia musicale completa nel buffer musicBuffers[idx].
    // idx 0..3 = livello (drammatico/oscura), idx 4 = boss (epico/aggressivo).
    void generateTrack(int trackIdx);

    // --- Sintetizzatori di forme d'onda chiptune ---
    // Pulse wave con duty cycle (0.0=0%, 0.5=50% square, 0.25=25%).
    static double pulseWave(double phase, double duty);
    // Triangle wave (bassi).
    static double triangleWave(double phase);
    // Sawtooth wave (pad/armonici).
    static double sawtoothWave(double phase);
    // Noise (percussioni).
    static double noiseGen();
};

#endif
