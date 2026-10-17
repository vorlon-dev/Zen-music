#ifndef FLUTTER_PLUGIN_FLUTTER_INAPPWEBVIEW_WINDOWS_FX_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_INAPPWEBVIEW_WINDOWS_FX_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void FlutterInappwebviewWindowsFxPluginRegisterWithRegistrar(
        FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_PLUGIN_FLUTTER_INAPPWEBVIEW_WINDOWS_FX_PLUGIN_H_