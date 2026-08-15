#include "AudioManager.h"
#include <cmath>
#include <cstdlib>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

AudioManager::AudioManager() {
    buffers.resize(11);
    sounds.resize(15); // Pool di suoni più grande
    for(auto& s : sounds) s.setVolume(60);
    generateMusic();
}

void AudioManager::generateMusic() {
    // Genera una traccia fantasy loopabile
    int sr = 44100;
    double tempo = 120.0; // BPM
    double beat = 60.0 / tempo;
    
    // Melodia ( scala minore ) - A minor
    int melody[] = {220, 261, 329, 440, 329, 261, 220, 0, 261, 329, 440, 523, 440, 329, 261, 0};
    int bass[] = {110, 110, 130, 130, 146, 146, 164, 164}; // Bass line
    
    for(int n=0; n<16; n++) {
        double freq = melody[n];
        double bFreq = bass[n % 8];
        for(int i=0; i<sr*beat*0.5; i++) { // 1/8 notes
            double t = (double)i / sr;
            double env = exp(-t * 4.0);
            if(freq > 0) {
                double wave = 0.5 * sin(2*M_PI*freq*t) + 0.3 * sin(2*M_PI*freq*2*t) + 0.2 * (sin(2*M_PI*freq*4*t) > 0 ? 1 : -1);
                musicSamples.push_back((sf::Int16)(1500 * wave * env));
            } else {
                musicSamples.push_back(0);
            }
        }
        // Aggiungi basso
        if(bFreq > 0) {
            for(int i=0; i<sr*beat*0.5; i++) {
                double t = (double)i / sr;
                double wave = sin(2*M_PI*bFreq*t) + 0.5 * sin(2*M_PI*bFreq*0.5*t);
                if(n < 16) musicSamples[i + n*sr*(int)(beat*0.5)] += (sf::Int16)(2000 * wave * 0.8); // Mix
            }
        }
    }
    
    if(!musicSamples.empty()) {
        musicBuffer.loadFromSamples(&musicSamples[0], musicSamples.size(), 1, sr);
        music.setBuffer(musicBuffer);
        music.setLoop(true);
        music.setVolume(40);
    }
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
        // Suono magico di cristallo
        int notes[] = {1046, 1318, 1568, 2093};
        for(int n=0; n<4; n++) {
            for(int i=0; i<sr*0.08; i++) {
                double t = (double)i / sr;
                double env = exp(-t * 20.0);
                samples.push_back((sf::Int16)(2500 * (sin(2*M_PI*notes[n]*t) + 0.5*sin(2*M_PI*notes[n]*2*t)) * env));
            }
        }
    } else if (type == SOUND_ENEMY_DEATH) {
        // Ruggito/esplosione
        for(int i=0; i<sr*0.4; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 8.0);
            double freq = 300 * exp(-t * 8.0) + 50;
            samples.push_back((sf::Int16)(2500 * (0.5 * sin(2*M_PI*freq*t) + 0.4 * (rand()%2000-1000)/1000.0) * env));
        }
    } else if (type == SOUND_LOSE_LIFE) {
        // Cuore che salta un battito
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
        // Suono generico
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