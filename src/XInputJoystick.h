#ifndef XINPUT_JOYSTICK_H
#define XINPUT_JOYSTICK_H

// ===========================================================================
// XInputJoystick.h - Supporto joystick nativo Windows (XInput) + fallback SFML
//
// Su Windows, usa XInput API (xinput9_1_0.dll) per leggere gamepad Xbox e
// arcade stick compatibili XInput. XInput e' piu' affidabile di DirectInput
// (usato da SFML) per questi controller.
//
// Su Linux/macOS, fallback a sf::Joystick (SFML).
//
// L'API pubblica e' identica a sf::Joystick per facilita' d'uso:
//   - isConnected(joystickId)
//   - getAxisPosition(joystickId, axis)
//   - isButtonPressed(joystickId, button)
//   - update()
// ===========================================================================

#include <SFML/Window.hpp>

// Namespace wrapper per astrazione cross-platform
namespace Joy {

// Inizializza XInput (Windows) o SFML (altro). Chiamare una volta in init().
void init();

// Aggiorna lo stato dei joystick. Chiamare una volta per frame.
void update();

// True se il joystick e' collegato.
bool isConnected(unsigned int joystickId);

// Restituisce la posizione dell'asse (-100..100). Su Windows XInput,
// mappa i thumbstick agli assi X/Y/Z/R di SFML per compatibilita'.
float getAxisPosition(unsigned int joystickId, sf::Joystick::Axis axis);

// True se il pulsante e' premuto.
bool isButtonPressed(unsigned int joystickId, unsigned int button);

// Restituisce il numero di pulsanti (per compatibilita').
unsigned int getButtonCount(unsigned int joystickId);

} // namespace Joy

#endif // XINPUT_JOYSTICK_H
