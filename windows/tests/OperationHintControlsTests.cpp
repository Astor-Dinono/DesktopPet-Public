// Only private fixture windows/settings; no App::run, real AppData, Raw Input,
// desktop capture or user input. Cross-compiling is not a Windows runtime pass.
#ifdef NDEBUG
#undef NDEBUG
#endif
#define DESKTOP_PET_NATIVE_UI_TEST
#include "../src/DesktopPet.cpp"
#include <cassert>
#include <iostream>

int main(){
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    ULONG_PTR token=0;GdiplusStartupInput startup;assert(GdiplusStartup(&token,&startup,nullptr)==Ok);
    {
        HINSTANCE instance=GetModuleHandleW(nullptr);App app(instance);
        wchar_t temp[MAX_PATH]{},name[MAX_PATH]{};assert(GetTempPathW(MAX_PATH,temp));assert(GetTempFileNameW(temp,L"DPh",0,name));assert(DeleteFileW(name));assert(CreateDirectoryW(name,nullptr));
        app.settings.folder=name;app.settings.file=std::wstring(name)+L"\\settings.ini";
        app.settings.counts.total=4321;app.settings.counts.today=21;app.settings.counts.date=date();app.settings.nap=0;
        assert(app.settings.operationHints);app.hintState.beginSession(app.settings.operationHints);
        WNDCLASSEXW cls{sizeof(cls)};cls.style=CS_DBLCLKS;cls.lpfnWndProc=App::proc;cls.hInstance=instance;cls.lpszClassName=L"DesktopPet.HintTest";assert(RegisterClassExW(&cls));
        HWND window=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,cls.lpszClassName,L"Hint fixture",WS_POPUP,0,0,1,1,nullptr,nullptr,instance,&app);assert(window);
        app.effects=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TRANSPARENT,L"STATIC",L"Hint effects fixture",WS_POPUP,0,0,1,1,window,nullptr,instance,nullptr);assert(app.effects);
        RECT area{};assert(SystemParametersInfoW(SPI_GETWORKAREA,0,&area,0));app.center={double(area.left+area.right)/2,double(area.top+area.bottom)/2};app.reduced=true;
        ShowWindow(window,SW_SHOWNOACTIVATE);HWND focusBefore=GetFocus();assert(app.draw(0));
        HWND hint=app.operationHint.windowHandle();assert(hint&&app.operationHint.isVisible());assert(GetFocus()==focusBefore);
        auto label=[&](int id){wchar_t text[64]{};assert(GetWindowTextW(GetDlgItem(hint,id),text,64));return std::wstring(text);};
        assert(label(dog::OperationHint::FirstLine)==L"双击按住拖动我");assert(label(dog::OperationHint::SecondLine)==L"按住来回摸摸我");
        assert(label(dog::OperationHint::CloseButton)==L"关闭"&&label(dog::OperationHint::NeverButton)==L"不再提示");
        wchar_t controlClass[32]{};assert(GetClassNameW(GetDlgItem(hint,dog::OperationHint::CloseButton),controlClass,32));assert(_wcsicmp(controlClass,L"Button")==0);
        assert(GetWindowLongPtrW(GetDlgItem(hint,dog::OperationHint::NeverButton),GWL_STYLE)&WS_TABSTOP);
        auto placed=app.operationHint.currentPlacement();assert(placed&&dog::hintFits(placed->frame,app.work()));
        RedrawWindow(hint,nullptr,nullptr,RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN);
        assert(!GetUpdateRect(hint,nullptr,FALSE));assert(app.draw(0));assert(app.operationHint.windowHandle()==hint);assert(!GetUpdateRect(hint,nullptr,FALSE));
        auto click=[&](int id){SendMessageW(GetDlgItem(hint,id),BM_CLICK,0,0);};
        click(dog::OperationHint::CloseButton);assert(!app.operationHint.isVisible()&&!app.hintState.requested&&app.settings.operationHints);
        app.show(false);app.show(true);assert(app.draw(0));assert(!app.operationHint.isVisible());
        app.command(ShowOperationHint);assert(app.draw(0));assert(app.operationHint.isVisible()&&app.settings.operationHints);
        click(dog::OperationHint::NeverButton);assert(!app.hintState.requested&&!app.settings.operationHints);app.save();
        assert(GetPrivateProfileIntW(L"Dog",L"OperationHints",99,app.settings.file.c_str())==0);
        app.command(ShowOperationHint);assert(app.draw(0));assert(app.operationHint.isVisible()&&!app.settings.operationHints);
        app.settings.positionLocked=false;assert(app.draw(0));
        assert(label(dog::OperationHint::FirstLine)==L"按住拖动我"&&label(dog::OperationHint::SecondLine)==L"点一下摸摸我");
        app.menu({LONG(app.center.x),LONG(app.center.y)});assert(!app.operationHint.isVisible()&&app.hintState.requested);
        app.contextMenu.close();assert(app.draw(0));assert(app.operationHint.isVisible());
        app.setNap(true);assert(!app.operationHint.isVisible()&&app.hintState.requested);assert(app.draw(0));assert(!app.operationHint.isVisible());
        app.activity(false);assert(app.draw(0));assert(app.operationHint.isVisible());
        app.beginPointer(app.center,10,true);assert(!app.operationHint.isVisible()&&app.hintState.requested);
        app.cancelPointer();assert(app.draw(0));assert(app.operationHint.isVisible());
        click(dog::OperationHint::CloseButton);app.hintState.beginSession(app.settings.operationHints);assert(app.draw(0));assert(!app.operationHint.isVisible());
        assert(!app.inputActive&&app.settings.counts.total==4321&&app.settings.counts.today==21);
        DestroyWindow(window);app.save();assert(DeleteFileW(app.settings.file.c_str()));DeleteFileW((app.settings.file+L".tmp").c_str());assert(RemoveDirectoryW(name));assert(UnregisterClassW(cls.lpszClassName,instance));
    }
    GdiplusShutdown(token);std::cout<<"PASS: native hint controls/text, close versus opt-out, manual reopen, transient hiding, stable frame and unchanged counts\n";
}
