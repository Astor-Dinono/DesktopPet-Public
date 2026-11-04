#pragma once
#include <windows.h>
#include <gdiplus.h>
#include "MenuModel.hpp"
#include "InteractionEffectArtwork.hpp"

namespace dog::menu {
using Gdiplus::Color;
struct Palette {
    Color background,foreground,muted,border,hover,pale,accent,pet,wag,nap,napInk,danger;
    bool highContrast=false;
};
inline Color rgb(COLORREF value){return Color(255,GetRValue(value),GetGValue(value),GetBValue(value));}
inline Palette systemPalette(){
    HIGHCONTRASTW contrast{sizeof(contrast)};SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(contrast),&contrast,0);
    if(contrast.dwFlags&HCF_HIGHCONTRASTON){
        Color bg=rgb(GetSysColor(COLOR_WINDOW)),fg=rgb(GetSysColor(COLOR_WINDOWTEXT));
        return {bg,fg,fg,fg,bg,bg,fg,bg,bg,bg,fg,fg,true};
    }
    DWORD light=1,bytes=sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",L"AppsUseLightTheme",RRF_RT_REG_DWORD,nullptr,&light,&bytes);
    if(!light)return {Color(0xff2c2d27u),Color(0xfff0f0e8u),Color(0xffb6bfacu),Color(0xff454a3bu),Color(0xff3b4532u),Color(0xff34392du),Color(0xffbfd6a4u),Color(0xff4b3937u),Color(0xff3b4630u),Color(0xff49422eu),Color(0xffe4ca88u),Color(0xfff1aaa3u)};
    return {Color(0xfffffdf8u),Color(0xff343b30u),Color(0xff6d7566u),Color(0xffe7eaddu),Color(0xfff0f4e8u),Color(0xfff5f6edu),Color(0xff526c43u),Color(0xfffaeceau),Color(0xffedf3e3u),Color(0xfffbf1d9u),Color(0xff8e7138u),Color(0xffa83c3cu)};
}
inline Gdiplus::GraphicsPath& rounded(Gdiplus::GraphicsPath& path,Rect r,double radius){
    Gdiplus::REAL d=Gdiplus::REAL(std::min({radius*2,r.w,r.h}));
    path.AddArc(Gdiplus::REAL(r.x),Gdiplus::REAL(r.y),d,d,180,90);
    path.AddArc(Gdiplus::REAL(r.x+r.w-d),Gdiplus::REAL(r.y),d,d,270,90);
    path.AddArc(Gdiplus::REAL(r.x+r.w-d),Gdiplus::REAL(r.y+r.h-d),d,d,0,90);
    path.AddArc(Gdiplus::REAL(r.x),Gdiplus::REAL(r.y+r.h-d),d,d,90,90);path.CloseFigure();return path;
}
inline void fillRound(Gdiplus::Graphics& g,Rect r,double radius,Color fill,Color stroke=Color(0u),double width=1){
    Gdiplus::GraphicsPath p;rounded(p,r,radius);Gdiplus::SolidBrush brush(fill);g.FillPath(&brush,&p);
    if(stroke.GetAlpha()){Gdiplus::Pen pen(stroke,Gdiplus::REAL(width));g.DrawPath(&pen,&p);}
}
template<class Segments,class Transform> inline void vectorPath(Gdiplus::Graphics& g,const Segments& segments,Transform transform,Color stroke,double width,Color fill=Color(0u)){
    Gdiplus::GraphicsPath path;Gdiplus::PointF current{};
    auto point=[&](dog::Point p){p=transform(p);return Gdiplus::PointF(Gdiplus::REAL(p.x),Gdiplus::REAL(p.y));};
    for(const auto& s:segments){
        if(s.type=='M'){path.StartFigure();current=point(s.points[0]);}
        else if(s.type=='L'){auto next=point(s.points[0]);path.AddLine(current,next);current=next;}
        else if(s.type=='C'){auto next=point(s.points[2]);path.AddBezier(current,point(s.points[0]),point(s.points[1]),next);current=next;}
        else if(s.type=='Z')path.CloseFigure();
    }
    if(fill.GetAlpha()){Gdiplus::SolidBrush brush(fill);g.FillPath(&brush,&path);}
    if(width>0&&stroke.GetAlpha()){Gdiplus::Pen pen(stroke,Gdiplus::REAL(width));pen.SetStartCap(Gdiplus::LineCapRound);pen.SetEndCap(Gdiplus::LineCapRound);pen.SetLineJoin(Gdiplus::LineJoinRound);g.DrawPath(&pen,&path);}
}
class MenuPainting {
    Gdiplus::Font normal{L"Segoe UI",13,Gdiplus::FontStyleRegular,Gdiplus::UnitPixel};
    Gdiplus::Font small{L"Segoe UI",11.5f,Gdiplus::FontStyleRegular,Gdiplus::UnitPixel};
    const std::vector<dog::Segment> head=dog::parsePath(dog::headPath),ears=dog::parsePath(dog::earsPath),mouth=dog::parsePath(dog::mouthPath),tail=dog::parsePath(dog::tailPath);
    static const std::vector<dog::Segment>& glyph(Icon icon){
        // Small geometric menu symbols, drawn locally. The dog/effects reuse approved artwork.
        static const std::vector<std::vector<dog::Segment>> paths=[](){
            std::vector<std::vector<dog::Segment>> p(unsigned(Icon::Exit)+1);
            auto set=[&](Icon i,const char* text){p[unsigned(i)]=dog::parsePath(text);};
            set(Icon::Moon,"M14 9 C9 12 4 7 7 2 C1 3 1 11 6 14 C10 16 14 13 14 9 Z");
            set(Icon::Sparkles,"M8 1 C8.7 5.5 9.5 6.2 14 7 C9.5 7.8 8.7 8.5 8 13 C7.3 8.5 6.5 7.8 2 7 C6.5 6.2 7.3 5.5 8 1 Z M13 1 L13 4 M11.5 2.5 L14.5 2.5");
            set(Icon::Sliders,"M2 4 L5 4 M9 4 L14 4 M7 2 L7 6 M2 8 L9 8 M13 8 L14 8 M11 6 L11 10 M2 12 L3 12 M7 12 L14 12 M5 10 L5 14");
            set(Icon::Timer,"M6 1 L10 1 M8 4 C1 4 1 14 8 14 C15 14 15 4 8 4 Z M8 6 L8 9 L10 10 M12 3 L13 2");
            set(Icon::Pointer,"M4 2 L13 8 L9 9 L7 14 L4 2 Z");
            set(Icon::Hide,"M2 2 L14 14 M5 5 C3 6 2 8 1 8 C4 14 12 14 15 8 C13 5 11 4 8 4 M7 7 C5 9 8 12 10 10");
            set(Icon::Chevron,"M6 3 L11 8 L6 13");set(Icon::Back,"M10 3 L5 8 L10 13");set(Icon::Close,"M4 4 L12 12 M12 4 L4 12");
            set(Icon::Rotate,"M13 6 C11 1 3 2 2 7 C1 13 9 16 13 11 M13 2 L13 6 L9 6");
            set(Icon::Edge,"M2 2 L14 2 L14 13 L2 13 Z M3 10 L13 10");
            set(Icon::Shield,"M8 1 L14 4 L13 10 C12 13 10 14 8 15 C6 14 4 13 3 10 L2 4 Z M5 8 L7 10 L11 6");
            set(Icon::Download,"M8 2 L8 10 M4 6 L8 10 L12 6 M2 11 L2 14 L14 14 L14 11");
            set(Icon::Exit,"M6 2 L2 2 L2 14 L6 14 M6 8 L14 8 M11 5 L14 8 L11 11");return p;
        }();
        return paths[unsigned(icon)];
    }
public:
    Palette palette=systemPalette();
    void text(Gdiplus::Graphics& g,const std::wstring& value,Rect r,Color color,bool tiny=false,bool centered=false,bool right=false){
        Gdiplus::StringFormat format;format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        format.SetAlignment(centered?Gdiplus::StringAlignmentCenter:right?Gdiplus::StringAlignmentFar:Gdiplus::StringAlignmentNear);
        format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
        Gdiplus::SolidBrush brush(color);Gdiplus::RectF box(Gdiplus::REAL(r.x),Gdiplus::REAL(r.y),Gdiplus::REAL(r.w),Gdiplus::REAL(r.h));
        g.DrawString(value.c_str(),int(value.size()),tiny?&small:&normal,box,&format,&brush);
    }
    void effect(Gdiplus::Graphics& g,unsigned index,dog::Point origin,double scale){
        for(const auto& shape:dog::effectArtwork()[index])vectorPath(g,shape.path,[&](dog::Point p){return p*scale+origin;},Color(shape.stroke),shape.width*scale,Color(shape.fill));
    }
    void icon(Gdiplus::Graphics& g,Icon kind,Rect frame,Color color){
        if(kind==Icon::None)return;
        if(kind==Icon::Heart){effect(g,0,{frame.x+frame.w/2,frame.y+frame.h/2},frame.w/36);return;}
        if(kind==Icon::Tail){
            double sx=frame.w/24,sy=frame.h/16;
            vectorPath(g,tail,[&](dog::Point p){return dog::Point{frame.x+(5+(p.x-550)*.1)*sx,frame.y+(1.2+(p.y-158)*.1)*sy};},color,1.4*sx);
            static const auto motion=dog::parsePath("M2.7 3.7 C1.3 5.4 1 7.3 1.9 9.1 M21.2 3.1 C22.6 4.8 22.9 6.6 22.1 8.5");
            vectorPath(g,motion,[&](dog::Point p){return dog::Point{frame.x+p.x*sx,frame.y+p.y*sy};},color,1.2*sx);return;
        }
        if(kind==Icon::More){Gdiplus::SolidBrush brush(color);for(int i=0;i<3;++i)g.FillEllipse(&brush,Gdiplus::REAL(frame.x+3+i*4),Gdiplus::REAL(frame.y+7),2.f,2.f);return;}
        vectorPath(g,glyph(kind),[&](dog::Point p){return dog::Point{frame.x+p.x*frame.w/16,frame.y+p.y*frame.h/16};},color,1.3*frame.w/16);
    }
    void avatar(Gdiplus::Graphics& g){
        fillRound(g,{14,12,32,27},9,palette.wag);
        auto transform=[](dog::Point p){return (p-dog::Point{57,50})*.05+dog::Point{16,17};};
        Color ink(0xff262821u),white(0xfffffefbu);
        vectorPath(g,head,transform,ink,1.08,white);vectorPath(g,ears,transform,ink,1.08);vectorPath(g,mouth,transform,ink,1.08);
        Gdiplus::SolidBrush brush(ink);
        for(dog::Point p:std::array<dog::Point,2>{{{200,198},{398,218}}}){p=transform(p);g.FillEllipse(&brush,Gdiplus::REAL(p.x-.93),Gdiplus::REAL(p.y-.93),1.86f,1.86f);}
        auto nose=transform({285,206});g.FillEllipse(&brush,Gdiplus::REAL(nose.x-1.08),Gdiplus::REAL(nose.y-.66),2.16f,1.32f);
    }
    void background(Gdiplus::Graphics& g,const Plan& plan){
        g.Clear(palette.background);fillRound(g,{.5,.5,plan.width-1,plan.height-1},18,palette.background,palette.border);
        if(plan.avatar)avatar(g);
        Gdiplus::Pen line(palette.border,1);for(double y:plan.separators)g.DrawLine(&line,18.f,Gdiplus::REAL(y),Gdiplus::REAL(plan.width-18),Gdiplus::REAL(y));
    }
    void button(Gdiplus::Graphics& g,const Item& item,bool hot,bool pressed,bool checked){
        const double w=item.frame.w,h=item.frame.h;Rect r{0,0,w,h};g.Clear(palette.background);
        auto state=g.Save();if(pressed&&item.style==Style::Shortcut){g.TranslateTransform(Gdiplus::REAL(w*.015),Gdiplus::REAL(h*.015+1));g.ScaleTransform(.97f,.97f);}
        Color foreground=item.id==Quit?palette.muted:palette.foreground;
        if(item.style==Style::Shortcut){
            Color fill=item.id==Pet?palette.pet:item.id==Wag?palette.wag:palette.nap;
            fillRound(g,r,13,fill,hot?palette.accent:Color(0u));
            if(item.icon==Icon::Heart)icon(g,item.icon,{w/2-12,9,24,24},palette.accent);
            else if(item.icon==Icon::Tail)icon(g,item.icon,{w/2-11,13,22,15},palette.accent);
            else icon(g,item.icon,{w/2-10,11,20,20},palette.napInk);
            text(g,item.label,{1,36,w-2,22},foreground,true,true);
        }else if(item.style==Style::Tile){
            fillRound(g,{.5,.5,w-1,h-1},11,checked?palette.hover:palette.background,checked?palette.accent:palette.border);
            effect(g,unsigned(item.id-EffectHeart),{w/2,29},.88);text(g,item.label,{4,52,w-8,20},foreground,false,true);
        }else if(item.style==Style::Close||item.style==Style::Back){
            if(hot||pressed)fillRound(g,r,9,palette.hover);icon(g,item.icon,{(w-16)/2,(h-16)/2,16,16},palette.muted);
        }else if(item.kind==Kind::Label){
            text(g,item.label,r,item.style==Style::Hint||item.style==Style::Stats?palette.muted:foreground,item.style==Style::Hint);
        }else{
            if(hot||pressed||checked)fillRound(g,r,11,hot||pressed?palette.hover:palette.pale);
            double left=item.icon==Icon::None?10:33;
            icon(g,item.icon,{9,(h-15)/2,15,15},palette.muted);
            double reserve=item.chevron?26:8;if(!item.detail.empty())reserve+=68;
            if(item.kind==Kind::Check||item.kind==Kind::Radio)reserve=36;
            text(g,item.label,{left,0,w-left-reserve,h},foreground);
            if(!item.detail.empty())text(g,item.detail,{w-reserve+1,0,64,h},palette.muted,true,false,true);
            if(item.chevron)icon(g,Icon::Chevron,{w-23,(h-14)/2,14,14},palette.muted);
        }
        if(item.kind==Kind::Check||item.kind==Kind::Radio){
            double x=item.style==Style::Tile?w-22:w-28,y=item.style==Style::Tile?9:(h-14)/2;
            if(item.kind==Kind::Radio){
                Gdiplus::Pen pen(palette.accent,1.2f);g.DrawEllipse(&pen,Gdiplus::REAL(x),Gdiplus::REAL(y),14.f,14.f);
                if(checked){Gdiplus::SolidBrush brush(palette.accent);g.FillEllipse(&brush,Gdiplus::REAL(x+4),Gdiplus::REAL(y+4),6.f,6.f);}
            }else{
                fillRound(g,{x,y,13,13},3,checked?palette.accent:palette.background,palette.accent);
                if(checked){Gdiplus::Pen pen(palette.background,1.6f);pen.SetLineJoin(Gdiplus::LineJoinRound);Gdiplus::PointF pts[]={{Gdiplus::REAL(x+3),Gdiplus::REAL(y+6.5)},{Gdiplus::REAL(x+5.5),Gdiplus::REAL(y+9)},{Gdiplus::REAL(x+10),Gdiplus::REAL(y+3.5)}};g.DrawLines(&pen,pts,3);}
            }
        }
        g.Restore(state);
    }
};
} // namespace dog::menu
