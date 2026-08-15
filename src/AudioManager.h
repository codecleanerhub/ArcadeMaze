#ifndef AUDIO_MANAGER_H
#define AUDIO_MANAGER_H
#include <SFML/Audio.hpp>
#include <vector>

enum SoundType {
    SOUND_PISTOL, SOUND_SHOTGUN, SOUND_ROCKET, SOUND_LASER, SOUND_TREASURE,
    SOUND_ENEMY_DEATH, SOUND_LOSE_LIFE, SOUND_WIN, SOUND_BOSS_SHOOT, SOUND_BOSS_HIT, SOUND_BOSS_DEATH
};

class AudioManager {
public:
    AudioManager();
    void playSound(SoundType type);
    void startMusic();
    void stopMusic();
    bool isMusicPlaying() { return music.getStatus() == sf::Sound::Playing; }
private:
    std::vector<sf::SoundBuffer> buffers;
    std::vector<sf::Sound> sounds;
    
    sf::SoundBuffer musicBuffer;
    sf::Sound music;
    std::vector<sf::Int16> musicSamples;
    
    int findFreeSound();
    void generateMusic();
};

#endif