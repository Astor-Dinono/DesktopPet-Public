#ifdef NDEBUG
#undef NDEBUG
#endif
#define NOMINMAX
#include "../src/LoginStartup.hpp"
#include <cassert>
#include <iostream>

int main(){
    using namespace dog::startup;
    // Every registry operation below is relative to a disposable non-startup root.
    HKEY test = nullptr;
    const auto path = L"Software\\DesktopPetLoginTest-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64());
    DWORD disposition = 0;
    assert(RegCreateKeyExW(HKEY_CURRENT_USER,path.c_str(),0,nullptr,0,KEY_ALL_ACCESS,nullptr,&test,&disposition)==ERROR_SUCCESS);
    assert(disposition==REG_CREATED_NEW_KEY);
    const std::wstring exe = L"C:\\小狗 Files\\DesktopPet.exe";
    LoginItem item(exe,test);
    assert(item.state()==State::Off);
    assert(item.setEnabled(true)==ERROR_SUCCESS && item.state()==State::On);
    const auto expected = L"\"" + exe + L"\"";
    wchar_t data[256]{};
    DWORD bytes = sizeof(data);
    assert(RegGetValueW(test,runKey,valueName,RRF_RT_REG_SZ,nullptr,data,&bytes)==ERROR_SUCCESS && data==expected);
    assert(item.setEnabled(true)==ERROR_SUCCESS);

    DWORD policy[3]{3,0,0};
    assert(RegSetKeyValueW(test,approvalKey,valueName,REG_BINARY,policy,sizeof(policy))==ERROR_SUCCESS);
    assert(item.state()==State::SystemDisabled && item.setEnabled(true)==ERROR_SUCCESS && item.state()==State::SystemDisabled);
    assert(item.setEnabled(false)==ERROR_SUCCESS && item.state()==State::Off);
    assert(item.setEnabled(true)==ERROR_SUCCESS && item.state()==State::SystemDisabled);
    policy[0]=15;
    assert(RegSetKeyValueW(test,approvalKey,valueName,REG_BINARY,policy,sizeof(policy))==ERROR_SUCCESS && item.state()==State::SystemManaged);
    assert(RegDeleteKeyValueW(test,approvalKey,valueName)==ERROR_SUCCESS && item.state()==State::On);

    LoginItem moved(L"D:\\Dog\\DesktopPet.exe",test);
    assert(moved.state()==State::OtherCopy);
    assert(moved.setEnabled(false)!=ERROR_SUCCESS && item.state()==State::On);
    assert(moved.setEnabled(true)!=ERROR_SUCCESS && item.state()==State::On);
    assert(moved.setEnabled(true,true)==ERROR_SUCCESS && moved.state()==State::On);
    const wchar_t foreign[]=L"unrelated.exe --option";
    assert(RegSetKeyValueW(test,runKey,valueName,REG_SZ,foreign,sizeof(foreign))==ERROR_SUCCESS);
    assert(moved.state()==State::Unavailable && moved.setEnabled(false)!=ERROR_SUCCESS && moved.setEnabled(true)!=ERROR_SUCCESS);
    bytes=sizeof(data);
    assert(RegGetValueW(test,runKey,valueName,RRF_RT_REG_SZ,nullptr,data,&bytes)==ERROR_SUCCESS && std::wstring(data)==foreign);
    RegCloseKey(test);
    assert(RegDeleteTreeW(HKEY_CURRENT_USER,path.c_str())==ERROR_SUCCESS);
    std::cout<<"PASS: opt-in, exact quoted command, disabled-by-Windows, unknown approvals, relocated copies and foreign values\n";
}
