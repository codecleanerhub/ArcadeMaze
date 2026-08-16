#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H

// ===========================================================================
// AudioManager.h - Audio generato proceduralmente (nessun file esterno).
//
// Tutti i suoni e le musiche sono generati a runtime sintetizzando campioni
// audio in formato PCM 16-bit mono a 44100 Hz. Questo rende il gioco
// completamente autonomo (no file .wav/.ogg da distribuire) e dona un
// carattere "arcade retrò" coerente col comparto visivo.
//
// Contenuto:
//   * 11 effetti sonori (SoundType) caricati on-demand in buffer separati.
//   * 5 tracce musicali (4 livelli + 1 boss), generate una volta per tutte
//     nel costruttore tramite generateTrack().
// ===========================================================================

#include <SFML/Audio.hpp>
#include <vector>

// Identificatori degli effetti sonori. Sono anche usati come indice
// nel vettore `buffers`: NON modificare l'ordine senza sincronizzare.
enum SoundType {
    SOUND_PISTOL, SOUND_SHOTGUN, SOUND_ROCKET, SOUND_LASER, SOUND_TREASURE,
    SOUND_ENEMY_DEATH, SOUND_LOSE_LIFE, SOUND_WIN, SOUND_BOSS_SHOOT, SOUND_BOSS_HIT, SOUND_BOSS_DEATH
};

class AudioManager {
public:
    AudioManager();

    // Sintetizza e riproduce un effetto sonoro. Il campione viene rigenerato
    // ad ogni chiamata (non e' il massimo per le prestazioni, ma e' semplice
    // e garantisce variazioni ogni volta).
    void playSound(SoundType type);

    // Avvia la musica di sottofondo corrente (se non sta gia' suonando).
    void startMusic();
    // Ferma la musica corrente.
    void stopMusic();
    // Cambia la traccia in base al livello (1-10) e se e' la stanza del boss.
    // La selezione cicla sulle 4 tracce "livello" (1->0, 2->1, ..., 5->0...)
    // oppure usa la traccia 4 (boss) se isBoss==true.
    void playLevelMusic(int level, bool isBoss);

    // True se la musica e' in riproduzione.
    bool isMusicPlaying() { return music.getStatus() == sf::Sound::Playing; }
private:
    // Pool di buffer per effetti sonori (11 tipi).
    std::vector<sf::SoundBuffer> buffers;
    // Pool di istanze sf::Sound per la riproduzione polifonica (20 voci).
    std::vector<sf::Sound> sounds;

    // 5 tracce musicali pre-generate: indici 0..3 = livelli, 4 = boss.
    sf::SoundBuffer musicBuffers[5];
    sf::Sound music;

    // Trova uno slot audio libero (o il primo se tutti occupati).
    int findFreeSound();
    // Sintetizza una traccia musicale completa nel buffer `musicBuffers[idx]`.
    void generateTrack(int trackIdx);
};

#endif
