#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/MenuModel.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>
#include <set>

using namespace dog::menu;
const Item& find(const Plan& p,int id){for(const auto& item:p.items)if(item.id==id)return item;assert(false);return p.items.front();}
int main(){
    const Page pages[]={Page::Home,Page::Appearance,Page::Effects,Page::Sleep,Page::Counts,Page::More};
    Snapshot s;assert(!s.positionLocked);s.today=std::numeric_limits<std::uint64_t>::max();s.total=s.today;
    for(unsigned mask=0;mask<16;++mask)for(int nap:{0,30,60,180,300})for(Page page:pages){
        s.effects=mask;s.nap=nap;Plan p=layout(page,s);std::set<int> ids;
        assert(p.width==252&&p.height<=layout(Page::Home,s).height);
        for(const auto& a:p.items){
            assert(ids.insert(a.id).second);
            assert(a.frame.x>=0&&a.frame.y>=0&&a.frame.w>0&&a.frame.h>0);
            assert(a.frame.x+a.frame.w<=p.width&&a.frame.y+a.frame.h<=p.height);
            for(const auto& b:p.items)if(a.id!=b.id){
                double x=std::min(a.frame.x+a.frame.w,b.frame.x+b.frame.w)-std::max(a.frame.x,b.frame.x);
                double y=std::min(a.frame.y+a.frame.h,b.frame.y+b.frame.h)-std::max(a.frame.y,b.frame.y);
                assert(x<=.01||y<=.01);
            }
            for(double dpi:{1.0,1.25,1.5,1.75,2.0,2.5,3.0,4.0}){
                // The same logical bounds place native controls at fractional scaling.
                double right=std::round((a.frame.x+a.frame.w)*dpi),bottom=std::round((a.frame.y+a.frame.h)*dpi);
                assert(right<=std::round(p.width*dpi)&&bottom<=std::round(p.height*dpi));
            }
        }
        assert(ids.count(Title)&&ids.count(Close));
        if(page==Page::Home){
            assert(!ids.count(Quit));assert(find(p,Pet).style==Style::Shortcut&&find(p,Wag).icon==Icon::Tail);
            assert(find(p,Sleep).detail==sleepLabel(nap));assert(find(p,ChooseEffects).chevron);
        }else assert(ids.count(Back));
        if(page==Page::Effects)for(int i=0;i<4;++i){const auto& item=find(p,EffectHeart+i);assert(item.kind==Kind::Check&&item.checked==bool(mask&(1u<<i)));}
        if(page==Page::Sleep){int selected=0;for(const auto& item:p.items)if(item.kind==Kind::Radio)selected+=item.checked;assert(selected==1);}
    }
    s.counting=false;assert(closesForCommand(Count,s));s.counting=true;assert(!closesForCommand(Count,s));
    for(int id:{Pet,Wag,Nap,Always,LockPosition,EffectHeart,EffectFlower,EffectPaw,EffectStar,Small,Medium,Large,TailSmall,TailOriginal})assert(!closesForCommand(id,s));
    for(int id:{ShowOperationHint,Rotate,Hide,Privacy,Website,Quit})assert(closesForCommand(id,s));
    assert(find(layout(Page::More,s),ShowOperationHint).label==L"操作提示…");
    assert(destination(ChooseEffects)==Page::Effects&&destination(More)==Page::More);
    assert(comboCommand(SizeChoice,0)==Small&&comboCommand(SizeChoice,1)==Medium&&comboCommand(SizeChoice,2)==Large);
    assert(comboCommand(TailChoice,0)==TailSmall&&comboCommand(TailChoice,1)==TailOriginal);
    s.asleep=true;s.visible=false;s.always=true;s.size=2;s.tail=100;
    assert(find(layout(Page::Home,s),Nap).label==L"醒醒");assert(find(layout(Page::Home,s),Hide).label==L"显示小狗");
    assert(find(layout(Page::Appearance,s),SizeChoice).selection==2&&find(layout(Page::Appearance,s),TailChoice).selection==1);
    s.positionLocked=false;assert(!find(layout(Page::Appearance,s),LockPosition).checked);
    s.positionLocked=true;assert(find(layout(Page::Appearance,s),LockPosition).checked);
    assert(find(layout(Page::Appearance,s),LockPosition).kind==Kind::Check);
    assert(find(layout(Page::Counts,s),Always).checked);
    assert(find(layout(Page::Counts,s),Total).label.find(std::to_wstring(s.total))!=std::wstring::npos);
    std::cout<<"PASS: all pages/masks/nap options, geometry at 100–400%, live state, navigation, safe action dismissal\n";
}
