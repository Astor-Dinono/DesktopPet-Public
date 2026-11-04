#pragma once
#include <array>
#include <string>
#include <optional>

namespace dog {
inline std::optional<std::array<unsigned,4>> parseVersion(const std::wstring& text){
    std::array<unsigned,4> result{};size_t at=0;
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
inline bool mayInstall(const std::wstring& current,const std::wstring& next){
    auto target=parseVersion(next);if(!target)return false;
    if(current.empty())return true;
    auto installed=parseVersion(current);return installed&&*target>=*installed;
}
inline constexpr std::array<const wchar_t*,7> installedFiles{{L"DesktopPet.exe",L"WinSparkle.dll",L"WinSparkle-LICENSE.txt",L"Expat-LICENSE.txt",L"先读我.txt",L"version.txt",L".desktop-pet-install"}};
}
