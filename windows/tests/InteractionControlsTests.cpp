// Windows-native regression: only owned fixture windows and a fresh temp folder.
// Cross-compilation is NOT evidence that the Windows focus/menu behavior ran.
#ifdef NDEBUG
#undef NDEBUG
#endif
#define DESKTOP_PET_NATIVE_UI_TEST
#include "../src/DesktopPet.cpp"
#include <cassert>
#include <iostream>

int main(){
    ULONG_PTR token=0;GdiplusStartupInput startup;assert(GdiplusStartup(&token,&startup,nullptr)==Ok);
    {
    HINSTANCE instance=GetModuleHandleW(nullptr);
    wchar_t temp[MAX_PATH]{},name[MAX_PATH]{};
    assert(GetTempPathW(MAX_PATH,temp));assert(GetTempFileNameW(temp,L"DPe",0,name));
    assert(DeleteFileW(name));assert(CreateDirectoryW(name,nullptr));
    App app(instance);app.settings.folder=name;app.settings.file=std::wstring(name)+L"\\settings.ini";
    WNDCLASSEXW cls{sizeof(cls)};cls.lpfnWndProc=App::proc;cls.hInstance=instance;cls.lpszClassName=L"DesktopPet.InteractionTest";assert(RegisterClassExW(&cls));
    HWND window=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,cls.lpszClassName,L"Dog fixture",WS_POPUP,100,100,160,100,nullptr,nullptr,instance,&app);assert(window);
    HWND peer=CreateWindowExW(WS_EX_TOOLWINDOW,L"STATIC",L"Other owned fixture",WS_POPUP,300,100,160,100,nullptr,nullptr,instance,nullptr);assert(peer);
    ShowWindow(window,SW_SHOWNOACTIVATE);ShowWindow(peer,SW_SHOW);SetActiveWindow(peer);SetFocus(peer);
    assert(GetWindowLongPtrW(window,GWL_EXSTYLE)&WS_EX_NOACTIVATE);
    int orientation=app.settings.orientation;
    SendMessageW(window,WM_KEYDOWN,'R',0);assert(app.settings.orientation==orientation);

    assert(SendMessageW(window,WM_MOUSEACTIVATE,WPARAM(window),MAKELPARAM(HTCLIENT,WM_LBUTTONDOWN))==MA_ACTIVATE);
    SendMessageW(window,WM_LBUTTONDOWN,0,0);
    assert(app.selected&&GetFocus()==window);
    assert(!(GetWindowLongPtrW(window,GWL_EXSTYLE)&WS_EX_NOACTIVATE));
    SendMessageW(window,WM_KEYDOWN,'R',0);assert(app.settings.orientation==(orientation+1)%4);
    orientation=app.settings.orientation;
    SendMessageW(window,WM_KEYDOWN,'R',LPARAM(1)<<30);assert(app.settings.orientation==orientation);
    SendMessageW(window,WM_LBUTTONUP,0,0);
    SendMessageW(window,WM_KEYDOWN,VK_ESCAPE,0);assert(!app.selected);
    assert(GetWindowLongPtrW(window,GWL_EXSTYLE)&WS_EX_NOACTIVATE);
    SendMessageW(window,WM_KEYDOWN,'R',0);assert(app.settings.orientation==orientation);

    // Choosing the menu command also grants a real local keyboard selection.
    app.command(Rotate);assert(app.selected&&GetFocus()==window);
    orientation=app.settings.orientation;
    SendMessageW(window,WM_KEYDOWN,'R',0);assert(app.settings.orientation==(orientation+1)%4);
    SetActiveWindow(peer);SetFocus(peer);assert(!app.selected);
    assert(GetWindowLongPtrW(window,GWL_EXSTYLE)&WS_EX_NOACTIVATE);

    unsigned expected=app.settings.effectsMask;
    app.menu({100,100},dog::menu::Page::Effects);
    HWND popup=app.contextMenu.windowHandle();assert(popup&&app.menuOpen);
    for(int pass=0;pass<2;++pass)for(unsigned index=0;index<4;++index){
        HWND checkbox=GetDlgItem(popup,EffectHeart+index);
        assert((GetWindowLongPtrW(checkbox,GWL_STYLE)&0xf)==BS_AUTOCHECKBOX);
        SendMessageW(checkbox,BM_CLICK,0,0);expected^=1u<<index;
        assert(app.settings.effectsMask==expected&&IsWindow(popup)&&IsWindow(window));
    }
    auto click=[&](int id){HWND child=GetDlgItem(popup,id);assert(child);SendMessageW(child,BM_CLICK,0,0);};
    click(dog::menu::Back);assert(!GetDlgItem(popup,Quit));assert(GetDlgItem(popup,Pet));
    app.hearts.items.clear();click(Pet);click(Pet);assert(app.hearts.items.size()==2&&IsWindow(popup));
    click(dog::menu::Appearance);
    HWND size=GetDlgItem(popup,dog::menu::SizeChoice);assert(size);
    SendMessageW(size,CB_SETCURSEL,2,0);SendMessageW(popup,WM_COMMAND,MAKEWPARAM(dog::menu::SizeChoice,CBN_SELCHANGE),LPARAM(size));
    assert(app.settings.size==.75&&IsWindow(popup));
    HWND tail=GetDlgItem(popup,dog::menu::TailChoice);assert(tail);
    SendMessageW(tail,CB_SETCURSEL,1,0);SendMessageW(popup,WM_COMMAND,MAKEWPARAM(dog::menu::TailChoice,CBN_SELCHANGE),LPARAM(tail));
    assert(app.settings.tailSize==dog::TailSize::Original);
    click(dog::menu::Back);click(dog::menu::Sleep);click(Nap300);assert(app.settings.nap==300&&IsWindow(popup));
    click(dog::menu::Back);click(dog::menu::Counts);click(Always);assert(app.settings.always&&IsWindow(popup));
    MSG escape{};escape.hwnd=GetFocus();escape.message=WM_KEYDOWN;escape.wParam=VK_ESCAPE;
    assert(app.contextMenu.dialogMessage(escape)&&GetDlgItem(popup,Pet));
    escape.hwnd=GetFocus();assert(app.contextMenu.dialogMessage(escape));assert(!app.contextMenu.windowHandle()&&!app.menuOpen);
    app.menu({100,100});popup=app.contextMenu.windowHandle();assert(popup);
    click(dog::menu::More);assert(GetDlgItem(popup,Quit));
    click(dog::menu::Back);click(dog::menu::Appearance);click(Rotate);
    assert(!app.contextMenu.windowHandle()&&!app.menuOpen&&app.selected&&GetFocus()==window);
    app.menu({100,100});assert(app.contextMenu.windowHandle());
    SetActiveWindow(peer);SetFocus(peer);assert(!app.contextMenu.windowHandle()&&!app.menuOpen);
    app.save();DestroyWindow(window);DestroyWindow(peer);
    assert(GetPrivateProfileIntW(L"Dog",L"TailSize",0,app.settings.file.c_str())==100);
    assert(GetPrivateProfileIntW(L"Dog",L"AutoNap",0,app.settings.file.c_str())==300);
    assert(GetPrivateProfileIntW(L"Dog",L"AlwaysShow",0,app.settings.file.c_str())==1);
    DeleteFileW(app.settings.file.c_str());DeleteFileW((app.settings.file+L".tmp").c_str());assert(RemoveDirectoryW(name));
    }
    GdiplusShutdown(token);
    std::cout<<"PASS: native focus/R, all soft menu pages, repeated native checkbox toggles, combos, radios, Esc/outside dismissal, safe exit placement, settings preservation\n";
}
