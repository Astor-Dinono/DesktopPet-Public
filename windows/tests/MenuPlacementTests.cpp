#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/MenuPlacement.hpp"
#include "../src/MenuModel.hpp"
#include <cassert>
#include <cmath>
#include <iostream>

namespace {
using dog::Bounds;
using dog::Point;
using dog::menu::Page;
constexpr Page pages[]={Page::Home,Page::Appearance,Page::Effects,Page::Sleep,Page::Counts,Page::More};
Bounds frame(Point p,double w,double h){return {p.x,p.y,p.x+w,p.y+h};}
bool fits(Bounds r,Bounds work){return r.left>=work.left&&r.top>=work.top&&r.right<=work.right&&r.bottom<=work.bottom;}
bool same(Point a,Point b){return a.x==b.x&&a.y==b.y;}
Bounds shifted(Bounds r,Point p){return {r.left+p.x,r.top+p.y,r.right+p.x,r.bottom+p.y};}
Bounds padded(Bounds r,double n){return {r.left-n,r.top-n,r.right+n,r.bottom+n};}
double tallestPage(){double h=0;for(auto page:pages)h=std::max(h,dog::menu::layout(page,{}).height);return h;}
struct MenuSize {double scale,w,h;};
MenuSize sizeFor(Bounds work,double dpi){
    const double width=dog::menu::layout(Page::Home,{}).width,height=tallestPage();
    const double scale=std::min({dpi,std::max(1.0,work.right-work.left-8)/width,std::max(1.0,work.bottom-work.top-8)/height});
    return {scale,std::round(width*scale),std::round(height*scale)};
}
double marginFor(Bounds work,MenuSize m){return std::min({std::ceil(4*m.scale),std::max(0.0,(work.right-work.left-m.w)/2),std::max(0.0,(work.bottom-work.top-m.h)/2)});}
void checkNoOverlap(Point p,MenuSize m,Bounds work,Bounds pet){
    const auto r=frame(p,m.w,m.h);
    assert(fits(r,work));
    assert(dog::menu::overlapArea(r,pet)==0);
    assert(dog::menu::overlapArea(r,padded(pet,std::ceil(8*m.scale)))==0);
}
}

