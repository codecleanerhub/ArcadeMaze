cmake_minimum_required(VERSION 3.10)
project(ArcadeMazeFantasy)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Trova SFML
find_package(SFML 2.5 COMPONENTS graphics audio system REQUIRED)

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
)

# Collega le librerie SFML
target_link_libraries(${PROJECT_NAME} sfml-graphics sfml-audio sfml-system)

target_include_directories(${PROJECT_NAME} PRIVATE src)