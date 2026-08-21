#include "XInputJoystick.h"
#include <iostream>
#include <cstring>
#include <cmath>

// ===========================================================================
// XInputJoystick.cpp - Implementazione
//
// 3 LIVELLI DI FALLBACK su Windows:
//   1. XInput (xinput9_1_0.dll) - per controller Xbox e arcade stick XInput
//   2. DirectInput nativo (dinput8.dll) - per controller DirectInput-only
//   3. SFML (sf::Joystick) - fallback finale
//
// Su Linux/macOS: usa direttamente sf::Joystick.
//
// LOGICA: per ogni joystick ID (0, 1, 2, 3), prova prima XInput. Se
// XInputGetState ritorna ERROR_DEVICE_NOT_CONNECTED per quell'ID, il
// controller non e' XInput, quindi usa DirectInput. Se anche DirectInput
// non trova nulla, usa SFML.
// ===========================================================================

#ifdef _WIN32
    #define DIRECTINPUT_VERSION 0x0800
    #include <windows.h>
    #include <dinput.h>
    #pragma comment(lib, "dinput8.lib")
    #pragma comment(lib, "dxguid.lib")

    // --- XInput structures ---
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
    // ERROR_DEVICE_NOT_CONNECTED e' gia' definito in Windows SDK (winerror.h = 1167)
    // NON ridefinirlo qui per evitare warning C4005.

    // M_PI non e' definito in MSVC senza _USE_MATH_DEFINES
    #ifndef M_PI
    #define M_PI 3.14159265358979323846
    #endif

    typedef DWORD (WINAPI *XInputGetStateFunc)(DWORD dwUserIndex, XINPUT_STATE* pState);

    // --- Stato globale ---
    static HMODULE g_xinputLib = nullptr;
    static XInputGetStateFunc g_xinputGetState = nullptr;
    static bool g_xinputAvailable = false;
    static XINPUT_STATE g_xinputStates[4] = {};
    // Traccia quali joystick ID sono XInput (true) vs non-XInput (false)
    static bool g_isXInput[4] = {false, false, false, false};
    static bool g_xInputChecked[4] = {false, false, false, false};

    // --- DirectInput ---
    static LPDIRECTINPUT8 g_dinput = nullptr;
    static LPDIRECTINPUTDEVICE8 g_dinputDevices[8] = {};  // max 8 joystick DirectInput
    static DIJOYSTATE2 g_dinputStates[8] = {};
    static int g_dinputDeviceCount = 0;
    static bool g_dinputAvailable = false;

    // Callback per enumerare joystick DirectInput
    static BOOL CALLBACK enumJoysticksCallback(const DIDEVICEINSTANCEA* pdidInstance, void* pContext) {
        if (g_dinputDeviceCount >= 8) return DIENUM_STOP;
        LPDIRECTINPUTDEVICE8 device;
        HRESULT hr = g_dinput->CreateDevice(pdidInstance->guidInstance, &device, nullptr);
        if (SUCCEEDED(hr)) {
            // Set data format
            hr = device->SetDataFormat(&c_dfDIJoystick2);
            if (SUCCEEDED(hr)) {
                // Set cooperative level (non-exclusive, foreground)
                hr = device->SetCooperativeLevel(GetDesktopWindow(), DISCL_NONEXCLUSIVE | DISCL_BACKGROUND);
                if (SUCCEEDED(hr)) {
                    // Acquire
                    device->Acquire();
                    g_dinputDevices[g_dinputDeviceCount] = device;
                    g_dinputDeviceCount++;
                    std::cout << "DirectInput: joystick " << g_dinputDeviceCount
                              << " trovato (GUID)" << std::endl;
                }
            }
        }
        return DIENUM_CONTINUE;
    }
#endif

