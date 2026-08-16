#include "AudioManager.h"
#include <cmath>
#include <cstdlib>
#include <cstring>

// ===========================================================================
// AudioManager.cpp - Sintesi audio chiptune procedurale.
//
// Tutti i suoni sono costruiti matematicamente con forme d'onda vintage:
//   * Pulse wave (square con duty cycle) -> melodie lead, arpeggi
//   * Triangle wave -> bassi
//   * Sawtooth wave -> pad, armonici
//   * Noise -> percussioni (kick/snare/hihat), effetti
//
// Le scale usate sono minori (naturale o armonica) per il mood fantasy/horror.
// Musiche: 32 battute a ~100 BPM (livelli) o ~130 BPM (boss), loop perfetto.
// SFX: brevi (0.05-2 sec), secchi, sintetici.
// ===========================================================================

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Sample rate
static const int SR = 44100;

// --- Forme d'onda chiptune ---

// Pulse wave con duty cycle: 0.5 = square, 0.25 = 25% pulse, 0.125 = 12.5%
double AudioManager::pulseWave(double phase, double duty) {
    double p = phase - floor(phase);  // normalizza a [0, 1)
    return (p < duty) ? 1.0 : -1.0;
}

// Triangle wave: lineare a salire e scendere
double AudioManager::triangleWave(double phase) {
    double p = phase - floor(phase);
    return (p < 0.5) ? (4.0 * p - 1.0) : (3.0 - 4.0 * p);
}

// Sawtooth wave: rampa lineare
double AudioManager::sawtoothWave(double phase) {
    double p = phase - floor(phase);
    return 2.0 * p - 1.0;
}

// Noise bianco [-1, 1]
double AudioManager::noiseGen() {
    return (rand() % 2000 - 1000) / 1000.0;
}

// --- Costruttore ---

AudioManager::AudioManager() {
    buffers.resize(SOUND_TYPE_COUNT);
    sounds.resize(20);
    for(auto& s : sounds) s.setVolume(70);
    // Pre-genera le 5 tracce musicali (una tantum)
    for(int i = 0; i < 5; ++i) generateTrack(i);
}

// --- Music management ---

void AudioManager::playLevelMusic(int level, bool isBoss) {
    int trackIdx = isBoss ? 4 : ((level - 1) % 4);
    music.stop();
    music.setBuffer(musicBuffers[trackIdx]);
    music.setLoop(true);
    music.setVolume(45);
    music.play();
}

void AudioManager::startMusic() {
    if(music.getStatus() != sf::Sound::Playing) music.play();
}

void AudioManager::stopMusic() {
    music.stop();
}

int AudioManager::findFreeSound() {
    for(size_t i = 0; i < sounds.size(); ++i) {
        if(sounds[i].getStatus() != sf::Sound::Playing) return i;
    }
    return 0;  // voice stealing
}

// ===========================================================================
// SFX: sintesi chiptune brevi e secchi
// ===========================================================================

