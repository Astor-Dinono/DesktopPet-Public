#pragma once
#include "DogCore.hpp"

namespace dog {
// Only this launch's request is transient. The saved opt-out remains in Settings.
struct OperationHintState {
    bool requested=false;
    void beginSession(bool enabled){requested=enabled;}
    void openManually(){requested=true;}
    void dismiss(){requested=false;}
    bool available(bool running,bool asleep,bool menu,bool pointer,bool turning)const{
        return requested&&running&&!asleep&&!menu&&!pointer&&!turning;
    }
};
enum class HintSide {Above,Below,Left,Right};
struct HintPlacement {Bounds frame;Point anchor;HintSide side;double scale;};
inline bool hintValid(Bounds r){return std::isfinite(r.left)&&std::isfinite(r.top)&&std::isfinite(r.right)&&std::isfinite(r.bottom)&&r.right>r.left&&r.bottom>r.top;}
inline bool hintIntersects(Bounds a,Bounds b){return hintValid(a)&&hintValid(b)&&a.left<b.right&&a.right>b.left&&a.top<b.bottom&&a.bottom>b.top;}
inline bool hintFits(Bounds r,Bounds area){return hintValid(r)&&r.left>=area.left&&r.top>=area.top&&r.right<=area.right&&r.bottom<=area.bottom;}
inline std::optional<HintPlacement> operationHintPlacement(Bounds pet,Bounds badge,Bounds work,double scale,
                                                          const std::optional<HintPlacement>& previous={}){
    if(!hintValid(pet)||!hintValid(work)||!std::isfinite(scale)||scale<=0)return {};
    const double margin=4*scale,gap=6*scale;
    Bounds area{work.left+margin,work.top+margin,work.right-margin,work.bottom-margin};
    if(!hintValid(area))return {};
    auto padded=[](Bounds r,double padding){return Bounds{r.left-padding,r.top-padding,r.right+padding,r.bottom+padding};};
    auto safe=[&](Bounds r,double padding){return hintFits(r,area)&&!hintIntersects(r,padded(pet,padding))&&(!hintValid(badge)||!hintIntersects(r,padded(badge,padding)));};
    Point center{(pet.left+pet.right)/2,(pet.top+pet.bottom)/2};
    // Do not chase breathing and tail motion. Keep the last safe placement until
    // the role really moves, another element would overlap, or DPI changes.
    if(previous&&previous->scale==scale&&std::hypot(center.x-previous->anchor.x,center.y-previous->anchor.y)<=12*scale&&safe(previous->frame,2*scale))return previous;
    Bounds obstacle=pet;
    if(hintValid(badge))obstacle={std::min(pet.left,badge.left),std::min(pet.top,badge.top),std::max(pet.right,badge.right),std::max(pet.bottom,badge.bottom)};
    const bool nearBottom=center.y>(work.top+work.bottom)/2;
    const std::array<HintSide,4> order=nearBottom
        ?std::array<HintSide,4>{HintSide::Above,HintSide::Below,HintSide::Left,HintSide::Right}
        :std::array<HintSide,4>{HintSide::Below,HintSide::Above,HintSide::Left,HintSide::Right};
    for(auto side:order){
        const bool vertical=side==HintSide::Above||side==HintSide::Below;
        const double w=(192+(vertical?0:6))*scale,h=(98+(vertical?6:0))*scale;
        if(std::ceil(w)>std::floor(area.right)-std::ceil(area.left)||std::ceil(h)>std::floor(area.bottom)-std::ceil(area.top))continue;
        double x=std::clamp(center.x-w/2,area.left,area.right-w),y=std::clamp(center.y-h/2,area.top,area.bottom-h);
        if(side==HintSide::Above)y=obstacle.top-gap-h;
        if(side==HintSide::Below)y=obstacle.bottom+gap;
        if(side==HintSide::Left)x=obstacle.left-gap-w;
        if(side==HintSide::Right)x=obstacle.right+gap;
        Bounds frame{std::round(x),std::round(y),std::round(x)+std::ceil(w),std::round(y)+std::ceil(h)};
        // Rounding must not consume the protective gap at fractional DPI.
        if(side==HintSide::Above){frame.bottom=std::floor(obstacle.top-gap);frame.top=frame.bottom-std::ceil(h);}
        if(side==HintSide::Below){frame.top=std::ceil(obstacle.bottom+gap);frame.bottom=frame.top+std::ceil(h);}
        if(side==HintSide::Left){frame.right=std::floor(obstacle.left-gap);frame.left=frame.right-std::ceil(w);}
        if(side==HintSide::Right){frame.left=std::ceil(obstacle.right+gap);frame.right=frame.left+std::ceil(w);}
        // Clamp only along the free axis; never push the bubble onto the dog.
        if(vertical){frame.left=std::clamp(frame.left,std::ceil(area.left),std::floor(area.right)-std::ceil(w));frame.right=frame.left+std::ceil(w);}
        else{frame.top=std::clamp(frame.top,std::ceil(area.top),std::floor(area.bottom)-std::ceil(h));frame.bottom=frame.top+std::ceil(h);}
        if(safe(frame,gap))return HintPlacement{frame,center,side,scale};
    }
    return {}; // The text never shrinks to fit an unsafe gap.
}
} // namespace dog
