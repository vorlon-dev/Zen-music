#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
        _In_ wchar_t *command_line, _In_ int show_command) {
// Attach to console when present (e.g., 'flutter run') or create a
// new console when running with a debugger.
if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
CreateAndAttachConsole();
}

// Initialize COM, so that it is available for use in the library and/or
// plugins.
::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

// ZENMUSIC: WebView2 EME engine (SP-5). Chromium's Windows occlusion
// calculation SUSPENDS the media lifecycle of hidden/occluded WebView2
// pages (proven in the SP-4 spike: sourceopen never fired, then the env
// var fixed it). This disables that tracker for every WebView2
// environment this process creates — the hidden desktop-Spotify engine
// then streams without suspension. Must run before any WebView2
// environment is created (plugins create lazily, so wWinMain is early
// enough). Inherited by the title-bar subprocess (harmless).
::SetEnvironmentVariableW(L"WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
L"--disable-features=CalculateNativeWinOcclusion");

flutter::DartProject project(L"data");

std::vector<std::string> command_line_arguments =
        GetCommandLineArguments();

project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

// ZENMUSIC: disable Impeller. Its OpenGL backend fails pipeline linking on
// some GPUs (observed: blank/white player screen, per-frame render-pass
// errors, eventual crash). Skia is the stable fallback and renders
// correctly everywhere. Baked in — applies to every launch, release included.
project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

FlutterWindow window(project);
Win32Window::Point origin(10, 10);
Win32Window::Size size(1280, 720);
if (!window.Create(L"ZenMusic", origin, size)) {
return EXIT_FAILURE;
}
window.SetQuitOnClose(true);

::MSG msg;
while (::GetMessage(&msg, nullptr, 0, 0)) {
::TranslateMessage(&msg);
::DispatchMessage(&msg);
}

::CoUninitialize();
return EXIT_SUCCESS;
}