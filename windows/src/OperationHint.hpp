#pragma once
#include <windows.h>
#include <gdiplus.h>
#include <functional>
#include "OperationHintModel.hpp"

namespace dog {
// One owned, event-painted popup with actual STATIC/BUTTON controls. No timer,
// input listener, web content, or per-frame window raising.
class OperationHint {
public:
    enum {CloseButton=1,NeverButton=2,FirstLine=3,SecondLine=4};
private:
    HWND window=nullptr,first=nullptr,second=nullptr,closeButton=nullptr,neverButton=nullptr;
    HFONT textFont=nullptr,buttonFont=nullptr;HBRUSH background=nullptr;
    std::function<void(bool)> dismiss;
    std::optional<HintPlacement> placement;
    bool locked=true,shown=false;
    double scale=1;
    int px(double value)const{return int(std::lround(value*scale));}
    double bodyX()const{return placement&&placement->side==HintSide::Right?6:0;}
    double bodyY()const{return placement&&placement->side==HintSide::Below?6:0;}
    void shape(Gdiplus::GraphicsPath& p)const{
        using Gdiplus::REAL;
        double x=bodyX()+.5,y=bodyY()+.5,w=191,h=97,r=12,cx=x+w/2,cy=y+h/2;
        auto line=[&](double a,double b,double c,double d){p.AddLine(REAL(a),REAL(b),REAL(c),REAL(d));};
        auto side=placement->side;
        if(side==HintSide::Below){line(x+r,y,cx-5,y);line(cx-5,y,cx,y-6);line(cx,y-6,cx+5,y);line(cx+5,y,x+w-r,y);}else line(x+r,y,x+w-r,y);
        p.AddArc(REAL(x+w-2*r),REAL(y),REAL(2*r),REAL(2*r),270,90);
        if(side==HintSide::Left){line(x+w,y+r,x+w,cy-5);line(x+w,cy-5,x+w+6,cy);line(x+w+6,cy,x+w,cy+5);line(x+w,cy+5,x+w,y+h-r);}else line(x+w,y+r,x+w,y+h-r);
        p.AddArc(REAL(x+w-2*r),REAL(y+h-2*r),REAL(2*r),REAL(2*r),0,90);
        if(side==HintSide::Above){line(x+w-r,y+h,cx+5,y+h);line(cx+5,y+h,cx,y+h+6);line(cx,y+h+6,cx-5,y+h);line(cx-5,y+h,x+r,y+h);}else line(x+w-r,y+h,x+r,y+h);
        p.AddArc(REAL(x),REAL(y+h-2*r),REAL(2*r),REAL(2*r),90,90);
        if(side==HintSide::Right){line(x,y+h-r,x,cy+5);line(x,cy+5,x-6,cy);line(x-6,cy,x,cy-5);line(x,cy-5,x,y+r);}else line(x,y+h-r,x,y+r);
        p.AddArc(REAL(x),REAL(y),REAL(2*r),REAL(2*r),180,90);p.CloseFigure();
    }
    void paint(HDC dc){
        Gdiplus::Graphics g(dc);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);g.ScaleTransform(Gdiplus::REAL(scale),Gdiplus::REAL(scale));
        Gdiplus::GraphicsPath path;shape(path);Gdiplus::SolidBrush fill(Gdiplus::Color(255,255,253,248));Gdiplus::Pen edge(Gdiplus::Color(255,204,211,198),1);
        g.FillPath(&fill,&path);g.DrawPath(&edge,&path);
    }
    void paintButton(DRAWITEMSTRUCT* item){
        HDC dc=item->hDC;RECT r=item->rcItem;
        Gdiplus::Graphics g(dc);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        const float x=1,y=1,w=float(r.right-r.left-2),h=float(r.bottom-r.top-2),d=float(px(12));
        Gdiplus::GraphicsPath p;p.AddArc(x,y,d,d,180,90);p.AddArc(x+w-d,y,d,d,270,90);p.AddArc(x+w-d,y+h-d,d,d,0,90);p.AddArc(x,y+h-d,d,d,90,90);p.CloseFigure();
        const bool pressed=(item->itemState&ODS_SELECTED)!=0;
        Gdiplus::SolidBrush fill(pressed?Gdiplus::Color(255,229,235,220):Gdiplus::Color(255,246,247,239));Gdiplus::Pen edge(Gdiplus::Color(255,211,217,204),1);
        g.FillPath(&fill,&p);g.DrawPath(&edge,&p);g.Flush();
        auto previous=SelectObject(dc,buttonFont);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(54,65,48));
        const wchar_t* text=item->CtlID==CloseButton?L"关闭":L"不再提示";
        DrawTextW(dc,text,-1,&r,DT_CENTER|DT_VCENTER|DT_SINGLELINE);SelectObject(dc,previous);
        if((item->itemState&ODS_FOCUS)&&!(item->itemState&ODS_NOFOCUSRECT)){InflateRect(&r,-px(3),-px(3));DrawFocusRect(dc,&r);}
    }
    void layout(){
        double x=bodyX(),y=bodyY();
        MoveWindow(first,px(x+14),px(y+13),px(164),px(20),FALSE);
        MoveWindow(second,px(x+14),px(y+35),px(164),px(20),FALSE);
        MoveWindow(closeButton,px(x+14),px(y+64),px(58),px(24),FALSE);
        MoveWindow(neverButton,px(x+80),px(y+64),px(98),px(24),FALSE);
        HDC dc=GetDC(window);{
            Gdiplus::Graphics g(dc);Gdiplus::GraphicsPath p;shape(p);Gdiplus::Matrix transform;transform.Scale(Gdiplus::REAL(scale),Gdiplus::REAL(scale));p.Transform(&transform);
            Gdiplus::Region region(&p);HRGN native=region.GetHRGN(&g);if(native&&!SetWindowRgn(window,native,TRUE))DeleteObject(native);
        }ReleaseDC(window,dc);
        InvalidateRect(window,nullptr,TRUE);
    }
    void fonts(){
        if(textFont)DeleteObject(textFont);if(buttonFont)DeleteObject(buttonFont);
        textFont=CreateFontW(-px(13),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
        buttonFont=CreateFontW(-px(11.5),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
        for(HWND h:{first,second})SendMessageW(h,WM_SETFONT,WPARAM(textFont),FALSE);
        for(HWND h:{closeButton,neverButton})SendMessageW(h,WM_SETFONT,WPARAM(buttonFont),FALSE);
    }
    LRESULT message(UINT m,WPARAM w,LPARAM l){
        switch(m){
        case WM_PAINT:{PAINTSTRUCT p;HDC dc=BeginPaint(window,&p);paint(dc);EndPaint(window,&p);return 0;}
        case WM_ERASEBKGND:return 1;
        case WM_CTLCOLORSTATIC:{HDC dc=reinterpret_cast<HDC>(w);SetTextColor(dc,RGB(49,61,44));SetBkColor(dc,RGB(255,253,248));return LRESULT(background);}
        case WM_DRAWITEM:paintButton(reinterpret_cast<DRAWITEMSTRUCT*>(l));return TRUE;
        case WM_COMMAND:if(HIWORD(w)==BN_CLICKED&&(LOWORD(w)==CloseButton||LOWORD(w)==NeverButton)){auto callback=dismiss;hide();if(callback)callback(LOWORD(w)==NeverButton);return 0;}break;
        case WM_MOUSEACTIVATE:return MA_NOACTIVATE;
        case WM_CLOSE:{auto callback=dismiss;hide();if(callback)callback(false);return 0;}
        case WM_NCDESTROY:{HWND old=window;window=nullptr;shown=false;placement.reset();first=second=closeButton=neverButton=nullptr;SetWindowLongPtrW(old,GWLP_USERDATA,0);return DefWindowProcW(old,m,w,l);}
        }
        return DefWindowProcW(window,m,w,l);
    }
    static LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
        auto self=reinterpret_cast<OperationHint*>(GetWindowLongPtrW(h,GWLP_USERDATA));
        if(m==WM_NCCREATE){self=static_cast<OperationHint*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);self->window=h;SetWindowLongPtrW(h,GWLP_USERDATA,LONG_PTR(self));}
        return self?self->message(m,w,l):DefWindowProcW(h,m,w,l);
    }
    bool create(HWND owner){
        HINSTANCE instance=reinterpret_cast<HINSTANCE>(GetWindowLongPtrW(owner,GWLP_HINSTANCE));
        WNDCLASSEXW cls{sizeof(cls)};cls.lpfnWndProc=proc;cls.hInstance=instance;cls.lpszClassName=L"DesktopPet.OperationHint";cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);
        if(!RegisterClassExW(&cls)&&GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return false;
        HWND h=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_TOPMOST|WS_EX_NOACTIVATE|WS_EX_CONTROLPARENT,cls.lpszClassName,L"小狗操作提示",WS_POPUP|WS_CLIPCHILDREN,0,0,1,1,owner,nullptr,instance,this);
        if(!h)return false;
        first=CreateWindowExW(0,L"STATIC",L"",WS_CHILD|WS_VISIBLE|SS_LEFT,0,0,1,1,h,reinterpret_cast<HMENU>(INT_PTR(FirstLine)),instance,nullptr);
        second=CreateWindowExW(0,L"STATIC",L"",WS_CHILD|WS_VISIBLE|SS_LEFT,0,0,1,1,h,reinterpret_cast<HMENU>(INT_PTR(SecondLine)),instance,nullptr);
        closeButton=CreateWindowExW(0,L"BUTTON",L"关闭",WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW,0,0,1,1,h,reinterpret_cast<HMENU>(INT_PTR(CloseButton)),instance,nullptr);
        neverButton=CreateWindowExW(0,L"BUTTON",L"不再提示",WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW,0,0,1,1,h,reinterpret_cast<HMENU>(INT_PTR(NeverButton)),instance,nullptr);
        if(!first||!second||!closeButton||!neverButton){destroy();return false;}
        if(!background)background=CreateSolidBrush(RGB(255,253,248));return true;
    }
