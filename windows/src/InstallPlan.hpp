#pragma once
#include <array>
#include <string>
#include <optional>

namespace dog {
using InstallVersion = std::array<unsigned,4>;
enum class InstallDecision { Proceed, NewerInstalled, UnknownInstalledVersion, InvalidTargetVersion };

inline std::optional<InstallVersion> parseVersion(const std::wstring& text){
    InstallVersion result{};size_t at=0;
    for(unsigned i=0;i<4;++i){
        if(at==text.size()||text[at]<L'0'||text[at]>L'9')return {};
        size_t start=at;
        while(at<text.size()&&text[at]>=L'0'&&text[at]<=L'9'){
            result[i]=result[i]*10+unsigned(text[at++]-L'0');if(result[i]>999999)return {};
        }
        if(at-start>1&&text[start]==L'0')return {};
        if(i<3){if(at==text.size()||text[at++]!=L'.')return {};}
    }
    if(at!=text.size())return {};
    return result;
}
inline InstallDecision checkInstallVersion(bool hadOld, const std::wstring& record,
                                           std::optional<InstallVersion> executable, const std::wstring& next){
    const auto target = parseVersion(next);
    if(!target) return InstallDecision::InvalidTargetVersion;
    if(!hadOld) return InstallDecision::Proceed;

    const auto recorded = parseVersion(record);
    // Either source can establish a newer install, even when the other is stale.
    if((recorded && *recorded > *target) || (executable && *executable > *target))
        return InstallDecision::NewerInstalled;
    if(!recorded && !executable) return InstallDecision::UnknownInstalledVersion;
    return InstallDecision::Proceed;
}
inline constexpr std::array<const wchar_t*,7> installedFiles{{L"DesktopPet.exe",L"WinSparkle.dll",L"WinSparkle-LICENSE.txt",L"Expat-LICENSE.txt",L"先读我.txt",L"version.txt",L".desktop-pet-install"}};
}
