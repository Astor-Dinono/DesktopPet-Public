#pragma once
#include <windows.h>
#include <windowsx.h>
#include <cmath>
#include <functional>
#include <memory>
#include "MenuPainting.hpp"

namespace dog {
// Event-driven, owned Win32 controls: no web runtime, global listener, or menu animation timer.
class ContextMenu {
    struct Control {ContextMenu* owner;menu::Item item;HWND window=nullptr;WNDPROC original=nullptr;bool hot=false;};
    HWND window=nullptr;HFONT font=nullptr;HBRUSH comboBrush=nullptr;
    std::vector<std::unique_ptr<Control>> controls;
    std::function<menu::Snapshot()> read;
    std::function<void(unsigned)> action;
    std::function<void()> didClose;
    menu::Page page=menu::Page::Home;menu::Plan plan;menu::MenuPainting painting;
    POINT anchor{},origin{};UINT dpi=96;double scale=1;bool rebuilding=false;
    int px(double n)const{return int(std::lround(n*scale));}
    Control* control(int id){for(auto& c:controls)if(c->item.id==id)return c.get();return nullptr;}
    void theme(){
        painting.palette=menu::systemPalette();if(comboBrush)DeleteObject(comboBrush);
        auto c=painting.palette.background;comboBrush=CreateSolidBrush(RGB(c.GetR(),c.GetG(),c.GetB()));
    }
    void configure(Gdiplus::Graphics& g){g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);g.ScaleTransform(Gdiplus::REAL(scale),Gdiplus::REAL(scale));}
    void paintControl(Control& c,HDC dc){
        Gdiplus::Graphics g(dc);configure(g);
        auto state=SendMessageW(c.window,BM_GETSTATE,0,0);
        bool checked=(c.item.kind==menu::Kind::Check||c.item.kind==menu::Kind::Radio)&&SendMessageW(c.window,BM_GETCHECK,0,0)==BST_CHECKED;
        painting.button(g,c.item,c.hot,(state&BST_PUSHED)!=0,checked);
        if(c.item.kind!=menu::Kind::Label&&GetFocus()==c.window&&!(SendMessageW(c.window,WM_QUERYUISTATE,0,0)&UISF_HIDEFOCUS)){
            g.Flush();RECT r{px(3),px(3),px(c.item.frame.w-3),px(c.item.frame.h-3)};DrawFocusRect(dc,&r);
        }
    }
    static LRESULT CALLBACK childProc(HWND h,UINT m,WPARAM w,LPARAM l){
        auto c=reinterpret_cast<Control*>(GetWindowLongPtrW(h,GWLP_USERDATA));if(!c)return DefWindowProcW(h,m,w,l);
        WNDPROC original=c->original;
        if(m==WM_PAINT){PAINTSTRUCT paint;HDC dc=BeginPaint(h,&paint);c->owner->paintControl(*c,dc);EndPaint(h,&paint);return 0;}
        if(m==WM_PRINTCLIENT){c->owner->paintControl(*c,reinterpret_cast<HDC>(w));return 0;}
        if(m==WM_ERASEBKGND)return 1;
        if(m==WM_MOUSEMOVE&&c->item.kind!=menu::Kind::Label&&!c->hot){c->hot=true;TRACKMOUSEEVENT track{sizeof(track),TME_LEAVE,h,0};TrackMouseEvent(&track);InvalidateRect(h,nullptr,FALSE);}
        if(m==WM_MOUSELEAVE){c->hot=false;InvalidateRect(h,nullptr,FALSE);}
        if(m==WM_NCDESTROY){SetWindowLongPtrW(h,GWLP_USERDATA,0);return CallWindowProcW(original,h,m,w,l);}
        if(m==BM_SETCHECK||m==BM_SETSTATE||m==WM_SETFOCUS||m==WM_KILLFOCUS||m==WM_UPDATEUISTATE){auto result=CallWindowProcW(original,h,m,w,l);InvalidateRect(h,nullptr,FALSE);return result;}
        // A click may navigate and destroy its old button. Do not touch c after dispatch.
        return CallWindowProcW(original,h,m,w,l);
    }
    void resize(){
        MONITORINFO monitor{sizeof(monitor)};GetMonitorInfoW(MonitorFromPoint(anchor,MONITOR_DEFAULTTONEAREST),&monitor);
        double width=monitor.rcWork.right-monitor.rcWork.left,height=monitor.rcWork.bottom-monitor.rcWork.top;
        double maxHeight=menu::layout(menu::Page::Home,read()).height;
        scale=std::min({dpi/96.0,std::max(1.0,width-8)/plan.width,std::max(1.0,height-8)/maxHeight});
        int w=px(plan.width),h=px(plan.height);
        origin.x=std::clamp(origin.x,monitor.rcWork.left,std::max(monitor.rcWork.left,monitor.rcWork.right-w));
        origin.y=std::clamp(origin.y,monitor.rcWork.top,std::max(monitor.rcWork.top,monitor.rcWork.bottom-h));
        SetWindowPos(window,nullptr,origin.x,origin.y,w,h,SWP_NOZORDER|SWP_NOACTIVATE);
        HRGN region=CreateRoundRectRgn(0,0,w+1,h+1,px(36),px(36));if(region&&!SetWindowRgn(window,region,TRUE))DeleteObject(region);
        if(font)DeleteObject(font);
        font=CreateFontW(-px(13),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    }
    bool rebuild(bool focusFirst=true){
        rebuilding=true;for(auto& c:controls)if(IsWindow(c->window))DestroyWindow(c->window);controls.clear();
        plan=menu::layout(page,read());resize();
        HINSTANCE instance=reinterpret_cast<HINSTANCE>(GetWindowLongPtrW(window,GWLP_HINSTANCE));
        bool radioStart=true;
        for(auto item:plan.items){
            auto c=std::make_unique<Control>();c->owner=this;c->item=item;
            DWORD style=WS_CHILD|WS_VISIBLE;const wchar_t* cls=L"BUTTON";
            if(item.kind==menu::Kind::Label)cls=L"STATIC";
            else if(item.kind==menu::Kind::Combo){cls=L"COMBOBOX";style|=WS_TABSTOP|CBS_DROPDOWNLIST|CBS_OWNERDRAWFIXED|CBS_HASSTRINGS|WS_VSCROLL;}
            else{
                style|=WS_TABSTOP;
                if(item.kind==menu::Kind::Check)style|=BS_AUTOCHECKBOX;
                else if(item.kind==menu::Kind::Radio){style|=BS_AUTORADIOBUTTON;if(radioStart){style|=WS_GROUP;radioStart=false;}}
                else style|=BS_PUSHBUTTON;
            }
            auto r=item.frame;
            c->window=CreateWindowExW(0,cls,item.label.c_str(),style,px(r.x),px(r.y),px(r.w),px(item.kind==menu::Kind::Combo?170:r.h),window,reinterpret_cast<HMENU>(INT_PTR(item.id)),instance,nullptr);
            if(!c->window){rebuilding=false;close();return false;}
            SendMessageW(c->window,WM_SETFONT,WPARAM(font),FALSE);
            if(item.kind==menu::Kind::Combo){
                const wchar_t* sizeNames[]={L"小号",L"中号",L"大号"};const wchar_t* tailNames[]={L"小一圈",L"原来大小"};
                for(int i=0;i<(item.id==menu::SizeChoice?3:2);++i)SendMessageW(c->window,CB_ADDSTRING,0,LPARAM(item.id==menu::SizeChoice?sizeNames[i]:tailNames[i]));
                SendMessageW(c->window,CB_SETITEMHEIGHT,WPARAM(-1),px(24));SendMessageW(c->window,CB_SETCURSEL,item.selection,0);
            }else{
                SetWindowLongPtrW(c->window,GWLP_USERDATA,LONG_PTR(c.get()));
                c->original=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(c->window,GWLP_WNDPROC,LONG_PTR(childProc)));
                if(item.kind==menu::Kind::Check||item.kind==menu::Kind::Radio)SendMessageW(c->window,BM_SETCHECK,item.checked?BST_CHECKED:BST_UNCHECKED,0);
            }
            controls.push_back(std::move(c));
        }
        rebuilding=false;InvalidateRect(window,nullptr,FALSE);
        if(focusFirst){HWND first=page==menu::Page::Home?control(menu::Pet)->window:GetNextDlgTabItem(window,nullptr,FALSE);if(first)SetFocus(first);}
        return true;
    }
    void navigate(menu::Page next){page=next;rebuild();}
    void execute(int id){
        if(id==menu::Close){close();return;}
        if(id==menu::Back){navigate(menu::Page::Home);return;}
        if(menu::isNavigation(id)){navigate(menu::destination(id));return;}
        auto callback=action;
        bool dismiss=menu::closesForCommand(id,read());
        if(dismiss)close();
        callback(unsigned(id));
        if(!dismiss&&window)refresh();
    }
    LRESULT message(UINT m,WPARAM w,LPARAM l){
        switch(m){
        case WM_PAINT:{PAINTSTRUCT paint;HDC dc=BeginPaint(window,&paint);{Gdiplus::Graphics g(dc);configure(g);painting.background(g,plan);}EndPaint(window,&paint);return 0;}
        case WM_ERASEBKGND:return 1;
        case WM_COMMAND:{
            int id=LOWORD(w);auto c=control(id);if(!c)return 0;
            if(c->item.kind==menu::Kind::Combo&&HIWORD(w)==CBN_SELCHANGE){int index=int(SendMessageW(c->window,CB_GETCURSEL,0,0));if(index>=0){action(menu::comboCommand(id,index));refresh();}return 0;}
            if(c->item.kind!=menu::Kind::Combo&&HIWORD(w)==BN_CLICKED){execute(id);return 0;}break;
        }
        case WM_MEASUREITEM:{auto measure=reinterpret_cast<MEASUREITEMSTRUCT*>(l);if(measure->CtlType==ODT_COMBOBOX){measure->itemHeight=UINT(px(24));return TRUE;}break;}
        case WM_DRAWITEM:{
            auto draw=reinterpret_cast<DRAWITEMSTRUCT*>(l);if(draw->CtlType!=ODT_COMBOBOX)break;
            auto c=control(int(draw->CtlID));if(!c)return TRUE;Gdiplus::Graphics g(draw->hDC);configure(g);
            const wchar_t* sizes[]={L"小号",L"中号",L"大号"};const wchar_t* tails[]={L"小一圈",L"原来大小"};
            int n=int(draw->itemID);if(n<0)n=c->item.selection;if(n<0||n>=(c->item.id==menu::SizeChoice?3:2))return TRUE;
            menu::Rect r{draw->rcItem.left/scale,draw->rcItem.top/scale,(draw->rcItem.right-draw->rcItem.left)/scale,(draw->rcItem.bottom-draw->rcItem.top)/scale};
            Gdiplus::SolidBrush brush((draw->itemState&ODS_SELECTED)?painting.palette.hover:painting.palette.background);g.FillRectangle(&brush,Gdiplus::REAL(r.x),Gdiplus::REAL(r.y),Gdiplus::REAL(r.w),Gdiplus::REAL(r.h));
            r.x+=5;r.w-=10;painting.text(g,c->item.id==menu::SizeChoice?sizes[n]:tails[n],r,painting.palette.foreground);return TRUE;
        }
        case WM_CTLCOLORLISTBOX:{HDC dc=reinterpret_cast<HDC>(w);auto fg=painting.palette.foreground,bg=painting.palette.background;SetTextColor(dc,RGB(fg.GetR(),fg.GetG(),fg.GetB()));SetBkColor(dc,RGB(bg.GetR(),bg.GetG(),bg.GetB()));return LRESULT(comboBrush);}
        case WM_ACTIVATE:if(LOWORD(w)==WA_INACTIVE&&!rebuilding)close();return 0;
        case WM_CLOSE:close();return 0;
        case WM_DPICHANGED:if(!rebuilding){dpi=HIWORD(w);auto r=reinterpret_cast<RECT*>(l);origin={r->left,r->top};rebuild();}return 0;
        case WM_SETTINGCHANGE:case WM_THEMECHANGED:theme();if(window){InvalidateRect(window,nullptr,FALSE);for(auto& c:controls)InvalidateRect(c->window,nullptr,FALSE);}return 0;
        case WM_NCDESTROY:{
            HWND old=window;SetWindowLongPtrW(old,GWLP_USERDATA,0);window=nullptr;controls.clear();
            if(font){DeleteObject(font);font=nullptr;}if(comboBrush){DeleteObject(comboBrush);comboBrush=nullptr;}
            auto callback=didClose;if(callback)callback();return DefWindowProcW(old,m,w,l);
        }
        }
        return DefWindowProcW(window,m,w,l);
    }
    static LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
        auto self=reinterpret_cast<ContextMenu*>(GetWindowLongPtrW(h,GWLP_USERDATA));
        if(m==WM_NCCREATE){self=static_cast<ContextMenu*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);self->window=h;SetWindowLongPtrW(h,GWLP_USERDATA,LONG_PTR(self));}
        return self?self->message(m,w,l):DefWindowProcW(h,m,w,l);
    }