void AudioManager::playSound(SoundType type) {
    std::vector<sf::Int16> samples;
    int idx = static_cast<int>(type);

    if (type == SOUND_PISTOL) {
        // 0.08s: noise burst + 80Hz pulse, decay veloce
        for(int i = 0; i < SR * 0.08; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 35.0);
            double s = 0.5 * noiseGen() + 0.5 * pulseWave(t * 80.0, 0.5);
            samples.push_back((sf::Int16)(2500 * s * env));
        }
    }
    else if (type == SOUND_SHOTGUN) {
        // 0.15s: piu' noise, 60Hz, decay medio
        for(int i = 0; i < SR * 0.15; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 20.0);
            double s = 0.7 * noiseGen() + 0.3 * pulseWave(t * 60.0, 0.5);
            samples.push_back((sf::Int16)(2500 * s * env));
        }
    }
    else if (type == SOUND_ROCKET) {
        // 0.25s: rumble grave 40Hz + noise
        for(int i = 0; i < SR * 0.25; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 12.0);
            double s = 0.4 * noiseGen() + 0.6 * pulseWave(t * 40.0, 0.3);
            samples.push_back((sf::Int16)(2200 * s * env));
        }
    }
    else if (type == SOUND_LASER) {
        // 0.15s: sweep frequenza alta discendente
        for(int i = 0; i < SR * 0.15; i++) {
            double t = (double)i / SR;
            double freq = 1200 - t * 4000;
            if (freq < 200) freq = 200;
            double env = exp(-t * 15.0);
            double s = pulseWave(t * freq, 0.25);
            samples.push_back((sf::Int16)(2000 * s * env));
        }
    }
    else if (type == SOUND_TREASURE) {
        // Arpeggio ascendente 4 note: Do-Mi-Sol-Do (ottava superiore)
        int notes[] = {523, 659, 784, 1047};
        for(int n = 0; n < 4; n++) {
            for(int i = 0; i < SR * 0.06; i++) {
                double t = (double)i / SR;
                double env = exp(-t * 20.0);
                double s = 0.6 * pulseWave(t * notes[n], 0.5) +
                           0.4 * triangleWave(t * notes[n]);
                samples.push_back((sf::Int16)(2200 * s * env));
            }
        }
    }
    else if (type == SOUND_ENEMY_DEATH) {
        // 0.5s: morte drammatica - 3 fasi:
        // 1) gridolato pitch discendente (pulse wave)
        // 2) esplosione noise burst
        // 3) dissolve basso
        for(int i = 0; i < SR * 0.5; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 5.0);
            double s = 0;
            if (t < 0.15) {
                // Fase 1: gridolato (pitch discendente veloce)
                double freq = 600 * exp(-t * 12.0) + 100;
                s = 0.5 * pulseWave(t * freq, 0.25);
            } else if (t < 0.3) {
                // Fase 2: esplosione (noise)
                s = 0.6 * noiseGen();
            } else {
                // Fase 3: dissolve (basso discendente)
                double freq = 150 * exp(-(t-0.3) * 8.0) + 40;
                s = 0.4 * triangleWave(t * freq);
            }
            samples.push_back((sf::Int16)(2500 * s * env));
        }
    }
    else if (type == SOUND_LOSE_LIFE) {
        // 0.5s: onda quadra discendente (classico "lose life" NES)
        for(int i = 0; i < SR * 0.5; i++) {
            double t = (double)i / SR;
            double freq = 300 - t * 400;
            if (freq < 60) freq = 60;
            double env = exp(-t * 4.0);
            double s = pulseWave(t * freq, 0.5);
            samples.push_back((sf::Int16)(2500 * s * env));
        }
    }
    else if (type == SOUND_WIN) {
        // Fanfara vittoria: 5 note ascendenti
        int notes[] = {523, 659, 784, 1047, 1319};
        for(int n = 0; n < 5; n++) {
            for(int i = 0; i < SR * 0.1; i++) {
                double t = (double)i / SR;
                double env = exp(-t * 6.0);
                double s = 0.5 * pulseWave(t * notes[n], 0.5) +
                           0.5 * triangleWave(t * notes[n] * 2);
                samples.push_back((sf::Int16)(2200 * s * env));
            }
        }
    }
    else if (type == SOUND_BOSS_HIT) {
        // 0.1s: clank metallico (due freq alte + noise)
        for(int i = 0; i < SR * 0.1; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 25.0);
            double s = 0.3 * pulseWave(t * 800, 0.5) +
                       0.3 * pulseWave(t * 1100, 0.25) +
                       0.4 * noiseGen();
            samples.push_back((sf::Int16)(2000 * s * env));
        }
    }
    else if (type == SOUND_BOSS_DEATH) {
        // 1.5s: esplosione lunga (noise + basso discendente)
        for(int i = 0; i < SR * 1.5; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 2.0);
            double freq = 100 * exp(-t * 1.5) + 30;
            double s = 0.5 * noiseGen() + 0.5 * pulseWave(t * freq, 0.3);
            samples.push_back((sf::Int16)(2800 * s * env));
        }
    }
    // --- Nuovi SFX retro ---
    else if (type == SOUND_JUMP) {
        // 0.15s: sweep triangolare ascendente (salto)
        for(int i = 0; i < SR * 0.15; i++) {
            double t = (double)i / SR;
            double freq = 200 + t * 1200;  // 200 -> 1400 Hz
            double env = exp(-t * 8.0);
            double s = triangleWave(t * freq);
            samples.push_back((sf::Int16)(2500 * s * env));
        }
    }
    else if (type == SOUND_DOOR_OPEN) {
        // 0.4s: cigolio grave (pulse a bassa freq con vibrato)
        for(int i = 0; i < SR * 0.4; i++) {
            double t = (double)i / SR;
            double freq = 60 + 20 * sin(t * 30);  // vibrato
            double env = exp(-t * 3.0) * (1.0 - exp(-t * 20.0));  // attack + decay
            double s = pulseWave(t * freq, 0.3) + 0.3 * noiseGen();
            samples.push_back((sf::Int16)(1800 * s * env));
        }
    }
    else if (type == SOUND_TRAP) {
        // 0.2s: scatto secco (noise burst + click alto)
        for(int i = 0; i < SR * 0.2; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 15.0);
            double s = 0.6 * noiseGen() + 0.4 * pulseWave(t * 1500, 0.1);
            samples.push_back((sf::Int16)(2500 * s * env));
        }
    }
    else if (type == SOUND_MENU_SELECT) {
        // 0.05s: blip corto (cursor move NES style)
        for(int i = 0; i < SR * 0.05; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 40.0);
            double s = pulseWave(t * 880, 0.5);  // La5
            samples.push_back((sf::Int16)(2000 * s * env));
        }
    }
    else if (type == SOUND_MENU_CONFIRM) {
        // 0.15s: due toni (La -> Do) classico confirm
        int notes[] = {880, 1319};  // La5, Mi6
        for(int n = 0; n < 2; n++) {
            for(int i = 0; i < SR * 0.07; i++) {
                double t = (double)i / SR;
                double env = exp(-t * 15.0);
                double s = pulseWave(t * notes[n], 0.5);
                samples.push_back((sf::Int16)(2200 * s * env));
            }
        }
    }

    if(!samples.empty()) {
        buffers[idx].loadFromSamples(&samples[0], samples.size(), 1, SR);
        int slot = findFreeSound();
        sounds[slot].setBuffer(buffers[idx]);
        sounds[slot].play();
    }
}

