cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_inappwebview_windows_fx")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_inappwebview_windows_fx_plugin")

add_library(${PLUGIN_NAME} SHARED
        "flutter_inappwebview_windows_fx_plugin.cpp"
        "include/flutter_inappwebview_windows_fx/flutter_inappwebview_windows_fx_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
        CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# ▼▼▼ CHANGED FROM INTERFACE TO PUBLIC ▼▼▼
target_include_directories(${PLUGIN_NAME} PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)