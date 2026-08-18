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
//   * 25 effetti sonori (SoundType) - chiptune brevi e secchi
//   * 9 tracce musicali:
//     - 0..3 = livelli 1..4 (drammatici, oscuri, mood dungeon)
//     - 4    = boss (epico, aggressivo, 130 BPM)
//     - 5    = portale magico (mistico, lento)
//     - 6    = MUSICA EPICA CALICE (fanfara eroica, dorata, maestosa)
//     - 7    = MUSICA EPICA SCETTRO (mistica, arcana, tensione magica)
//     - 8    = MUSICA MENU' PRINCIPALE (corale fantasy, drammatica, eterea)
//   Le ultime 3 tracce sono DISTINTE tra loro e DISTINTE dalle musiche
//   di gioco: ognuna usa scale, BPM e orchestrazione dedicati.
//   I jingle epici (calice/scettro) sono riprodotti su un canale SEPARATO
//   (`epicSound`) cosi' non interrompono la musica di sottofondo.
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
    SOUND_POTION_DRINK,  // ingestione pozione (glug-glug)
    SOUND_LIGHTNING,     // fulmine (crack elettrico + boom)
    SOUND_SCEPTER_PICKUP // raccolta scettro magico (oh-oh-oh evocativo fantasy, suspense)
};

// Numero totale di SFX (usato per dimensionare i buffer).
constexpr int SOUND_TYPE_COUNT = 25;

// Indici delle tracce musicali nel buffer (uso simbolico, non enum).
// 0..3 livelli, 4 boss, 5 portale, 6 calice epica, 7 scettro epica, 8 menu'.
constexpr int TRACK_LEVEL_BASE   = 0;  // livelli 0..3
constexpr int TRACK_BOSS         = 4;
constexpr int TRACK_PORTAL       = 5;
constexpr int TRACK_EPIC_CHALICE = 6;   // musica epica per pickup calice
constexpr int TRACK_EPIC_SCEPTER = 7;   // musica epica per pickup scettro
constexpr int TRACK_MENU         = 8;   // musica menu' principale (diversa)
constexpr int MUSIC_TRACK_COUNT  = 9;

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

    // Avvia un jingle epico DEDICATO su un canale SEPARATO (epicSound).
    // Non interferisce con la musica di gioco di sottofondo (che resta
    // attiva sul canale `music`). trackIdx = TRACK_EPIC_CHALICE o
    // TRACK_EPIC_SCEPTER. Il jingle e' pensato per una durata ~5-7 secondi:
    // si auto-ferma al termine (loop=false).
    void playEpicMusic(int trackIdx);
    // Ferma il jingle epico (se in riproduzione).
    void stopEpicMusic();
    // Avvia la traccia DEDICATA del menu' principale (corale fantasy).
    // Sostituisce la musica di gioco quando si e' nel menu'. Loop infinito.
    // DIVERSA da tutte le musiche di gioco (vedi generateMenuTrack).
    void playMenuMusic();
    // True se la musica e' in riproduzione.
    bool isMusicPlaying() { return music.getStatus() == sf::Sound::Playing; }
private:
    // Pool di buffer per effetti sonori.
    std::vector<sf::SoundBuffer> buffers;
    // Pool di istanze sf::Sound per riproduzione polifonica (30 voci).
    std::vector<sf::Sound> sounds;

    // 9 tracce musicali pre-generate:
    //   0..3 = livelli, 4 = boss, 5 = portale,
    //   6 = calice epica, 7 = scettro epica, 8 = menu' principale.
    sf::SoundBuffer musicBuffers[MUSIC_TRACK_COUNT];
    sf::Sound music;          // canale musica di gioco (livelli/boss/portale)
    sf::Sound epicSound;      // canale SEPARATO per jingle epici (calice/scettro)
    // flag: se true, il jingle epico e' in riproduzione (per evitare restart).
    bool epicPlaying;

    // Trova uno slot audio libero (o il primo se tutti occupati).
    int findFreeSound();
    // Pre-sintetizza un suono nel buffer (chiamato dal costruttore).
    void preGenerateSound(SoundType type);
    // Sintetizza una traccia musicale completa nel buffer musicBuffers[idx].
    // idx 0..3 = livello (drammatico/oscura), idx 4 = boss (epico/aggressivo).
    // idx 5 = portale (mistico, lento).
    // idx 6 = jingle epico calice (fanfara eroica dorata, maestosa, ~6s).
    // idx 7 = jingle epico scettro (arcano, magico, tensione, ~7s).
    // idx 8 = musica menu' principale (corale fantasy drammatica, loop).
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

    // --- Generatori di tracce epiche dedicate (jingle) ---
    // Fanfara eroica per il pickup del calice d'oro. Maestosa, dorata,
    // ~6 secondi, accordi maggiori brillanti (Do magg. -> Sol magg.),
    // orchestrazione a 3 voci (lead pulse + pad saw + basso triangolare).
    void generateEpicChaliceTrack();
    // Jingle magico-arcano per il pickup dello scettro. Mistico, teso,
    // ~7 secondi, accordi sospesi (tritono Do-Fa#), shimmer acuto,
    // pad sawtooth + arpeggi veloci + basso profondo.
    void generateEpicScepterTrack();
    // Musica del menu' principale: corale fantasy drammatica, eterea,
    // loop, ~80 BPM, minore armonica, pad sawtooth ampio + lead pulse
    // lento + arpeggi cristallini + basso triangolare.
    void generateMenuTrack();
};

#endif
