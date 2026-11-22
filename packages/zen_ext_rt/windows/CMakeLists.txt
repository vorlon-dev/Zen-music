cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "zen_ext_rt")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/../rust zen_ext_rt "")

set(zen_ext_rt_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