namespace Joy {

void init() {
#ifdef _WIN32
    // --- Livello 1: XInput ---
    g_xinputLib = LoadLibraryA("xinput9_1_0.dll");
    if (!g_xinputLib) g_xinputLib = LoadLibraryA("xinput1_4.dll");
    if (!g_xinputLib) g_xinputLib = LoadLibraryA("xinput1_3.dll");
    if (g_xinputLib) {
        g_xinputGetState = (XInputGetStateFunc)GetProcAddress(g_xinputLib, "XInputGetState");
        if (g_xinputGetState) {
            g_xinputAvailable = true;
            std::cout << "XInput: caricato con successo" << std::endl;
        }
    }

    // --- Livello 2: DirectInput (per controller non-XInput) ---
    HRESULT hr = DirectInput8Create(GetModuleHandle(nullptr), DIRECTINPUT_VERSION,
                                    IID_IDirectInput8A, (void**)&g_dinput, nullptr);
    if (SUCCEEDED(hr) && g_dinput) {
        g_dinputDeviceCount = 0;
        g_dinput->EnumDevices(DI8DEVCLASS_GAMECTRL, enumJoysticksCallback, nullptr, DIEDFL_ATTACHEDONLY);
        if (g_dinputDeviceCount > 0) {
            g_dinputAvailable = true;
            std::cout << "DirectInput: " << g_dinputDeviceCount << " joystick rilevati" << std::endl;
        }
    }

    if (!g_xinputAvailable && !g_dinputAvailable) {
        std::cout << "Joystick: nessun XInput/DirectInput rilevato, uso SFML" << std::endl;
    }

    // --- Livello 3: SFML (sempre disponibile come fallback finale) ---
    sf::Joystick::update();
#else
    // Linux/macOS: usa SFML
    sf::Joystick::update();
#endif
}

void update() {
#ifdef _WIN32
    // --- XInput: polla 4 controller ---
    if (g_xinputAvailable) {
        for (DWORD i = 0; i < 4; i++) {
            DWORD result = g_xinputGetState(i, &g_xinputStates[i]);
            if (!g_xInputChecked[i]) {
                if (result == ERROR_SUCCESS) {
                    g_isXInput[i] = true;
                    g_xInputChecked[i] = true;
                    std::cout << "Joystick " << i << ": XInput controller" << std::endl;
                } else if (result == ERROR_DEVICE_NOT_CONNECTED) {
                    g_isXInput[i] = false;
                    g_xInputChecked[i] = true;
                    // Non loggare per ogni ID non collegato (spam)
                }
            }
        }
    }

    // --- DirectInput: polla tutti i dispositivi ---
    if (g_dinputAvailable) {
        for (int i = 0; i < g_dinputDeviceCount; i++) {
            if (g_dinputDevices[i]) {
                HRESULT hr = g_dinputDevices[i]->GetDeviceState(sizeof(DIJOYSTATE2), &g_dinputStates[i]);
                if (FAILED(hr)) {
                    // Try to reacquire
                    g_dinputDevices[i]->Acquire();
                    g_dinputDevices[i]->GetDeviceState(sizeof(DIJOYSTATE2), &g_dinputStates[i]);
                }
            }
        }
    }

    // --- SFML: aggiorna sempre (fallback finale) ---
    sf::Joystick::update();
#else
    sf::Joystick::update();
#endif
}

bool isConnected(unsigned int joystickId) {
#ifdef _WIN32
    // XInput
    if (g_xinputAvailable && joystickId < 4) {
        XINPUT_STATE state;
        if (g_xinputGetState(joystickId, &state) == ERROR_SUCCESS) {
            return true;
        }
    }
    // DirectInput: mappa joystickId ai dispositivi DirectInput
    // I primi 4 ID sono riservati a XInput, i successivi a DirectInput
    // Ma se XInput non ha un controller per quell'ID, usa DirectInput
    if (g_dinputAvailable) {
        // Conta quanti XInput sono attivi
        int xinputCount = 0;
        if (g_xinputAvailable) {
            for (int i = 0; i < 4; i++) {
                XINPUT_STATE state;
                if (g_xinputGetState(i, &state) == ERROR_SUCCESS) xinputCount++;
            }
        }
        // DirectInput devices iniziano dopo gli XInput
        int diIndex = joystickId - xinputCount;
        if (diIndex >= 0 && diIndex < g_dinputDeviceCount) {
            return true;
        }
    }
    // SFML fallback
    return sf::Joystick::isConnected(joystickId);
#else
    return sf::Joystick::isConnected(joystickId);
#endif
}

float getAxisPosition(unsigned int joystickId, sf::Joystick::Axis axis) {
#ifdef _WIN32
    // --- XInput ---
    if (g_xinputAvailable && joystickId < 4) {
        XINPUT_STATE state;
        if (g_xinputGetState(joystickId, &state) == ERROR_SUCCESS) {
            const XINPUT_GAMEPAD& gp = state.Gamepad;
            switch (axis) {
                case sf::Joystick::X:
                    return (gp.sThumbLX == 0) ? 0.f : (float)gp.sThumbLX / 327.67f;
                case sf::Joystick::Y:
                    return (gp.sThumbLY == 0) ? 0.f : -(float)gp.sThumbLY / 327.67f;
                case sf::Joystick::Z:
                    return (gp.sThumbRX == 0) ? 0.f : (float)gp.sThumbRX / 327.67f;
                case sf::Joystick::R:
                    return (gp.sThumbRY == 0) ? 0.f : -(float)gp.sThumbRY / 327.67f;
                case sf::Joystick::U:
                    return (float)gp.bLeftTrigger / 2.55f;
                case sf::Joystick::V:
                    return (float)gp.bRightTrigger / 2.55f;
                case sf::Joystick::PovX:
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) return 100.f;
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_LEFT)  return -100.f;
                    return 0.f;
                case sf::Joystick::PovY:
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_DOWN)  return 100.f;
                    if (gp.wButtons & XINPUT_GAMEPAD_DPAD_UP)     return -100.f;
                    return 0.f;
                default: return 0.f;
            }
        }
    }

    // --- DirectInput ---
    if (g_dinputAvailable) {
        // Conta XInput attivi per calcolare l'offset DirectInput
        int xinputCount = 0;
        if (g_xinputAvailable) {
            for (int i = 0; i < 4; i++) {
                XINPUT_STATE state;
                if (g_xinputGetState(i, &state) == ERROR_SUCCESS) xinputCount++;
            }
        }
        int diIndex = joystickId - xinputCount;
        if (diIndex >= 0 && diIndex < g_dinputDeviceCount && g_dinputDevices[diIndex]) {
            const DIJOYSTATE2& js = g_dinputStates[diIndex];
            // DirectInput usa range -1000..1000 per gli assi (con proprietà)
            // ma per semplicità assumiamo -1000..1000 e convertiamo a -100..100
            switch (axis) {
                case sf::Joystick::X:  return (float)js.lX / 10.f;
                case sf::Joystick::Y:  return (float)js.lY / 10.f;
                case sf::Joystick::Z:  return (float)js.lZ / 10.f;
                case sf::Joystick::R:  return (float)js.lRx / 10.f;
                case sf::Joystick::U:  return (float)js.lRy / 10.f;
                case sf::Joystick::V:  return (float)js.lRz / 10.f;
                case sf::Joystick::PovX: {
                    // POV hat: range 0..36000 (centoesimi di grado), -1 = non premuto
                    DWORD pov = js.rgdwPOV[0];
                    if (pov == (DWORD)-1) return 0.f;
                    float angle = (float)pov / 100.f;  // gradi
                    return sinf(angle * (float)M_PI / 180.f) * 100.f;
                }
                case sf::Joystick::PovY: {
                    DWORD pov = js.rgdwPOV[0];
                    if (pov == (DWORD)-1) return 0.f;
                    float angle = (float)pov / 100.f;
                    return -cosf(angle * (float)M_PI / 180.f) * 100.f;
                }
                default: return 0.f;
            }
        }
    }
