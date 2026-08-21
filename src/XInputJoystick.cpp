#include "XInputJoystick.h"
#include <iostream>

// ===========================================================================
// XInputJoystick.cpp - Implementazione
//
// Su Windows: carica dinamicamente xinput9_1_0.dll e usa XInputGetState().
// Su Linux/macOS: fallback a sf::Joystick.
// ===========================================================================

#ifdef _WIN32
    #include <windows.h>
    // XInput state structures (definiti qui per evitare dipendenze SDK)
    struct XINPUT_GAMEPAD {
        WORD wButtons;
        BYTE bLeftTrigger;
        BYTE bRightTrigger;
        SHORT sThumbLX;
        SHORT sThumbLY;
        SHORT sThumbRX;
        SHORT sThumbRY;
    };
    struct XINPUT_STATE {
        DWORD dwPacketNumber;
        XINPUT_GAMEPAD Gamepad;
    };
    #define XINPUT_GAMEPAD_DPAD_UP          0x0001
    #define XINPUT_GAMEPAD_DPAD_DOWN        0x0002
    #define XINPUT_GAMEPAD_DPAD_LEFT        0x0004
    #define XINPUT_GAMEPAD_DPAD_RIGHT       0x0008
    #define XINPUT_GAMEPAD_START            0x0010
    #define XINPUT_GAMEPAD_BACK             0x0020
    #define XINPUT_GAMEPAD_LEFT_THUMB       0x0040
    #define XINPUT_GAMEPAD_RIGHT_THUMB      0x0080
    #define XINPUT_GAMEPAD_LEFT_SHOULDER   0x0100
    #define XINPUT_GAMEPAD_RIGHT_SHOULDER  0x0200
    #define XINPUT_GAMEPAD_A               0x1000
    #define XINPUT_GAMEPAD_B               0x2000
    #define XINPUT_GAMEPAD_X               0x4000
    #define XINPUT_GAMEPAD_Y               0x8000

    // Tipo funzione XInputGetState
    typedef DWORD (WINAPI *XInputGetStateFunc)(DWORD dwUserIndex, XINPUT_STATE* pState);

    static HMODULE g_xinputLib = nullptr;
    static XInputGetStateFunc g_xinputGetState = nullptr;
    static XINPUT_STATE g_xinputStates[4] = {};  // cache stati per 4 controller
    static bool g_xinputAvailable = false;
#endif

namespace Joy {

void init() {
#ifdef _WIN32
    // Prova a caricare xinput9_1_0.dll (standard su Windows 7+)
    g_xinputLib = LoadLibraryA("xinput9_1_0.dll");
    if (!g_xinputLib) {
        // Fallback: xinput1_4.dll (Windows 8+)
        g_xinputLib = LoadLibraryA("xinput1_4.dll");
    }
    if (!g_xinputLib) {
        // Fallback: xinput1_3.dll (DirectX SDK)
        g_xinputLib = LoadLibraryA("xinput1_3.dll");
    }
    if (g_xinputLib) {
        g_xinputGetState = (XInputGetStateFunc)GetProcAddress(g_xinputLib, "XInputGetState");
        if (g_xinputGetState) {
            g_xinputAvailable = true;
            std::cout << "XInput: caricato con successo (xinput.dll)" << std::endl;
        } else {
            std::cout << "XInput: dll caricata ma XInputGetState non trovato" << std::endl;
        }
    } else {
        std::cout << "XInput: xinput.dll non trovato, uso SFML fallback" << std::endl;
    }
#endif
    // Su Linux/macOS, usa SFML direttamente
}

void update() {
#ifdef _WIN32
    if (g_xinputAvailable && g_xinputGetState) {
        // Polling di 4 controller XInput
        for (DWORD i = 0; i < 4; i++) {
            g_xinputGetState(i, &g_xinputStates[i]);
        }
        return;  // XInput gestito, non chiamare sf::Joystick::update()
    }
#endif
    // Fallback SFML (Linux/macOS o Windows senza XInput)
    sf::Joystick::update();
}

bool isConnected(unsigned int joystickId) {
#ifdef _WIN32
    if (g_xinputAvailable && g_xinputGetState && joystickId < 4) {
        XINPUT_STATE state;
        DWORD result = g_xinputGetState(joystickId, &state);
        return (result == ERROR_SUCCESS);
    }
#endif
    // Fallback SFML
    return sf::Joystick::isConnected(joystickId);
}

float getAxisPosition(unsigned int joystickId, sf::Joystick::Axis axis) {
#ifdef _WIN32
    if (g_xinputAvailable && g_xinputGetState && joystickId < 4) {
        const XINPUT_GAMEPAD& gp = g_xinputStates[joystickId].Gamepad;
        // Mappa thumbstick sinistro -> X/Y, thumbstick destro -> Z/R
        // I thumbstick XInput vanno da -32768 a +32767. Convertiamo a -100..100.
        switch (axis) {
            case sf::Joystick::X:  // Left thumbstick X
                return (gp.sThumbLX == 0) ? 0.f : (float)gp.sThumbLX / 327.67f;
            case sf::Joystick::Y:  // Left thumbstick Y (invertito perche' su e' positivo in XInput)
                return (gp.sThumbLY == 0) ? 0.f : -(float)gp.sThumbLY / 327.67f;
            case sf::Joystick::Z:  // Right thumbstick X
                return (gp.sThumbRX == 0) ? 0.f : (float)gp.sThumbRX / 327.67f;
            case sf::Joystick::R:  // Right thumbstick Y (invertito)
                return (gp.sThumbRY == 0) ? 0.f : -(float)gp.sThumbRY / 327.67f;
            case sf::Joystick::U:
            case sf::Joystick::V:
                // Trigger come assi U/V (0..100 invece di 0..255)
                if (axis == sf::Joystick::U) return (float)gp.bLeftTrigger / 2.55f;
                return (float)gp.bRightTrigger / 2.55f;
            case sf::Joystick::PovX:
            case sf::Joystick::PovY:
                // D-pad: XInput riporta i 4 direzionali come pulsanti,
                // non come assi POV. Mappiamoli qui per compatibilita'.
                if (axis == sf::Joystick::PovX) {
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) return 100.f;
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_LEFT)  return -100.f;
                    return 0.f;
                } else {  // PovY
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_DOWN)  return 100.f;
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_UP)     return -100.f;
                    return 0.f;
                }
            default:
                return 0.f;
        }
    }
