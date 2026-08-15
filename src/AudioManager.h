#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H
#include <SFML/Audio.hpp>
enum SoundType {
    SOUND_PISTOL, SOUND_SHOTGUN, SOUND_ROCKET, SOUND_LASER, SOUND_TREASURE,
    SOUND_ENEMY_DEATH, SOUND_LOSE_LIFE, SOUND_WIN, SOUND_BOSS_SHOOT, SOUND_BOSS_HIT, SOUND_BOSS_DEATH
};
class AudioManager {
public:
    AudioManager();
    void playSound(SoundType type);
private:
    std::vector<sf::SoundBuffer> buffers;
    std::vector<sf::Sound> sounds;
    int findFreeSound();
};
#endif