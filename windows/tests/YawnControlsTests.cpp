// Windows-native integration regression. Own temporary windows/settings only;
// never App::run(), a Raw Input listener, or injected physical input. Building
// this on macOS does not mean the native rendering/controls ran on Windows.
#ifdef NDEBUG
#undef NDEBUG
#endif
#define DESKTOP_PET_NATIVE_UI_TEST
#include "../src/DesktopPet.cpp"
#include <cassert>
#include <iostream>

namespace {
void expectNear(double a,double b){assert(std::abs(a-b)<1e-10);}
void unchangedCounts(const App& app){assert(!app.inputActive&&app.settings.counts.total==123456&&app.settings.counts.today==321);}
dog::Point screenPoint(const App& app,dog::Point p){
    return dog::rotated((p-dog::pivot)*app.unit(),app.angle)
        +dog::Point{double(app.windowRect.left+app.radius),double(app.windowRect.top+app.radius)};
}
std::vector<BYTE> pixels(const App& app){const auto* data=static_cast<const BYTE*>(app.surface.bits);return {data,data+app.surface.width*app.surface.height*4};}
}

int main(){
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    ULONG_PTR token=0;GdiplusStartupInput startup;assert(GdiplusStartup(&token,&startup,nullptr)==Ok);
    {
        HINSTANCE instance=GetModuleHandleW(nullptr);App app(instance);
        wchar_t temp[MAX_PATH]{},name[MAX_PATH]{};
        assert(GetTempPathW(MAX_PATH,temp));assert(GetTempFileNameW(temp,L"DPy",0,name));
        assert(DeleteFileW(name)&&CreateDirectoryW(name,nullptr));
        app.settings.folder=name;app.settings.file=std::wstring(name)+L"\\settings.ini";
        app.settings.counts.total=123456;app.settings.counts.today=321;app.settings.counts.date=date();
        app.settings.nap=0;app.settings.operationHints=false;app.hintState.beginSession(false);
        assert(app.settings.save());
        WNDCLASSEXW cls{sizeof(cls)};cls.style=CS_DBLCLKS;cls.lpfnWndProc=App::proc;
        cls.hInstance=instance;cls.lpszClassName=L"DesktopPet.YawnTest";assert(RegisterClassExW(&cls));
        HWND window=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,
            cls.lpszClassName,L"Yawn test fixture",WS_POPUP,100,100,1,1,nullptr,nullptr,instance,&app);assert(window);
        app.effects=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TRANSPARENT,
            L"STATIC",L"Yawn effects fixture",WS_POPUP,0,0,1,1,window,nullptr,instance,nullptr);assert(app.effects);
        RECT work{};assert(SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0));
        app.center={double(work.left+work.right)/2,double(work.top+work.bottom)/2};
        app.dpi=1;ShowWindow(window,SW_SHOWNOACTIVATE);

        // Repeated sleep requests preserve the first timeline. Draw every
        // transition stage with native GDI+ and verify transformed hit geometry.
        app.setNap(true,10);app.setNap(true,11);expectNear(app.rest.started,10);expectNear(app.yawn.pose(11)->time,1);
        for(double dpi:{1.,1.25,1.5,2.})for(int orientation=0;orientation<4;++orientation){
            app.dpi=dpi;app.angle=orientation*dog::pi/2;
            for(double age:{.08,1.2,3.4,4.18,5.2}){
                assert(app.draw(10+age)&&app.petHitReady);
                const auto pose=app.yawn.pose(10+age);
                const auto head=dog::blendedYawnHead(pose?pose->time:0,pose?pose->weight:0,1,1);
                assert(app.hitsPet(screenPoint(app,head.apply({305,150}))));
                assert(!app.hitsPet({double(app.windowRect.left+1),double(app.windowRect.top+1)}));
                if(age<4)assert(!app.fxShown);else if(age>5)assert(app.fxShown);
            }
        }
        app.dpi=1;app.angle=0;
        // Reduced motion draws ordinary sleep, independent of a live yawn.
        app.reduced=true;assert(app.draw(12));const auto reduced=pixels(app);const auto recorded=app.yawn;
        app.yawn.clear();assert(app.draw(12));assert(pixels(app)==reduced);app.yawn=recorded;app.reduced=false;

        // Real hover routing changes only cheeks while sleeping, including
        // while the clip is still active. It never postpones automatic sleep.
        const double epoch=now()-1.2;
        app.setNap(false,epoch);app.setNap(true,epoch);app.lastActivity=epoch-30;
        assert(app.draw(epoch+1.2));
        const auto a=screenPoint(app,{250,150}),b=screenPoint(app,{350,150});
        assert(app.hitsPet(a)&&app.hitsPet(b));
        const auto tailStart=app.tail.started,duangStart=app.duang.started,lastActivity=app.lastActivity;
        app.moveHover(a,epoch+1.2,false);app.validateHover(a,epoch+1.56,false,true);app.moveHover(b,epoch+1.7,false);
        assert(app.rest.sleeping);expectNear(app.rest.started,epoch);expectNear(app.lastActivity,lastActivity);
        expectNear(app.yawn.pose(epoch+2)->time,2);assert(app.blush.value(epoch+2)>0);
        expectNear(app.tail.started,tailStart);expectNear(app.duang.started,duangStart);
        assert(app.hearts.items.empty()&&!app.petExpression.moving(epoch+2));unchangedCounts(app);

        // Global activity wakes quietly, and further activity does not restart
        // the current-frame handoff or create local interaction particles.
        const double activityTime=now();const auto before=*app.yawn.pose(activityTime);
        app.activity(false);assert(!app.rest.sleeping);auto after=app.yawn.pose(now());assert(after);
        assert(std::abs(after->time-before.time)<.1);assert(app.hearts.items.empty());
        const double future=now()+.12;const auto fading=app.yawn.pose(future);app.activity(false);
        assert(fading&&app.yawn.pose(future));expectNear(fading->weight,app.yawn.pose(future)->weight);
        assert(!app.yawn.pose(now()+.3));unchangedCounts(app);

        // A direct click/press and drag still wake; sleep-hover is the sole
        // special branch. Existing drag uses the existing pointer capture.
        app.setNap(true,now()-1);app.pet(a);assert(!app.rest.sleeping&&app.hearts.items.size()==1);
        app.setNap(true,now()-1);app.settings.positionLocked=false;
        app.beginPointer(a,now());assert(!app.rest.sleeping&&app.pressed);
        app.movePointer(a+dog::Point{30,18},now());assert(app.dragging);
        app.cancelPointer();assert(!app.dragging&&!app.pressed);unchangedCounts(app);

        // An overdue automatic nap starts at its original inactivity deadline,
        // so returning after a long gap never replays an already elapsed yawn.
        app.lastActivity=now()-100;app.settings.nap=30;const double deadline=app.lastActivity+30;
        app.tick();assert(app.rest.sleeping&&!app.yawn.pose(now()));expectNear(app.rest.started,deadline);
        app.settings.nap=0;app.setNap(false);

        // Hide and suspension discard an unfinished clip without trapping
        // its suppressed bubble/letters at zero after resuming.
        app.setNap(true,now()-1);app.show(false);assert(!app.yawn.pose(now()));
        expectNear(app.yawn.sleepDecorationAmount(now()),1);app.show(true);assert(app.rest.sleeping);
        app.setNap(false);app.setNap(true,now()-1);app.suspended=true;app.pauseChanged();
        assert(!app.yawn.pose(now()));expectNear(app.yawn.sleepDecorationAmount(now()),1);
        app.suspended=false;app.pauseChanged();assert(app.rest.sleeping);unchangedCounts(app);
        DestroyWindow(window);
        assert(DeleteFileW(app.settings.file.c_str()));DeleteFileW((app.settings.file+L".tmp").c_str());assert(RemoveDirectoryW(name));
    }
    GdiplusShutdown(token);
    std::cout<<"PASS: native yawn handoff rendering/hit paths, reduced motion, sleeping hover, wake/drag and lifecycle cancellation; counts unchanged\n";
}