public:
    ~ContextMenu(){close();}
    HWND windowHandle()const{return window;}
    void close(){if(window)DestroyWindow(window);}
    void refresh(){
        if(!window)return;plan=menu::layout(page,read());
        for(auto& c:controls)for(const auto& item:plan.items)if(c->item.id==item.id){
            bool changed=c->item.label!=item.label;c->item=item;
            if(changed)SetWindowTextW(c->window,item.label.c_str());
            if(item.kind==menu::Kind::Check||item.kind==menu::Kind::Radio)SendMessageW(c->window,BM_SETCHECK,item.checked?BST_CHECKED:BST_UNCHECKED,0);
            if(item.kind==menu::Kind::Combo)SendMessageW(c->window,CB_SETCURSEL,item.selection,0);
            InvalidateRect(c->window,nullptr,FALSE);break;
        }
        InvalidateRect(window,nullptr,FALSE);
    }
    bool dialogMessage(MSG& msg){
        if(!window||!(msg.hwnd==window||IsChild(window,msg.hwnd)))return false;
        if(msg.message==WM_KEYDOWN&&msg.wParam==VK_ESCAPE){
            HWND focus=GetFocus();auto c=control(GetDlgCtrlID(focus));
            if(c&&c->item.kind==menu::Kind::Combo&&SendMessageW(focus,CB_GETDROPPEDSTATE,0,0)){SendMessageW(focus,CB_SHOWDROPDOWN,FALSE,0);return true;}
            if(page==menu::Page::Home)close();else navigate(menu::Page::Home);return true;
        }
        if(msg.message==WM_KEYDOWN&&msg.wParam==VK_RETURN){auto c=control(GetDlgCtrlID(GetFocus()));if(c&&c->item.kind!=menu::Kind::Combo&&c->item.kind!=menu::Kind::Label){SendMessageW(c->window,BM_CLICK,0,0);return true;}}
        return IsDialogMessageW(window,&msg)!=FALSE;
    }
    bool show(HWND owner,POINT point,std::function<menu::Snapshot()> getter,std::function<void(unsigned)> callback,std::function<void()> closed,menu::Page initial=menu::Page::Home){
        if(window){navigate(initial);SetForegroundWindow(window);return true;}
        anchor=origin=point;read=std::move(getter);action=std::move(callback);didClose=std::move(closed);page=initial;
        plan=menu::layout(page,read());dpi=GetDpiForWindow(owner);theme();
        HINSTANCE instance=reinterpret_cast<HINSTANCE>(GetWindowLongPtrW(owner,GWLP_HINSTANCE));
        WNDCLASSEXW cls{sizeof(cls)};cls.lpfnWndProc=proc;cls.hInstance=instance;cls.lpszClassName=L"DesktopPet.ContextMenu";cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);cls.style=CS_DROPSHADOW;
        if(!RegisterClassExW(&cls)&&GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return false;
        rebuilding=true;
        HWND h=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_TOPMOST|WS_EX_CONTROLPARENT,cls.lpszClassName,L"小狗桌宠 · 菜单",WS_POPUP|WS_CLIPCHILDREN,point.x,point.y,1,1,read().visible?owner:nullptr,nullptr,instance,this);
        rebuilding=false;if(!h)return false;dpi=GetDpiForWindow(h);
        if(!rebuild(false))return false;
        ShowWindow(h,SW_SHOW);SetForegroundWindow(h);HWND first=page==menu::Page::Home?control(menu::Pet)->window:GetNextDlgTabItem(h,nullptr,FALSE);if(first)SetFocus(first);return true;
    }
};
} // namespace dog
