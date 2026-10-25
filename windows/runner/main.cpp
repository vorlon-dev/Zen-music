#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// ──────────────────────────────────────────────────────────────────────────
// ZENMUSIC: WebView2 stealth CBT hook.
//
// The desktop-Spotify engine needs a WebView2 host that Chromium considers
// visible (IsWindowVisible == TRUE), otherwise MediaSource never fires
// sourceopen and the whole EME pipeline stalls (SP-4 lesson). But the user
// must never see that white rectangle.
//
// Dart-side masking (SpotifyDesktopEngine._maskWebViewWindows) runs ~1s
// after WebviewWindow.create() — long enough for the window to flash for a
// few seconds. This CBT hook fires on HCBT_CREATEWND, i.e. BEFORE the
// window is first shown, so the layered-alpha style is in place from frame
// zero.
//
// We filter by class name: the Flutter runner window is
// "FLUTTER_RUNNER_WIN32_WINDOW"; WebView2 uses "Chrome_WidgetWin_*" or
// similar. Only WebView2-class windows get masked, the runner is
// untouched.
// ──────────────────────────────────────────────────────────────────────────

namespace {

    HHOOK g_cbt_hook = nullptr;

    LRESULT CALLBACK ZenCbtProc(int nCode, WPARAM wParam, LPARAM lParam) {
        if (nCode == HCBT_CREATEWND) {
            HWND hwnd = reinterpret_cast<HWND>(wParam);
            wchar_t cls[256] = {0};
            ::GetClassNameW(hwnd, cls, 256);
            const std::wstring cls_str(cls);

            const bool is_webview =
                    cls_str.find(L"Chrome_WidgetWin") != std::wstring::npos ||
                    cls_str.find(L"WebView") != std::wstring::npos ||
                    cls_str.find(L"Edge") != std::wstring::npos;

            if (is_webview) {
                // Layered + alpha 0 -> invisible pixels while IsWindowVisible stays
                // TRUE. Toolwindow -> no taskbar button. Noactivate -> no focus steal.
                const LONG_PTR ex = ::GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
                ::SetWindowLongPtrW(
                        hwnd, GWL_EXSTYLE,
                        ex | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
                ::SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);

                // Belt-and-suspenders: park it off-screen too.
                ::SetWindowPos(hwnd, nullptr, -32000, -32000, 0, 0,
                               SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSIZE);
            }
        }
        return ::CallNextHookEx(g_cbt_hook, nCode, wParam, lParam);
    }

    void InstallZenCbtHook() {
        // Thread-specific hook. The Flutter platform thread IS the main thread
        // on Windows, and desktop_webview_window creates its window from the
        // platform channel handler, which runs here. If a future plugin creates
        // the WebView2 window on a different thread, the Dart-side
        // _maskWebViewWindows() fallback catches it.
        g_cbt_hook = ::SetWindowsHookExW(WH_CBT, ZenCbtProc, nullptr,
                                         ::GetCurrentThreadId());
    }

    void UninstallZenCbtHook() {
        if (g_cbt_hook) {
            ::UnhookWindowsHookEx(g_cbt_hook);
            g_cbt_hook = nullptr;
        }
    }

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
        _In_ wchar_t* command_line, _In_ int show_command) {
if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
CreateAndAttachConsole();
}

::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

// ZENMUSIC: WebView2 EME engine — backgrounding disables. These keep the
// renderer at full priority while the window is technically visible but
// masked. Still needed even with the CBT hook: without them, hiding the
// WebView2 window at OS level still suspends Chromium's media pipeline.
//
// SP-48: MediaSessionService is ALSO disabled — that Chromium feature is
// what registers the webview's own session with Windows SMTC, which made
// the volume flyout / Quick Settings show "127.0.0.1:<port>/_spengine"
// instead of the song. With it off, the ONLY SMTC card is the app's own
// smtc_bridge session (native title/artist/artwork/timeline). The engine
// page's navigator.mediaSession guard tolerates the API being absent.
::SetEnvironmentVariableW(
L"WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
L"--disable-features=CalculateNativeWinOcclusion,MediaSessionService"
L" --disable-backgrounding-occluded-windows"
L" --disable-renderer-backgrounding"
L" --disable-background-timer-throttling");

// ZENMUSIC: hide every WebView2 window the moment it is created — before
// the first paint. This is what eliminates the ~4s white rectangle that
// Dart-side masking used to leave on screen.
InstallZenCbtHook();

flutter::DartProject project(L"data");

std::vector<std::string> command_line_arguments = GetCommandLineArguments();
project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

// ZENMUSIC: disable Impeller — its OpenGL backend fails pipeline linking
// on some GPUs (blank player screen, eventual crash). Skia is the stable
// fallback. Baked in.
project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

FlutterWindow window(project);
Win32Window::Point origin(10, 10);
Win32Window::Size size(1280, 720);
if (!window.Create(L"ZenMusic", origin, size)) {
UninstallZenCbtHook();
return EXIT_FAILURE;
}
window.SetQuitOnClose(true);

::MSG msg;
while (::GetMessage(&msg, nullptr, 0, 0)) {
::TranslateMessage(&msg);
::DispatchMessage(&msg);
}

UninstallZenCbtHook();
::CoUninitialize();
return EXIT_SUCCESS;
}