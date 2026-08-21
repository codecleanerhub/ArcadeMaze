cmake_minimum_required(VERSION 3.10)
project(ArcadeMazeFantasy)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ===========================================================================
# Rilevamento piattaforma e configurazione SFML
# ===========================================================================

# Su Windows, SFML potrebbe essere installata in percorsi non standard.
# L'utente puo' specificare SFML_DIR o CMAKE_PREFIX_PATH per aiutare CMake.
# Esempi:
#   cmake .. -DSFML_DIR="C:/SFML/lib/cmake/SFML"
#   cmake .. -DCMAKE_PREFIX_PATH="C:/SFML"
#
# Inoltre, su Windows e' importante copiare le DLL di SFML accanto
# all'eseguibile. Lo facciamo automaticamente dopo la build (vedi sotto).

if(WIN32)
    # Percorsi comuni dove SFML potrebbe essere installata su Windows
    set(SFML_SEARCH_PATHS
        "$ENV{SFML_DIR}"
        "$ENV{SFML_HOME}"
        "C:/SFML"
        "C:/SFML-2.5.1"
        "C:/libraries/SFML"
        "$ENV{USERPROFILE}/SFML"
        "C:/vcpkg/installed/x64-windows"
        "C:/vcpkg/vcpkg/packages/sfml_x64-windows"
        "C:/msys64/mingw64"
    )
    # Aggiungi i percorsi di ricerca per find_package
    foreach(path ${SFML_SEARCH_PATHS})
        if(EXISTS "${path}")
            list(APPEND CMAKE_PREFIX_PATH "${path}")
        endif()
    endforeach()
endif()

# Trova SFML (graphics, audio, system, window)
find_package(SFML 2.5 COMPONENTS graphics audio system window REQUIRED)

add_executable(${PROJECT_NAME}
    src/main.cpp
    src/Game.cpp
    src/Maze.cpp
    src/Player.cpp
    src/Enemy.cpp
    src/Weapon.cpp
    src/UI.cpp
    src/Utils.cpp
    src/AudioManager.cpp
    src/Boss.cpp
    src/MiniBoss.cpp
    src/SpriteSheet.cpp
    src/XInputJoystick.cpp
)

target_link_libraries(${PROJECT_NAME} sfml-graphics sfml-audio sfml-system sfml-window)

target_include_directories(${PROJECT_NAME} PRIVATE src)

# ===========================================================================
# Copia automatica DLL di SFML su Windows (post-build)
# ===========================================================================
# Su Windows, se SFML e' compilata come shared library (DLL), l'eseguibile
# ha bisogno delle DLL accanto a se per avviarsi. Le copiamo automaticamente
# dopo la build.
# ===========================================================================
if(WIN32)
    # Cerca le DLL di SFML nei percorsi comuni
    set(SFML_DLL_SEARCH_PATHS
        "$<TARGET_FILE_DIR:sfml-graphics>"          # cartella delle lib di SFML
        "${SFML_DIR}/../bin"
        "${SFML_HOME}/bin"
        "C:/SFML/bin"
        "C:/SFML-2.5.1/bin"
        "C:/libraries/SFML/bin"
        "$ENV{USERPROFILE}/SFML/bin"
        "C:/vcpkg/installed/x64-windows/bin"
        "C:/vcpkg/vcpkg/packages/sfml_x64-windows/bin"
        "C:/msys64/mingw64/bin"
    )

    # Elenco delle DLL necessarie
    set(SFML_DLLS
        sfml-graphics-2.dll
        sfml-audio-2.dll
        sfml-system-2.dll
        sfml-window-2.dll
        # Dipendenze audio
        openal32.dll
        # Dipendenze Windows comuni (potrebbero non servire tutte)
        libsndfile-1.dll
    )

    # Funzione: copia una DLL se esiste
    function(copy_sfml_dll DLL_NAME SEARCH_PATHS DEST_DIR)
        foreach(path ${SEARCH_PATHS})
            set(dll_path "${path}/${DLL_NAME}")
            if(EXISTS "${dll_path}")
                add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${dll_path}" "${DEST_DIR}/${DLL_NAME}"
                    COMMENT "Copia ${DLL_NAME} da ${path}")
                return()  # trovata, esci
            endif()
        endforeach()
    endfunction()

    # Copia ogni DLL
    foreach(dll ${SFML_DLLS})
        copy_sfml_dll(${dll} "${SFML_DLL_SEARCH_PATHS}" "$<TARGET_FILE_DIR:${PROJECT_NAME}>")
    endforeach()

    # Messaggio informativo se le DLL non vengono trovate
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo
        "NOTA: se l'eseguibile non si avvia, copia manualmente le DLL di SFML"
        "(C:/SFML/bin/*.dll) accanto a ${PROJECT_NAME}.exe")
endif()

# ===========================================================================
# Copia la cartella assets accanto all'eseguibile (per Windows e macOS)
# ===========================================================================
# Su Linux il gioco viene lanciato dalla root del progetto, percio' i
# percorsi relativi "assets/sprites/..." funzionano. Su Windows invece
# l'eseguibile potrebbe essere in build/Release/ o build/Debug/, e i
# percorsi relativi non funzionerebbero. Copiamo la cartella assets.
if(WIN32 OR APPLE)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/assets"
        "$<TARGET_FILE_DIR:${PROJECT_NAME}>/assets"
        COMMENT "Copia cartella assets accanto all'eseguibile")
    # Copia anche config.ini se esiste
    if(EXISTS "${CMAKE_SOURCE_DIR}/config.ini")
        add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/config.ini"
            "$<TARGET_FILE_DIR:${PROJECT_NAME}>/config.ini"
            COMMENT "Copia config.ini")
    endif()
endif()
