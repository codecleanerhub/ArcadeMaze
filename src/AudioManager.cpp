#include "AudioManager.h"
#include <cmath>
#include <cstdlib>
#include <cstring>

// ===========================================================================
// AudioManager.cpp - Sintesi audio procedurale.
//
// Tutti i campioni sono costruiti matematicamente:
//   * Suoni one-shot: brevi (0.1-2 sec) con inviluppo esponenziale exp(-t*k)
//     e miscuglio di sinusoide + rumore bianco.
//   * Tracce musicali: 32 battute a 120 BPM (100 per il boss), con batteria
//     (kick/snare/hihat), basso (dente di sega), lead (onda quadra) e pad
//     (sine) opzionale nei ritornelli.
//
// Le scale usate sono minori naturali o armoniche per il mood fantasy-horror.
// ===========================================================================

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Costruttore: prealloca buffer e suoni, imposta il volume e genera tutte
// le tracce musicali (5 tracce, una tantum). Generare qui evita di pagare
// il costo della sintesi durante il gioco.
AudioManager::AudioManager() {
    buffers.resize(11);
    sounds.resize(20);
    for(auto& s : sounds) s.setVolume(70);
    for(int i=0; i<5; ++i) generateTrack(i);
}

// Rumore bianco uniforme in [-1, 1]: usato per percussioni e rombi.
double noise() { return (rand() % 2000 - 1000) / 1000.0; }

