// Windows-native regression, not a simulated rendering test. It uses only its
// own temporary windows/settings and explicit pointer samples. It never starts
// App::run(), installs a Raw Input listener, or reads actual user input/content.
// Cross-compilation alone does NOT mean this test has run on Windows.
#ifdef NDEBUG
#undef NDEBUG
#endif
#define DESKTOP_PET_NATIVE_UI_TEST
#include "../src/DesktopPet.cpp"
#include <cassert>
#include <iostream>

namespace {
bool same(dog::Point a,dog::Point b){return std::abs(a.x-b.x)<1e-7&&std::abs(a.y-b.y)<1e-7;}
dog::Point projected(const App& app,dog::Point source){
    return dog::rotated((source-dog::pivot)*app.unit(),app.angle)
        +dog::Point{double(app.windowRect.left+app.radius),double(app.windowRect.top+app.radius)};
}
unsigned pixelAlpha(const App& app,int x,int y){
    assert(app.surface.bits&&x>=0&&y>=0&&x<app.surface.width&&y<app.surface.height);
    return static_cast<const BYTE*>(app.surface.bits)[(std::size_t(y)*app.surface.width+x)*4+3];
}
void assertReleased(const App& app){
    assert(!app.pressed&&!app.dragging&&!app.pressIsStroke&&!app.pressOnPet&&!app.stroke.active());
    assert(GetCapture()!=app.window);
}
void unchangedCounts(const App& app){
    assert(app.settings.counts.total==123456&&app.settings.counts.today==321);
    assert(!app.inputActive);
}
}

