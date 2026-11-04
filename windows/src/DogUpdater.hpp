#pragma once
#include <windows.h>
#include <string>
#include "../vendor/winsparkle/winsparkle.h"
#include "Version.hpp"

namespace dog {
// WinSparkle and its network work do not initialize until the menu is selected.
class Updater {
    HMODULE module=nullptr;
    decltype(&win_sparkle_cleanup) cleanup=nullptr;
    decltype(&win_sparkle_check_update_with_ui) check=nullptr;
    template<class T> bool bind(T& function,const char* name) {function=reinterpret_cast<T>(GetProcAddress(module,name));return function!=nullptr;}
public:
    ~Updater(){if(cleanup)cleanup();if(module)FreeLibrary(module);}
    bool checkNow(win_sparkle_can_shutdown_callback_t canQuit,win_sparkle_shutdown_request_callback_t quit) {
        if(check){check();return true;}
        wchar_t path[32768]{};DWORD length=GetModuleFileNameW(nullptr,path,32768);
        if(!length||length==32768)return false;
        std::wstring full(path,length);auto slash=full.find_last_of(L"\\/");if(slash==std::wstring::npos)return false;
        full.resize(slash+1);full+=L"WinSparkle.dll";
        module=LoadLibraryExW(full.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
        if(!module)return false;
        decltype(&win_sparkle_set_appcast_url) setFeed;
        decltype(&win_sparkle_set_eddsa_public_key) setKey;
        decltype(&win_sparkle_set_app_details) setDetails;
        decltype(&win_sparkle_set_app_build_version) setBuild;
        decltype(&win_sparkle_set_automatic_check_for_updates) setAutomatic;
        decltype(&win_sparkle_set_can_shutdown_callback) setCanQuit;
        decltype(&win_sparkle_set_shutdown_request_callback) setQuit;
        decltype(&win_sparkle_set_http_header) setHeader;
        decltype(&win_sparkle_init) init;
        bool ok=bind(setFeed,"win_sparkle_set_appcast_url")&&bind(setKey,"win_sparkle_set_eddsa_public_key")&&bind(setDetails,"win_sparkle_set_app_details")&&bind(setBuild,"win_sparkle_set_app_build_version")&&bind(setAutomatic,"win_sparkle_set_automatic_check_for_updates")&&bind(setCanQuit,"win_sparkle_set_can_shutdown_callback")&&bind(setQuit,"win_sparkle_set_shutdown_request_callback")&&bind(setHeader,"win_sparkle_set_http_header")&&bind(init,"win_sparkle_init")&&bind(cleanup,"win_sparkle_cleanup")&&bind(check,"win_sparkle_check_update_with_ui");
        if(!ok){cleanup=nullptr;check=nullptr;FreeLibrary(module);module=nullptr;return false;}
        setDetails(L"DesktopPet",L"小狗桌宠",displayVersion);setBuild(version);setFeed(updateFeed);
        if(setKey(updatePublicKey)!=1){cleanup=nullptr;check=nullptr;FreeLibrary(module);module=nullptr;return false;}
        // Override any previous library setting before initialization; no prompt
        // enabling periodic checks or sending counts/system profiles.
        setAutomatic(0);setHeader("User-Agent","DesktopPet-Updater");
        setCanQuit(canQuit);setQuit(quit);init();check();return true;
    }
};
}
