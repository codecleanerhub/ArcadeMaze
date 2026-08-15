cmake_minimum_required(VERSION 3.10)
project(ArcadeMaze)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(SDL2 REQUIRED)

add_executable(${PROJECT_NAME}
    src/main.cpp
    src/Game.cpp
    src/Maze.cpp
    src/Player.cpp
    src/Enemy.cpp
    src/Weapon.cpp
    src/UI.cpp
    src/Utils.cpp
)

if(TARGET SDL2::SDL2)
    target_link_libraries(${PROJECT_NAME} SDL2::SDL2)
else()
    target_include_directories(${PROJECT_NAME} PRIVATE ${SDL2_INCLUDE_DIRS})
    target_link_libraries(${PROJECT_NAME} ${SDL2_LIBRARIES})
endif()

target_include_directories(${PROJECT_NAME} PRIVATE src)
