#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <tchar.h>
#include <uni_links_desktop/uni_links_desktop_plugin.h>
#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "win32_desktop.h"
#include "flutter_window.h"
#include "utils.h"

/// Hide the current process's own console window (if any).
static void HideOwnConsole() {
  HWND consoleWnd = ::GetConsoleWindow();
  if (consoleWnd) {
    ::ShowWindow(consoleWnd, SW_HIDE);
  }
}

/// Hide ALL visible top-level windows whose owning process is conhost.exe.
/// This catches console windows created by child processes (--server,
/// --cm, --service, --tray) that inherit the console before FreeConsole
/// takes effect.  Called periodically during the first 30 seconds.
static void HideAllConHostWindows() {
  HideOwnConsole();
  struct ConHostPidSet {
    std::vector<DWORD> pids;
  } data;
  HANDLE snap = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);
    if (::Process32FirstW(snap, &pe)) {
      do {
        if (_wcsicmp(pe.szExeFile, L"conhost.exe") == 0) {
          data.pids.push_back(pe.th32ProcessID);
        }
      } while (::Process32NextW(snap, &pe));
    }
    ::CloseHandle(snap);
  }
  if (data.pids.empty()) return;
  struct EnumCtx {
    const std::vector<DWORD>* targetPids;
  } ctx{&data.pids};
  ::EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
    auto* ctx = reinterpret_cast<EnumCtx*>(lParam);
    DWORD winPid = 0;
    ::GetWindowThreadProcessId(hwnd, &winPid);
    for (DWORD pid : *ctx->targetPids) {
      if (winPid == pid) {
        if (::IsWindowVisible(hwnd)) {
          ::ShowWindow(hwnd, SW_HIDE);
        }
        break;
      }
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&ctx));
}

typedef char** (*FUNC_LUODA_CORE_MAIN)(int*);
typedef void (*FUNC_LUODA_FREE_ARGS)( char**, int);
typedef int (*FUNC_LUODA_GET_APP_NAME)(wchar_t*, int);
/// Note: `--server`, `--service` are already handled in [core_main.rs].
const std::vector<std::string> parameters_white_list = {"--install", "--cm"};

const wchar_t* getWindowClassName();

