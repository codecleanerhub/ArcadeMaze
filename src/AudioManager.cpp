#include "AudioManager.h"
#include <cmath>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

AudioManager::AudioManager() : device(0) {
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) return;
    spec.freq = 44100;
    spec.format = AUDIO_S16SYS;
    spec.channels = 1;
    spec.samples = 1024;
    spec.callback = nullptr;
    spec.userdata = nullptr;
    device = SDL_OpenAudioDevice(nullptr, 0, &spec, nullptr, 0);
    if (device > 0) SDL_PauseAudioDevice(device, 0);
}

AudioManager::~AudioManager() {
    if (device > 0) SDL_CloseAudioDevice(device);
}

Sint16 noise(double amplitude) {
    return (Sint16)((rand() % 4000 - 2000) * amplitude);
}

void AudioManager::playSound(SoundType type) {
    if (device == 0) return;
    std::vector<Sint16> buffer;
    int sr = spec.freq;
    
    if (type == SOUND_PISTOL) {
        for(int i=0; i<sr*0.1; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 30.0);
            double wave = 0.7 * sin(2 * M_PI * 900 * t) + 0.3 * (rand() % 2000 - 1000)/2000.0;
            buffer.push_back((Sint16)(3000 * wave * env));
        }
    } else if (type == SOUND_SHOTGUN) {
        for(int i=0; i<sr*0.2; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 25.0);
            buffer.push_back((Sint16)(500 * sin(2 * M_PI * 120 * t) * env + noise(1.0) * env));
        }
    } else if (type == SOUND_ROCKET) {
        for(int i=0; i<sr*0.4; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 8.0);
            buffer.push_back((Sint16)(noise(0.8) * env + 800 * sin(2 * M_PI * 200 * t) * env));
        }
    } else if (type == SOUND_LASER) {
        for(int i=0; i<sr*0.15; i++) {
            double t = (double)i / sr;
            double freq = 1200 - i * 15;
            double env = exp(-t * 35.0);
            buffer.push_back((Sint16)(2500 * sin(2 * M_PI * freq * t) * env));
        }
    } else if (type == SOUND_TREASURE) {
        int notes[] = {1046, 1318, 1568};
        for(int n=0; n<3; n++) {
            for(int i=0; i<sr*0.1; i++) {
                double t = (double)i / sr;
                double env = exp(-t * 15.0);
                buffer.push_back((Sint16)(2000 * sin(2 * M_PI * notes[n] * t) * env));
            }
        }
    } else if (type == SOUND_ENEMY_DEATH) {
        for(int i=0; i<sr*0.3; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 15.0);
            buffer.push_back((Sint16)(1500 * sin(2 * M_PI * (400 - i*50) * t) * env + noise(0.3) * env));
        }
    } else if (type == SOUND_LOSE_LIFE) {
        for(int i=0; i<sr*0.6; i++) {
            double t = (double)i / sr;
            double freq = 150 - i * 0.1;
            buffer.push_back((Sint16)(3000 * (sin(2 * M_PI * freq * t) > 0 ? 1 : -1)));
        }
    } else if (type == SOUND_WIN) {
        int notes[] = {523, 659, 784, 1046};
        for(int n=0; n<4; n++) {
            for(int i=0; i<sr*0.2; i++) {
                double t = (double)i / sr;
                buffer.push_back((Sint16)(2000 * sin(2 * M_PI * notes[n] * t)));
            }
        }
    } else if (type == SOUND_BOSS_SHOOT) {
        for(int i=0; i<sr*0.2; i++) {
            double t = (double)i / sr;
            double freq = 300 - i*10;
            double env = exp(-t * 20.0);
            buffer.push_back((Sint16)(2000 * sin(2 * M_PI * freq * t) * env));
        }
    } else if (type == SOUND_BOSS_HIT) {
        for(int i=0; i<sr*0.1; i++) {
            buffer.push_back(noise(1.0));
        }
    } else if (type == SOUND_BOSS_DEATH) {
        for(int i=0; i<sr*1.5; i++) {
            double t = (double)i / sr;
            double env = exp(-t * 3.0);
            buffer.push_back((Sint16)(3000 * sin(2 * M_PI * (200 - i*0.1) * t) * env + noise(0.5) * env));
        }
    }
    
    if (!buffer.empty()) {
        if (SDL_GetQueuedAudioSize(device) > sr * sizeof(Sint16)) SDL_ClearQueuedAudio(device);
        SDL_QueueAudio(device, buffer.data(), buffer.size() * sizeof(Sint16));
    }
}