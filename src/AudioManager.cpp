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
    if (device > 0) {
        SDL_PauseAudioDevice(device, 0); // Avvia l'audio
    }
}

AudioManager::~AudioManager() {
    if (device > 0) SDL_CloseAudioDevice(device);
}

void AudioManager::playSound(SoundType type) {
    if (device == 0) return;
    
    std::vector<Sint16> buffer;
    int sr = spec.freq;
    
    if (type == SOUND_SHOOT) {
        // Suono laser acuto e rapido
        for(int i=0; i<sr*0.1; i++) {
            double freq = 800 - i*50;
            buffer.push_back((Sint16)(1500 * sin(2 * M_PI * freq * i / sr)));
        }
    } else if (type == SOUND_DOT) {
        // Tick breve
        for(int i=0; i<sr*0.04; i++) {
            buffer.push_back((Sint16)(3000 * sin(2 * M_PI * 1200 * i / sr)));
        }
    } else if (type == SOUND_ENEMY_DEATH) {
        // Rumore di esplosione (frequenza discendente)
        for(int i=0; i<sr*0.3; i++) {
            double freq = 400 - i*50;
            buffer.push_back((Sint16)(1500 * sin(2 * M_PI * freq * i / sr)));
        }
    } else if (type == SOUND_LOSE_LIFE) {
        // Suono basso e prolungato (onda quadra)
        for(int i=0; i<sr*0.5; i++) {
            double freq = 100;
            buffer.push_back((Sint16)(3000 * (sin(2 * M_PI * freq * i / sr) > 0 ? 1 : -1)));
        }
    } else if (type == SOUND_WIN) {
        // Melodia di vittoria (Do, Mi, Sol, Do ottava)
        int notes[] = {523, 659, 784, 1046};
        for(int n=0; n<4; n++) {
            for(int i=0; i<sr*0.2; i++) {
                buffer.push_back((Sint16)(2000 * sin(2 * M_PI * notes[n] * i / sr)));
            }
        }
    }
    
    if (!buffer.empty()) {
        // Pulisci la coda se troppi suoni sono accodati per evitare lag
        if (SDL_GetQueuedAudioSize(device) > sr * sizeof(Sint16)) {
            SDL_ClearQueuedAudio(device);
        }
        SDL_QueueAudio(device, buffer.data(), buffer.size() * sizeof(Sint16));
    }
}