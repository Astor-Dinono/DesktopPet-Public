#pragma once
namespace dog {
inline constexpr wchar_t version[]=L"0.1.0.11";
inline constexpr wchar_t displayVersion[]=L"0.1.0 · Windows build 11";
inline constexpr char updateFeed[]="https://desktop-pet-dog.pages.dev/updates/windows-appcast.xml";
// Generated once; its private counterpart stays in the Mac login Keychain.
// The release build refuses a placeholder or malformed key.
#include "UpdatePublicKey.inc"
}
