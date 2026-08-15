#include "AudioManager.h"
#include <cmath>
#include <vector>

AudioManager::AudioManager() {
    buffers.resize(11);
    sounds.resize(10); // Pool di suoni
    for(auto& s : sounds) s.setVolume(50);
}

int AudioManager::findFreeSound() {
    for(size_t i=0; i<sounds.size(); ++i) {
        if(sounds[i].getStatus() != sf::Sound::Playing) return i;
    }
    return 0; // Overwrite se tutti occupati
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
                samples.push_back((sf::Int16)(2000 * sin(2 * M_PI * notes[n] * t) * exp(-t * 20.0)));
            }
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
            double env = exp(-t * 15.0);
            samples.push_back((sf::Int16)(2000 * sin(2 * M_PI * 400 * t) * env));
        }
    }
    
    if(!samples.empty()) {
        buffers[type].loadFromSamples(&samples[0], samples.size(), 1, sr);
        int idx = findFreeSound();
        sounds[idx].setBuffer(buffers[type]);
        sounds[idx].play();
    }
}