public:
    ~OperationHint(){destroy();if(textFont)DeleteObject(textFont);if(buttonFont)DeleteObject(buttonFont);if(background)DeleteObject(background);}
    HWND windowHandle()const{return window;}
    bool isVisible()const{return window&&shown;}
    std::optional<HintPlacement> currentPlacement()const{return shown?placement:std::optional<HintPlacement>{};}
    void hide(){if(window&&shown)ShowWindow(window,SW_HIDE);shown=false;}
    void destroy(){if(window)DestroyWindow(window);}
    bool show(HWND owner,const HintPlacement& next,bool positionLocked,std::function<void(bool)> callback){
        bool created=!window;if(created&&!create(owner))return false;
        bool geometry=!placement||placement->side!=next.side||placement->scale!=next.scale
            ||placement->frame.left!=next.frame.left||placement->frame.top!=next.frame.top||placement->frame.right!=next.frame.right||placement->frame.bottom!=next.frame.bottom;
        bool content=created||locked!=positionLocked;bool resized=created||scale!=next.scale;
        dismiss=std::move(callback);locked=positionLocked;placement=next;scale=next.scale;
        if(resized)fonts();
        if(content){SetWindowTextW(first,locked?L"双击按住拖动我":L"按住拖动我");SetWindowTextW(second,locked?L"按住来回摸摸我":L"点一下摸摸我");}
        if(geometry){const auto r=next.frame;SetWindowPos(window,nullptr,int(r.left),int(r.top),int(r.right-r.left),int(r.bottom-r.top),SWP_NOZORDER|SWP_NOACTIVATE);layout();}
        if(!shown){ShowWindow(window,SW_SHOWNOACTIVATE);shown=true;}
        return true;
    }
    bool dialogMessage(MSG& msg){
        if(!shown||!(msg.hwnd==window||IsChild(window,msg.hwnd)))return false;
        if(msg.message==WM_KEYDOWN&&msg.wParam==VK_ESCAPE){SendMessageW(window,WM_CLOSE,0,0);return true;}
        return IsDialogMessageW(window,&msg)!=FALSE;
    }
};
} // namespace dog
