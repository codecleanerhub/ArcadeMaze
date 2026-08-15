#include "AudioManager.h"
#include <cmath>
#include <cstdlib>
#include <cstring>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

AudioManager::AudioManager() {
    buffers.resize(11);
    sounds.resize(20);
    for(auto& s : sounds) s.setVolume(70);
    for(int i=0; i<5; ++i) generateTrack(i);
}

double noise() { return (rand() % 2000 - 1000) / 1000.0; }

void AudioManager::generateTrack(int trackIdx) {
    int sr = 44100;
    double tempo = (trackIdx == 4) ? 100 : 120;
    double beatDur = 60.0 / tempo;
    double eighthDur = beatDur / 2.0;
    int samplesPerEighth = sr * eighthDur;

    // Scale minori per tema fantasy horror
    // Root, 2nd, 3rd, 4th, 5th, 6th, 7th
    double scale[7];
    double root;
    bool harmonic;

    if (trackIdx == 0) { // Level 1: D Natural Minor (Misterioso)
        root = 146.83; harmonic = false;
    } else if (trackIdx == 1) { // Level 2: C Harmonic Minor (Teso)
        root = 130.81; harmonic = true;
    } else if (trackIdx == 2) { // Level 3: B Natural Minor (Oscuro)
        root = 123.47; harmonic = false;
    } else if (trackIdx == 3) { // Level 4: E Harmonic Minor (Epico)
        root = 82.41; harmonic = true;
    } else { // Boss: F Harmonic Minor (Aggressivo)
        root = 87.31; harmonic = true;
        tempo = 90;
    }

    // Costruzione scala
    int intervals[] = {0, 2, 3, 5, 7, 8, 10};
    if (harmonic) intervals[6] = 11;
    for(int i=0; i<7; i++) {
        scale[i] = root * pow(2.0, intervals[i] / 12.0);
    }

    std::vector<sf::Int16> trackSamples;
    int numBars = 32;

    // Pattern Drum
    bool kick[8]  = {1, 0, 0, 1, 1, 0, 0, 0};
    bool snare[8] = {0, 0, 1, 0, 0, 0, 1, 0};
    bool hihat[8] = {1, 1, 1, 1, 1, 1, 1, 1};

    // Progressione: i, VI, III, VII (Tipica minore)
    int prog[] = {0, 5, 2, 6}; 

    for(int bar = 0; bar < numBars; ++bar) {
        int chordRoot = scale[prog[bar % 4]];
        bool isChorus = (bar >= 8 && bar <= 11) || (bar >= 16 && bar <= 19) || (bar >= 24 && bar <= 27);

        for(int i = 0; i < 8; ++i) {
            // Melodia Arpeggiata
            double freq = chordRoot;
            if(i == 0) freq = chordRoot;
            else if(i == 2) freq = chordRoot * pow(2.0, 3.0/12.0); // 4th
            else if(i == 4) freq = chordRoot * pow(2.0, 7.0/12.0); // 5th
            else if(i == 6) freq = chordRoot * 2.0; // Octave
            else continue; // Note sparse per tensione

            for(int s = 0; s < samplesPerEighth; ++s) {
                double t = (double)s / sr;
                double sample = 0.0;

                // Drums
                if (kick[i] && s < samplesPerEighth * 0.2) {
                    double env = exp(-t * 40.0);
                    sample += 3000 * sin(2*M_PI*50*t) * env;
                }
                if (snare[i] && s > samplesPerEighth * 0.1) {
                    double env = exp(-t * 15.0);
                    sample += 1500 * noise() * env;
                }
                if (hihat[i] && s % 4 == 0) {
                    double env = exp(-t * 60.0);
                    sample += 500 * noise() * env * 0.3;
                }

                // Bass (Dente di sega scuro)
                if (i == 0 || i == 4) {
                    double bPhase = t * (chordRoot/2.0);
                    double bWave = 2.0 * (bPhase - floor(0.5 + bPhase));
                    double bEnv = exp(-t * 3.0) * 0.8;
                    sample += 2500 * bWave * bEnv;
                }

                // Lead (Onda quadra fantasy)
                double mPhase = t * freq;
                double mWave = (sin(2*M_PI*mPhase) > 0 ? 1 : -1) * 0.5 + 0.5 * sin(2*M_PI*mPhase*2.0);
                double mEnv = exp(-t * 4.0);
                sample += 1200 * mWave * mEnv;

                // Pad (Sine wave per sustained drammatico)
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
    for(size_t i=0; i<sounds.size(); ++i) {
        if(sounds[i].getStatus() != sf::Sound::Playing) return i;
    }
    return 0;
}

void AudioManager::playSound(SoundType type) {
    int sr = 44100;
    std::vector<sf::Int16> samples;
    
    if (type == SOUND_PISTOL) {
        for(int i=0; i<sr*0.1; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 30.0);
            samples.push_back((sf::Int16)(3000 * (0.6 * (rand()%2000-1000)/1000.0 + 0.8 * sin(2*M_PI*80*t)) * env));
        }
    } else if (type == SOUND_SHOTGUN) {
        for(int i=0; i<sr*0.2; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 20.0);
            samples.push_back((sf::Int16)(3000 * (0.8 * (rand()%2000-1000)/1000.0 + 500 * sin(2*M_PI*60*t)) * env));
        }
    } else if (type == SOUND_TREASURE) {
        int notes[] = {1046, 1318, 1568, 2093};
        for(int n=0; n<4; n++) {
            for(int i=0; i<sr*0.08; i++) {
                double t = (double)i / sr;
                double env = exp(-t * 20.0);
                samples.push_back((sf::Int16)(2500 * (sin(2*M_PI*notes[n]*t) + 0.5*sin(2*M_PI*notes[n]*2*t)) * env));
            }
        }
    } else if (type == SOUND_ENEMY_DEATH) {
        for(int i=0; i<sr*0.4; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 8.0);
            double freq = 300 * exp(-t * 8.0) + 50;
            samples.push_back((sf::Int16)(2500 * (0.5 * sin(2*M_PI*freq*t) + 0.4 * (rand()%2000-1000)/1000.0) * env));
        }
    } else if (type == SOUND_LOSE_LIFE) {
        for(int i=0; i<sr*0.8; i++) {
            double t = (double)i / sr;
            double freq = 150 - i * 0.1;
            samples.push_back((sf::Int16)(3000 * (sin(2*M_PI*freq*t) > 0 ? 1 : -1) * exp(-t*3.0)));
        }
    } else if (type == SOUND_BOSS_DEATH) {
        for(int i=0; i<sr*2.0; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 2.0);
            samples.push_back((sf::Int16)(3000 * (sin(2*M_PI*40*t) + sin(2*M_PI*60*t)) * env + 2000 * (rand()%2000-1000)/1000.0 * env));
        }
    } else {
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