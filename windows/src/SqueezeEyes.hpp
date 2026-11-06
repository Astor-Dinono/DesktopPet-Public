#pragma once
#include "PetExpression.hpp"

namespace dog {
// The sole petting expression: left > and right <, matching the chosen B draft.
// Keep the historical arc-eye helper available to old, independent design tools.
struct SqueezeEye {
    std::array<Segment,6> normal;
    std::array<Segment,3> squeeze;
    std::vector<Segment> outline;
    double normalAlpha=1,squeezeAlpha=0;
    double strokeWidth=1.7/sourceScale;
};
inline constexpr int squeezeMorphSteps=256;
inline const std::array<Point,squeezeMorphSteps>& squeezeMorphBoundary(bool left){
    static const auto boundaries=[](){
        std::array<std::array<Point,squeezeMorphSteps>,2> result;
        for(int eye=0;eye<2;++eye){const double sign=eye==0?1:-1,w=3.7,h=4.6,radius=.85;
            const Point apex{sign*w,0},top{-sign*w,-h},bottom{-sign*w,h};
            auto distance=[](Point p,Point a,Point b){const auto d=b-a,q=p-a;
                const double t=clamp((q.x*d.x+q.y*d.y)/(d.x*d.x+d.y*d.y));const auto e=q-d*t;return std::hypot(e.x,e.y);};
            for(int step=0;step<squeezeMorphSteps;++step){const double theta=2*pi*step/squeezeMorphSteps;
                const Point direction{std::cos(theta),-std::sin(theta)};double low=0,high=20;
                for(int iteration=0;iteration<40;++iteration){const double middle=(low+high)/2;const auto p=apex+direction*middle;
                    if(std::min(distance(p,apex,top),distance(p,apex,bottom))<=radius)low=middle;else high=middle;}
                result[eye][step]=(apex+direction*((low+high)/2))*(1/sourceScale);
            }
        }
        return result;
    }();
    return boundaries[left?0:1];
}
inline std::vector<Segment> squeezeMorphPath(Point center,bool left,double normalClosed,double amount){
    const auto& boundary=squeezeMorphBoundary(left);
    // Petting takes over a coincident blink continuously. A fully closed
    // ordinary eye has a shallow crescent cusp; retaining that cusp while
    // bending into the chevron could fold a tiny loop at the eye corner.
    normalClosed=clamp(normalClosed)*clamp(1-2*amount);
    const double w=(5.4+normalClosed*.9)/sourceScale,h=(5.4*(1-normalClosed)+normalClosed*1.52)/sourceScale,
        sag=normalClosed*1.8/sourceScale,top=sag-h,bottom=sag+h,k=.55228475;
    const std::array<std::array<Point,4>,4> arcs{{
        {{{w,0},{w,top*k},{w*k,top},{0,top}}},
        {{{0,top},{-w*k,top},{-w,top*k},{-w,0}}},
        {{{-w,0},{-w,bottom*k},{-w*k,bottom},{0,bottom}}},
        {{{0,bottom},{w*k,bottom},{w,bottom*k},{w,0}}}
    }};
    std::vector<Segment> result;result.reserve(squeezeMorphSteps+1);
    for(int step=0;step<squeezeMorphSteps;++step){const int quarter=step/(squeezeMorphSteps/4);
        const double t=double(step%(squeezeMorphSteps/4))/(squeezeMorphSteps/4),v=1-t;const auto& p=arcs[quarter];
        const auto normal=p[0]*(v*v*v)+p[1]*(3*v*v*t)+p[2]*(3*v*t*t)+p[3]*(t*t*t);
        const auto point=center+normal+(boundary[step]-normal)*amount;
        result.push_back({step==0?'M':'L',{{point,{},{}}}});
    }
    result.push_back({'Z',{}});return result;
}
inline SqueezeEye squeezeEye(Point center,bool left,double normalClosed,double amount){
    const double a=std::isfinite(amount)?clamp(amount):0;
    SqueezeEye result;
    result.normal=eyePath(center,normalClosed);
    if(a>=1){result.normalAlpha=0;result.squeezeAlpha=1;}
    else if(a>0){result.normalAlpha=0;result.outline=squeezeMorphPath(center,left,normalClosed,a);}
    const double w=3.7/sourceScale,h=4.6/sourceScale,sign=left?1:-1;
    result.squeeze[0]={'M',{{{center.x-sign*w,center.y-h},{},{}}}};
    result.squeeze[1]={'L',{{{center.x+sign*w,center.y},{},{}}}};
    result.squeeze[2]={'L',{{{center.x-sign*w,center.y+h},{},{}}}};
    return result;
}
} // namespace dog