#endif
    // Fallback SFML
    return sf::Joystick::getAxisPosition(joystickId, axis);
}

bool isButtonPressed(unsigned int joystickId, unsigned int button) {
#ifdef _WIN32
    if (g_xinputAvailable && g_xinputGetState && joystickId < 4) {
        const XINPUT_GAMEPAD& gp = g_xinputStates[joystickId].Gamepad;
        // Mappa pulsanti XInput (16 pulsanti totali)
        // 0=A 1=B 2=X 3=Y 4=LB 5=RB 6=Back 7=Start 8=LeftThumb 9=RightThumb
        // 10=DPadUp 11=DPadDown 12=DPadLeft 13=DPadRight 14=LeftTrigger 15=RightTrigger
        switch (button) {
            case 0:  return (gp.wButtons & XINPUT_GAMEPAD_A) != 0;
            case 1:  return (gp.wButtons & XINPUT_GAMEPAD_B) != 0;
            case 2:  return (gp.wButtons & XINPUT_GAMEPAD_X) != 0;
            case 3:  return (gp.wButtons & XINPUT_GAMEPAD_Y) != 0;
            case 4:  return (gp.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0;
            case 5:  return (gp.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0;
            case 6:  return (gp.wButtons & XINPUT_GAMEPAD_BACK) != 0;
            case 7:  return (gp.wButtons & XINPUT_GAMEPAD_START) != 0;
            case 8:  return (gp.wButtons & XINPUT_GAMEPAD_LEFT_THUMB) != 0;
            case 9:  return (gp.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0;
            case 10: return (gp.wButtons & XINPUT_GAMEPAD_DPAD_UP) != 0;
            case 11: return (gp.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) != 0;
            case 12: return (gp.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) != 0;
            case 13: return (gp.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0;
            case 14: return gp.bLeftTrigger > 30;   // Trigger come pulsante
            case 15: return gp.bRightTrigger > 30;
            default: return false;
        }
    }
#endif
    // Fallback SFML
    return sf::Joystick::isButtonPressed(joystickId, button);
}

unsigned int getButtonCount(unsigned int joystickId) {
#ifdef _WIN32
    if (g_xinputAvailable && g_xinputGetState && joystickId < 4) {
        return 16;  // XInput ha 16 pulsanti mappati
    }
#endif
    return sf::Joystick::getButtonCount(joystickId);
}

} // namespace Joy
