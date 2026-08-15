#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H

#include <SDL2/SDL.h>

enum SoundType {
    SOUND_SHOOT,
    SOUND_DOT,
    SOUND_ENEMY_DEATH,
    SOUND_LOSE_LIFE,
    SOUND_WIN
};

class AudioManager {
public:
    AudioManager();
    ~AudioManager();
    
    void playSound(SoundType type);

private:
    SDL_AudioDeviceID device;
    SDL_AudioSpec spec;
};

#endif