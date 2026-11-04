#pragma once
#include "DogArtwork.hpp"

namespace dog {
// A short, continuous pleased expression. Only the most recent response and its
// current value/velocity are retained; there is no pointer or activity history.
class PetExpression {
    double started_=-100;
    State from_{};
    bool active_=false;
    State sample(double t) const {
        if(!active_||!std::isfinite(t))return {};
        const double age=std::max(0.0,t-started_);
        if(age<=.35)return spring(from_,1,age,32);
        return fall(spring(from_,1,.35,32),age-.35,.50,15);
    }
public:
    void touch(double t) {
        if(!std::isfinite(t)||(active_&&t<started_))return;
        from_=sample(t);started_=t;active_=true;
    }
    double value(double t) const { return clamp(sample(t).value); }
    bool moving(double t) const { return active_&&std::isfinite(t)&&t-started_<.85; }
    void clear() { from_={};started_=-100;active_=false; }
};

// Preserve the exact original eye when happy == 0. The happy endpoint is a
// gentle upward arch, distinct from the downward sleeping lid. Existing mouth,
// nose, and eye centres are unchanged. Both endpoints share six path segments.
inline std::array<Segment,6> petEyePath(Point center,double normalClosed,double happy) {
    const double amount=std::isfinite(happy)?clamp(happy):0;
    auto result=eyePath(center,normalClosed);
    if(amount==0)return result;
    const double w=6.3/sourceScale,k=.55228475;
    const double top=center.y-3.55/sourceScale,bottom=center.y-1.65/sourceScale;
    auto target=eyePath(center,1);
    target[1].points={{{center.x-w,center.y+(top-center.y)*k},{center.x-w*k,top},{center.x,top}}};
    target[2].points={{{center.x+w*k,top},{center.x+w,center.y+(top-center.y)*k},{center.x+w,center.y}}};
    target[3].points={{{center.x+w,center.y+(bottom-center.y)*k},{center.x+w*k,bottom},{center.x,bottom}}};
    target[4].points={{{center.x-w*k,bottom},{center.x-w,center.y+(bottom-center.y)*k},{center.x-w,center.y}}};
    for(std::size_t i=0;i<result.size();++i){
        const unsigned n=result[i].type=='C'?3:result[i].type=='M'?1:0;
        for(unsigned j=0;j<n;++j)result[i].points[j]=result[i].points[j]+(target[i].points[j]-result[i].points[j])*amount;
    }
    return result;
}
} // namespace dog
