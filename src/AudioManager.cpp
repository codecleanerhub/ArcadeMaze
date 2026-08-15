#include "AudioManager.h"
#include <cmath>
#include <cstdlib>
#include <cstring>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

AudioManager::AudioManager() {
    buffers.resize(11);
    sounds.resize(15);
    for(auto& s : sounds) s.setVolume(60);
    
    // Pre-genera tutte le 5 tracce (circa 1 minuto ciascuna)
    for(int i=0; i<5; ++i) generateTrack(i);
}

void AudioManager::generateTrack(int trackIdx) {
    int sr = 44100;
    int tempo = 120;
    int chords[4][3];
    int bass[4];
    int prog[4] = {0, 1, 2, 3}; // Progressione standard
    int numBars = 32; // 32 battute a 120 BPM = 64 secondi
    bool isBoss = (trackIdx == 4);
    
    if (isBoss) {
        // BOSS: Re Minore Melodica (Re, Do, Sib, La) - Power Chords
        tempo = 100; // Più lento ed epico
        int c[4][3] = {{147, 220, 294}, {131, 196, 262}, {117, 175, 233}, {110, 165, 220}};
        int b[4] = {73, 65, 58, 55};
        std::memcpy(chords, c, sizeof(c));
        std::memcpy(bass, b, sizeof(b));
    } else if (trackIdx == 0) {
        // LIVELLO 1: Do Maggiore (Innocente, classico fantasy)
        int c[4][3] = {{261,329,392}, {174,220,261}, {220,261,329}, {196,246,293}};
        int b[4] = {130, 87, 110, 98};
        std::memcpy(chords, c, sizeof(c));
        std::memcpy(bass, b, sizeof(b));
    } else if (trackIdx == 1) {
        // LIVELLO 2: La Minore (Più esplorativo e misterioso)
        int c[4][3] = {{220,261,329}, {174,220,261}, {261,329,392}, {196,246,293}};
        int b[4] = {110, 87, 130, 98};
        std::memcpy(chords, c, sizeof(c));
        std::memcpy(bass, b, sizeof(b));
    } else if (trackIdx == 2) {
        // LIVELLO 3: Mi Minore (Teso, pericoloso)
        int c[4][3] = {{164,196,246}, {261,329,392}, {196,246,294}, {293,369,440}};
        int b[4] = {82, 130, 98, 146};
        std::memcpy(chords, c, sizeof(c));
        std::memcpy(bass, b, sizeof(b));
    } else if (trackIdx == 3) {
        // LIVELLO 4: Re Minore (Oscura, inquietante)
        int c[4][3] = {{147,174,220}, {117,147,175}, {175,220,262}, {196,246,294}};
        int b[4] = {73, 58, 87, 98};
        std::memcpy(chords, c, sizeof(c));
        std::memcpy(bass, b, sizeof(b));
    }

    std::vector<sf::Int16> trackSamples;
    double beatDur = 60.0 / tempo;
    double eighthDur = beatDur / 2.0;
    int samplesPerEighth = sr * eighthDur;

    for(int bar = 0; bar < numBars; ++bar) {
        int chordIdx = prog[bar % 4];
        int root = chords[chordIdx][0];
        int third = chords[chordIdx][1];
        int fifth = chords[chordIdx][2];
        int bassFreq = bass[chordIdx];
        
        bool isChorus = (bar >= 8 && bar <= 11) || (bar >= 16 && bar <= 19) || (bar >= 24 && bar <= 27);
        int octaveShift = isChorus ? 2 : 1; 
        
        for(int i = 0; i < 8; ++i) {
            int noteChoice = rand() % 3;
            double freq;
            if(i == 0) freq = root * octaveShift;
            else if(noteChoice == 0) freq = root * octaveShift;
            else if(noteChoice == 1) freq = third * octaveShift;
            else freq = fifth * octaveShift;
            
            if(rand() % 8 == 0) freq *= 2;
            
            for(int s = 0; s < samplesPerEighth; ++s) {
                double t = (double)s / sr;
                double env = exp(-t * 3.0) * (1.0 - (double)i/8.0); 
                
                double wave;
                if(isBoss) {
                    // Onda segata + quadra per simulare strumenti ad arco pesanti o chitarre distorte
                    double phase = t * freq;
                    wave = 0.6 * (2.0 * (phase - floor(0.5 + phase))) + 0.4 * (sin(2*M_PI*phase) > 0 ? 1 : -1);
                } else {
                    // Onda complessa armonica per musica fantasy
                    wave = 0.4 * sin(2*M_PI*freq*t) + 0.3 * sin(2*M_PI*freq*2*t) + 0.2 * (sin(2*M_PI*freq*4*t) > 0 ? 1 : -1);
                }
                
                double bassWave;
                if(isBoss) {
                    double bPhase = t * bassFreq;
                    bassWave = 0.9 * (2.0 * (bPhase - floor(0.5 + bPhase))); // Basso dente di sega
                } else {
                    bassWave = 0.8 * sin(2*M_PI*bassFreq*t) + 0.5 * sin(2*M_PI*bassFreq*0.5*t);
                }
                
                double bassEnv = (i % 4 == 0) ? 1.0 : 0.5;
                
                trackSamples.push_back((sf::Int16)(1500 * wave * env + 2000 * bassWave * bassEnv));
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
    music.setVolume(40);
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