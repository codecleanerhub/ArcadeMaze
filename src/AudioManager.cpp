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

AudioManager::AudioManager() : epicPlaying(false) {
    buffers.resize(SOUND_TYPE_COUNT);
    sounds.resize(30);  // 30 voci per gestire piu' suoni simultanei
    for(auto& s : sounds) s.setVolume(70);
    // Pre-genera le 9 tracce musicali (una tantum):
    //   0..3 livelli, 4 boss, 5 portale, 6 calice epica, 7 scettro epica, 8 menu'.
    for(int i = 0; i < MUSIC_TRACK_COUNT; ++i) generateTrack(i);
    // Pre-sintetizza TUTTI i suoni nei buffer (evita lag durante il gioco)
    for(int i = 0; i < SOUND_TYPE_COUNT; ++i) {
        preGenerateSound(static_cast<SoundType>(i));
    }
    // Configura il canale jingle epico: volume un po' piu' alto della musica
    // di gioco (perche' e' un jingle "evento", deve essere percepito).
    epicSound.setVolume(80);
}

// --- Music management ---

void AudioManager::playLevelMusic(int level, bool isBoss) {
    // level=0 e isBoss=false -> traccia 5 (portale magico: evocativa fantasy)
    int trackIdx;
    if (level == 0 && !isBoss) trackIdx = 5;       // portale magico
    else if (isBoss) trackIdx = 4;                  // boss
    else trackIdx = (level - 1) % 4;                // livello normale
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

// Avvia un jingle epico su un canale SEPARATO. Non tocca la musica di gioco.
// Utilizzato per i pickup del calice (TRACK_EPIC_CHALICE) e dello scettro
// (TRACK_EPIC_SCEPTER): sono tracce DEDICATE, distinte tra loro e distinte
// dalle musiche di gioco. Il jingle e' pensato per durare 5-7 secondi e NON
// va in loop (auto-stop al termine).
void AudioManager::playEpicMusic(int trackIdx) {
    if (trackIdx < TRACK_EPIC_CHALICE || trackIdx > TRACK_MENU) return;
    // Evita restart se e' gia' in riproduzione lo stesso jingle
    if (epicPlaying && epicSound.getStatus() == sf::Sound::Playing) return;
    epicSound.stop();
    epicSound.setBuffer(musicBuffers[trackIdx]);
    epicSound.setLoop(false);  // one-shot (jingle, non loop)
    epicSound.setVolume(80);
    epicSound.play();
    epicPlaying = true;
}

void AudioManager::stopEpicMusic() {
    epicSound.stop();
    epicPlaying = false;
}

// Avvia la traccia DEDICATA del menu' principale. Sostituisce la musica
// di gioco (che non e' adatta al menu': e' troppo aggressiva/ritmata).
// La traccia del menu' e' una corale fantasy drammatica in loop, DISTINTA
// da tutte le musiche di gioco (vedi generateMenuTrack).
void AudioManager::playMenuMusic() {
    music.stop();
    music.setBuffer(musicBuffers[TRACK_MENU]);
    music.setLoop(true);
    music.setVolume(45);
    music.play();
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

// Pre-sintetizza un suono nel buffer corrispondente. Chiamato dal
// costruttore per evitare lag durante il gameplay.
void AudioManager::preGenerateSound(SoundType type) {
    // playSound(type) sintetizza i campioni nel buffer `buffers[idx]` (dove
    // idx = static_cast<int>(type)) e li riproduce una volta. Fermando subito
    // i suoni dopo la chiamata, otteniamo solo il pre-caricamento del buffer
    // senza audio udibile. Il buffer resta caricato per le chiamate future.
    playSound(type);
    // Ferma tutti i suoni appena avviati (erano solo per pre-generare)
    for(auto& s : sounds) s.stop();
}

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
    // --- Gameplay effects ---
    else if (type == SOUND_PORTAL_OPEN) {
        // 0.8s: fanfara epica ascendente - arpeggio + sweep + reverb
        // 6 note ascendenti (Do-Mi-Sol-Do-Mi-Sol) con sweep di freq
        int notes[] = {262, 330, 392, 523, 659, 784};
        for(int n = 0; n < 6; n++) {
            for(int i = 0; i < SR * 0.1; i++) {
                double t = (double)i / SR;
                double env = exp(-t * 8.0) * (1.0 - exp(-t * 30.0));
                double s = 0.4 * pulseWave(t * notes[n], 0.5) +
                           0.3 * triangleWave(t * notes[n] * 2) +
                           0.3 * sawtoothWave(t * notes[n] * 0.5);
                samples.push_back((sf::Int16)(2500 * s * env));
            }
        }
        // Tail reverb (0.2s)
        for(int i = 0; i < SR * 0.2; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 5.0);
            double s = 0.3 * triangleWave(t * 784) + 0.2 * noiseGen();
            samples.push_back((sf::Int16)(1500 * s * env));
        }
    }
    else if (type == SOUND_PORTAL_CLOSE) {
        // 0.6s: chiusura discendente - sweep inverso + impatto
        for(int i = 0; i < SR * 0.6; i++) {
            double t = (double)i / SR;
            double freq = 600 * exp(-t * 4.0) + 80;  // discendente
            double env = exp(-t * 3.0);
            double s = 0.4 * pulseWave(t * freq, 0.3) +
                       0.3 * triangleWave(t * freq * 0.5) +
                       0.3 * noiseGen();
            samples.push_back((sf::Int16)(2200 * s * env));
        }
        // Impatto finale (0.1s)
        for(int i = 0; i < SR * 0.1; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 20.0);
            double s = 0.6 * noiseGen() + 0.4 * pulseWave(t * 50, 0.5);
            samples.push_back((sf::Int16)(3000 * s * env));
        }
    }
    else if (type == SOUND_WEAPON_PICKUP) {
        // 0.6s: caricamento fucile (click-click-clack meccanico)
        // Fase 1: click metallico secco (0.05s)
        for(int i = 0; i < SR * 0.05; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 50.0);
            double s = 0.6 * noiseGen() + 0.4 * pulseWave(t * 2000, 0.1);
            samples.push_back((sf::Int16)(2500 * s * env));
        }
        // Pausa (0.05s silenzio)
        for(int i = 0; i < SR * 0.05; i++) samples.push_back(0);
        // Fase 2: secondo click (0.05s)
        for(int i = 0; i < SR * 0.05; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 50.0);
            double s = 0.5 * noiseGen() + 0.5 * pulseWave(t * 1500, 0.1);
            samples.push_back((sf::Int16)(2200 * s * env));
        }
        // Pausa (0.05s silenzio)
        for(int i = 0; i < SR * 0.05; i++) samples.push_back(0);
        // Fase 3: clack di caricamento (0.15s) - slide meccanico grave
        for(int i = 0; i < SR * 0.15; i++) {
            double t = (double)i / SR;
            double freq = 300 - t * 800;  // sweep discendente
            if (freq < 80) freq = 80;
            double env = exp(-t * 12.0) * (1.0 - exp(-t * 30.0));
            double s = 0.4 * pulseWave(t * freq, 0.3) +
                       0.3 * sawtoothWave(t * freq * 0.5) +
                       0.3 * noiseGen();
            samples.push_back((sf::Int16)(2500 * s * env));
        }
        // Fase 4: click finale di chiusura (0.05s)
        for(int i = 0; i < SR * 0.05; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 40.0);
            double s = 0.7 * noiseGen() + 0.3 * pulseWave(t * 1800, 0.1);
            samples.push_back((sf::Int16)(2800 * s * env));
        }
        // Fase 5: tonfo basso di conferma (0.1s)
        for(int i = 0; i < SR * 0.1; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 15.0);
            double s = 0.5 * triangleWave(t * 100) + 0.3 * pulseWave(t * 50, 0.5);
            samples.push_back((sf::Int16)(2000 * s * env));
        }
    }
    else if (type == SOUND_ENEMY_EXPLODE) {
        // 0.4s: boom esplosione (noise burst + basso discendente + debris)
        for(int i = 0; i < SR * 0.4; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 6.0);
            double freq = 120 * exp(-t * 5.0) + 30;
            double s = 0.5 * noiseGen() +
                       0.3 * pulseWave(t * freq, 0.3) +
                       0.2 * sawtoothWave(t * freq * 2);
            samples.push_back((sf::Int16)(2800 * s * env));
        }
    }
    else if (type == SOUND_BLOOD_SPLAT) {
        // 0.5s: splatter gore (schizzo sangue + impatto carnoso + gocce)
        // Fase 1 (0.05s): impatto carnoso iniziale (tonfo + noise burst)
        for(int i = 0; i < SR * 0.05; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 30.0);
            double s = 0.6 * noiseGen() + 0.4 * triangleWave(t * 60);
            samples.push_back((sf::Int16)(3000 * s * env));
        }
        // Fase 2 (0.15s): schizzo liquido (sweep discendente + gorgoglio)
        for(int i = 0; i < SR * 0.15; i++) {
            double t = (double)i / SR;
            double freq = 400 * exp(-t * 6.0) + 50;
            double env = exp(-t * 8.0) * (1.0 - exp(-t * 50.0));
            // Modulazione liquida (vibrazione del schizzo)
            double mod = 1.0 + 0.4 * sin(t * 40.0);
            double s = 0.4 * sawtoothWave(t * freq * mod) +
                       0.3 * noiseGen() * exp(-t * 10.0) +
                       0.3 * triangleWave(t * freq * 0.3);
            samples.push_back((sf::Int16)(2800 * s * env));
        }
        // Fase 3 (0.1s): gocce che cadono (3 blip discendenti)
        for(int g = 0; g < 3; g++) {
            double gulpFreq = 200 - g * 50;
            for(int i = 0; i < SR * 0.03; i++) {
                double t = (double)i / SR;
                double env = exp(-t * 40.0);
                double s = 0.5 * triangleWave(t * gulpFreq) +
                           0.3 * noiseGen() * exp(-t * 60.0);
                samples.push_back((sf::Int16)(1800 * s * env));
            }
            // Pausa breve tra le gocce
            for(int i = 0; i < SR * 0.015; i++) samples.push_back(0);
        }
        // Fase 4 (0.05s): dissolvenza bassa (pozza che si forma)
        for(int i = 0; i < SR * 0.05; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 15.0);
            double s = 0.4 * triangleWave(t * 40) + 0.2 * noiseGen();
            samples.push_back((sf::Int16)(1500 * s * env));
        }
    }
    else if (type == SOUND_MINE_BOUNCE) {
        // 0.12s: boing metallico (sweep discendente rapido + noise)
        for(int i = 0; i < SR * 0.12; i++) {
            double t = (double)i / SR;
            double freq = 800 * exp(-t * 8.0) + 200;
            double env = exp(-t * 18.0) * (1.0 - exp(-t * 50.0));
            double s = 0.5 * pulseWave(t * freq, 0.3) +
                       0.3 * triangleWave(t * freq * 1.5) +
                       0.2 * noiseGen();
            samples.push_back((sf::Int16)(2200 * s * env));
        }
    }
    else if (type == SOUND_POTION_DRINK) {
        // 0.7s: glug-glug (ingestione liquido)
        // 3 fasi: glug basso, pausa, glug piu' acuto, pausa, deglutizione
        for (int gulp = 0; gulp < 3; gulp++) {
            double gulpFreq = 120 + gulp * 40;  // ogni glug piu' acuto
            double gulpDur = 0.12;
            for (int i = 0; i < SR * gulpDur; i++) {
                double t = (double)i / SR;
                double env = exp(-t * 10.0) * (1.0 - exp(-t * 40.0));
                // Modulazione: vibrazione della gola
                double mod = 1.0 + 0.3 * sin(t * 30.0);
                double s = 0.4 * triangleWave(t * gulpFreq * mod) +
                           0.3 * sawtoothWave(t * gulpFreq * 0.7 * mod) +
                           0.2 * noiseGen() * exp(-t * 15.0);  // bubbles
                samples.push_back((sf::Int16)(2200 * s * env));
            }
            // Pausa breve tra un glug e l'altro
            for (int i = 0; i < SR * 0.06; i++) samples.push_back(0);
        }
        // Deglutizione finale (tonfo basso)
        for (int i = 0; i < SR * 0.1; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 15.0);
            double s = 0.5 * triangleWave(t * 90) + 0.3 * pulseWave(t * 60, 0.5);
            samples.push_back((sf::Int16)(1800 * s * env));
        }
    }
    else if (type == SOUND_LIGHTNING) {
        // 0.4s: fulmine (crack elettrico + boom + tuono)
        // Fase 1 (0.02s): crack iniziale (noise burst acuto)
        for(int i = 0; i < SR * 0.02; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 80.0);
            double s = noiseGen();
            samples.push_back((sf::Int16)(3200 * s * env));
        }
        // Fase 2 (0.1s): scarica elettrica (sweep acuto discendente + buzz)
        for(int i = 0; i < SR * 0.1; i++) {
            double t = (double)i / SR;
            double freq = 3000 * exp(-t * 15.0) + 200;
            double env = exp(-t * 12.0);
            double s = 0.4 * pulseWave(t * freq, 0.1) +
                       0.3 * noiseGen() * exp(-t * 10.0) +
                       0.3 * sawtoothWave(t * freq * 0.3);
            samples.push_back((sf::Int16)(2800 * s * env));
        }
        // Fase 3 (0.15s): boom (basso discendente)
        for(int i = 0; i < SR * 0.15; i++) {
            double t = (double)i / SR;
            double freq = 100 * exp(-t * 5.0) + 30;
            double env = exp(-t * 6.0);
            double s = 0.5 * triangleWave(t * freq) +
                       0.3 * pulseWave(t * freq, 0.3) +
                       0.2 * noiseGen();
            samples.push_back((sf::Int16)(2500 * s * env));
        }
        // Fase 4 (0.13s): tuono morente (rumore basso che sfuma)
        for(int i = 0; i < SR * 0.13; i++) {
            double t = (double)i / SR;
            double env = exp(-t * 8.0);
            double s = 0.4 * noiseGen() * (1.0 - t / 0.13) +
                       0.2 * triangleWave(t * 50);
            samples.push_back((sf::Int16)(1800 * s * env));
        }
    }
    else if (type == SOUND_SCEPTER_PICKUP) {
        // ~1.7s: "oh-oh-oh" magico, evocativo fantasy, suspense
        // Come se stesse per accadere qualcosa di epico.
        //
        // Struttura:
        //   * 3 esclamazioni "oh" discendenti (vocal-like, vibrato)
        //   - Frequenze: 392 (Sol4) -> 349 (Fa4) -> 311 (Eb4)
        //     Intervallo calante = senso di suspense / attesa
        //   - Forma d'onda: triangle (timbro vocale) + pulse filter (formanti)
        //   - Attack morbido (non percussivo): onset "oh" con exe(-t*k)
        //   - Vibrato 5.5 Hz (LFO sulla frequenza, depth 8 cent ~ +-=6Hz)
        //   * Layer shimmer magico: pulse 1200-2000Hz sweep + noise filtered
        //   * Sottofondo pad: saw 130 Hz (Do3 minore) per mood fantasy
        //   * Finale: accordo sospeso (tritono Do-Fa#) che NON risolve
        //     - Do3 (130.8) + Fa#3 (185.0) = intervallo instabile, tensione
        //     - Fade out lento (2.5s exp) per "lasciare appesi"

        const int totalDur = (int)(SR * 1.7);
        // Pad di fondo (Do minore basso, sawtooth tremolato)
        // Lo generiamo in un buffer separato e lo sommiamo
        std::vector<double> pad(totalDur, 0.0);
        for (int i = 0; i < totalDur; i++) {
            double t = (double)i / SR;
            double env = (1.0 - exp(-t * 4.0)) * exp(-t * 1.4);  // attacco lento, decadimento lungo
            // Tritono sospeso: Do3 (130.81) + Fa#3 (185.00)
            double do3  = sawtoothWave(t * 130.81);
            double fis3 = sawtoothWave(t * 185.00);
            // Tremolo lento (LFO 3 Hz)
            double trem = 0.85 + 0.15 * sin(t * 2.0 * M_PI * 3.0);
            pad[i] = 0.18 * (do3 + 0.8 * fis3) * env * trem;
        }

        // 3 esclamazioni "oh" discendenti
        // Posizionamento nel tempo: 0.0-0.35, 0.4-0.75, 0.8-1.2 secondi
        const double ohStart[3]  = {0.00, 0.40, 0.80};
        const double ohDur[3]    = {0.35, 0.35, 0.40};
        const double ohFreq[3]   = {392.0, 349.23, 311.13};  // Sol4, Fa4, Eb4
        // Per ogni "oh", buffer locale con attacco morbido + decadimento
        std::vector<double> ohLayer(totalDur, 0.0);
        for (int k = 0; k < 3; k++) {
            int start = (int)(SR * ohStart[k]);
            int len   = (int)(SR * ohDur[k]);
            for (int i = 0; i < len && (start + i) < totalDur; i++) {
                double t = (double)i / SR;
                // Envelope "oh": attack 0.06s + sustain + release 0.15s
                double attack  = 1.0 - exp(-t * 30.0);
                double release = exp(-t * 6.0);
                double env = attack * release;
                // Vibrato: LFO 5.5 Hz, depth 6 Hz
                double vib = 6.0 * sin(t * 2.0 * M_PI * 5.5);
                double f = ohFreq[k] + vib;
                // Timbro vocale: triangle (fondamentale) + pulse 2a/3a armonica (formanti)
                double fundamental = 0.55 * triangleWave(t * f);
                double formant1    = 0.20 * pulseWave(t * f * 2.0, 0.35);  // 2a armonica
                double formant2    = 0.12 * pulseWave(t * f * 3.0, 0.25);  // 3a armonica
                // Filtro approssimato: attenua in base alla fase "oh"
                // Il "oh" ha apertura->chiusura: attenua le alte verso la fine
                double openFilter = exp(-t * 4.0);  // 1 all'inizio, 0.x alla fine
                double s = fundamental + formant1 * openFilter + formant2 * openFilter;
                ohLayer[start + i] += 0.55 * s * env;
            }
        }

        // Layer shimmer magico: sweep pulse acuto + noise filtered
        std::vector<double> shimmer(totalDur, 0.0);
        for (int i = 0; i < totalDur; i++) {
            double t = (double)i / SR;
            double env = (1.0 - exp(-t * 8.0)) * exp(-t * 1.8);
            // Sweep: 1200 -> 2000 Hz in 1.7s
            double freq = 1200.0 + 800.0 * (t / 1.7);
            // Pulse molto duty-cycle stretto (0.1) = timbro "magico/cristallino"
            double shimmerWave = 0.18 * pulseWave(t * freq, 0.1);
            // Noise "scintillio" attenuato e modulato
            double sparkle = 0.08 * noiseGen() * (0.5 + 0.5 * sin(t * 2.0 * M_PI * 7.0));
            shimmer[i] = (shimmerWave + sparkle) * env;
        }

        // Mix finale
        for (int i = 0; i < totalDur; i++) {
            double s = pad[i] + ohLayer[i] + shimmer[i];
            // Soft clip per evitare clipping netto
            if (s > 1.0) s = 1.0 - 0.3 * (1.0 - 1.0 / s);
            if (s < -1.0) s = -1.0 + 0.3 * (1.0 + 1.0 / s);
            samples.push_back((sf::Int16)(2600 * s));
        }
    }

    if(!samples.empty()) {
        buffers[idx].loadFromSamples(&samples[0], samples.size(), 1, SR);
    }
    // Riproduci dal buffer (pre-generato o appena sintetizzato)
    if(buffers[idx].getSampleCount() > 0) {
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
    // --- Tracce epiche dedicate (jingle calice/scettro + menu') ---
    // Sono DISTINTE dalle musiche di gioco: scale, BPM e orchestrazione
    // dedicati, non condividono pattern con le tracce dei livelli.
    if (trackIdx == TRACK_EPIC_CHALICE) { generateEpicChaliceTrack(); return; }
    if (trackIdx == TRACK_EPIC_SCEPTER) { generateEpicScepterTrack(); return; }
    if (trackIdx == TRACK_MENU)         { generateMenuTrack();         return; }

    // --- Tracce di gioco (livelli 0..3, boss 4, portale 5) ---
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
    else if (trackIdx == 5) { root = 110.0; harmonic = true; tempo = 70.0; }  // La minore armonica (portale: lento, mistico)
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
    // Per il portale: pattern molto morbido, mistico, ethereal
    if (trackIdx == 5) {
        // Kick solo sul beat 1, niente snare, hihat raro
        for(int i = 0; i < 16; i++) { kick[i] = 0; snare[i] = 0; hihat[i] = 0; }
        kick[0] = 1;  // solo sul beat 1
        hihat[0] = 1; hihat[8] = 1;  // ogni 2 beat
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

// ===========================================================================
// JINGLE EPICO CALICE (trackIdx == TRACK_EPIC_CHALICE = 6)
//
// Fanfara eroica "dorata" per il pickup del calice d'oro. ~6 secondi,
// MAESTOSA e BRILLANTE: accordi MAGGIORI luminosi, orchestrazione a 4 voci.
//
// Struttura (durata totale ~6.0s):
//   * Intro (0.0-0.6s): rullo di timpani (kick + basso discendente)
//   * Fanfara 1 (0.6-2.4s): arpeggio Do magg. -> Sol magg. -> Do magg. ottava
//     - Lead pulse 50% duty (timbro brass-band) + arpeggio pulse 25%
//     - Pad sawtooth ampio per riempire il mid-range
//   * Climax (2.4-4.2s): accordo pieno Do magg. (Do-Mi-Sol-Do) con
//     rullante + charleston 16esimi, accordo maestoso "vittorioso"
//   * Outro (4.2-6.0s): risoluzione trionfale, accordo finale tenuto,
//     diminuendo (fade out) e piatto finale
//
// Distinta da:
//   - musiche di gioco (che sono in scala MINORE, mood dungeon)
//   - jingle scettro (che e' MISTICO/ARCANO con tritono sospeso)
// ===========================================================================
void AudioManager::generateEpicChaliceTrack() {
    std::vector<sf::Int16> samples;
    const double dur = 6.0;  // 6 secondi totali
    const int totalSamples = (int)(SR * dur);

    // Scala Do MAGGIORE: Do-Re-Mi-Fa-Sol-La-Si (intervalli 0,2,4,5,7,9,11)
    // La radice e' Do3 = 130.81 Hz. Brilliante, "dorata", eroica.
    const double do3 = 130.81;
    const double sol3 = 196.00;
    const double do4 = 261.63, mi4 = 329.63, sol4 = 392.00, do5 = 523.25;

    // 4 fasi temporali per definire l'arrangiamento
    auto phaseOf = [](double t) -> int {
        if (t < 0.6)  return 0;  // intro
        if (t < 2.4)  return 1;  // fanfara 1
        if (t < 4.2)  return 2;  // climax
        return 3;                // outro
    };

    for (int i = 0; i < totalSamples; i++) {
        double t = (double)i / SR;
        int phase = phaseOf(t);
        double sample = 0.0;

        // --- Rullo di timpani (intro + climax) ---
        // Kick ogni 0.15s in intro, ogni 0.3s in climax
        bool kickHit = false;
        if (phase == 0) {
            double local = fmod(t, 0.15);
            if (local < 0.04) kickHit = true;
        } else if (phase == 2) {
            double local = fmod(t - 2.4, 0.3);
            if (local < 0.05) kickHit = true;
        }
        if (kickHit) {
            double local = fmod(t, phase == 0 ? 0.15 : 0.3);
            double env = exp(-local * 25.0);
            sample += 2200 * sin(2 * M_PI * 50 * local) * env;
        }

        // --- Basso triangolare (Do pedal tutta la traccia) ---
        // Do2 (65.4 Hz) profondo per dare maestosita'
        if (phase >= 1) {
            double bEnv = (1.0 - exp(-t * 2.0)) * exp(-(t - 4.0 > 0 ? (t - 4.0) : 0) * 1.5);
            if (phase == 3) bEnv = exp(-(t - 4.2) * 1.5) * (1.0 - exp(-(t - 4.2) * 5.0));
            sample += 1800 * triangleWave(t * 65.41) * bEnv * 0.7;
        }

        // --- Lead pulse (brass-band) ---
        // Fanfara: arpeggio Do-Sol-Mi-Sol-Do-Mi-Sol-Do (6 note in 1.8s)
        if (phase == 1) {
            // 6 note in 1.8s = 0.3s per nota
            int noteIdx = (int)((t - 0.6) / 0.3);
            if (noteIdx < 0) noteIdx = 0;
            if (noteIdx > 5) noteIdx = 5;
            // Pattern: Do4, Sol4, Mi4, Sol4, Do5, Mi4
            double notes[] = {do4, sol4, mi4, sol4, do5, mi4};
            double freq = notes[noteIdx];
            double local = fmod(t - 0.6, 0.3);
            double attack = 1.0 - exp(-local * 30.0);
            double release = exp(-local * 5.0);
            double env = attack * release;
            // Brass-like: pulse 50% + 2a armonica (ottava)
            double wave = 0.6 * pulseWave(t * freq, 0.5) + 0.4 * pulseWave(t * freq * 2, 0.5);
            sample += 1400 * wave * env;
        }
        // Climax: accordo pieno Do magg. (Do-Mi-Sol-Do)
        if (phase == 2) {
            double chord[] = {do4, mi4, sol4, do5};
            double wave = 0.0;
            for (int n = 0; n < 4; n++) {
                wave += 0.25 * pulseWave(t * chord[n], 0.5);
            }
            double local = t - 2.4;
            double env = (1.0 - exp(-local * 4.0)) * exp(-local * 0.5);
            sample += 1600 * wave * env;
        }
        // Outro: accordo Do magg. tenuto (Do3+Sol3+Mi4+Do5) con fade
        if (phase == 3) {
            double local = t - 4.2;
            double chord[] = {do3, sol3, mi4, do5};
            double wave = 0.0;
            for (int n = 0; n < 4; n++) {
                wave += 0.25 * sawtoothWave(t * chord[n]);
            }
            double env = exp(-local * 1.5) * (1.0 - exp(-local * 5.0));
            sample += 1400 * wave * env;
        }

        // --- Pad sawtooth ampio (chorus fill) ---
        // Riempie il mid-range con un pad caldo in fase climax e outro.
        if (phase == 2 || phase == 3) {
            double padWave = 0.5 * sawtoothWave(t * do4) +
                             0.5 * sawtoothWave(t * sol4);
            double env = (phase == 2)
                ? (1.0 - exp(-(t - 2.4) * 3.0))
                : exp(-(t - 4.2) * 1.0);
            sample += 700 * padWave * env * 0.6;
        }

        // --- Arpeggio pulse 25% (cristallino, fase 1) ---
        if (phase == 1) {
            // 8 note veloci in 1.8s = 0.225s per nota
            int arpIdx = (int)((t - 0.6) / 0.225) % 4;
            double arpNotes[] = {do5, sol4, mi4, sol4};
            double freq = arpNotes[arpIdx];
            double local = fmod(t - 0.6, 0.225);
            double env = exp(-local * 12.0);
            sample += 800 * pulseWave(t * freq, 0.25) * env;
        }

        // --- Rullante (snare) in climax ogni 0.6s ---
        if (phase == 2) {
            double local = fmod(t - 2.4, 0.6);
            if (local < 0.05) {
                double env = exp(-local * 18.0);
                sample += 800 * noiseGen() * env;
            }
        }

        // --- Charleston 16esimi in climax ---
        if (phase == 2) {
            double local = fmod(t - 2.4, 0.15);
            if (local < 0.02) {
                double env = exp(-local * 80.0);
                sample += 250 * noiseGen() * env * 0.4;
            }
        }

        // --- Piatto finale (crash noise) a 4.2s ---
        if (t > 4.2 && t < 4.6) {
            double local = t - 4.2;
            double env = exp(-local * 4.0);
            sample += 600 * noiseGen() * env * 0.5;
        }

        // Clamp
        if (sample > 32000) sample = 32000;
        if (sample < -32000) sample = -32000;
        samples.push_back((sf::Int16)sample);
    }

    if (!samples.empty()) {
        musicBuffers[TRACK_EPIC_CHALICE].loadFromSamples(&samples[0],
            samples.size(), 1, SR);
    }
}

// ===========================================================================
// JINGLE EPICO SCETTRO (trackIdx == TRACK_EPIC_SCEPTER = 7)
//
// Jingle magico-arcano per il pickup dello scettro. ~7 secondi,
// MISTICO e TESO: tritono sospeso Do-Fa#, shimmer acuto, arpeggi veloci.
//
// Struttura (durata totale ~7.0s):
//   * Intro (0.0-1.0s): pad profondo saw (Fa# basso) + shimmer cristallino
//   * Fase magica (1.0-3.5s): arpeggi veloci (Do-Fa#-Do-Fa#) su tritono
//     - Pulse 12.5% (timbro cristallino) + lead triangle
//   * Tensione (3.5-5.5s): accordo sospeso Do3 + Fa#3 (tritono = diavolo
//     in musica), basso profondo, shimmer acuto che sale
//   * Risoluzione parziale (5.5-7.0s): scende verso Do basso, fade out
//     lento, NON risolve completamente (lascia suspense)
//
// Distinta da:
//   - musiche di gioco (che usano scale minori classiche, non tritono)
//   - jingle calice (che e' MAGGIORE, eroico, dorato)
// ===========================================================================
void AudioManager::generateEpicScepterTrack() {
    std::vector<sf::Int16> samples;
    const double dur = 7.0;  // 7 secondi
    const int totalSamples = (int)(SR * dur);

    // Tritono sospeso: Do3 (130.81) + Fa#3 (185.00)
    // Intervallo instabile che NON risolve = tensione magica
    const double do3  = 130.81;
    const double fis3 = 185.00;  // Fa#3 (tritono sopra Do)
    const double do4  = 261.63;
    const double fis4 = 369.99;  // Fa#4
    const double do5  = 523.25;

    auto phaseOf = [](double t) -> int {
        if (t < 1.0)  return 0;  // intro
        if (t < 3.5)  return 1;  // fase magica (arpeggi)
        if (t < 5.5)  return 2;  // tensione
        return 3;                // risoluzione parziale
    };

    for (int i = 0; i < totalSamples; i++) {
        double t = (double)i / SR;
        int phase = phaseOf(t);
        double sample = 0.0;

        // --- Pad sawtooth profondo (Do3 + Fa#3 tritono) ---
        // Presente tutta la traccia, e' il "tappeto" mistico.
        {
            double env;
            if (phase == 0) env = (1.0 - exp(-t * 3.0));
            else if (phase == 3) env = exp(-(t - 5.5) * 1.2);
            else env = 1.0;
            // Tremolo lento LFO 3 Hz
            double trem = 0.85 + 0.15 * sin(t * 2.0 * M_PI * 3.0);
            double padWave = 0.5 * sawtoothWave(t * do3) +
                             0.5 * sawtoothWave(t * fis3);
            sample += 900 * padWave * env * trem;
        }

        // --- Shimmer acuto (Fa#5 sweep up) ---
        // Sweep da 1200 Hz a 2400 Hz (Fa#5 ~ 740 Hz, ma usiamo sweep armonico)
        {
            double sweepFreq = 1200.0 + 1200.0 * (t / dur);
            double env = (1.0 - exp(-t * 6.0)) * exp(-t * 0.5);
            double shimmer = 0.18 * pulseWave(t * sweepFreq, 0.1);
            // Modulazione ampio per "scintillio" magico
            double sparkle = 0.10 * noiseGen() *
                             (0.5 + 0.5 * sin(t * 2.0 * M_PI * 7.0));
            sample += 1000.0 * (shimmer + sparkle) * env;
        }

        // --- Arpeggi cristallini (fase magica) ---
        // Arpeggio veloce Do4-Fa#4-Do5-Fa#4 (8 note in 0.4s = 0.05s/nota)
        if (phase == 1) {
            int arpIdx = (int)((t - 1.0) / 0.05) % 4;
            double arpNotes[] = {do4, fis4, do5, fis4};
            double freq = arpNotes[arpIdx];
            double local = fmod(t - 1.0, 0.05);
            double env = exp(-local * 30.0);
            sample += 1200 * pulseWave(t * freq, 0.125) * env;
        }

        // --- Lead triangle (melodia misteriosa, fase 1-2) ---
        // Melodia lenta su Do4-Fa#4-Do5 (intervallo tritono)
        if (phase == 1 || phase == 2) {
            double local = (phase == 1) ? (t - 1.0) : (t - 3.5);
            int noteIdx;
            if (phase == 1) {
                noteIdx = (int)(local / 0.6) % 3;
            } else {
                noteIdx = 2 - (int)((local) / 0.7);
                if (noteIdx < 0) noteIdx = 0;
            }
            double notes[] = {do4, fis4, do5};
            double freq = notes[noteIdx % 3];
            double noteLocal = (phase == 1) ? fmod(local, 0.6) : fmod(local, 0.7);
            double attack = 1.0 - exp(-noteLocal * 8.0);
            double release = exp(-noteLocal * 3.0);
            double env = attack * release;
            // Vibrato 5.5 Hz depth 4 Hz
            double vib = 4.0 * sin(t * 2.0 * M_PI * 5.5);
            sample += 1200 * triangleWave(t * (freq + vib)) * env;
        }

        // --- Basso profondo (Do2 = 65.4 Hz) in tensione e risoluzione ---
        if (phase >= 2) {
            double env = (phase == 2)
                ? (1.0 - exp(-(t - 3.5) * 3.0))
                : (1.0 - exp(-(t - 5.5) * 3.0)) * exp(-(t - 5.5) * 0.8);
            double bassWave = triangleWave(t * 65.41);
            sample += 1500 * bassWave * env * 0.7;
        }

        // --- Tensione: accordo Do3+Fa#3 (tritono) piu' intenso ---
        if (phase == 2) {
            double local = t - 3.5;
            double env = (1.0 - exp(-local * 2.0)) * exp(-local * 0.3);
            double wave = 0.5 * sawtoothWave(t * do3) +
                          0.5 * sawtoothWave(t * fis3);
            sample += 800 * wave * env;
        }

        // --- Risoluzione parziale: scende verso Do basso, NON risolve ---
        if (phase == 3) {
            double local = t - 5.5;
            double env = exp(-local * 1.0) * (1.0 - exp(-local * 4.0));
            // Do basso + Mi basso (terza minore, NON risolve su Do magg.)
            // lascia suspense: accordo Do3 + Eb3 (mi bemolle)
            double eb3 = 155.56;
            double wave = 0.5 * sawtoothWave(t * do3) +
                          0.5 * sawtoothWave(t * eb3);
            sample += 1000 * wave * env * 0.7;
        }

        // --- Pulsazione magica (LFO 1 Hz sul volume) ---
        // Da un senso di "respiro magico"
        {
            double pulse = 0.85 + 0.15 * sin(t * 2.0 * M_PI * 1.0);
            sample *= pulse;
        }

        // Clamp
        if (sample > 32000) sample = 32000;
        if (sample < -32000) sample = -32000;
        samples.push_back((sf::Int16)sample);
    }

    if (!samples.empty()) {
        musicBuffers[TRACK_EPIC_SCEPTER].loadFromSamples(&samples[0],
            samples.size(), 1, SR);
    }
}

// ===========================================================================
// MUSICA MENU' PRINCIPALE (trackIdx == TRACK_MENU = 8)
//
// Corale fantasy drammatica, eterea, in LOOP (per il menu' principale).
// ~80 BPM, scala minore armonica (Re minore armonica), pad sawtooth ampio,
// lead pulse lento, arpeggi cristallini, basso triangolare profondo.
//
// DISTINTA da tutte le musiche di gioco:
//   - Livelli 0..3: 100-110 BPM, scale minori di Re/Do/Si/Mi
//   - Boss: 130 BPM, Fa minore armonica (molto aggressivo)
//   - Portale: 70 BPM, La minore armonica (molto lento, mistico)
//   - Menu': 80 BPM, Re minore armonica (corale, drammatico, etereo),
//     orchestrazione DIFFERENTE (piu' pad, meno percussioni, niente charleston)
//   - Pattern drum minimalista (kick ogni 2 beat, niente snare) per dare
//     un senso di "attesa solenne" tipica del menu' principale.
// ===========================================================================
void AudioManager::generateMenuTrack() {
    std::vector<sf::Int16> samples;
    // 80 BPM, 32 battute, 4 beat/battuta, 4 sedicesimi/beat
    const double tempo = 80.0;
    const double beatDur = 60.0 / tempo;       // 0.75s
    const double sixteenthDur = beatDur / 4.0; // 0.1875s
    const int samplesPerSixteenth = (int)(SR * sixteenthDur);
    const int numBars = 32;

    // Re minore armonica: intervalli 0,2,3,5,7,8,11
    const double root = 146.83;  // Re3
    int har[] = {0, 2, 3, 5, 7, 8, 11};
    double scale[7];
    for (int i = 0; i < 7; i++) scale[i] = root * pow(2.0, har[i] / 12.0);

    // Progressione armonica piu' "eterea": i, VII, VI, V (minore armonica)
    // Gradi: 0, 6, 5, 4
    int prog[] = {0, 6, 5, 4};

    // Pattern drum MINIMALISTA per menu' (solenne, attesa):
    //   kick solo sul beat 1 di ogni battuta (1 su 16)
    bool kick[16]  = {1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0};

    for (int bar = 0; bar < numBars; ++bar) {
        double chordRoot = scale[prog[bar % 4]];
        // In menu' non usiamo il concetto di "chorus" come nei livelli:
        // tutta la traccia e' un corale costante con sviluppi minimi.

        for (int s = 0; s < 16; ++s) {
            // Lead: nota lunga (1 per beat, non arpeggio come nei livelli)
            double leadFreq = 0;
            if (s == 0) leadFreq = chordRoot * 2;
            else if (s == 8) leadFreq = chordRoot * pow(2, 7.0/12) * 2;  // 5th
            // In menu', aggiungi anche terza (3a) sulla seconda meta'
            if (s == 4) leadFreq = chordRoot * pow(2, 3.0/12) * 2;  // 3rd
            if (s == 12) leadFreq = chordRoot * 4;  // ottava

            for (int i = 0; i < samplesPerSixteenth; ++i) {
                double t = (double)i / SR;
                double sample = 0.0;

                // --- Drums minimalisti ---
                if (kick[s] && i < samplesPerSixteenth * 0.3) {
                    double env = exp(-t * 18.0);
                    sample += 1800 * sin(2 * M_PI * 45 * t) * env;
                }
                // (snare e hihat sono sempre 0 in menu')

                // --- Basso triangolare (root ottava sotto, lungo) ---
                if (s == 0 || s == 8) {
                    double bPhase = t * (chordRoot / 2.0);
                    double bEnv = exp(-t * 2.0) * 0.7;  // decay lento
                    sample += 1500 * triangleWave(bPhase) * bEnv;
                }

                // --- Lead pulse (melodia corale, duty 50%) ---
                if (leadFreq > 0) {
                    double lPhase = t * leadFreq;
                    double lWave = pulseWave(lPhase, 0.5);
                    // Lead piu' caldo: aggiungi 2a armonica
                    lWave = 0.7 * lWave + 0.3 * pulseWave(lPhase * 2, 0.5);
                    double lEnv = exp(-t * 2.5);
                    sample += 1200 * lWave * lEnv;
                }

                // --- Pad sawtooth AMPIO (sempre presente) ---
                // E' la firma del menu': un tappeto di saw che da' il
                // senso "etereo, corale". Molto piu' prominente dei livelli.
                {
                    double pWave = 0.35 * sawtoothWave(t * chordRoot) +
                                   0.35 * sawtoothWave(t * chordRoot * pow(2, 3.0/12)) +  // 3rd
                                   0.30 * sawtoothWave(t * chordRoot * pow(2, 7.0/12));  // 5th
                    // Pad con attack lento (corale)
                    double pEnv = (1.0 - exp(-t * 1.5)) * 0.8;
                    sample += 800 * pWave * pEnv;
                }

                // --- Arpeggio cristallino lento (ogni 2 beat) ---
                // Solo sugli odd bar (1, 3, 5...) per non saturare
                if (bar % 2 == 1 && (s == 4 || s == 12)) {
                    int arpNote = (s == 4) ? 0 : 2;
                    double arpFreq = chordRoot * pow(2, (4 + arpNote * 2) / 12.0) * 2;
                    double aWave = pulseWave(t * arpFreq, 0.125);
                    double aEnv = exp(-t * 5.0);
                    sample += 500 * aWave * aEnv;
                }

                // --- Shimmer acuto (cristallino, lento, per "etereo") ---
                // Modulazione molto lenta per non disturbare
                {
                    double shFreq = chordRoot * 8;  // 3 ottave sopra
                    double shWave = pulseWave(t * shFreq, 0.1) * 0.15;
                    double shEnv = 0.3 + 0.2 * sin(t * 2 * M_PI * 0.5);
                    sample += 200 * shWave * shEnv;
                }

                // Clamp
                if (sample > 32000) sample = 32000;
                if (sample < -32000) sample = -32000;

                samples.push_back((sf::Int16)sample);
            }
        }
    }

    if (!samples.empty()) {
        musicBuffers[TRACK_MENU].loadFromSamples(&samples[0],
            samples.size(), 1, SR);
    }
}