// Named mutex for single-instance enforcement.  This is the earliest,
// most reliable guard: it runs before any DLL is loaded, before any
// Rust initialisation, and before any Flutter window is created.
// If the mutex already exists, another instance owns the main UI
// profile.  We activate that instance's window (or just exit) and
// never create a second process / tray icon.
static const wchar_t* kSingleInstanceMutexName = L"Luoda_SingleInstance_Mutex_v1";

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
 _In_ wchar_t *command_line, _In_ int show_command)
{
 // Immediately detach from any inherited console window so the app
 // never shows a terminal when launched from cmd/PowerShell/scripts.
 ::FreeConsole();
 // Redirect the C runtime standard streams to NUL so that std::cout/
 // std::cerr never attempt to attach a new console.
 { FILE* fNul = nullptr; freopen_s(&fNul, "NUL", "w", stdout); }
 { FILE* fNul = nullptr; freopen_s(&fNul, "NUL", "w", stderr); }
 // Aggressively hide any console windows already visible.
 HideAllConHostWindows();

 // --- Single-instance mutex (earliest possible guard) ---
 // Only check the mutex for a bare double-click launch (no args).
 // Any args (--connect, --tray, --cm, ...) skip this and fall through
 // to the FindWindowW logic below, which dispatches args to the
 // existing window or starts a fresh instance as needed.
 std::vector<std::string> early_args = GetCommandLineArguments();
 for (auto& a : early_args) {
 a.erase(a.find_last_not_of(" \n\r\t"));
 }
 if (early_args.empty()) {
 HANDLE hMutex = ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
 if (hMutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
 // Another instance is running.  Find its main window and bring
 // it to the foreground instead of starting a second process.
 std::wstring app_name = L"\u70B9\u804A";
 HWND hwnd = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", app_name.c_str());
 if (hwnd) {
 ::ShowWindow(hwnd, SW_SHOW);
 ::ShowWindow(hwnd, SW_RESTORE);
 ::SetForegroundWindow(hwnd);
 }
 if (hMutex) ::CloseHandle(hMutex);
 return EXIT_FAILURE;
 // NOTE: the first real instance keeps its own mutex handle alive
 // for the whole process lifetime (see below).
 }
 // Keep the mutex handle alive for the process lifetime on first launch.
 // Do not close it — closing would release the mutex and allow a second
 // instance to grab it.
 }

  HINSTANCE hInstance = LoadLibraryA("luoda.dll");
  if (!hInstance)
  {
    return EXIT_FAILURE;
  }
  FUNC_LUODA_CORE_MAIN luoda_core_main =
      (FUNC_LUODA_CORE_MAIN)GetProcAddress(hInstance, "luoda_core_main_args");
  if (!luoda_core_main)
  {
    return EXIT_FAILURE;
  }
  FUNC_LUODA_FREE_ARGS free_c_args =
      (FUNC_LUODA_FREE_ARGS)GetProcAddress(hInstance, "free_c_args");
  if (!free_c_args)
  {
    return EXIT_FAILURE;
  }
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // Remove possible trailing whitespace from command line arguments
  for (auto& argument : command_line_arguments) {
    argument.erase(argument.find_last_not_of(" \n\r\t"));
  }

  int args_len = 0;
  char** c_args = luoda_core_main(&args_len);
  if (!c_args)
  {
    std::string args_str = "";
    for (const auto& argument : command_line_arguments) {
      args_str += (argument + " ");
    }
    // std::cout << "LUODA [" << args_str << "], core returns false, exiting without launching Flutter app." << std::endl;
    return EXIT_SUCCESS;
  }
  std::vector<std::string> rust_args(c_args, c_args + args_len);
  free_c_args(c_args, args_len);

  std::wstring app_name = L"\u70B9\u804A";
  FUNC_LUODA_GET_APP_NAME get_luoda_app_name = (FUNC_LUODA_GET_APP_NAME)GetProcAddress(hInstance, "get_luoda_app_name");
  if (get_luoda_app_name) {
    wchar_t app_name_buffer[512] = {0};
    if (get_luoda_app_name(app_name_buffer, 512) == 0) {
      app_name = std::wstring(app_name_buffer);
    }
  }

  // Uri links dispatch
  HWND hwnd = ::FindWindowW(getWindowClassName(), app_name.c_str());
  if (hwnd != NULL) {
    // Allow multiple flutter instances when being executed by parameters
    // contained in whitelists.
    bool allow_multiple_instances = false;
    for (auto& whitelist_param : parameters_white_list) {
      allow_multiple_instances =
          allow_multiple_instances ||
          std::find(command_line_arguments.begin(),
                    command_line_arguments.end(),
                    whitelist_param) != command_line_arguments.end();
    }
    if (!allow_multiple_instances) {
      // Only treat this as a duplicate launch when the existing window belongs
      // to a process running from the SAME executable. If it comes from a
      // different build (users upgrade by replacing/copying a new folder while
      // the old build is still running), let this instance start so the Rust
      // single-instance takeover can terminate the stale processes. Otherwise
      // an upgraded build would exit right here and the machine would stay
      // "listening but never online".
      bool same_exe = false;
      DWORD pid = 0;
      ::GetWindowThreadProcessId(hwnd, &pid);
      if (pid != 0) {
        HANDLE h = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
        if (h != NULL) {
          wchar_t path[MAX_PATH] = {0};
          DWORD size = MAX_PATH;
          if (::QueryFullProcessImageNameW(h, 0, path, &size)) {
            wchar_t self[MAX_PATH] = {0};
            DWORD self_size = MAX_PATH;
            if (::GetModuleFileNameW(nullptr, self, self_size) > 0) {
              same_exe = (::_wcsicmp(path, self) == 0);
            }
          }
          ::CloseHandle(h);
        }
      }
      if (same_exe) {
        if (!command_line_arguments.empty()) {
          // Dispatch command line arguments
          DispatchToUniLinksDesktop(hwnd);
        } else {
          // Not called with arguments, or just open the app shortcut on desktop.
          // So we just show the main window instead.
          ::ShowWindow(hwnd, SW_NORMAL);
          ::SetForegroundWindow(hwnd);
        }
        return EXIT_FAILURE;
      }
      // Different executable: fall through and start a new main instance.
    }
  }

  // Note: we intentionally do NOT call AttachConsole here.
  // FreeConsole() above already detached from any inherited console.
  // Re-attaching would make the terminal window reappear when the app
  // is launched from cmd/PowerShell/scripts.

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Many plugin DLLs (flutter_windows.dll, desktop_multi_window, etc.)
  // are compiled as Console subsystem.  When they are loaded they may
  // cause a console window to appear.  Re-detach here after all DLLs
  // have been loaded to prevent that.
  ::FreeConsole();
  { FILE* fNul = nullptr; freopen_s(&fNul, "NUL", "w", stdout); }
  { FILE* fNul = nullptr; freopen_s(&fNul, "NUL", "w", stderr); }

  flutter::DartProject project(L"data");
  // connection manager hide icon from taskbar
  bool is_cm_page = false;
  auto cmParam = std::string("--cm");
  if (!command_line_arguments.empty() && command_line_arguments.front().compare(0, cmParam.size(), cmParam.c_str()) == 0) {
    is_cm_page = true;
  }
  bool is_install_page = false;
  auto installParam = std::string("--install");
  if (!command_line_arguments.empty() && command_line_arguments.front().compare(0, installParam.size(), installParam.c_str()) == 0) {
    is_install_page = true;
  }

  command_line_arguments.insert(command_line_arguments.end(), rust_args.begin(), rust_args.end());
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Portable launchers request foreground UI before the Dart startup work
  // finishes. Keep the window visible while native initialization continues.
  char foreground_value[2] = {0};
  const bool show_on_startup =
      GetEnvironmentVariableA("SET_FOREGROUND_WINDOW", foreground_value,
                              sizeof(foreground_value)) > 0 &&
      foreground_value[0] == '1';
  char launcher_name[260] = {0};
  const DWORD launcher_name_length = GetEnvironmentVariableA(
      "LUODA_APPNAME", launcher_name, sizeof(launcher_name));
  const bool is_client_launcher =
      launcher_name_length > 0 &&
      std::string(launcher_name).find("Client") != std::string::npos;

  // Get primary monitor's work area.
  Win32Window::Point workarea_origin(0, 0);
  Win32Window::Size workarea_size(0, 0);

  Win32Desktop::GetWorkArea(workarea_origin, workarea_size);

  // Compute window bounds for default main window position: (10, 10) x(800, 600)
  Win32Window::Point relative_origin(10, 10);

  Win32Window::Point origin(workarea_origin.x + relative_origin.x, workarea_origin.y + relative_origin.y);
  const bool use_client_startup_size = is_client_launcher && show_on_startup;
  Win32Window::Size size = use_client_startup_size
      ? Win32Window::Size(380u, 500u)
      : Win32Window::Size(800u, 600u);

  // Fit the window to the monitor's work area.
  Win32Desktop::FitToWorkArea(origin, size);

  std::wstring window_title;
  if (is_cm_page) {
    window_title = app_name + L" - Connection Manager";
  } else if (is_install_page) {
    window_title = app_name + L" - Install";
  } else {
    window_title = app_name;
  }
  if (!window.CreateAndShow(window_title, origin, size, !is_cm_page)) {
      return EXIT_FAILURE;
  }
  // The Flutter engine and plugin DLLs are loaded during CreateAndShow.
  // Several of these DLLs are Console-subsystem and may re-attach a
  // console.  Detach again unconditionally and hide any visible console.
  ::FreeConsole();
  { FILE* fNul = nullptr; freopen_s(&fNul, "NUL", "w", stdout); }
  { FILE* fNul = nullptr; freopen_s(&fNul, "NUL", "w", stderr); }
  HideAllConHostWindows();
  if (show_on_startup) {
    const HWND startup_window = window.GetHandle();
    ::ShowWindow(startup_window, SW_SHOWNORMAL);
    ::UpdateWindow(startup_window);
    // window_manager may apply its hidden startup state after the native
    // window is created. Re-assert visibility during the portable boot window.
    std::thread([startup_window]() {
      for (const auto delay_seconds : {1, 3, 8}) {
        std::this_thread::sleep_for(std::chrono::seconds(delay_seconds));
        if (!::IsWindow(startup_window)) {
          return;
        }
        ::ShowWindow(startup_window, SW_SHOWNORMAL);
        ::UpdateWindow(startup_window);
      }
    }).detach();
  }
  window.SetQuitOnClose(true);

  // Console-subsystem DLLs (flutter_windows.dll, plugins) and child
  // processes (--server, --cm, --service) may create or attach to
  // console windows.  Spawn a guard thread that keeps detaching and
  // hiding console windows for the first 30 seconds.
  std::thread([]() {
    for (int i = 0; i < 60; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(500));
      ::FreeConsole();
      FILE* fNul = nullptr;
      freopen_s(&fNul, "NUL", "w", stdout);
      freopen_s(&fNul, "NUL", "w", stderr);
      HideAllConHostWindows();
    }
  }).detach();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
