#pragma once
#include <algorithm>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace dog::menu {
enum Command {Pet=100,Wag,Nap,Hide,Rotate,Snap,Small,Medium,Large,NapOff,Nap30,Nap60,Nap180,Nap300,Count,Always,Privacy,Website,Quit,EffectHeart=200,EffectFlower,EffectPaw,EffectStar,ChooseEffects,TailSmall=300,TailOriginal,LockPosition,ShowOperationHint};
enum class Page {Home,Appearance,Effects,Sleep,Counts,More};
enum class Kind {Push,Check,Radio,Combo,Label};
enum class Style {Row,Shortcut,Tile,Close,Back,Title,Hint,Field,Stats};
enum class Icon {None,Heart,Tail,Moon,Sparkles,Sliders,Timer,Pointer,Hide,More,Chevron,Close,Back,Rotate,Edge,Shield,Download,Exit};
enum ControlID {Back=400,Close,Appearance,Sleep,Counts,More,SizeChoice,TailChoice,Title,Hint,Today,Total};
struct Rect { double x,y,w,h; };
struct Snapshot {
    bool visible=true,asleep=false,counting=false,always=false,positionLocked=true;
    unsigned effects=1;int nap=180,size=1,tail=80;
    std::uint64_t today=0,total=0;
};
struct Item {
    int id;Kind kind;Style style;Rect frame;std::wstring label,detail;Icon icon=Icon::None;
    bool checked=false,chevron=false;int selection=0;
};
struct Plan { double width=252,height=0;bool avatar=false;std::vector<Item> items;std::vector<double> separators; };
inline std::wstring sleepLabel(int n){return n==0?L"关闭":n==30?L"30 秒":n==60?L"1 分钟":n==300?L"5 分钟":L"3 分钟";}
inline unsigned effectCount(unsigned value){unsigned n=0;for(unsigned i=0;i<4;++i)n+=(value>>i)&1;return n;}
inline Plan layout(Page page,const Snapshot& s){
    Plan p;double y=50;
    auto add=[&](int id,Kind kind,Style style,Rect r,std::wstring label,Icon icon=Icon::None,std::wstring detail=L"",bool checked=false,bool chevron=false,int selection=0){p.items.push_back({id,kind,style,r,std::move(label),std::move(detail),icon,checked,chevron,selection});};
    auto row=[&](int id,const wchar_t* label,Icon icon=Icon::None,std::wstring detail=L"",bool chevron=false){add(id,Kind::Push,Style::Row,{12,y,228,32},label,icon,std::move(detail),false,chevron);y+=32;};
    auto line=[&](){p.separators.push_back(y+6);y+=12;};
    auto label=[&](int id,std::wstring value,Style style=Style::Hint){add(id,Kind::Label,style,{20,y,212,24},std::move(value));y+=24;};
    const wchar_t* title=page==Page::Home?L"小狗桌宠":page==Page::Appearance?L"外观与摆放":page==Page::Effects?L"互动特效":page==Page::Sleep?L"自动打盹":page==Page::Counts?L"点击次数":L"更多";
    p.avatar=page==Page::Home;
    if(page!=Page::Home)add(Back,Kind::Push,Style::Back,{12,13,24,24},L"返回主菜单",Icon::Back);
    add(Title,Kind::Label,Style::Title,{page==Page::Home?56.0:42.0,13,page==Page::Home?152.0:166.0,24},title);
    add(Close,Kind::Push,Style::Close,{216,13,24,24},L"关闭菜单",Icon::Close);
    switch(page){
    case Page::Home:{
        double width=(224.0-12)/3;
        add(Pet,Kind::Push,Style::Shortcut,{14,y,width,64},L"摸摸它",Icon::Heart);
        add(Wag,Kind::Push,Style::Shortcut,{20+width,y,width,64},L"摇尾巴",Icon::Tail);
        add(Nap,Kind::Push,Style::Shortcut,{26+width*2,y,width,64},s.asleep?L"醒醒":L"打个盹",Icon::Moon);
        y+=72;unsigned n=effectCount(s.effects);
        row(ChooseEffects,L"互动特效",Icon::Sparkles,n?std::to_wstring(n)+L" 种":L"关闭",true);line();
        row(Appearance,L"外观与摆放",Icon::Sliders,L"",true);
        row(Sleep,L"自动打盹",Icon::Timer,sleepLabel(s.nap),true);
        row(Counts,L"点击次数",Icon::Pointer,s.counting?L"计数中":L"已暂停",true);line();
        row(Hide,s.visible?L"收起小狗":L"显示小狗",Icon::Hide);
        row(More,L"更多",Icon::More,L"",true);break;
    }
    case Page::Appearance:
        add(LockPosition,Kind::Check,Style::Row,{12,y,228,32},L"锁定位置",Icon::None,L"",s.positionLocked);y+=32;
        label(Hint,s.positionLocked?L"按住摸摸 · 双击第二下拖动":L"已解锁 · 按住可直接拖动");
        row(Rotate,L"转个身",Icon::Rotate,L"选中后 R");row(Snap,L"贴到当前朝向的边缘",Icon::Edge);line();
        add(Title+20,Kind::Label,Style::Field,{20,y,108,36},L"小狗大小");
        add(SizeChoice,Kind::Combo,Style::Field,{136,y+4,96,28},L"小狗大小",Icon::None,L"",false,false,s.size);y+=38;
        add(Title+21,Kind::Label,Style::Field,{20,y,108,36},L"尾巴大小");
        add(TailChoice,Kind::Combo,Style::Field,{136,y+4,96,28},L"尾巴大小",Icon::None,L"",false,false,s.tail==100?1:0);y+=38;break;
    case Page::Effects:{
        label(Hint,effectCount(s.effects)?L"可多选 · 随机出现":L"特效已关闭");
        const wchar_t* names[]={L"爱心",L"小花",L"小爪子",L"小星星"};
        for(int i=0;i<4;++i)add(EffectHeart+i,Kind::Check,Style::Tile,{14.0+(i%2)*114,y+(i/2)*84,110,78},names[i],Icon::None,L"",(s.effects&(1u<<i))!=0);
        y+=162;break;
    }
    case Page::Sleep:{
        label(Hint,L"空闲多久后打盹");const int ids[]={NapOff,Nap30,Nap60,Nap180,Nap300},values[]={0,30,60,180,300};
        for(int i=0;i<5;++i){add(ids[i],Kind::Radio,Style::Row,{12,y,228,32},sleepLabel(values[i]),Icon::None,L"",s.nap==values[i]);y+=32;}break;
    }
    case Page::Counts:
        add(Count,Kind::Check,Style::Row,{12,y,228,32},L"开启计数",Icon::None,L"",s.counting);y+=32;
        add(Always,Kind::Check,Style::Row,{12,y,228,32},L"始终显示数字",Icon::None,L"",s.always);y+=32;line();
        label(Today,L"今日  "+std::to_wstring(s.today),Style::Stats);label(Total,L"累计  "+std::to_wstring(s.total),Style::Stats);break;
    case Page::More:
        row(ShowOperationHint,L"操作提示…",Icon::Pointer);row(Privacy,L"隐私与计数说明",Icon::Shield);row(Website,L"检查更新",Icon::Download);line();row(Quit,L"退出小狗",Icon::Exit);break;
    }
    p.height=y+12;return p;
}
inline bool isNavigation(int id){return id==Appearance||id==ChooseEffects||id==Sleep||id==Counts||id==More;}
inline Page destination(int id){return id==Appearance?Page::Appearance:id==ChooseEffects?Page::Effects:id==Sleep?Page::Sleep:id==Counts?Page::Counts:Page::More;}
inline int comboCommand(int id,int value){return id==SizeChoice?(value==0?Small:value==2?Large:Medium):(value==1?TailOriginal:TailSmall);}
inline bool closesForCommand(int id,const Snapshot& s){return id==ShowOperationHint||id==Rotate||id==Hide||id==Privacy||id==Website||id==Quit||(id==Count&&!s.counting);}
} // namespace dog::menu