#endif
    // --- SFML fallback ---
    return sf::Joystick::getAxisPosition(joystickId, axis);
}

bool isButtonPressed(unsigned int joystickId, unsigned int button) {
#ifdef _WIN32
    // --- XInput ---
    if (g_xinputAvailable && joystickId < 4) {
        XINPUT_STATE state;
        if (g_xinputGetState(joystickId, &state) == ERROR_SUCCESS) {
            const XINPUT_GAMEPAD& gp = state.Gamepad;
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
                case 14: return gp.bLeftTrigger > 30;
                case 15: return gp.bRightTrigger > 30;
                default: return false;
            }
        }
    }

    // --- DirectInput ---
    if (g_dinputAvailable) {
        int xinputCount = 0;
        if (g_xinputAvailable) {
            for (int i = 0; i < 4; i++) {
                XINPUT_STATE state;
                if (g_xinputGetState(i, &state) == ERROR_SUCCESS) xinputCount++;
            }
        }
        int diIndex = joystickId - xinputCount;
        if (diIndex >= 0 && diIndex < g_dinputDeviceCount && g_dinputDevices[diIndex]) {
            const DIJOYSTATE2& js = g_dinputStates[diIndex];
            if (button < 128) {
                return (js.rgbButtons[button] & 0x80) != 0;
            }
            return false;
        }
    }
#endif
    // --- SFML fallback ---
    return sf::Joystick::isButtonPressed(joystickId, button);
}

unsigned int getButtonCount(unsigned int joystickId) {
#ifdef _WIN32
    if (g_xinputAvailable && joystickId < 4) {
        XINPUT_STATE state;
        if (g_xinputGetState(joystickId, &state) == ERROR_SUCCESS) {
            return 16;
        }
    }
    if (g_dinputAvailable) {
        int xinputCount = 0;
        if (g_xinputAvailable) {
            for (int i = 0; i < 4; i++) {
                XINPUT_STATE state;
                if (g_xinputGetState(i, &state) == ERROR_SUCCESS) xinputCount++;
            }
        }
        int diIndex = joystickId - xinputCount;
        if (diIndex >= 0 && diIndex < g_dinputDeviceCount) {
            return 128;  // DirectInput supporta fino a 128 pulsanti
        }
    }
#endif
    return sf::Joystick::getButtonCount(joystickId);
}

} // namespace Joy