// ---------------------------------------------------------------------------
// generateTrack: sintetizza una traccia musicale completa.
//
// Parametri per traccia (scelti per dare carattere crescente):
//   * Traccia 0 (Livello 1): Re minore naturale, 120 BPM, "misterioso"
//   * Traccia 1 (Livello 2): Do minore armonica, 120 BPM, "teso"
//   * Traccia 2 (Livello 3): Si minore naturale, 120 BPM, "oscuro"
//   * Traccia 3 (Livello 4): Mi minore armonica, 120 BPM, "epico"
//   * Traccia 4 (Boss): Fa minore armonica, 90 BPM, "aggressivo"
//
// Struttura musicale:
//   * 32 battute, ognuna con 8 ottavi (1 ottavo = beatDur/2 secondi).
//   * Progressione armonica: i, VI, III, VII (tipica minore) ciclica.
//   * Battute 8-11, 16-19, 24-27 marcate come "chorus": qui si aggiunge
//     un pad (sine) per dare profondita'.
//   * Drum pattern fisso (kick, snare, hihat) per tutta la traccia.
//   * Lead: arpeggio su 4 note della triade corrente (radice, quarta,
//     quinta, ottava) con onda quadra.
//   * Basso: dente di sega sulla radice, suonato sull'ottavo 0 e 4.
// ---------------------------------------------------------------------------
void AudioManager::generateTrack(int trackIdx) {
    int sr = 44100;
    double tempo = (trackIdx == 4) ? 100 : 120;  // boss piu' lento
    double beatDur = 60.0 / tempo;
    double eighthDur = beatDur / 2.0;
    int samplesPerEighth = sr * eighthDur;

    // Scala: 7 gradi. `harmonic=true` -> 7° grado alzato di un semitono.
    double scale[7];
    double root;
    bool harmonic;

    if (trackIdx == 0) { // Livello 1: Re minore naturale (misterioso)
        root = 146.83; harmonic = false;
    } else if (trackIdx == 1) { // Livello 2: Do minore armonica (teso)
        root = 130.81; harmonic = true;
    } else if (trackIdx == 2) { // Livello 3: Si minore naturale (oscuro)
        root = 123.47; harmonic = false;
    } else if (trackIdx == 3) { // Livello 4: Mi minore armonica (epico)
        root = 82.41; harmonic = true;
    } else { // Boss: Fa minore armonica (aggressivo)
        root = 87.31; harmonic = true;
        tempo = 90;
    }

    // Costruzione scala: intervalli della minore naturale, con 7° alzato se
    // vogliamo la minore armonica. Si usa pow(2, n/12) per i semitoni.
    int intervals[] = {0, 2, 3, 5, 7, 8, 10};
    if (harmonic) intervals[6] = 11;
    for(int i=0; i<7; i++) {
        scale[i] = root * pow(2.0, intervals[i] / 12.0);
    }

    std::vector<sf::Int16> trackSamples;
    int numBars = 32;

    // Pattern drum (8 ottavi per battuta)
    bool kick[8]  = {1, 0, 0, 1, 1, 0, 0, 0};  // tipico pattern "four-on-the-floor" variato
    bool snare[8] = {0, 0, 1, 0, 0, 0, 1, 0};  // rullante su 3 e 7
    bool hihat[8] = {1, 1, 1, 1, 1, 1, 1, 1};  // hihat su ogni ottavo

    // Progressione armonica i, VI, III, VII (gradi della scala minore)
    int prog[] = {0, 5, 2, 6};

    for(int bar = 0; bar < numBars; ++bar) {
        // Nota di base del accordo corrente
        int chordRoot = scale[prog[bar % 4]];
        // Le battute "chorus" attivano il pad
        bool isChorus = (bar >= 8 && bar <= 11) || (bar >= 16 && bar <= 19) || (bar >= 24 && bar <= 27);

        for(int i = 0; i < 8; ++i) {
            // Lead arpeggiato: radice, quarta, quinta, ottava (sugli ottavi pari)
            double freq = chordRoot;
            if(i == 0) freq = chordRoot;
            else if(i == 2) freq = chordRoot * pow(2.0, 3.0/12.0); // 4th
            else if(i == 4) freq = chordRoot * pow(2.0, 7.0/12.0); // 5th
            else if(i == 6) freq = chordRoot * 2.0; // Octave
            else continue; // Ottavi dispari senza lead: tesa

            for(int s = 0; s < samplesPerEighth; ++s) {
                double t = (double)s / sr;
                double sample = 0.0;

                // --- Drums ---
                // Kick: breve burst a 50 Hz nei primi 20% dell'ottavo
                if (kick[i] && s < samplesPerEighth * 0.2) {
                    double env = exp(-t * 40.0);
                    sample += 3000 * sin(2*M_PI*50*t) * env;
                }
                // Snare: rumore bianco dal 10% in poi
                if (snare[i] && s > samplesPerEighth * 0.1) {
                    double env = exp(-t * 15.0);
                    sample += 1500 * noise() * env;
                }
                // Hihat: rumore corto ogni 4 campioni (16esimi)
                if (hihat[i] && s % 4 == 0) {
                    double env = exp(-t * 60.0);
                    sample += 500 * noise() * env * 0.3;
                }

                // --- Basso: dente di sega scuro su 0/4 ---
                if (i == 0 || i == 4) {
                    double bPhase = t * (chordRoot/2.0);
                    // Dente di sega: 2*(phase - floor(0.5+phase))
                    double bWave = 2.0 * (bPhase - floor(0.5 + bPhase));
                    double bEnv = exp(-t * 3.0) * 0.8;
                    sample += 2500 * bWave * bEnv;
                }

                // --- Lead: onda quadra fantasy ---
                double mPhase = t * freq;
                double mWave = (sin(2*M_PI*mPhase) > 0 ? 1 : -1) * 0.5 + 0.5 * sin(2*M_PI*mPhase*2.0);
                double mEnv = exp(-t * 4.0);
                sample += 1200 * mWave * mEnv;

                // --- Pad (solo nel chorus): due sine per "sustained" ---
                if(isChorus) {
                    double pWave = 0.3 * sin(2*M_PI*chordRoot*t) + 0.3 * sin(2*M_PI*(chordRoot*1.2)*t);
                    sample += 800 * pWave * 0.5;
                }

                trackSamples.push_back((sf::Int16)sample);
            }
        }
    }

    if(!trackSamples.empty()) {
        musicBuffers[trackIdx].loadFromSamples(&trackSamples[0], trackSamples.size(), 1, sr);
    }
}

// ---------------------------------------------------------------------------
// playLevelMusic: cambia traccia in base a livello e modalita'.
//   * Boss sempre traccia 4.
//   * Livelli normali ciclano sulle tracce 0..3: (level-1) % 4.
// Il volume e' fissato a 45 (su 100) per non coprire gli effetti.
// ---------------------------------------------------------------------------
void AudioManager::playLevelMusic(int level, bool isBoss) {
    int trackIdx = isBoss ? 4 : ((level - 1) % 4);
    music.stop();
    music.setBuffer(musicBuffers[trackIdx]);
    music.setLoop(true);
    music.setVolume(45);
    music.play();
}

// startMusic/stopMusic: controllo semplice della traccia corrente.
void AudioManager::startMusic() {
    if(music.getStatus() != sf::Sound::Playing) music.play();
}

void AudioManager::stopMusic() {
    music.stop();
}

