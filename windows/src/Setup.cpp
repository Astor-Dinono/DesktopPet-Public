#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <winver.h>
#include <string>
#include <vector>
#include "InstallPlan.hpp"
#include "InstallFiles.hpp"
#include "Version.hpp"

namespace {
constexpr wchar_t marker[]=L"DesktopPet Windows managed installation v1\r\n";
HWND statusWindow=nullptr,label=nullptr;
bool plainDirectory(const std::wstring& p){DWORD a=GetFileAttributesW(p.c_str());return a!=INVALID_FILE_ATTRIBUTES&&(a&FILE_ATTRIBUTE_DIRECTORY)&&!(a&FILE_ATTRIBUTE_REPARSE_POINT);}
bool exists(const std::wstring& p){return GetFileAttributesW(p.c_str())!=INVALID_FILE_ATTRIBUTES;}
std::wstring join(const std::wstring& a,const wchar_t* b){return a+L"\\"+b;}
bool directory(const std::wstring& p){return CreateDirectoryW(p.c_str(),nullptr)||(GetLastError()==ERROR_ALREADY_EXISTS&&plainDirectory(p));}
bool write(const std::wstring& p,const void* data,DWORD size){
    HANDLE f=CreateFileW(p.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return false;
    DWORD written=0;bool ok=WriteFile(f,data,size,&written,nullptr)&&written==size&&FlushFileBuffers(f);CloseHandle(f);return ok;
}
bool text(const std::wstring& p,const std::wstring& value){return write(p,value.data(),DWORD(value.size()*sizeof(wchar_t)));}
std::wstring read(const std::wstring& p){
    HANDLE f=CreateFileW(p.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);if(f==INVALID_HANDLE_VALUE)return {};
    LARGE_INTEGER n{};if(!GetFileSizeEx(f,&n)||n.QuadPart<0||n.QuadPart>4096||n.QuadPart%2){CloseHandle(f);return {};}
    std::wstring s(size_t(n.QuadPart/2),L'\0');DWORD got=0;bool ok=ReadFile(f,s.data(),DWORD(n.QuadPart),&got,nullptr)&&got==n.QuadPart;CloseHandle(f);return ok?s:std::wstring();
}
bool managed(const std::wstring& p){return plainDirectory(p)&&read(join(p,L".desktop-pet-install"))==marker;}
std::optional<dog::InstallVersion> installedExecutableVersion(const std::wstring& path){
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if(attributes == INVALID_FILE_ATTRIBUTES || (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)))
        return std::nullopt;
    const DWORD size = GetFileVersionInfoSizeW(path.c_str(), nullptr);
    if(size == 0 || size > 1024 * 1024) return std::nullopt;
    std::vector<BYTE> data(size);
    if(!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) return std::nullopt;
    void* value = nullptr;
    UINT length = 0;
    if(!VerQueryValueW(data.data(), L"\\", &value, &length) || !value || length < sizeof(VS_FIXEDFILEINFO))
        return std::nullopt;
    const auto& version = *static_cast<const VS_FIXEDFILEINFO*>(value);
    if(version.dwSignature != VS_FFI_SIGNATURE || version.dwFileType != VFT_APP) return std::nullopt;
    return dog::InstallVersion{HIWORD(version.dwFileVersionMS), LOWORD(version.dwFileVersionMS),
                               HIWORD(version.dwFileVersionLS), LOWORD(version.dwFileVersionLS)};
}
// Delete only the fixed files of our own marked, non-reparse backup directory.
// Extra user files prevent cleanup; they are never recursively deleted.
bool removeBackup(const std::wstring& p){
    if(!managed(p))return false;
    WIN32_FIND_DATAW found;HANDLE search=FindFirstFileW(join(p,L"*").c_str(),&found);if(search==INVALID_HANDLE_VALUE)return false;
    bool safe=true;
    do{
        std::wstring name=found.cFileName;if(name==L"."||name==L"..")continue;
        bool known=false;for(auto allowed:dog::installedFiles)if(name==allowed)known=true;
        if(!known||(found.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))safe=false;
    }while(FindNextFileW(search,&found));FindClose(search);if(!safe)return false;
    // Marker is last so failed deletion never turns an arbitrary directory into
    // a trusted backup on a later attempt.
    for(auto name:dog::installedFiles)if(std::wstring(name)!=L".desktop-pet-install"&&exists(join(p,name))&&!DeleteFileW(join(p,name).c_str()))return false;
    return DeleteFileW(join(p,L".desktop-pet-install").c_str())&&RemoveDirectoryW(p.c_str());
}
void pump(){MSG m;while(PeekMessageW(&m,nullptr,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessageW(&m);}}
void status(const wchar_t* value){if(label)SetWindowTextW(label,value);pump();}
void progress(){
    statusWindow=CreateWindowExW(WS_EX_DLGMODALFRAME|WS_EX_TOPMOST,L"STATIC",L"小狗桌宠",WS_OVERLAPPED|WS_CAPTION|WS_VISIBLE,CW_USEDEFAULT,CW_USEDEFAULT,460,145,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    if(statusWindow){label=CreateWindowExW(0,L"STATIC",L"正在给小狗准备桌面上的位置…",WS_CHILD|WS_VISIBLE,24,28,406,50,statusWindow,nullptr,GetModuleHandleW(nullptr),nullptr);SendMessageW(label,WM_SETFONT,WPARAM(GetStockObject(DEFAULT_GUI_FONT)),TRUE);pump();}
}
int error(const wchar_t* message){if(statusWindow)DestroyWindow(statusWindow);MessageBoxW(nullptr,message,L"小狗暂时没有搬好",MB_OK|MB_ICONWARNING);return 1;}
int moveError(const wchar_t* message,DWORD code){
    std::wstring detail=std::wstring(message)+L"\n\nWindows 错误代码："+std::to_wstring(code);
    return error(detail.c_str());
}
bool shortcut(const std::wstring& root){
    PWSTR programs=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_Programs,KF_FLAG_CREATE,nullptr,&programs)))return false;
    auto file=join(programs,L"小狗桌宠.lnk");CoTaskMemFree(programs);
    IShellLinkW* link=nullptr;bool ok=false;
    if(SUCCEEDED(CoCreateInstance(CLSID_ShellLink,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&link)))){
        IPersistFile* existing=nullptr;
        // Preserve an unrelated shortcut with the same friendly name.
        if(exists(file)&&SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&existing)))){
            wchar_t path[32768]{};bool ours=SUCCEEDED(existing->Load(file.c_str(),STGM_READ))&&SUCCEEDED(link->GetPath(path,32768,nullptr,SLGP_RAWPATH))&&_wcsicmp(path,join(root,L"DesktopPet.exe").c_str())==0;existing->Release();
            if(!ours){link->Release();return false;}
        }
        link->SetPath(join(root,L"DesktopPet.exe").c_str());link->SetWorkingDirectory(root.c_str());link->SetDescription(L"一只安静陪你的小狗");link->SetIconLocation(join(root,L"DesktopPet.exe").c_str(),0);
        IPersistFile* persist=nullptr;if(SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&persist)))){ok=SUCCEEDED(persist->Save(file.c_str(),TRUE));persist->Release();}link->Release();
    }return ok;
}
bool launch(const std::wstring& root,HANDLE& process){
    std::wstring executable=join(root,L"DesktopPet.exe"),command=L"\""+executable+L"\"";STARTUPINFOW startup{sizeof(startup)};PROCESS_INFORMATION p{};
    if(!CreateProcessW(executable.c_str(),command.data(),nullptr,nullptr,FALSE,0,nullptr,root.c_str(),&startup,&p))return false;
    CloseHandle(p.hThread);process=p.hProcess;return true;
}
int install(HINSTANCE instance,bool update){
    if(!update&&MessageBoxW(nullptr,L"把小狗带回桌面？\n\n只安装到当前 Windows 账户，不需要管理员权限。\n已有计数和设置会保留，日常陪伴无需联网。",L"小狗桌宠 · Windows 测试版",MB_OKCANCEL|MB_ICONINFORMATION)!=IDOK)return 0;
    HANDLE installLock=CreateMutexW(nullptr,TRUE,L"Local\\DesktopPet.Windows.Install");
    if(!installLock||GetLastError()==ERROR_ALREADY_EXISTS){if(installLock)CloseHandle(installLock);return error(L"另一个小狗安装程序正在运行，请等它完成后再试。");}
    PWSTR local=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,KF_FLAG_CREATE,nullptr,&local)))return error(L"暂时找不到当前账户的应用文件夹，原小狗和设置没有改变。");
    std::wstring programs=join(local,L"Programs"),root=join(programs,L"DesktopPetDog"),backup=root+L".previous";CoTaskMemFree(local);
    if(!directory(programs))return error(L"无法创建当前账户的应用文件夹，请检查磁盘空间或文件夹权限。");
    if(!dog::leaveInstallationDirectory(programs))return moveError(L"安装器暂时无法离开旧小狗的文件夹，本次未替换程序，计数和设置保留。",GetLastError());
    // Recover a power interruption between the two directory renames before
    // considering any backup cleanup. A working prior install is never discarded
    // merely because the active path is temporarily absent.
    if(!exists(root)&&exists(backup)){
        if(!managed(backup)||!dog::moveInstallDirectory(backup,root,pump).moved)return error(L"上次安装尚未完成，原小狗备份仍在，暂时无法恢复。请联系邀请你试用的人。");
    }
    bool hadOld=exists(root);
    if(hadOld&&!managed(root))return error(L"安装位置已有其他文件，为了保留它们，本次安装已停止。请联系邀请你试用的人。");
    const auto oldVersion = hadOld ? read(join(root, L"version.txt")) : L"";
    const auto exeVersion = hadOld ? installedExecutableVersion(join(root, L"DesktopPet.exe")) : std::nullopt;
    switch(dog::checkInstallVersion(hadOld, oldVersion, exeVersion, dog::version)){
        case dog::InstallDecision::Proceed: break;
        case dog::InstallDecision::NewerInstalled:
            return error(L"电脑上已有较新版的小狗，本次未替换。请从开始菜单打开“小狗桌宠”。");
        case dog::InstallDecision::UnknownInstalledVersion:
            return error(L"无法确认现有小狗的版本，本次未替换程序。请从开始菜单打开“小狗桌宠”，并将此提示反馈给邀请你试用的人。");
        case dog::InstallDecision::InvalidTargetVersion:
            return error(L"安装包的版本信息异常，请从官网重新下载。原小狗没有改变。");
    }
    if(exists(backup)&&!removeBackup(backup))return error(L"上一版备份包含额外文件或正在使用，已保留备份和当前小狗，请稍后再试。");
    GUID id{};if(FAILED(CoCreateGuid(&id)))return error(L"暂时无法准备安装位置，原小狗没有改变。");wchar_t guid[40]{};StringFromGUID2(id,guid,40);std::wstring stage=root+L".staging-"+guid;
    if(!CreateDirectoryW(stage.c_str(),nullptr))return error(L"无法准备安装文件，当前小狗和计数没有改变。");
    if(!text(join(stage,L".desktop-pet-install"),marker))return error(L"无法写入安装标记，当前小狗没有改变。");
    for(int i=0;i<5;++i){
        HRSRC resource=FindResourceW(instance,MAKEINTRESOURCEW(101+i),RT_RCDATA);HGLOBAL loaded=resource?LoadResource(instance,resource):nullptr;DWORD size=resource?SizeofResource(instance,resource):0;
        if(!resource||!loaded||!size||!write(join(stage,dog::installedFiles[size_t(i)]),LockResource(loaded),size)){removeBackup(stage);return error(L"安装包未能完整展开，原小狗与计数没有改变。请重新下载后再试。");}
    }
    if(!text(join(stage,L"version.txt"),dog::version)){removeBackup(stage);return error(L"无法写入版本记录，原小狗没有改变。");}
    progress();status(L"正在等待旧版小狗保存进度并退出…");
    HANDLE dogLock=OpenMutexW(SYNCHRONIZE|MUTEX_MODIFY_STATE,FALSE,L"Local\\DesktopPet.Windows.Preview");
    if(dogLock){
        if(!update)MessageBoxW(statusWindow,L"请先右键正在运行的小狗，选择“退出小狗”。\n计数和设置保留，退出后会继续安装。",L"先让旧小狗歇一会儿",MB_OK|MB_ICONINFORMATION);
        DWORD elapsed=0,result=WAIT_TIMEOUT;
        while(elapsed<30000&&(result=WaitForSingleObject(dogLock,50))==WAIT_TIMEOUT){elapsed+=50;pump();}
        if(result==WAIT_OBJECT_0||result==WAIT_ABANDONED){ReleaseMutex(dogLock);CloseHandle(dogLock);}
        else{CloseHandle(dogLock);removeBackup(stage);return error(L"旧小狗还没有退出，本次未替换程序。请正常退出后再试，计数和设置保留。");}
    }
    status(L"正在安放新版小狗，计数和设置保留…");
    if(hadOld){
        auto moved=dog::moveInstallDirectory(root,backup,pump);
        if(!moved.moved){removeBackup(stage);return moveError(L"Windows 暂时不允许移动旧版文件，可能仍被占用或受文件夹权限限制。本次未替换旧版，计数和设置保留，请稍后再试。",moved.error);}
    }
    if(!dog::moveInstallDirectory(stage,root,pump).moved){
        bool restored=!hadOld||dog::moveInstallDirectory(backup,root,pump).moved;removeBackup(stage);
        return error(restored?L"新版没有安装成功，原小狗已保留，计数和设置没有改变。":L"安装未完成，原小狗保留在 DesktopPetDog.previous 备份中，计数仍在原来的本地设置文件夹，请联系邀请你试用的人。");
    }
    HANDLE ready=CreateEventW(nullptr,TRUE,FALSE,L"Local\\DesktopPet.Windows.Ready");if(ready)ResetEvent(ready);
    HANDLE process=nullptr;bool started=launch(root,process),healthy=false;
    if(started){
        status(L"正在叫醒小狗…");
        for(int elapsed=0;elapsed<10000;elapsed+=50){if(ready&&WaitForSingleObject(ready,0)==WAIT_OBJECT_0){healthy=true;break;}if(WaitForSingleObject(process,50)==WAIT_OBJECT_0)break;pump();}
    }
    if(ready)CloseHandle(ready);
    if(!started||WaitForSingleObject(process,0)==WAIT_OBJECT_0){
        if(process)CloseHandle(process);
        bool removed=removeBackup(root),restored=hadOld&&removed&&dog::moveInstallDirectory(backup,root,pump).moved;
        if(restored){HANDLE old=nullptr;if(launch(root,old))CloseHandle(old);}
        return error(restored?L"新版未能正常启动，已恢复原小狗。计数和设置保留，请把情况反馈给邀请你试用的人。":L"小狗未能启动。计数和设置没有删除，请联系邀请你试用的人；已有原版备份会保留。");
    }
    CloseHandle(process);shortcut(root);if(statusWindow)DestroyWindow(statusWindow);ReleaseMutex(installLock);CloseHandle(installLock);
    if(!healthy)MessageBoxW(nullptr,L"小狗已经安装，但还没有确认画面准备完毕。请观察是否出现，必要时从开始菜单重新打开；计数和原版备份保留。",L"小狗正在醒来",MB_OK|MB_ICONINFORMATION);
    return 0;
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR args,int){
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    bool update=std::wstring(args)==L"/update";
    int result=install(instance,update);CoUninitialize();return result;
}
