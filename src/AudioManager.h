#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H

#include <SDL2/SDL.h>

enum SoundType {
    SOUND_PISTOL,
    SOUND_SHOTGUN,
    SOUND_ROCKET,
    SOUND_LASER,
    SOUND_TREASURE,
    SOUND_ENEMY_DEATH,
    SOUND_LOSE_LIFE,
    SOUND_WIN,
    SOUND_BOSS_SHOOT,
    SOUND_BOSS_HIT,
    SOUND_BOSS_DEATH
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