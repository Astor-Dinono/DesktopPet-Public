#pragma once
#include "DogCore.hpp"
#include <optional>
#include <vector>

namespace dog::menu {
inline bool validArea(Bounds a){return std::isfinite(a.left)&&std::isfinite(a.top)&&std::isfinite(a.right)&&std::isfinite(a.bottom)&&a.right>a.left&&a.bottom>a.top;}
inline double overlapArea(Bounds a,Bounds b){return std::max(0.0,std::min(a.right,b.right)-std::max(a.left,b.left))*std::max(0.0,std::min(a.bottom,b.bottom)-std::max(a.top,b.top));}
// Physical screen pixels, including negative monitor coordinates. Reserve the
// largest page so navigation does not jump or grow back across the character.
inline Point placeMenu(Point anchor,double width,double height,Bounds work,
                       std::optional<Bounds> pet,double scale,
                       std::optional<Point> previous={}){
    const double margin=std::floor(std::min({std::ceil(4*scale),std::max(0.0,(work.right-work.left-width)/2),std::max(0.0,(work.bottom-work.top-height)/2)}));
    Bounds area{work.left+margin,work.top+margin,work.right-margin,work.bottom-margin};
    auto fit=[&](Point p){return Point{std::clamp(std::round(p.x),area.left,std::max(area.left,area.right-width)),std::clamp(std::round(p.y),area.top,std::max(area.top,area.bottom-height))};};
    auto frame=[&](Point p){return Bounds{p.x,p.y,p.x+width,p.y+height};};
    if(!pet||!validArea(*pet)||overlapArea(*pet,work)==0)return fit(previous.value_or(anchor));
    const double gap=std::ceil(8*scale);
    Bounds obstacle{pet->left-gap,pet->top-gap,pet->right+gap,pet->bottom+gap};
    auto safe=[&](Point p){const auto r=frame(p);return r.left>=area.left&&r.top>=area.top&&r.right<=area.right&&r.bottom<=area.bottom&&overlapArea(r,obstacle)==0;};
    if(previous&&safe(fit(*previous)))return fit(*previous);
    // A tray menu stays at the pointer when it already leaves the dog clear.
    bool onPet=anchor.x>=pet->left&&anchor.x<=pet->right&&anchor.y>=pet->top&&anchor.y<=pet->bottom;
    if(!onPet&&safe(fit(anchor)))return fit(anchor);
    double x=fit({anchor.x-width/2,anchor.y}).x,y=fit({anchor.x,anchor.y-height/2}).y;
    const Point above{x,std::floor(obstacle.top-height)},below{x,std::ceil(obstacle.bottom)},
                left{std::floor(obstacle.left-width),y},right{std::ceil(obstacle.right),y};
    bool low=(pet->top+pet->bottom)>(work.top+work.bottom);
    std::vector<Point> candidates{low?above:below,low?below:above,right,left};
    for(auto p:candidates)if(safe(p))return p;
    // Extremely small work areas may have no disjoint placement. Keep every
    // control reachable and choose the least overlap, without moving the pet.
    candidates.push_back(anchor);
    for(double cx:{area.left,area.right-width})for(double cy:{area.top,area.bottom-height})candidates.push_back({cx,cy});
    Point best=fit(anchor);double score=overlapArea(frame(best),obstacle);
    for(auto p:candidates){p=fit(p);double next=overlapArea(frame(p),obstacle);if(next<score){best=p;score=next;}}
    return best;
}
}
