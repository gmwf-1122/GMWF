#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME);

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

  HANDLE hMutex = nullptr;

#ifdef NDEBUG
  // ── Single-instance guard (Release builds only) ───────────────────────────
  // Prevents a second release instance from launching and fighting over Hive
  // lock files (which causes the PathAccessException / errno=32 startup crash).
  // If an instance is already running with an active window, bring it to front.
  hMutex = ::CreateMutex(nullptr, FALSE, L"GmwfSingleInstanceMutex");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is running — find its window by class name or title.
    HWND existing = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (!existing) {
      existing = ::FindWindow(nullptr, L"Gulzar Madina Dispensary");
    }
    if (!existing) {
      existing = ::FindWindow(nullptr, L"GMWF");
    }
    if (existing) {
      ::ShowWindow(existing, SW_SHOW);
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
      if (hMutex) {
        ::CloseHandle(hMutex);
        hMutex = nullptr;
      }
      ::CoUninitialize();
      return 0;
    }
  }
  // ─────────────────────────────────────────────────────────────────────────
#endif

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"GMWF", origin, size)) {
    if (hMutex) {
      ::CloseHandle(hMutex);
      hMutex = nullptr;
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (hMutex) {
    ::ReleaseMutex(hMutex);
    ::CloseHandle(hMutex);
    hMutex = nullptr;
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}