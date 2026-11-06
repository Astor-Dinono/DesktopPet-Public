#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wtsapi32.h>
#include <gdiplus.h>
#include <cwchar>
#include <memory>
#include <string>
#include <atomic>
#include <random>
#include "DogArtwork.hpp"
#include "InteractionEffectArtwork.hpp"
#include "DogUpdater.hpp"
#include "ContextMenu.hpp"
#include "RotationFocus.hpp"
#include "HeldKeys.hpp"
#include "StrokeGesture.hpp"
#include "HoverStrokeGesture.hpp"
#include "PetExpression.hpp"
#include "YawnMotion.hpp"
#include "YawnDrawing.hpp"
#include "SqueezeEyes.hpp"
#include "OperationHint.hpp"

using namespace Gdiplus;
using namespace dog::menu;
namespace {
constexpr wchar_t className[]=L"DesktopPet.Windows.Preview";
constexpr UINT trayMessage=WM_APP+1,showMessage=WM_APP+2,updateSaveMessage=WM_APP+3,updateQuitMessage=WM_APP+4;
constexpr UINT_PTR saveTimer=2;
const GUID consoleDisplayState={0x6fe69556,0x704a,0x47a0,{0x8f,0x24,0xc2,0x8d,0x93,0x6f,0xda,0x47}};
double now() { static LARGE_INTEGER f{},start{};if(!f.QuadPart){QueryPerformanceFrequency(&f);QueryPerformanceCounter(&start);}LARGE_INTEGER t;QueryPerformanceCounter(&t);return double(t.QuadPart-start.QuadPart)/double(f.QuadPart); }
int date() {SYSTEMTIME t;GetLocalTime(&t);return t.wYear*10000+t.wMonth*100+t.wDay;}
PointF pf(dog::Point p){return PointF(REAL(p.x),REAL(p.y));}
BYTE alpha(double v){return BYTE(std::lround(dog::clamp(v)*255));}

// DIB/DC/Bitmap are reused. No window enumeration, path parsing, or resource creation per point.
struct Surface {
    HDC dc=nullptr;HBITMAP dib=nullptr;HGDIOBJ old=nullptr;void* bits=nullptr;int width=0,height=0;
    std::unique_ptr<Bitmap> bitmap;std::unique_ptr<Graphics> graphics;
    ~Surface(){clear();}
    void clear(){graphics.reset();bitmap.reset();if(dc&&old)SelectObject(dc,old);if(dib)DeleteObject(dib);if(dc)DeleteDC(dc);dc=nullptr;dib=nullptr;old=nullptr;bits=nullptr;width=height=0;}
    bool resize(int w,int h){
        if(width==w&&height==h&&graphics)return true;
        clear();BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=w;info.bmiHeader.biHeight=-h;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
        dc=CreateCompatibleDC(nullptr);if(!dc)return false;
        dib=CreateDIBSection(dc,&info,DIB_RGB_COLORS,&bits,nullptr,0);if(!dib){clear();return false;}
        old=SelectObject(dc,dib);width=w;height=h;
        bitmap=std::make_unique<Bitmap>(w,h,w*4,PixelFormat32bppPARGB,static_cast<BYTE*>(bits));
        graphics=std::make_unique<Graphics>(bitmap.get());
        graphics->SetSmoothingMode(SmoothingModeAntiAlias);graphics->SetPixelOffsetMode(PixelOffsetModeHighQuality);
        graphics->SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
        if(bitmap->GetLastStatus()!=Ok||graphics->GetLastStatus()!=Ok){clear();return false;}return true;
    }
    bool present(HWND window,int x,int y){
        graphics->Flush(FlushIntentionSync);POINT dst{x,y},src{0,0};SIZE size{width,height};BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
        return UpdateLayeredWindow(window,nullptr,&dst,&size,dc,&src,0,&blend,ULW_ALPHA)!=FALSE;
    }
};
struct Settings {
    dog::TailSize tailSize=dog::TailSize::Small;
    std::wstring folder,file;dog::Counts counts;double size=.62;int orientation=0,nap=180;unsigned effectsMask=1;bool always=false,hasPosition=false,positionLocked=false,operationHints=true;dog::Point center;
    bool init(){
        PWSTR base=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,KF_FLAG_CREATE,nullptr,&base)))return false;
        folder=std::wstring(base)+L"\\DesktopPet";CoTaskMemFree(base);
        if(!CreateDirectoryW(folder.c_str(),nullptr)&&GetLastError()!=ERROR_ALREADY_EXISTS)return false;
        file=folder+L"\\settings.ini";
        auto read=[&](const wchar_t* key,const wchar_t* fallback){wchar_t text[128]{};GetPrivateProfileStringW(L"Dog",key,fallback,text,128,file.c_str());return std::wstring(text);};
        auto integer=[&](const wchar_t* key,int fallback){return int(GetPrivateProfileIntW(L"Dog",key,fallback,file.c_str()));};
        counts.enabled=integer(L"Counting",0)==1;counts.total=std::wcstoull(read(L"Total",L"0").c_str(),nullptr,10);counts.today=std::wcstoull(read(L"Today",L"0").c_str(),nullptr,10);counts.date=integer(L"Date",0);counts.roll(date());
        size=dog::clamp(std::wcstod(read(L"Size",L"0.62").c_str(),nullptr),.5,.75);
        orientation=std::clamp(integer(L"Orientation",0),0,3);nap=integer(L"AutoNap",180);
        if(nap!=0&&nap!=30&&nap!=60&&nap!=180&&nap!=300)nap=180;
        always=integer(L"AlwaysShow",0)==1;hasPosition=integer(L"HasPosition",0)==1;
        effectsMask=unsigned(integer(L"InteractionEffects",1))&15;
        tailSize=dog::storedTailSize(integer(L"TailSize",80));
        positionLocked=integer(L"PositionLocked",0)==1;
        operationHints=integer(L"OperationHints",1)==1;
        center={std::wcstod(read(L"CenterX",L"0").c_str(),nullptr),std::wcstod(read(L"CenterY",L"0").c_str(),nullptr)};
        if(!std::isfinite(center.x)||!std::isfinite(center.y)||std::abs(center.x)>100000||std::abs(center.y)>100000)hasPosition=false;
        return true;
    }
    bool save(){
        std::wstring text=L"\xFEFF[Dog]\r\nCounting="+std::to_wstring(counts.enabled)+L"\r\nTotal="+std::to_wstring(counts.total)+L"\r\nToday="+std::to_wstring(counts.today)+L"\r\nDate="+std::to_wstring(counts.date)+L"\r\nSize="+std::to_wstring(size)+L"\r\nOrientation="+std::to_wstring(orientation)+L"\r\nAutoNap="+std::to_wstring(nap)+L"\r\nAlwaysShow="+std::to_wstring(always)+L"\r\nHasPosition=1\r\nCenterX="+std::to_wstring(center.x)+L"\r\nCenterY="+std::to_wstring(center.y)+L"\r\n";
        text+=L"InteractionEffects="+std::to_wstring(effectsMask)+L"\r\n";
        text+=L"TailSize="+std::to_wstring(int(tailSize))+L"\r\n";
        text+=L"PositionLocked="+std::to_wstring(positionLocked)+L"\r\n";
        text+=L"OperationHints="+std::to_wstring(operationHints)+L"\r\n";
        auto temp=file+L".tmp";HANDLE h=CreateFileW(temp.c_str(),GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(h==INVALID_HANDLE_VALUE)return false;
        DWORD written=0,bytes=DWORD(text.size()*sizeof(wchar_t));bool ok=WriteFile(h,text.data(),bytes,&written,nullptr)&&written==bytes;CloseHandle(h);
        if(ok)ok=MoveFileExW(temp.c_str(),file.c_str(),MOVEFILE_REPLACE_EXISTING)!=FALSE;
        if(!ok)DeleteFileW(temp.c_str());return ok;
    }
};
struct App {
    HINSTANCE instance;HWND window=nullptr,effects=nullptr;HANDLE timer=nullptr;HPOWERNOTIFY displayNotification=nullptr;UINT taskbarCreated=0;bool trayAdded=false,displayOff=false,saveWarningShown=false,fxShown=false;
    Settings settings;Surface surface,fx;dog::Tail tail;dog::Duang duang;dog::Rest rest;dog::Blush blush;dog::Hearts hearts;dog::Turn turn;dog::Updater updater;
    dog::ContextMenu contextMenu;dog::HeldKeys heldKeys;
    dog::StrokeGesture stroke;dog::HoverStrokeGesture hoverStroke;dog::PetExpression petExpression;dog::YawnMotion yawn;
    std::unique_ptr<dog::YawnDrawing> yawnDrawing;
    dog::OperationHint operationHint;dog::OperationHintState hintState;
    GraphicsPath petHitPath{FillModeWinding},petHitClip,earFill{FillModeWinding};bool petHitReady=false,pressIsStroke=false,pressOnPet=false;
    double lastStrokeEffect=-100,lastStrokeDuang=-100;
    inline static std::atomic<HWND> callbackWindow{nullptr};bool readySent=false;
    dog::Fade countFade;bool resumeTurn=false;double resumeAngle=0;
    dog::EffectPicker effectPicker;std::mt19937 effectRandom{std::random_device{}()};
    dog::Point center;double angle=0,dpi=1,lastActivity=0,nextFrame=0,lastFrame=-100;bool turning=false,visible=true,suspended=false,locked=false,reduced=false,hover=false,selected=false,pressed=false,dragging=false,inputActive=false,dirty=false,menuOpen=false;
    POINT pressPoint{};dog::Point pressCenter;int radius=0,fxPad=0;RECT windowRect{};unsigned frameFailures=0;
    // Parsed once, then only transformed at render time.
    const std::vector<dog::Segment> head=dog::parsePath(dog::headPath),tailShape=dog::parsePath(dog::tailPath),mouth=dog::parsePath(dog::mouthPath),bubble=dog::parsePath(dog::bubblePath),heart=dog::parsePath(dog::heartPath);
    App(HINSTANCE value):instance(value){
        (void)dog::effectArtwork();dog::Point current{};
        for(const auto& s:dog::earFillSegments()){
            if(s.type=='M'){earFill.StartFigure();current=s.points[0];}
            else if(s.type=='L'){earFill.AddLine(pf(current),pf(s.points[0]));current=s.points[0];}
            else if(s.type=='Z')earFill.CloseFigure();
        }
    }
    double unit()const{return dog::sourceScale*settings.size*dpi;}
    dog::Bounds work()const{
        POINT p{LONG(std::lround(center.x)),LONG(std::lround(center.y))};MONITORINFO info{sizeof(info)};
        GetMonitorInfoW(MonitorFromPoint(p,MONITOR_DEFAULTTONEAREST),&info);
        return {double(info.rcWork.left),double(info.rcWork.top),double(info.rcWork.right),double(info.rcWork.bottom)};
    }
    void markDirty(){if(!dirty)SetTimer(window,saveTimer,2000,nullptr);dirty=true;}
    void save(){
        if(!dirty)return;settings.center=center;
        if(settings.save()){dirty=false;saveWarningShown=false;}
        else if(!saveWarningShown){saveWarningShown=true;MessageBoxW(window,L"本地设置暂时无法保存，最近的计数和位置可能丢失。请检查本地文件夹权限或磁盘空间。",L"小狗桌宠",MB_OK|MB_ICONWARNING);}
    }
    void updateReduced(){BOOL enabled=TRUE;SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION,0,&enabled,0);reduced=!enabled;}
    bool running()const{return visible&&!suspended&&!locked&&!displayOff;}
    void requestFrame(){if(running()){nextFrame=std::min(nextFrame,std::max(now(),lastFrame+1.0/60));schedule();}}
    void schedule(){
        if(!timer)return;if(!running()){CancelWaitableTimer(timer);return;}
        LARGE_INTEGER due;due.QuadPart=-LONGLONG(std::max(.0001,nextFrame-now())*10000000);
        SetWaitableTimer(timer,&due,0,nullptr,nullptr,FALSE);
    }
    bool fast(double t)const{return !reduced&&(turning||(pressed&&!pressIsStroke)||tail.moving(t)||duang.moving(t)||rest.moving(t)||yawn.moving(t)||t-blush.started<2.6||petExpression.moving(t)||countFade.moving(t)||!hearts.items.empty());}
    void activity(bool wag){
        double t=now();lastActivity=t;
        if(running()&&!dragging){if(rest.sleeping)yawn.cancel(t);rest.setSleep(false,t);if(wag)tail.wag(t);requestFrame();}
    }
    void setNap(bool sleeping,double t){
        if(rest.sleeping==sleeping){if(!sleeping)lastActivity=t;return;}
        if(sleeping){yawn.start(t);hoverStroke.cancel();operationHint.hide();tail.settle(t);petExpression.clear();hearts.items.clear();if(duang.moving(t))duang.kick(t,0);}
        else{yawn.cancel(t);lastActivity=t;}
        rest.setSleep(sleeping,t);requestFrame();
    }
    void setNap(bool sleeping){setNap(sleeping,now());}
    void updateOperationHint(dog::Bounds petBounds,dog::Bounds badgeBounds){
        if(!hintState.available(running(),rest.sleeping,menuOpen,pressed,turning)){operationHint.hide();return;}
        auto placement=dog::operationHintPlacement(petBounds,badgeBounds,work(),dpi,operationHint.currentPlacement());
        if(!placement){operationHint.hide();return;}
        operationHint.show(window,*placement,settings.positionLocked,[this](bool never){
            hintState.dismiss();if(never){settings.operationHints=false;markDirty();}
        });
    }
    void touchEffect(dog::Point p,double t){auto kind=effectPicker.next(settings.effectsMask,[&](unsigned n){return std::uniform_int_distribution<unsigned>(0,n-1)(effectRandom);});if(kind)hearts.add(p,t,*kind);}
    void pet(dog::Point p){activity(false);double t=now();duang.kick(t,.75);blush.touch(t);if(!reduced)tail.wag(t);touchEffect(p,t);requestFrame();}
    void strokePet(dog::Point p,double t,bool fromHover=false){
        if(fromHover&&rest.sleeping){blush.touch(t);requestFrame();return;}
        activity(false);blush.touch(t);petExpression.touch(t);if(!reduced)tail.wag(t);
        // Sustain the expression; keep repeated squashes and floating marks sparse.
        if(t-lastStrokeDuang>=.65){duang.kick(t,.22);lastStrokeDuang=t;}
        if(t-lastStrokeEffect>=.65){touchEffect(p,t);lastStrokeEffect=t;}
        requestFrame();
    }
    bool hitsPet(dog::Point screenPoint){
        if(!petHitReady)return false;
        PointF p(REAL(screenPoint.x-windowRect.left),REAL(screenPoint.y-windowRect.top));
        if(!petHitClip.IsVisible(p))return false;
        Pen outline(Color(255,0,0,0),REAL(dog::outlineWidth*unit()));
        outline.SetLineJoin(LineJoinRound);outline.SetStartCap(LineCapRound);outline.SetEndCap(LineCapRound);
        return petHitPath.IsVisible(p)||petHitPath.IsOutlineVisible(p,&outline);
    }
    static bool pointerButtonsDown(){
        for(int key:{VK_LBUTTON,VK_RBUTTON,VK_MBUTTON,VK_XBUTTON1,VK_XBUTTON2})
            if(GetAsyncKeyState(key)&0x8000)return true;
        return false;
    }
    bool hoverBlocked(bool buttonsDown)const{
        return buttonsDown||pressed||dragging||menuOpen||turning||!running();
    }
    void moveHover(dog::Point p,double t,bool buttonsDown){
        if(hoverStroke.move(p*(1/dpi),t,hitsPet(p),hoverBlocked(buttonsDown)))strokePet(p,t,true);
    }
    void validateHover(dog::Point p,double t,bool buttonsDown,bool overWindow){
        // Existing frames only validate/arm the dwell. They never accumulate
        // movement, trigger feedback, or treat breathing as cursor movement.
        hoverStroke.validate(p*(1/dpi),t,overWindow&&hitsPet(p),hoverBlocked(buttonsDown));
    }
    dog::Point pointerPoint(LPARAM l){POINT p{GET_X_LPARAM(l),GET_Y_LPARAM(l)};ClientToScreen(window,&p);return {double(p.x),double(p.y)};}
    void resumePointerTurn(){
        if(resumeTurn){turn.begin({center,{},angle,0},resumeAngle,now(),unit(),work());turning=true;resumeTurn=false;requestFrame();}
    }
    void cancelPointer(){
        bool wasDragging=dragging;pressed=dragging=pressIsStroke=pressOnPet=false;stroke.cancel();hoverStroke.cancel();
        if(GetCapture()==window)ReleaseCapture();
        if(wasDragging)fit();resumePointerTurn();
    }
    void beginPointer(dog::Point p,double t){
        if(!running()||menuOpen)return;
        operationHint.hide();
        cancelPointer();selectForRotation();pressed=true;pressIsStroke=settings.positionLocked;pressOnPet=hitsPet(p);dragging=false;
        resumeTurn=turning;if(turning){auto pose=turn.pose(t);center=pose.center;angle=pose.angle;resumeAngle=turn.target;turning=false;}
        pressPoint={LONG(std::lround(p.x)),LONG(std::lround(p.y))};pressCenter=center;
        if(pressIsStroke)stroke.begin(p*(1/dpi),t,hitsPet(p));
        SetCapture(window);activity(false);requestFrame();
    }
    void movePointer(dog::Point p,double t){
        if(!pressed)return;
        if(GetCapture()!=window){cancelPointer();return;}
        if(pressIsStroke){if(stroke.move(p*(1/dpi),t,hitsPet(p)))strokePet(p,t);return;}
        double dx=p.x-pressPoint.x,dy=p.y-pressPoint.y;
        if(!dragging&&dx*dx+dy*dy>16*dpi*dpi){dragging=true;duang.cancel();}
        if(dragging){center=pressCenter+dog::Point{dx,dy};center=dog::fit(center,dog::extent(angle,unit()),work());requestFrame();}
    }
    void endPointer(dog::Point p){
        if(!pressed)return;
        if(GetCapture()!=window){cancelPointer();return;}
        bool wasDragging=dragging,wasStroke=pressIsStroke;
        bool click=wasStroke?stroke.finish(p*(1/dpi),hitsPet(p))
            :!wasDragging&&(!settings.positionLocked||(pressOnPet&&hitsPet(p)));
        pressed=dragging=pressIsStroke=pressOnPet=false;
        if(GetCapture()==window)ReleaseCapture();
        if(wasDragging){duang.kick(now(),1);fit();activity(false);}else if(click)pet(p);
        resumePointerTurn();
    }
    bool registerInput(){
        bool wanted=settings.counts.enabled&&!suspended&&!locked;
        if(!wanted||!inputActive)heldKeys.clear();
        DWORD flags=wanted?RIDEV_INPUTSINK:RIDEV_REMOVE;
        RAWINPUTDEVICE devices[2]={{1,6,flags,wanted?window:nullptr},{1,2,flags,wanted?window:nullptr}};
        bool ok=RegisterRawInputDevices(devices,2,sizeof(RAWINPUTDEVICE))!=FALSE;inputActive=ok&&wanted;if(!inputActive)heldKeys.clear();return ok;
    }
    void rawInput(HRAWINPUT handle){
        if(!inputActive)return;
        RAWINPUT input{};UINT bytes=sizeof(input);
        if(GetRawInputData(handle,RID_INPUT,&input,&bytes,sizeof(RAWINPUTHEADER))==UINT(-1))return;
        countInput(input);
    }
    void countInput(const RAWINPUT& input){
        if(!inputActive||!settings.counts.enabled||suspended||locked)return;
        // Scan codes are used ONLY by the ephemeral down/up bitset to suppress
        // repeats, with explicit approval. Never read VKey, hDevice, movement
        // coordinates, character content, applications, or event timestamps.
        unsigned n=0;bool keyboard=false;
        if(input.header.dwType==RIM_TYPEKEYBOARD){
            const auto& key=input.data.keyboard;
            keyboard=key.Message==WM_KEYDOWN||key.Message==WM_SYSKEYDOWN;
            bool release=key.Message==WM_KEYUP||key.Message==WM_SYSKEYUP;
            if(keyboard||release)n=heldKeys.transition(key.MakeCode,(key.Flags&RI_KEY_E0)!=0,(key.Flags&RI_KEY_E1)!=0,keyboard)?1:0;
        }
        else if(input.header.dwType==RIM_TYPEMOUSE){
            USHORT flags=input.data.mouse.usButtonFlags;
            for(USHORT flag:std::array<USHORT,5>{{RI_MOUSE_LEFT_BUTTON_DOWN,RI_MOUSE_RIGHT_BUTTON_DOWN,RI_MOUSE_MIDDLE_BUTTON_DOWN,RI_MOUSE_BUTTON_4_DOWN,RI_MOUSE_BUTTON_5_DOWN}})if(flags&flag)++n;
        }
        if(n){settings.counts.add(date(),n);markDirty();activity(keyboard);}
    }
    void addTray(){
        NOTIFYICONDATAW n{};n.cbSize=sizeof(n);n.hWnd=window;n.uID=1;n.uFlags=NIF_MESSAGE|NIF_ICON|NIF_TIP;n.uCallbackMessage=trayMessage;
        n.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));wcscpy_s(n.szTip,L"小狗桌宠 · Windows 试用版");
        trayAdded=Shell_NotifyIconW(NIM_ADD,&n)!=FALSE;
    }
    void removeTray(){NOTIFYICONDATAW n{};n.cbSize=sizeof(n);n.hWnd=window;n.uID=1;Shell_NotifyIconW(NIM_DELETE,&n);trayAdded=false;}
    void show(bool value){
        operationHint.hide();
        cancelPointer();petExpression.clear();
        clearSelection();if(!value)contextMenu.close();
        visible=value;selected=false;hover=false;pressed=false;dragging=false;hearts.items.clear();
        if(value){center=dog::fit(center,dog::extent(angle,unit()),work());lastActivity=now();ShowWindow(window,SW_SHOWNOACTIVATE);requestFrame();}
        else{yawn.clear();ShowWindow(window,SW_HIDE);ShowWindow(effects,SW_HIDE);fxShown=false;CancelWaitableTimer(timer);save();}
    }
    void fit(){center=dog::fit(center,dog::extent(angle,unit()),work());markDirty();requestFrame();}
    void clearSelection(){selected=false;dog::passiveWindow(window,true);}
    void selectForRotation(){selected=dog::focusForRotation(window);}
    void rotate(){
        operationHint.hide();
        cancelPointer();
        double t=now();auto current=turning?turn.pose(t):dog::TurnPose{center,{},angle,0};
        int next=(settings.orientation+1)%4;settings.orientation=next;
        // Continue clockwise through 360°, preserving velocity on interruption.
        double target=std::ceil((current.angle+1e-7)/(dog::pi/2))*(dog::pi/2);
        if(turning)target=turn.target+dog::pi/2;
        turn.begin(current,target,t,unit(),work());turning=true;
        if(reduced){auto end=turn.pose(t+turn.duration);center=end.center;angle=end.angle;turning=false;}
        markDirty();requestFrame();
    }
    void snap(){
        auto w=work(),b=dog::extent(angle,unit());
        switch(settings.orientation){case 0:center.y=w.bottom-b.bottom;break;case 1:center.x=w.left-b.left;break;case 2:center.y=w.top-b.top;break;case 3:center.x=w.right-b.right;break;}
        fit();
    }
    template<class Segments,class Transform> void path(Graphics& g,const Segments& segments,Transform transform,Color color,double width,Color fill=Color(0,0,0,0),Brush* gradient=nullptr,GraphicsPath* hit=nullptr){
        GraphicsPath p;dog::Point current{};
        for(auto& s:segments){
            if(s.type=='M'){p.StartFigure();current=transform(s.points[0]);}
            else if(s.type=='L'){auto end=transform(s.points[0]);p.AddLine(pf(current),pf(end));current=end;}
            else if(s.type=='C'){auto end=transform(s.points[2]);p.AddBezier(pf(current),pf(transform(s.points[0])),pf(transform(s.points[1])),pf(end));current=end;}
            else if(s.type=='Z')p.CloseFigure();
        }
        if(hit)hit->AddPath(&p,FALSE);
        if(gradient)g.FillPath(gradient,&p);else if(fill.GetAlpha()){SolidBrush brush(fill);g.FillPath(&brush,&p);}
        if(width>0&&color.GetAlpha()){Pen pen(color,REAL(width));pen.SetStartCap(LineCapRound);pen.SetEndCap(LineCapRound);pen.SetLineJoin(LineJoinRound);g.DrawPath(&pen,&p);}
    }
    template<class Transform> void ellipse(Graphics& g,Transform transform,dog::Point center,double rx,double ry,Color fill){
        constexpr double k=.5522847498307936;GraphicsPath p;
        dog::Point pts[13]={{center.x+rx,center.y},{center.x+rx,center.y+k*ry},{center.x+k*rx,center.y+ry},{center.x,center.y+ry},{center.x-k*rx,center.y+ry},{center.x-rx,center.y+k*ry},{center.x-rx,center.y},{center.x-rx,center.y-k*ry},{center.x-k*rx,center.y-ry},{center.x,center.y-ry},{center.x+k*rx,center.y-ry},{center.x+rx,center.y-k*ry},{center.x+rx,center.y}};
        for(int i=0;i<12;i+=3)p.AddBezier(pf(transform(pts[i])),pf(transform(pts[i+1])),pf(transform(pts[i+2])),pf(transform(pts[i+3])));
        p.CloseFigure();SolidBrush brush(fill);g.FillPath(&brush,&p);
    }
    void text(Graphics& g,const wchar_t* value,double x,double y,double size,Color color){FontFamily semibold(L"Segoe UI Semibold"),fallback(L"Segoe UI");bool hasSemibold=semibold.GetLastStatus()==Ok;Font font(hasSemibold?&semibold:&fallback,REAL(size),hasSemibold?FontStyleRegular:FontStyleBold,UnitPixel);SolidBrush brush(color);g.DrawString(value,-1,&font,PointF(REAL(x),REAL(y)),&brush);}
    bool draw(double t){
        radius=int(std::ceil(162*settings.size*dpi+8*dpi));fxPad=int(std::ceil(48*dpi));int side=radius*2;
        if(!surface.resize(side,side))return false;
        int left=int(std::lround(center.x))-radius,top=int(std::lround(center.y))-radius;windowRect={left,top,left+side,top+side};
        auto& g=*surface.graphics;g.Clear(Color(0,0,0,0));
        auto restPose=rest.pose(t);const double decoration=reduced?1:yawn.sleepDecorationAmount(t);restPose.bubble*=decoration;restPose.letters*=decoration;
        double breath=reduced?0:std::sin(t*2*dog::pi/4.6)*(1+restPose.settle*.35),squash=reduced?0:duang.value(t);
        double sx=1-breath*.012+squash*.48+restPose.settle*.010-restPose.stretch*.4,sy=1+breath*.040-squash-restPose.settle*.025+restPose.stretch;
        const auto yawnPose=reduced?std::nullopt:yawn.pose(t);
        const double yawnTime=yawnPose?yawnPose->time:0,yawnWeight=yawnPose?yawnPose->weight:0;
        restPose.letters*=1-yawnWeight;
        const auto headPose=dog::blendedYawnHead(yawnTime,yawnWeight,sx,sy);sx=headPose.sx;sy=headPose.sy;
        auto project=[&](dog::Point p){return dog::rotated((p-dog::pivot)*unit(),angle)+dog::Point{double(radius),double(radius)};};
        auto headTransform=[&](dog::Point p){return project(headPose.apply(p));};
        auto faceTransform=[&](dog::Point p){p.y+=restPose.settle*1.1/dog::sourceScale;return headTransform(p);};
        PointF clipPoints[4]={pf(project({-100,-1000})),pf(project({850,-1000})),pf(project({850,268})),pf(project({-100,268}))};GraphicsPath clip;clip.AddPolygon(clipPoints,4);g.SetClip(&clip);
        const bool wantsHint=hintState.available(running(),rest.sleeping,menuOpen,pressed,turning);
        dog::Bounds hintPetBounds{},hintBadgeBounds{};
        petHitReady=false;
        petHitPath.Reset();petHitPath.SetFillMode(FillModeWinding);petHitClip.Reset();petHitClip.AddPath(&clip,FALSE);
        auto tailPose=tail.pose(t,reduced);auto tailTransform=[&](dog::Point p){return project(dog::blendedYawnTailPoint(p,yawnTime,yawnWeight,tailPose,settings.tailSize));};
        Color ink(255,0,0,0),white(255,255,255,255);
        GraphicsPath* hit=&petHitPath;
        path(g,tailShape,tailTransform,ink,dog::outlineWidth*unit(),white,nullptr,hit);path(g,head,headTransform,ink,dog::outlineWidth*unit(),white,nullptr,hit);
        if(wantsHint){
            RectF shapeBounds,clipBounds;Pen outline(ink,REAL(dog::outlineWidth*unit()));outline.SetLineJoin(LineJoinRound);
            petHitPath.GetBounds(&shapeBounds,nullptr,&outline);clip.GetBounds(&clipBounds);
            auto area=work();
            hintPetBounds={std::max({double(shapeBounds.X),double(clipBounds.X),area.left-left})+left,
                std::max({double(shapeBounds.Y),double(clipBounds.Y),area.top-top})+top,
                std::min({double(shapeBounds.GetRight()),double(clipBounds.GetRight()),area.right-left})+left,
                std::min({double(shapeBounds.GetBottom()),double(clipBounds.GetBottom()),area.bottom-top})+top};
        }
        {
            // Reuse the source-space GDI+ fill path. Only the affine head pose
            // changes per frame; no tessellation/path reconstruction here.
            auto origin=headTransform({0,0});double c=std::cos(angle),sn=std::sin(angle),u=unit();
            Matrix transform(REAL(c*u*sx),REAL(sn*u*sx),REAL(-sn*u*sy),REAL(c*u*sy),REAL(origin.x),REAL(origin.y));
            auto saved=g.Save();g.MultiplyTransform(&transform);SolidBrush fill(ink);g.FillPath(&fill,&earFill);g.Restore(saved);
        }
        auto drawNormalFace=[&](Graphics& faceGraphics){
        path(faceGraphics,mouth,faceTransform,ink,dog::mouthWidth*unit());ellipse(faceGraphics,faceTransform,{285,206},17.57,10.95,ink);
        const double blink=dog::blink(t,reduced),closed=1-(1-restPose.closed)*(1-blink);
        double happy=petExpression.value(t)*(1-restPose.closed);if(reduced)happy=happy>.05?1:0;
        auto drawEye=[&](dog::Point p,bool leftEye){
            auto eye=dog::squeezeEye(p,leftEye,closed,happy);
            if(!eye.outline.empty())path(faceGraphics,eye.outline,faceTransform,ink,0,ink);
            if(eye.normalAlpha>0)path(faceGraphics,eye.normal,faceTransform,ink,0,Color(alpha(eye.normalAlpha),0,0,0));
            if(eye.squeezeAlpha>0)path(faceGraphics,eye.squeeze,faceTransform,Color(alpha(eye.squeezeAlpha),0,0,0),eye.strokeWidth*unit());
        };
        if(happy>0){drawEye({200,198},true);drawEye({398,218},false);
        }else if(restPose.closed>=1){
            yawnDrawing->drawSleepEyes(faceGraphics,headTransform);
        }else if(restPose.closed>0){
            const BYTE gray=BYTE(std::lround(9*restPose.closed));const Color eyeInk(255,gray,gray,gray);
            for(std::size_t i=0;i<2;++i){
                const auto eye=dog::yawnSleepTransitionEye(i,i==0?dog::Point{200,198}:dog::Point{398,218},restPose.closed,blink,restPose.settle);
                path(faceGraphics,eye,faceTransform,eyeInk,0,eyeInk);
            }
        }else{drawEye({200,198},true);drawEye({398,218},false);}
        Color cheek(alpha(blush.value(t)*.36),255,128,153);ellipse(faceGraphics,faceTransform,{164,228},26.5,9.5,cheek);ellipse(faceGraphics,faceTransform,{438,244},26.5,9.5,cheek);
        if(restPose.bubble>.001){double growth=(reduced?1:restPose.bubble)*(1+breath*.09);auto bubbleTransform=[&](dog::Point p){return faceTransform({301+p.x*growth/dog::sourceScale,208+p.y*growth/dog::sourceScale});};path(faceGraphics,bubble,bubbleTransform,Color(alpha(restPose.bubble*.65),102,158,184),.85*settings.size*dpi*(reduced?1:restPose.bubble),Color(alpha(restPose.bubble*.35),209,237,255));static auto glint=dog::parsePath("M9 12 C8 10 9 8 10 8");path(faceGraphics,glint,bubbleTransform,Color(alpha(restPose.bubble*.8),255,255,255),1.4*settings.size*dpi*(reduced?1:restPose.bubble));}
        };
        if(yawnWeight>0||restPose.closed>0){
            if(!yawnDrawing)yawnDrawing=std::make_unique<dog::YawnDrawing>();
            if(!yawnDrawing->drawFaces(g,side,clip,yawnTime,yawnWeight,headTransform,drawNormalFace))return false;
        }else drawNormalFace(g);
        g.ResetClip();Pen baseline(ink,REAL(2.5*settings.size*dpi));baseline.SetStartCap(LineCapRound);baseline.SetEndCap(LineCapRound);g.DrawLine(&baseline,pf(project(dog::baselineStart)),pf(project(dog::baselineEnd)));
        bool countWanted=settings.counts.enabled&&(settings.always||hover);countFade.set(countWanted?1:0,t);double countAlpha=reduced?(countWanted?1:0):countFade.value(t);
        if(countAlpha>.001){
            auto value=std::to_wstring(settings.counts.total);double w=std::max(30.0,14.0+value.size()*6.2)*dpi,h=18*dpi;auto b=dog::extent(angle,unit()),area=work();
            double x=dog::clamp(radius-w/2,2*dpi,side-w-2*dpi),y=radius+b.bottom+5*dpi;
            if(top+y+h>area.bottom)y=radius+b.top-h-5*dpi;y=dog::clamp(y,2*dpi,side-h-2*dpi);
            if(wantsHint)hintBadgeBounds={left+x,top+y,left+x+w,top+y+h};
            double r=6*dpi;GraphicsPath badge;badge.AddArc(REAL(x),REAL(y),REAL(r*2),REAL(r*2),180,90);badge.AddArc(REAL(x+w-r*2),REAL(y),REAL(r*2),REAL(r*2),270,90);badge.AddArc(REAL(x+w-r*2),REAL(y+h-r*2),REAL(r*2),REAL(r*2),0,90);badge.AddArc(REAL(x),REAL(y+h-r*2),REAL(r*2),REAL(r*2),90,90);badge.CloseFigure();
            SolidBrush bg(Color(alpha(countAlpha*.92),242,242,242));Pen border(Color(alpha(countAlpha*.45),170,170,170),REAL(.5*dpi));g.FillPath(&bg,&badge);g.DrawPath(&border,&badge);
            FontFamily family(L"Segoe UI");Font font(&family,REAL(10*dpi),FontStyleRegular,UnitPixel);StringFormat format;format.SetAlignment(StringAlignmentCenter);format.SetLineAlignment(StringAlignmentCenter);SolidBrush color(Color(alpha(countAlpha*.7),65,65,65));g.DrawString(value.c_str(),-1,&font,RectF(REAL(x),REAL(y),REAL(w),REAL(h)),&format,&color);
        }
        if(!surface.present(window,left,top))return false;
        petHitReady=true;
        updateOperationHint(hintPetBounds,hintBadgeBounds);
        bool needsEffects=restPose.letters>.001||!hearts.items.empty();
        if(needsEffects){
        if(!fx.resize(side+2*fxPad,side+2*fxPad))return false;
        auto& f=*fx.graphics;f.Clear(Color(0,0,0,0));
        if(restPose.letters>.001){for(int i=0;i<3;++i){
            double phase=std::fmod(restPose.phaseAge/4.8+i/3.0,1.0),drift=reduced?0:phase*25,fontSize=(12+i*3)*1.08*settings.size*dpi;
            auto p=project({(164+i*12)/dog::sourceScale,268-(70+i*14+drift-3.8)/dog::sourceScale});
            auto saved=f.Save();Matrix transform(REAL(std::cos(angle)),REAL(std::sin(angle)),REAL(-std::sin(angle)),REAL(std::cos(angle)),REAL(p.x+fxPad),REAL(p.y+fxPad));f.SetTransform(&transform);
            text(f,i==2?L"Z":L"z",0,-fontSize*1.25,fontSize,Color(alpha(std::sin(phase*dog::pi)*restPose.letters*.56),102,94,88));f.Restore(saved);
        }}
        for(auto h:hearts.items){auto pose=dog::effectPose(h,t,reduced);double scale=pose.scale*dpi;
            dog::Point origin{h.origin.x-left+fxPad+(pose.origin.x-h.origin.x)*dpi,h.origin.y-top+fxPad+(pose.origin.y-h.origin.y)*dpi};
            auto transform=[&](dog::Point p){return dog::rotated(p*scale,pose.rotation)+origin;};
            auto color=[&](unsigned packed){return packed?Color((packed&0xffffff)|(unsigned(alpha(pose.alpha))<<24)):Color(0u);};
            for(const auto& shape:dog::effectArtwork()[unsigned(h.effect)])path(f,shape.path,transform,color(shape.stroke),shape.width*scale,color(shape.fill));
        }
        if(!fx.present(effects,left-fxPad,top-fxPad))return false;
        if(!fxShown){ShowWindow(effects,SW_SHOWNOACTIVATE);fxShown=true;}
        }else if(fxShown){ShowWindow(effects,SW_HIDE);fxShown=false;}
        return true;
    }
    void tick(){
        double t=now();if(!running()){schedule();return;}lastFrame=t;
        if(settings.counts.roll(date()))markDirty();
        if(turning){auto p=turn.pose(t);center=p.center;angle=p.angle;if(!turn.moving(t)){turning=false;angle=std::fmod(angle,2*dog::pi);markDirty();}}
        if(!pressed&&!menuOpen&&settings.nap&&t-lastActivity>=settings.nap&&!rest.sleeping)setNap(true,lastActivity+settings.nap);
        hearts.expire(t);
        if(!draw(t)){if(++frameFailures>=3){show(false);MessageBoxW(nullptr,L"小狗暂时无法绘制，请从托盘重新显示，或退出后再试。",L"小狗桌宠",MB_OK|MB_ICONWARNING);return;}}else{
            frameFailures=0;
            if(!readySent){HANDLE ready=OpenEventW(EVENT_MODIFY_STATE,FALSE,L"Local\\DesktopPet.Windows.Ready");if(ready){SetEvent(ready);CloseHandle(ready);}readySent=true;}
        }
        if(hoverStroke.active()){
            POINT p{};
            if(!GetCursorPos(&p))hoverStroke.cancel();
            else validateHover({double(p.x),double(p.y)},t,pointerButtonsDown(),WindowFromPoint(p)==window);
        }
        nextFrame=t+(fast(t)?1.0/60:1.0/30);schedule();
    }
    static int __cdecl canInstall(){
        HWND target=callbackWindow.load();DWORD_PTR saved=0;
        return target&&SendMessageTimeoutW(target,updateSaveMessage,0,0,SMTO_ABORTIFHUNG|SMTO_BLOCK,10000,&saved)&&saved==1;
    }
    static void __cdecl quitForUpdate(){if(HWND target=callbackWindow.load())PostMessageW(target,updateQuitMessage,0,0);}
    void checkUpdates(){
        callbackWindow.store(window);
        if(!updater.checkNow(canInstall,quitForUpdate))MessageBoxW(window,L"更新组件暂时不可用，小狗可以照常陪你。请从官网重新下载安装包，不要删除本地计数和设置。",L"暂时无法检查更新",MB_OK|MB_ICONINFORMATION);
    }
    void privacy(){MessageBoxW(window,L"计数默认关闭，开启后累计键盘和鼠标按钮的按下次数。\n\n为排除长按重复，仅在内存里用物理按键编号保留“按着／已松开”标记，松开就清除，暂停计数、锁屏、休眠或退出时全部清空。不转换文字、不读取虚拟键码、应用或设备身份，不记录顺序、逐次时间或事件明细；只在本机保存今日、累计和偏好。\n\n长按只计一次，松开再按正常计数。单独修饰键仍计入，移动和滚轮不计。计数开启时，跨应用按下也能唤醒小狗，键盘会摇尾巴。\n\n日常没有后台联网或更新轮询。只有主动选择“检查更新”时才初始化更新器并访问官网，确认后下载、校验签名并安装。更新请求不包含计数或输入；服务器仍可看到普通网络信息（例如 IP 地址）。",L"小狗的隐私说明",MB_OK|MB_ICONINFORMATION);}
    void command(UINT id){
        if(id>=EffectHeart&&id<=EffectStar){settings.effectsMask^=1u<<(id-EffectHeart);markDirty();return;}
        switch(id){
        case ShowOperationHint:if(!visible)show(true);hintState.openManually();activity(false);requestFrame();break;
        case LockPosition:cancelPointer();settings.positionLocked=!settings.positionLocked;petHitReady=false;markDirty();requestFrame();break;
        case ChooseEffects:{POINT point;GetCursorPos(&point);menu(point,dog::menu::Page::Effects);break;}
        case TailSmall:case TailOriginal:cancelPointer();petHitReady=false;settings.tailSize=id==TailOriginal?dog::TailSize::Original:dog::TailSize::Small;markDirty();requestFrame();break;
        case Pet:if(!visible)show(true);pet(center);break;case Wag:activity(true);break;case Nap:cancelPointer();setNap(!rest.sleeping);break;case Hide:show(!visible);break;case Rotate:selectForRotation();rotate();break;case Snap:cancelPointer();turning=false;angle=settings.orientation*dog::pi/2;snap();break;
        case Small:case Medium:case Large:{cancelPointer();petHitReady=false;auto anchor=center+dog::rotated((dog::Point{374.5,268}-dog::pivot)*unit(),angle);settings.size=id==Small?.5:id==Medium?.62:.75;turning=false;angle=settings.orientation*dog::pi/2;center=anchor-dog::rotated((dog::Point{374.5,268}-dog::pivot)*unit(),angle);fit();break;}
        case NapOff:case Nap30:case Nap60:case Nap180:case Nap300:settings.nap=id==NapOff?0:id==Nap30?30:id==Nap60?60:id==Nap180?180:300;activity(false);markDirty();break;
        case Count:{
            if(!settings.counts.enabled){int answer=MessageBoxW(window,L"开启后，小狗可以在你打字时摇尾巴，并累计键盘和鼠标点击。\n\n长按只计一次：仅在内存里用物理按键编号标记按着／已松开，松开就清除，暂停或退出时全部清空。不转换文字、不保存按键编号、顺序或单次记录，只保存本机汇总。\n\n单独修饰键仍计入，移动和滚轮不计。要开启吗？",L"开启点击次数",MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2);if(answer!=IDYES)break;}
            settings.counts.enabled=!settings.counts.enabled;
            if(!registerInput()&&settings.counts.enabled){settings.counts.enabled=false;MessageBoxW(window,L"系统暂时没有启用计数，请稍后再试。小狗的其他互动可以继续使用。",L"点击次数",MB_OK|MB_ICONWARNING);}
            markDirty();requestFrame();break;}
        case Always:settings.always=!settings.always;markDirty();requestFrame();break;case Privacy:privacy();break;
        case Website:checkUpdates();break;
        case Quit:save();DestroyWindow(window);break;
        }
    }
    dog::menu::Snapshot menuSnapshot()const{
        dog::menu::Snapshot s;s.visible=visible;s.asleep=rest.sleeping;s.counting=settings.counts.enabled;s.always=settings.always;
        s.positionLocked=settings.positionLocked;
        s.effects=settings.effectsMask;s.nap=settings.nap;s.size=settings.size<.56?0:settings.size<.70?1:2;s.tail=int(settings.tailSize);
        s.today=settings.counts.today;s.total=settings.counts.total;return s;
    }
    std::optional<dog::Bounds> menuAvoidBounds()const{
        if(!running())return std::nullopt;
        // Stable animation envelope rather than the transparent square window.
        // Reserve all angles during a turn; the menu never chases breathing.
        const double pad=12*settings.size*dpi;
        auto b=dog::extent(angle,unit());
        if(turning){const double r=162*settings.size*dpi;
            const double dx=std::abs(turn.from.velocity.x)*turn.duration+std::abs(turn.excursion.x),
                         dy=std::abs(turn.from.velocity.y)*turn.duration+std::abs(turn.excursion.y);
            b={std::min(turn.from.center.x,turn.to.x)-center.x-r-dx,
               std::min(turn.from.center.y,turn.to.y)-center.y-r-dy,
               std::max(turn.from.center.x,turn.to.x)-center.x+r+dx,
               std::max(turn.from.center.y,turn.to.y)-center.y+r+dy};}
        const double x=std::round(center.x),y=std::round(center.y);
        return dog::Bounds{x+b.left-pad,y+b.top-pad,x+b.right+pad,y+b.bottom+pad};
    }
    void menu(POINT point,dog::menu::Page initial=dog::menu::Page::Home){
        operationHint.hide();
        cancelPointer();
        menuOpen=true;
        bool shown=contextMenu.show(window,point,[this](){return menuSnapshot();},[this](unsigned id){command(id);},[this](){menuOpen=false;lastActivity=now();requestFrame();},initial,[this](){return menuAvoidBounds();});
        if(!shown){menuOpen=false;requestFrame();MessageBoxW(window,L"菜单暂时没有打开，请从托盘重试。",L"小狗桌宠",MB_OK|MB_ICONINFORMATION);}
    }
    void pauseChanged(){
        operationHint.hide();
        cancelPointer();petExpression.clear();
        clearSelection();contextMenu.close();
        selected=false;pressed=false;dragging=false;hover=false;hearts.items.clear();registerInput();
        if(!running()){yawn.clear();CancelWaitableTimer(timer);ShowWindow(effects,SW_HIDE);fxShown=false;save();}
        else{lastActivity=now();requestFrame();}
    }
    LRESULT message(UINT m,WPARAM w,LPARAM l){
        if(taskbarCreated&&m==taskbarCreated){addTray();return 0;}
        switch(m){
        case WM_INPUT:rawInput(reinterpret_cast<HRAWINPUT>(l));return DefWindowProcW(window,m,w,l);
        case WM_MOUSEACTIVATE:if(HIWORD(l)==WM_LBUTTONDOWN||HIWORD(l)==WM_LBUTTONDBLCLK){dog::passiveWindow(window,false);return MA_ACTIVATE;}return MA_NOACTIVATE;
        case WM_LBUTTONDOWN:beginPointer(pointerPoint(l),now());return 0;
        case WM_LBUTTONDBLCLK:beginPointer(pointerPoint(l),now());return 0;
        case WM_MOUSEMOVE:{
            if(!hover){hover=true;TRACKMOUSEEVENT track{sizeof(track),TME_LEAVE,window,0};TrackMouseEvent(&track);requestFrame();}
            const auto point=pointerPoint(l);const double t=now();
            const bool buttons=(w&(MK_LBUTTON|MK_RBUTTON|MK_MBUTTON|MK_XBUTTON1|MK_XBUTTON2))||pointerButtonsDown();
            if(pressed){hoverStroke.cancel();movePointer(point,t);}
            else moveHover(point,t,buttons);
            return 0;}
        case WM_MOUSELEAVE:hover=false;hoverStroke.cancel();requestFrame();return 0;
        case WM_LBUTTONUP:endPointer(pointerPoint(l));return 0;
        case WM_CAPTURECHANGED:hoverStroke.cancel();if(pressed)cancelPointer();return 0;
        case WM_CANCELMODE:cancelPointer();return 0;
        case WM_RBUTTONDOWN:case WM_RBUTTONDBLCLK:case WM_MBUTTONDOWN:case WM_MBUTTONDBLCLK:
        case WM_XBUTTONDOWN:case WM_XBUTTONDBLCLK:hoverStroke.cancel();break;
        case WM_CONTEXTMENU:{POINT p{GET_X_LPARAM(l),GET_Y_LPARAM(l)};if(p.x==-1)GetCursorPos(&p);menu(p);return 0;}
        case WM_KEYDOWN:if(selected&&GetFocus()==window&&!menuOpen){if(w=='R'&&!(l&(1LL<<30)))rotate();if(w==VK_ESCAPE){clearSelection();SetFocus(nullptr);}}return 0;
        case WM_KILLFOCUS:cancelPointer();clearSelection();return 0;
        case WM_ACTIVATE:if(LOWORD(w)==WA_INACTIVE){cancelPointer();clearSelection();}return 0;
        case WM_DPICHANGED:{cancelPointer();petHitReady=false;dpi=double(HIWORD(w))/96;turning=false;angle=settings.orientation*dog::pi/2;fit();return 0;}
        case WM_DISPLAYCHANGE:cancelPointer();petHitReady=false;turning=false;angle=settings.orientation*dog::pi/2;fit();return 0;
        case WM_SETTINGCHANGE:hoverStroke.cancel();updateReduced();fit();return 0;
        case WM_POWERBROADCAST:
            if(w==PBT_APMSUSPEND){suspended=true;pauseChanged();}
            else if(w==PBT_APMRESUMEAUTOMATIC||w==PBT_APMRESUMESUSPEND){suspended=false;pauseChanged();}
            else if(w==PBT_POWERSETTINGCHANGE){auto setting=reinterpret_cast<POWERBROADCAST_SETTING*>(l);if(IsEqualGUID(setting->PowerSetting,consoleDisplayState)&&setting->DataLength==sizeof(DWORD)){DWORD value;CopyMemory(&value,setting->Data,sizeof(value));displayOff=value==0;pauseChanged();}}
            return TRUE;
        case WM_WTSSESSION_CHANGE:if(w==WTS_SESSION_LOCK){locked=true;pauseChanged();}else if(w==WTS_SESSION_UNLOCK){locked=false;pauseChanged();}return 0;
        case WM_TIMER:if(w==saveTimer){save();contextMenu.refresh();if(!dirty)KillTimer(window,saveTimer);}return 0;
        case trayMessage:if(l==WM_RBUTTONUP||l==WM_CONTEXTMENU){POINT p;GetCursorPos(&p);menu(p);}else if(l==WM_LBUTTONUP)show(!visible);return 0;
        case showMessage:show(true);return 0;
        case updateSaveMessage:save();return dirty?0:1;
        case updateQuitMessage:save();if(!dirty)DestroyWindow(window);return 0;
        case WM_QUERYENDSESSION:save();return TRUE;
        case WM_ENDSESSION:if(w)save();return 0;
        case WM_CLOSE:show(false);return 0;
        case WM_DESTROY:save();registerShutdown();PostQuitMessage(0);return 0;
        }
        return DefWindowProcW(window,m,w,l);
    }
    void registerShutdown(){operationHint.destroy();hintState.dismiss();cancelPointer();yawn.clear();heldKeys.clear();contextMenu.close();callbackWindow.store(nullptr);RAWINPUTDEVICE d[2]={{1,6,RIDEV_REMOVE,nullptr},{1,2,RIDEV_REMOVE,nullptr}};RegisterRawInputDevices(d,2,sizeof(RAWINPUTDEVICE));WTSUnRegisterSessionNotification(window);if(displayNotification)UnregisterPowerSettingNotification(displayNotification);removeTray();if(timer)CancelWaitableTimer(timer);if(effects)DestroyWindow(effects);}
    static LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
        App* app=reinterpret_cast<App*>(GetWindowLongPtrW(h,GWLP_USERDATA));
        if(m==WM_NCCREATE){app=static_cast<App*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);app->window=h;SetWindowLongPtrW(h,GWLP_USERDATA,LONG_PTR(app));}
        return app?app->message(m,w,l):DefWindowProcW(h,m,w,l);
    }
    int run(){
        if(!settings.init()){MessageBoxW(nullptr,L"无法创建本地设置文件夹，小狗没有启动。",L"小狗桌宠",MB_OK|MB_ICONERROR);return 1;}
        hintState.beginSession(settings.operationHints);
        WNDCLASSEXW cls{sizeof(cls)};cls.style=CS_DBLCLKS;cls.lpfnWndProc=proc;cls.hInstance=instance;cls.lpszClassName=className;cls.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);if(!RegisterClassExW(&cls))return 2;
        window=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,className,L"小狗桌宠",WS_POPUP,0,0,1,1,nullptr,nullptr,instance,this);if(!window)return 3;
        WNDCLASSEXW effectClass{sizeof(effectClass)};effectClass.lpfnWndProc=DefWindowProcW;effectClass.hInstance=instance;effectClass.lpszClassName=L"DesktopPet.Windows.Effects";RegisterClassExW(&effectClass);
        effects=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TRANSPARENT,effectClass.lpszClassName,L"",WS_POPUP,0,0,1,1,window,nullptr,instance,nullptr);if(!effects)return 4;
        timer=CreateWaitableTimerExW(nullptr,nullptr,0x2,TIMER_ALL_ACCESS);if(!timer)timer=CreateWaitableTimerW(nullptr,FALSE,nullptr);if(!timer)return 5;
        updateReduced();dpi=GetDpiForWindow(window)/96.0;
        center=settings.hasPosition?settings.center:dog::Point{double(GetSystemMetrics(SM_CXSCREEN))*.72,double(GetSystemMetrics(SM_CYSCREEN))*.85};angle=settings.orientation*dog::pi/2;center=dog::fit(center,dog::extent(angle,unit()),work());if(!settings.hasPosition)snap();
        SetWindowPos(window,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);SetWindowPos(effects,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
        taskbarCreated=RegisterWindowMessageW(L"TaskbarCreated");addTray();WTSRegisterSessionNotification(window,NOTIFY_FOR_THIS_SESSION);displayNotification=RegisterPowerSettingNotification(window,&consoleDisplayState,DEVICE_NOTIFY_WINDOW_HANDLE);
        if(!registerInput()&&settings.counts.enabled){settings.counts.enabled=false;markDirty();}
        show(true);tick();MSG msg{};bool quit=false;
        while(!quit){
            DWORD result=MsgWaitForMultipleObjectsEx(1,&timer,INFINITE,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
            if(result==WAIT_FAILED)break;
            if(result==WAIT_OBJECT_0)tick();
            for(int n=0;n<64&&PeekMessageW(&msg,nullptr,0,0,PM_REMOVE);++n){if(msg.message==WM_QUIT){quit=true;break;}if(contextMenu.dialogMessage(msg)||operationHint.dialogMessage(msg))continue;TranslateMessage(&msg);DispatchMessageW(&msg);}
        }
        CloseHandle(timer);return int(msg.wParam);
    }
};
}
#ifndef DESKTOP_PET_NATIVE_UI_TEST
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR,int){
    // One dog and one listener per Windows login session. A second launch reveals it.
    HANDLE mutex=CreateMutexW(nullptr,TRUE,L"Local\\DesktopPet.Windows.Preview");
    if(!mutex)return 1;
    if(GetLastError()==ERROR_ALREADY_EXISTS){HWND other=FindWindowW(className,nullptr);if(other)PostMessageW(other,showMessage,0,0);CloseHandle(mutex);return 0;}
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    ULONG_PTR token=0;GdiplusStartupInput input;if(GdiplusStartup(&token,&input,nullptr)!=Ok){CloseHandle(mutex);return 2;}
    int result;{App app(instance);result=app.run();}
    GdiplusShutdown(token);ReleaseMutex(mutex);CloseHandle(mutex);return result;
}
#endif
