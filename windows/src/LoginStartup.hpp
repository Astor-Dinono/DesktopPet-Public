#pragma once
#include <windows.h>
#include <string>
#include <utility>

namespace dog::startup {
// Windows owns approval. We only change our application's single Run value.
inline constexpr wchar_t runKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
inline constexpr wchar_t approvalKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
inline constexpr wchar_t valueName[] = L"DesktopPetDog";

enum class State { Off, On, SystemDisabled, SystemManaged, OtherCopy, Unavailable };

inline bool missing(LSTATUS result) {
    return result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND;
}

inline std::wstring modulePath() {
    wchar_t path[MAX_PATH + 1];
    const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
    // The documented limit for a Run command is 260 characters, including quotes.
    if (!length || length + 2 > MAX_PATH) return {};
    return std::wstring(path, length);
}

class LoginItem {
    HKEY root;
    std::wstring executable;

    State approval() const {
        DWORD bytes = 0;
        LSTATUS result = RegGetValueW(root, approvalKey, valueName, RRF_RT_REG_BINARY, nullptr, nullptr, &bytes);
        if (missing(result)) return State::On;
        // This shell record has no public write contract. Read only familiar
        // layouts; direct the user to Startup Apps for any other layout.
        if (result != ERROR_SUCCESS || bytes != 12) return State::SystemManaged;
        DWORD fields[3]{};
        result = RegGetValueW(root, approvalKey, valueName, RRF_RT_REG_BINARY, nullptr, fields, &bytes);
        if (missing(result)) return State::On;
        if (result != ERROR_SUCCESS || bytes != sizeof(fields)) return State::SystemManaged;
        switch (fields[0]) {
        case 2: case 6: return State::On;
        case 3: case 7: return State::SystemDisabled;
        default: return State::SystemManaged;
        }
    }

public:
    explicit LoginItem(std::wstring path, HKEY account = HKEY_CURRENT_USER)
        : root(account), executable(std::move(path)) {}

    State state() const {
        if (executable.empty()) return State::Unavailable;
        wchar_t data[MAX_PATH + 1]{};
        DWORD bytes = sizeof(data);
        const LSTATUS result = RegGetValueW(root, runKey, valueName, RRF_RT_REG_SZ, nullptr, data, &bytes);
        if (missing(result)) return State::Off;
        if (result != ERROR_SUCCESS || bytes < sizeof(wchar_t) || bytes % sizeof(wchar_t)) return State::Unavailable;
        const std::wstring command(data, bytes / sizeof(wchar_t) - 1);
        if (command.find(L'\0') != std::wstring::npos) return State::Unavailable;
        const auto expected = L"\"" + executable + L"\"";
        if (CompareStringOrdinal(command.c_str(), -1, expected.c_str(), -1, TRUE) == CSTR_EQUAL) return approval();
        // Allow relocating a portable copy, but never claim an arbitrary command.
        const auto slash = command.find_last_of(L'\\');
        if (command.size() > 3 && command.front() == L'"' && command.find(L'"', 1) == command.size() - 1 &&
            slash != std::wstring::npos && _wcsicmp(command.c_str() + slash + 1, L"DesktopPet.exe\"") == 0)
            return State::OtherCopy;
        return State::Unavailable;
    }

    LSTATUS setEnabled(bool enabled, bool replaceOtherCopy = false) const {
        const State current = state();
        if (current == State::Unavailable || (current == State::OtherCopy && !replaceOtherCopy)) return ERROR_INVALID_DATA;
        if (enabled) {
            if (current != State::Off && current != State::OtherCopy) return ERROR_SUCCESS;
            const auto command = L"\"" + executable + L"\"";
            return RegSetKeyValueW(root, runKey, valueName, REG_SZ, command.c_str(),
                                   DWORD((command.size() + 1) * sizeof(wchar_t)));
        }
        if (current == State::Off) return ERROR_SUCCESS;
        if (current == State::OtherCopy) return ERROR_INVALID_DATA;
        const LSTATUS result = RegDeleteKeyValueW(root, runKey, valueName);
        return missing(result) ? ERROR_SUCCESS : result;
    }
};
} // namespace dog::startup