int main(){
    std::size_t placements=0,pageChecks=0;
    // Real rotated DogCore bounds, including fractional pet size, display scale,
    // rounded rendering centers and the stable motion padding used by the app.
    for(double dpi:{1.0,1.25,1.5,1.75,2.0,3.0,4.0})
    for(double displayX:{-1920.0,0.0,1920.0})
    for(double size:{.5,.62,.75})
    for(int direction=0;direction<8;++direction)
    for(double x:{0.0,.5,1.0})for(double y:{0.0,.5,1.0}){
        const Bounds work{displayX,-300,displayX+1280*dpi,-300+720*dpi};
        const double angle=direction*dog::pi/4;
        const auto relative=dog::extent(angle,dog::sourceScale*size*dpi);
        Point center{work.left-relative.left+x*(work.right-work.left-relative.right+relative.left),
                     work.top-relative.top+y*(work.bottom-work.top-relative.bottom+relative.top)};
        center={std::round(center.x),std::round(center.y)};
        const auto pet=padded(shifted(relative,center),12*size*dpi);
        const auto m=sizeFor(work,dpi);
        const auto p=dog::menu::placeMenu(center,m.w,m.h,work,pet,m.scale);
        checkNoOverlap(p,m,work,pet);++placements;
        // All settings pages reserve the tallest page. Back/forward navigation
        // must preserve the same origin and keep each actual page on-screen.
        for(auto page:pages){
            const auto next=dog::menu::placeMenu(center,m.w,m.h,work,pet,m.scale,p);
            assert(same(next,p));
            const double actualHeight=std::round(dog::menu::layout(page,{}).height*m.scale);
            assert(fits(frame(next,m.w,actualHeight),work));++pageChecks;
        }
    }
    const Bounds work{0,0,1000,700};const auto m=sizeFor(work,1);
    // Bottom/top attachments must move inward; a tall menu in a short work
    // area must use a side slot rather than clamp vertically over the dog.
    for(const auto pet:std::array<Bounds,2>{{{420,620,580,690},{420,10,580,80}}}){
        const Point anchor{500,(pet.top+pet.bottom)/2};
        const auto p=dog::menu::placeMenu(anchor,m.w,m.h,work,pet,m.scale);
        checkNoOverlap(p,m,work,pet);
        if(pet.top>350)assert(p.y+m.h<=pet.top);else assert(p.y>=pet.bottom);
    }
    for(bool right:{false,true}){
        const Bounds area{0,0,1200,420},pet=right?Bounds{1120,150,1190,270}:Bounds{10,150,80,270};
        const Point anchor{(pet.left+pet.right)/2,210};const auto sm=sizeFor(area,1);
        const auto p=dog::menu::placeMenu(anchor,sm.w,sm.h,area,pet,sm.scale);
        checkNoOverlap(p,sm,area,pet);
        if(right)assert(p.x+sm.w<=pet.left);else assert(p.x>=pet.right);
    }
    // The dog can grow or snap while the menu remains open. A newly unsafe
    // origin must be replaced; a safe origin must stay stable across refreshes.
    const Bounds initialPet{420,620,580,690};const Point anchor{500,655};
    const auto first=dog::menu::placeMenu(anchor,m.w,m.h,work,initialPet,m.scale);
    const Bounds movedPet{first.x+25,first.y+100,first.x+185,first.y+170};
    const auto moved=dog::menu::placeMenu(anchor,m.w,m.h,work,movedPet,m.scale,first);
    assert(!same(first,moved));checkNoOverlap(moved,m,work,movedPet);
    assert(same(moved,dog::menu::placeMenu(anchor,m.w,m.h,work,movedPet,m.scale,moved)));
    const auto breathed=padded(initialPet,1);
    assert(same(first,dog::menu::placeMenu(anchor,m.w,m.h,work,breathed,m.scale,first))==
           (dog::menu::overlapArea(frame(first,m.w,m.h),padded(breathed,8))==0));

    // Tray and hidden-pet requests retain a safe pointer anchor. A dog on
    // another display, or an absent/invalid bound, must not pull the menu away.
    const Point tray{100,100};
    assert(same(tray,dog::menu::placeMenu(tray,m.w,m.h,work,std::nullopt,m.scale)));
    for(auto pet:std::array<Bounds,3>{{{700,500,850,600},{-500,50,-300,150},{0,0,0,0}}})
        assert(same(tray,dog::menu::placeMenu(tray,m.w,m.h,work,pet,m.scale)));
    const auto clamped=dog::menu::placeMenu({999,699},m.w,m.h,work,std::nullopt,m.scale);
    assert(fits(frame(clamped,m.w,m.h),work));
    assert(same(clamped,dog::menu::placeMenu({999,699},m.w,m.h,work,std::nullopt,m.scale,clamped)));

    // At high DPI or on a truly tiny display there may be no clear slot.
    // Preserve reachable controls, determinism and the minimum overlap among
    // boundary placements, including a work area with a negative origin.
    for(double dpi:{1.0,1.25,2.0,4.0})for(double span:{24.0,80.0,160.0,320.0}){
        const Bounds area{-800,-500,-800+span,-500+span*.75};const auto sm=sizeFor(area,dpi);
        const Bounds pet{area.left+span*.1,area.top+span*.075,area.right-span*.1,area.bottom-span*.075};
        const Point middle{(pet.left+pet.right)/2,(pet.top+pet.bottom)/2};
        const auto p=dog::menu::placeMenu(middle,sm.w,sm.h,area,pet,sm.scale);
        assert(fits(frame(p,sm.w,sm.h),area));
        assert(same(p,dog::menu::placeMenu(middle,sm.w,sm.h,area,pet,sm.scale)));
        const double margin=marginFor(area,sm);const auto obstacle=padded(pet,std::ceil(8*sm.scale));
        const double overlap=dog::menu::overlapArea(frame(p,sm.w,sm.h),obstacle);
        for(double px:{area.left+margin,area.right-margin-sm.w})
        for(double py:{area.top+margin,area.bottom-margin-sm.h})
            assert(overlap<=dog::menu::overlapArea(frame({px,py},sm.w,sm.h),obstacle)+1e-9);
    }
    std::cout<<"PASS: "<<placements<<" rotated/edge/DPI/negative-origin placements, "<<pageChecks
             <<" stable page transitions, geometry refresh, tray/hidden and tiny-screen fallback\n";
}
