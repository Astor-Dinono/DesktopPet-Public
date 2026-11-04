// Windows-only filesystem regression. All fixtures are inside one new temp
// directory; no installed app, user settings, registry, security or processes
// are changed. Cross-compilation alone does not count as running these tests.
#ifdef NDEBUG
#undef NDEBUG
#endif
#define UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "../src/InstallFiles.hpp"
#include <cassert>
#include <iostream>
#include <thread>

int main() {
    wchar_t temp[MAX_PATH]{},name[MAX_PATH]{},original[32768]{};
    assert(GetCurrentDirectoryW(32768,original));
    assert(GetTempPathW(MAX_PATH,temp));
    assert(GetTempFileNameW(temp,L"DPt",0,name));assert(DeleteFileW(name));
    const std::wstring base=name,root=base+L"\\dog",backup=base+L"\\previous";
    assert(CreateDirectoryW(base.c_str(),nullptr));assert(CreateDirectoryW(root.c_str(),nullptr));
    assert(SetCurrentDirectoryW(root.c_str()));
    assert(!MoveFileExW(root.c_str(),backup.c_str(),MOVEFILE_WRITE_THROUGH));
    // Same inherited working directory as an in-app update: leave it first.
    assert(dog::leaveInstallationDirectory(base));
    assert(dog::moveInstallDirectory(root,backup).moved);
    assert(dog::moveInstallDirectory(backup,root).moved);

    HANDLE held=CreateFileW(root.c_str(),FILE_LIST_DIRECTORY,FILE_SHARE_READ|FILE_SHARE_WRITE,
                           nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
    assert(held!=INVALID_HANDLE_VALUE);
    auto started=GetTickCount64();
    std::thread release([held]{Sleep(200);CloseHandle(held);});
    auto delayed=dog::moveInstallDirectory(root,backup,nullptr,2000);release.join();
    assert(delayed.moved&&GetTickCount64()-started>=200);
    assert(dog::moveInstallDirectory(backup,root).moved);

    held=CreateFileW(root.c_str(),FILE_LIST_DIRECTORY,FILE_SHARE_READ|FILE_SHARE_WRITE,
                    nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
    assert(held!=INVALID_HANDLE_VALUE);
    auto busy=dog::moveInstallDirectory(root,backup,nullptr,200);CloseHandle(held);
    assert(!busy.moved&&busy.error!=ERROR_SUCCESS);
    assert(GetFileAttributesW(root.c_str())!=INVALID_FILE_ATTRIBUTES);
    assert(GetFileAttributesW(backup.c_str())==INVALID_FILE_ATTRIBUTES);
    assert(CreateDirectoryW(backup.c_str(),nullptr));
    auto collision=dog::moveInstallDirectory(root,backup,nullptr,200);
    assert(!collision.moved);
    assert(GetFileAttributesW(root.c_str())!=INVALID_FILE_ATTRIBUTES);
    assert(GetFileAttributesW(backup.c_str())!=INVALID_FILE_ATTRIBUTES);
    assert(SetCurrentDirectoryW(original));
    assert(RemoveDirectoryW(root.c_str()));assert(RemoveDirectoryW(backup.c_str()));assert(RemoveDirectoryW(base.c_str()));
    std::cout<<"PASS: inherited working directory, transient lock retry, timeout preservation, destination collision\n";
}
