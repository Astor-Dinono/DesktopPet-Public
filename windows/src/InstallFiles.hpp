#pragma once
#include <windows.h>
#include <string>

namespace dog {
struct InstallMoveResult { bool moved; DWORD error; };

// Windows locks a process's current directory. The installer can inherit the
// live installation as its working directory from WinSparkle or a shortcut.
// Leave it before recovery, replacement or cleanup, even after the dog exits.
inline bool leaveInstallationDirectory(const std::wstring& parent) {
    return SetCurrentDirectoryW(parent.c_str()) != FALSE;
}

inline InstallMoveResult moveInstallDirectory(const std::wstring& from, const std::wstring& to,
                                              void (*pump)() = nullptr, DWORD timeout = 5000) {
    const ULONGLONG started = GetTickCount64();
    for (;;) {
        if (MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_WRITE_THROUGH)) return {true, ERROR_SUCCESS};
        const DWORD error = GetLastError();
        const ULONGLONG elapsed = GetTickCount64() - started;
        // A destination collision or malformed/missing path needs intervention,
        // not retries. Never overwrite another directory or schedule a reboot.
        if ((error != ERROR_SHARING_VIOLATION && error != ERROR_LOCK_VIOLATION && error != ERROR_ACCESS_DENIED)
            || elapsed >= timeout || GetFileAttributesW(to.c_str()) != INVALID_FILE_ATTRIBUTES)
            return {false, error};
        if (pump) pump();
        Sleep(DWORD((timeout - elapsed) < 100 ? (timeout - elapsed) : 100));
    }
}
}