// Trova un'istanza sf::Sound non in riproduzione; se tutte sono occupate
// ritorna 0 (sovrascrive la prima: effetto "voice stealing").
int AudioManager::findFreeSound() {
    for(size_t i=0; i<sounds.size(); ++i) {
        if(sounds[i].getStatus() != sf::Sound::Playing) return i;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// playSound: sintetizza e riproduce un effetto sonoro.
//
// Ogni tipo ha la sua "ricetta":
//   * PISTOL/SHOTGUN: breve burst di rumore + sinusoide grave con exp decay
//   * TREASURE: 4 note arpeggiate crescenti (Do6-Mi6-Sol6-Do7)
//   * ENEMY_DEATH: pitch discendente + rumore
//   * LOSE_LIFE: onda quadra con pitch che scende linearmente
//   * BOSS_DEATH: 2 sec di toni gravi + rumore
//   * Default (rocket/laser/hit): tono puro a 400 Hz con decay
//
// Il campione viene rigenerato a ogni chiamata. Per suoni frequenti (es.
// sparo) questo e' inefficiente; per un gioco arcade piccolo e' accettabile.
// ---------------------------------------------------------------------------
void AudioManager::playSound(SoundType type) {
    int sr = 44100;
    std::vector<sf::Int16> samples;

    if (type == SOUND_PISTOL) {
        // 0.1 sec: rumore + 80 Hz, decay veloce
        for(int i=0; i<sr*0.1; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 30.0);
            samples.push_back((sf::Int16)(3000 * (0.6 * (rand()%2000-1000)/1000.0 + 0.8 * sin(2*M_PI*80*t)) * env));
        }
    } else if (type == SOUND_SHOTGUN) {
        // 0.2 sec: piu' rumore + 60 Hz
        for(int i=0; i<sr*0.2; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 20.0);
            samples.push_back((sf::Int16)(3000 * (0.8 * (rand()%2000-1000)/1000.0 + 500 * sin(2*M_PI*60*t)) * env));
        }
    } else if (type == SOUND_TREASURE) {
        // Arpeggio 4 note: Do6-Mi6-Sol6-Do7 (1046, 1318, 1568, 2093 Hz)
        int notes[] = {1046, 1318, 1568, 2093};
        for(int n=0; n<4; n++) {
            for(int i=0; i<sr*0.08; i++) {
                double t = (double)i / sr;
                double env = exp(-t * 20.0);
                samples.push_back((sf::Int16)(2500 * (sin(2*M_PI*notes[n]*t) + 0.5*sin(2*M_PI*notes[n]*2*t)) * env));
            }
        }
    } else if (type == SOUND_ENEMY_DEATH) {
        // 0.4 sec: pitch che scende esponenzialmente + rumore
        for(int i=0; i<sr*0.4; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 8.0);
            double freq = 300 * exp(-t * 8.0) + 50;
            samples.push_back((sf::Int16)(2500 * (0.5 * sin(2*M_PI*freq*t) + 0.4 * (rand()%2000-1000)/1000.0) * env));
        }
    } else if (type == SOUND_LOSE_LIFE) {
        // 0.8 sec: onda quadra che scende linearmente di pitch
        for(int i=0; i<sr*0.8; i++) {
            double t = (double)i / sr;
            double freq = 150 - i * 0.1;
            samples.push_back((sf::Int16)(3000 * (sin(2*M_PI*freq*t) > 0 ? 1 : -1) * exp(-t*3.0)));
        }
    } else if (type == SOUND_BOSS_DEATH) {
        // 2 sec: due toni gravi (40/60 Hz) + rumore, decay lungo
        for(int i=0; i<sr*2.0; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 2.0);
            samples.push_back((sf::Int16)(3000 * (sin(2*M_PI*40*t) + sin(2*M_PI*60*t)) * env + 2000 * (rand()%2000-1000)/1000.0 * env));
        }
    } else {
        // Default: tono puro 400 Hz con decay
        for(int i=0; i<sr*0.2; i++) {
            double t = (double)i / sr;
            samples.push_back((sf::Int16)(2000 * sin(2 * M_PI * 400 * t) * exp(-t * 15.0)));
        }
    }

    if(!samples.empty()) {
        buffers[type].loadFromSamples(&samples[0], samples.size(), 1, sr);
        int idx = findFreeSound();
        sounds[idx].setBuffer(buffers[type]);
        sounds[idx].play();
    }
}
