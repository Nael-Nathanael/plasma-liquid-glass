cmake_minimum_required(VERSION 3.16)
project(glassbar-sampler LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core DBus)

add_executable(glassbar-sampler main.cpp)
target_link_libraries(glassbar-sampler Qt6::Core Qt6::DBus)
install(TARGETS glassbar-sampler DESTINATION bin)