int main(){
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    ULONG_PTR token=0;GdiplusStartupInput startup;
    assert(GdiplusStartup(&token,&startup,nullptr)==Ok);
    {
        HINSTANCE instance=GetModuleHandleW(nullptr);
        wchar_t temp[MAX_PATH]{},name[MAX_PATH]{};
        assert(GetTempPathW(MAX_PATH,temp));assert(GetTempFileNameW(temp,L"DPs",0,name));
        assert(DeleteFileW(name));assert(CreateDirectoryW(name,nullptr));
        App app(instance);
        // Do not call Settings::init(): that targets the user's real AppData.
        assert(app.settings.positionLocked);
        app.settings.folder=name;app.settings.file=std::wstring(name)+L"\\settings.ini";
        app.settings.counts.enabled=true;app.settings.counts.total=123456;
        app.settings.counts.today=321;app.settings.counts.date=date();
        app.settings.always=true;app.settings.nap=0;app.dirty=true;
        assert(!app.inputActive);
        assert(app.settings.save());
        assert(GetPrivateProfileIntW(L"Dog",L"PositionLocked",99,app.settings.file.c_str())==1);

        WNDCLASSEXW cls{sizeof(cls)};cls.style=CS_DBLCLKS;cls.lpfnWndProc=App::proc;cls.hInstance=instance;
        cls.lpszClassName=L"DesktopPet.PettingTest";assert(RegisterClassExW(&cls));
        HWND window=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,
            cls.lpszClassName,L"Petting test fixture",WS_POPUP,100,100,1,1,
            nullptr,nullptr,instance,&app);assert(window);
        app.effects=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TRANSPARENT,
            L"STATIC",L"Petting effects fixture",WS_POPUP,0,0,1,1,window,nullptr,instance,nullptr);
        assert(app.effects);
        HWND peer=CreateWindowExW(WS_EX_TOOLWINDOW,L"STATIC",L"Capture fixture",WS_POPUP,
            0,0,1,1,nullptr,nullptr,instance,nullptr);assert(peer);
        RECT work{};assert(SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0));
        app.center={double(work.left+work.right)/2,double(work.top+work.bottom)/2};
        const auto originalCenter=app.center;
        app.settings.positionLocked=true;app.reduced=true;app.dpi=1;
        ShowWindow(window,SW_SHOWNOACTIVATE);

        // Real GDI+ drawing/hit paths at every orientation and common DPI.
        // The known samples lie well inside the original head and tail shapes.
        for(double dpi:{1.0,1.25,1.5,2.0})for(int turn=0;turn<4;++turn){
            app.dpi=dpi;app.angle=turn*dog::pi/2;
            assert(app.draw(0));assert(app.petHitReady);
            assert(app.hitsPet(projected(app,{305,150})));
            const auto tail=dog::bendTail({650,220},{},app.settings.tailSize);
            assert(app.hitsPet(projected(app,tail)));
            assert(!app.hitsPet(projected(app,{305,-20})));
            assert(!app.hitsPet(projected(app,{25,268}))); // baseline extension
            assert(!app.hitsPet(projected(app,{305,278}))); // clipped-away body
            assert(!app.hitsPet({double(app.windowRect.left+1),double(app.windowRect.top+1)}));
        }
        app.dpi=1;app.angle=0;assert(app.draw(0));
        assert(pixelAlpha(app,1,1)==0);
        const auto a=projected(app,{250,150}),b=projected(app,{350,150});
        const auto outside=projected(app,{305,-20});
        assert(app.hitsPet(a)&&app.hitsPet(b)&&!app.hitsPet(outside));

        // Find actual nontransparent badge pixels below the dog's baseline.
        // They remain part of the window but must not count as pettable fur.
        int badgePixels=0;dog::Point badge{};
        int below=int(std::ceil(projected(app,{305,268}).y-app.windowRect.top+3));
        for(int y=below;y<app.surface.height;++y)for(int x=0;x<app.surface.width;++x){
            if(pixelAlpha(app,x,y)<128)continue;
            dog::Point p{double(app.windowRect.left+x)+.5,double(app.windowRect.top+y)+.5};
            assert(!app.hitsPet(p));badge=p;++badgePixels;
        }
        assert(badgePixels>20);
        app.beginPointer(badge,1);app.movePointer(a,1.2);app.endPointer(a);
        assertReleased(app);assert(app.hearts.items.empty());unchangedCounts(app);

        app.reduced=false;app.hearts.items.clear();
        // The only time source for gesture sampling is the explicit t argument.
        app.beginPointer(a,10);assert(app.pressed&&app.pressIsStroke&&app.stroke.active());
        assert(GetCapture()==window);
        app.movePointer(a,10.5);assert(app.hearts.items.empty()); // stationary hold
        app.movePointer(b,10.6);assert(app.hearts.items.size()==1);
        assert(app.petExpression.value(10.7)>0);
        assert(same(app.center,originalCenter)&&!app.dragging);
        auto effectCount=app.hearts.items.size();
        app.movePointer(a,10.61);app.movePointer(b,10.62);
        assert(app.hearts.items.size()==effectCount); // no rapid mark burst
        app.endPointer(b);assertReleased(app);
        assert(app.hearts.items.size()==effectCount); // release is not a second pet
        unchangedCounts(app);

        // Leaving and returning drops the outside travel; it never teleports a
        // stroke from blank pixels. Re-entry still permits later real strokes.
        app.hearts.items.clear();app.beginPointer(a,20);
        app.movePointer(outside,20.2);app.movePointer(b,21);
        assert(app.hearts.items.empty());app.movePointer(a,21.2);
        assert(app.hearts.items.size()==1);
        app.movePointer(outside,21.4);app.endPointer(outside);
        assertReleased(app);assert(app.hearts.items.size()==1);
        assert(same(app.center,originalCenter));unchangedCounts(app);

        // A normal click keeps its original feedback without starting squeeze eyes.
        app.hearts.items.clear();app.petExpression.clear();
        app.beginPointer(a,30);app.endPointer(a);
        assertReleased(app);assert(app.hearts.items.size()==1);
        assert(app.petExpression.value(now()+.1)==0);
        assert(!app.petExpression.moving(now()));unchangedCounts(app);
        // Clicking during an existing expression neither clears nor renews it.
        app.petExpression.touch(now()-.45);
        const double expressionCheck=now()+.1;
        const double fadingBefore=app.petExpression.value(expressionCheck);
        assert(fadingBefore>0);
        app.pet(a);
        assert(app.petExpression.value(expressionCheck)==fadingBefore);unchangedCounts(app);

        // Dispatch the real message sequence to our fixture, without injecting
        // global input or claiming to test Windows' physical double-click timing.
        app.hearts.items.clear();app.petExpression.clear();
        POINT local{LONG(std::lround(a.x)),LONG(std::lround(a.y))};
        assert(ScreenToClient(window,&local));const LPARAM localPoint=MAKELPARAM(local.x,local.y);
        assert(GetClassLongPtrW(window,GCL_STYLE)&CS_DBLCLKS);
        SendMessageW(window,WM_LBUTTONDOWN,MK_LBUTTON,localPoint);
        SendMessageW(window,WM_LBUTTONUP,0,localPoint);
        assert(app.hearts.items.size()==1);
        SendMessageW(window,WM_LBUTTONDBLCLK,MK_LBUTTON,localPoint);
        assert(app.pressed&&!app.pressIsStroke&&!app.stroke.active());
        assert(app.settings.positionLocked);
        SendMessageW(window,WM_LBUTTONUP,0,localPoint);
        assertReleased(app);assert(app.hearts.items.size()==2);
        assert(app.petExpression.value(now()+.1)==0);unchangedCounts(app);

        // Only the second press temporarily permits dragging. The existing
        // four-logical-pixel threshold, landing feedback and saved lock remain.
        app.hearts.items.clear();
        const dog::Point doubleDragPoint{std::round(a.x),std::round(a.y)};
        app.beginPointer(doubleDragPoint,31,true);
        app.movePointer(doubleDragPoint+dog::Point{4,0},31.1);
        assert(!app.dragging&&same(app.center,originalCenter));
        app.movePointer(doubleDragPoint+dog::Point{30,18},31.2);
        assert(app.dragging&&!app.pressIsStroke&&app.settings.positionLocked);
        assert(same(app.center,originalCenter+dog::Point{30,18}));
        app.endPointer(doubleDragPoint+dog::Point{30,18});assertReleased(app);
        assert(app.hearts.items.empty()&&app.settings.positionLocked);unchangedCounts(app);
        app.center=originalCenter;assert(app.draw(0));
        app.beginPointer(a,32);
        assert(app.pressIsStroke&&app.stroke.active());app.cancelPointer();assertReleased(app);

        // The visible badge retains the existing drag surface, but is not fur:
        // neither a quiet double press nor travel from it can start petting.
        app.beginPointer(badge,33,true);app.endPointer(badge);
        assert(app.hearts.items.empty()&&app.petExpression.value(now()+.1)==0);
        app.beginPointer(badge,34,true);app.movePointer(a,34.2);
        assert(app.dragging&&!app.pressIsStroke&&!app.stroke.active());
        app.endPointer(a);assertReleased(app);
        assert(app.hearts.items.empty()&&app.settings.positionLocked);unchangedCounts(app);
        app.center=originalCenter;assert(app.draw(0));

        // Actual capture transfer dispatches WM_CAPTURECHANGED to the pet.
        for(bool doubleClick:{false,true}){
            app.hearts.items.clear();app.beginPointer(a,40,doubleClick);
            SetCapture(peer);assert(GetCapture()==peer);assertReleased(app);
            app.movePointer(b,40.5);app.endPointer(b);assert(app.hearts.items.empty());
            ReleaseCapture();
            app.beginPointer(a,50,doubleClick);SendMessageW(window,WM_CANCELMODE,0,0);
            assertReleased(app);app.movePointer(b,50.5);app.endPointer(b);
            assert(app.hearts.items.empty()&&app.settings.positionLocked);unchangedCounts(app);
        }

        // Existing drag semantics remain intact when unlocked.
        app.settings.positionLocked=false;app.petHitReady=false;
        const dog::Point dragPoint{std::round(a.x),std::round(a.y)};
        app.beginPointer(dragPoint,60);app.movePointer(dragPoint+dog::Point{30,18},60.2);
        assert(app.dragging&&!app.pressIsStroke);
        assert(same(app.center,originalCenter+dog::Point{30,18}));
        app.endPointer(dragPoint+dog::Point{30,18});assertReleased(app);
        assert(app.hearts.items.empty());unchangedCounts(app);

        // The real native checkbox stays open, reflects state, and persists.
        app.menu({LONG(std::lround(app.center.x)),LONG(std::lround(app.center.y))},dog::menu::Page::Appearance);
        HWND popup=app.contextMenu.windowHandle();assert(popup&&app.menuOpen);
        HWND checkbox=GetDlgItem(popup,LockPosition);assert(checkbox);
        assert((GetWindowLongPtrW(checkbox,GWL_STYLE)&0xf)==BS_AUTOCHECKBOX);
        assert(SendMessageW(checkbox,BM_GETCHECK,0,0)==BST_UNCHECKED);
        SendMessageW(checkbox,BM_CLICK,0,0);
        assert(app.settings.positionLocked&&IsWindow(popup)&&app.menuOpen);
        assert(SendMessageW(checkbox,BM_GETCHECK,0,0)==BST_CHECKED);
        app.save();assert(!app.dirty);
        assert(GetPrivateProfileIntW(L"Dog",L"PositionLocked",99,app.settings.file.c_str())==1);
        SendMessageW(checkbox,BM_CLICK,0,0);
        assert(!app.settings.positionLocked&&IsWindow(popup));
        app.save();assert(GetPrivateProfileIntW(L"Dog",L"PositionLocked",99,app.settings.file.c_str())==0);
        unchangedCounts(app);

        app.contextMenu.close();DestroyWindow(window);DestroyWindow(peer);
        assert(GetPrivateProfileIntW(L"Dog",L"Total",0,app.settings.file.c_str())==123456);
        assert(GetPrivateProfileIntW(L"Dog",L"Today",0,app.settings.file.c_str())==321);
        assert(DeleteFileW(app.settings.file.c_str()));
        DeleteFileW((app.settings.file+L".tmp").c_str());assert(RemoveDirectoryW(name));
        assert(UnregisterClassW(cls.lpszClassName,instance));
    }
    GdiplusShutdown(token);
    std::cout<<"PASS: native dog-only hit geometry, default petting, temporary second-click drag, ordinary double clicks, badge exclusion, capture/cancel, unchanged counts, unlocked dragging, menu and private-fixture settings\n";
}