// ===========================================================================
// Generazione tracce musicali chiptune
//
// Struttura: 32 battute, ogni battuta = 4 beat, ogni beat = 4 sixteenth.
// Strumenti per traccia (max 4, stile chip vintage):
//   1. Pulse lead (melodia, duty 50% o 25%)
//   2. Triangle bass (basso, ottava sotto)
//   3. Noise drums (kick/snare/hihat)
//   4. Sawtooth pad (accordi brevi, solo nei chorus)
//
// Scale minori per mood horror/fantasy:
//   Traccia 0 (Livello 1): Re minore naturale - misterioso, 100 BPM
//   Traccia 1 (Livello 2): Do minore armonica - teso, 105 BPM
//   Traccia 2 (Livello 3): Si minore naturale - oscuro, 100 BPM
//   Traccia 3 (Livello 4): Mi minore armonica - epico, 110 BPM
//   Traccia 4 (Boss): Fa minore armonica - aggressivo, 130 BPM
// ===========================================================================

void AudioManager::generateTrack(int trackIdx) {
    // Parametri per traccia
    double tempo = (trackIdx == 4) ? 130.0 : 100.0 + trackIdx * 2.5;
    double beatDur = 60.0 / tempo;
    double sixteenthDur = beatDur / 4.0;
    int samplesPerSixteenth = SR * sixteenthDur;
    int numBars = 32;
    int totalSamples = numBars * 4 * samplesPerSixteenth;  // 32 bar * 4 beat * 4 sixteenth

    // Scala minore: root, intervalli
    // Minore naturale: 0, 2, 3, 5, 7, 8, 10
    // Minore armonica: 0, 2, 3, 5, 7, 8, 11
    double root;
    bool harmonic;
    int intervals[7];

    if (trackIdx == 0) { root = 146.83; harmonic = false; }      // Re minore
    else if (trackIdx == 1) { root = 130.81; harmonic = true; }   // Do minore armonica
    else if (trackIdx == 2) { root = 123.47; harmonic = false; }  // Si minore
    else if (trackIdx == 3) { root = 82.41; harmonic = true; }    // Mi minore armonica
    else { root = 87.31; harmonic = true; tempo = 130.0; }        // Fa minore armonica (boss)

    int nat[] = {0, 2, 3, 5, 7, 8, 10};
    int har[] = {0, 2, 3, 5, 7, 8, 11};
    for(int i = 0; i < 7; i++) intervals[i] = harmonic ? har[i] : nat[i];

    // Costruisci la scala (7 gradi)
    double scale[7];
    for(int i = 0; i < 7; i++) {
        scale[i] = root * pow(2.0, intervals[i] / 12.0);
    }

    // Progressione armonica: i, VI, III, VII (tipica minore)
    // Gradi: 0, 5, 2, 6 -> indici nella scala
    int prog[] = {0, 5, 2, 6};

    // Pattern drum (8 sixteenth per beat = 32 per bar... no, 4 sixteenth per beat, 16 per bar)
    // Semplificiamo: 4 sixteenth per beat, 16 per bar (4 beat)
    bool kick[16]  = {1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,0};
    bool snare[16] = {0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0};
    bool hihat[16] = {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0};

    // Per il boss: pattern piu' denso
    if (trackIdx == 4) {
        // Double-time feel
        kick[3] = 1; kick[7] = 1; kick[11] = 1; kick[15] = 1;
        snare[6] = 1; snare[14] = 1;
        for(int i = 0; i < 16; i++) hihat[i] = 1;  // tutti i sixteenth
    }

    std::vector<sf::Int16> trackSamples;
    trackSamples.reserve(totalSamples);

    for(int bar = 0; bar < numBars; ++bar) {
        int chordRoot = scale[prog[bar % 4]];
        bool isChorus = (bar >= 8 && bar <= 11) || (bar >= 20 && bar <= 23);
        // Boss: piu' intenso, chorus piu' frequente
        if (trackIdx == 4) isChorus = (bar % 4 == 0) || (bar % 4 == 1);

        for(int s = 0; s < 16; ++s) {
            // Lead: arpeggio sulla triade (root, 3rd, 5th, octave)
            double leadFreq = 0;
            if (s == 0) leadFreq = chordRoot * 2;        // root (ottava su)
            else if (s == 4) leadFreq = chordRoot * pow(2, 3.0/12) * 2;  // 3rd
            else if (s == 8) leadFreq = chordRoot * pow(2, 7.0/12) * 2;  // 5th
            else if (s == 12) leadFreq = chordRoot * 4;   // octave
            // Boss: arpeggi piu' veloci (ogni 2 sixteenth)
            if (trackIdx == 4 && s % 2 == 0) {
                int noteIdx = (s / 2) % 4;
                if (noteIdx == 0) leadFreq = chordRoot * 2;
                else if (noteIdx == 1) leadFreq = chordRoot * pow(2, 3.0/12) * 2;
                else if (noteIdx == 2) leadFreq = chordRoot * pow(2, 7.0/12) * 2;
                else leadFreq = chordRoot * 4;
            }

            for(int i = 0; i < samplesPerSixteenth; ++i) {
                double t = (double)i / SR;
                double sample = 0.0;

                // --- Drums (noise based) ---
                if (kick[s] && i < samplesPerSixteenth * 0.3) {
                    double env = exp(-t * 30.0);
                    sample += 2500 * sin(2 * M_PI * 50 * t) * env;
                }
                if (snare[s] && i > samplesPerSixteenth * 0.1) {
                    double env = exp(-t * 15.0);
                    sample += 1200 * noiseGen() * env;
                }
                if (hihat[s] && i % 2 == 0) {
                    double env = exp(-t * 50.0);
                    sample += 400 * noiseGen() * env * 0.3;
                }

                // --- Bass (triangle, root ottava sotto) ---
                if (s == 0 || s == 8 || (trackIdx == 4 && s % 4 == 0)) {
                    double bPhase = t * (chordRoot / 2.0);
                    double bEnv = exp(-t * 3.0) * 0.8;
                    sample += 2000 * triangleWave(bPhase) * bEnv;
                }

                // --- Lead (pulse wave, melodia principale) ---
                if (leadFreq > 0) {
                    double lPhase = t * leadFreq;
                    double duty = (trackIdx == 4) ? 0.25 : 0.5;
                    double lWave = pulseWave(lPhase, duty);
                    // Boss: piu' aggressivo, aggiunge armonico
                    if (trackIdx == 4) {
                        lWave = lWave * 0.6 + pulseWave(lPhase * 2, 0.5) * 0.4;
                    }
                    double lEnv = exp(-t * 4.0);
                    sample += (trackIdx == 4 ? 1500 : 1000) * lWave * lEnv;
                }

                // --- Armonia (secondo lead, terza sopra, solo nei chorus) ---
                if (isChorus && leadFreq > 0) {
                    double harmFreq = leadFreq * pow(2, 3.0/12);  // 3a maggiore sopra
                    double hPhase = t * harmFreq;
                    double hWave = pulseWave(hPhase, 0.5);
                    double hEnv = exp(-t * 5.0);
                    sample += 500 * hWave * hEnv;
                }

                // --- Arpeggio veloce (solo nei livelli 3+, aggiunge movimento) ---
                if (trackIdx >= 2 && !isChorus) {
                    int arpNote = (s + bar) % 4;
                    double arpFreqs[] = {
                        (double)(chordRoot * 2),
                        chordRoot * pow(2, 5.0/12) * 2,  // 4th
                        chordRoot * pow(2, 7.0/12) * 2,  // 5th
                        chordRoot * pow(2, 10.0/12) * 2  // 7th
                    };
                    double aPhase = t * arpFreqs[arpNote];
                    double aWave = pulseWave(aPhase, 0.125);  // duty 12.5% (piu' sottile)
                    double aEnv = exp(-t * 8.0);
                    sample += 400 * aWave * aEnv;
                }

                // --- Pad (sawtooth, solo chorus) ---
                if (isChorus) {
                    double pWave = 0.3 * sawtoothWave(t * chordRoot) +
                                   0.3 * sawtoothWave(t * chordRoot * 1.5);
                    sample += 600 * pWave * 0.5;
                }

                // Clamp per evitare clipping
                if (sample > 32000) sample = 32000;
                if (sample < -32000) sample = -32000;

                trackSamples.push_back((sf::Int16)sample);
            }
        }
    }

    if(!trackSamples.empty()) {
        musicBuffers[trackIdx].loadFromSamples(&trackSamples[0],
            trackSamples.size(), 1, SR);
    }
}
