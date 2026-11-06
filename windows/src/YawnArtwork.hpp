#pragma once
#include "DogArtwork.hpp"
#include <DogYawnData.hpp>

namespace dog {
// Source space is y-down, 749 units wide. The reviewed tracing is 1280 wide;
// its baseline y=696 maps to the same y=268 used by the native dog paths.
inline constexpr double yawnVideoToSource=749.0/1280.0;
inline double boundedYawnTime(double time) {
    return std::isfinite(time)?clamp(time,0,yawn_data::duration):0;
}
inline std::size_t yawnFrameIndex(double time) {
    time=boundedYawnTime(time);std::size_t low=0,high=yawn_data::frames.size()-1;
    while(low<high){const auto middle=(low+high+1)/2;
        if(yawn_data::frames[middle].time<=time+1e-7)low=middle;else high=middle-1;
    }
    return low;
}
struct YawnHeadTransform {
    double sx=1,sy=1,dx=0;
    Point apply(Point p) const {return {305+(p.x-305)*sx+dx,268+(p.y-268)*sy};}
    Point inverse(Point p) const {return {305+(p.x-305-dx)/sx,268+(p.y-268)/sy};}
};
inline YawnHeadTransform recordedYawnHead(double time) {
    const auto& rest=yawn_data::frames.front();const auto& frame=yawn_data::frames[yawnFrameIndex(time)];
    return {frame.width/rest.width,(696-frame.height)/(696-rest.height),(frame.center-rest.center)*yawnVideoToSource};
}
inline YawnHeadTransform blendedYawnHead(double time,double weight,double normalSX,double normalSY) {
    weight=std::isfinite(weight)?clamp(weight):0;
    if(weight<=0)return {normalSX,normalSY,0};
    const auto recorded=recordedYawnHead(time);
    return {normalSX+(recorded.sx-normalSX)*weight,normalSY+(recorded.sy-normalSY)*weight,recorded.dx*weight};
}
inline Point yawnTracedPoint(double x,double y) {return {x*yawnVideoToSource,268+(y-696)*yawnVideoToSource};}

struct YawnTailPose {double angle=0,scale=1,bend=0;};
inline double yawnTailDrop(double time) {
    static constexpr std::array<std::array<double,2>,13> keys{{
        {{0,0}},{{.25,0}},{{1.0/3,.07}},{{.5,.46}},{{2.0/3,.69}},
        {{1,.97}},{{7.0/6,1}},{{1.5,1}},{{5.0/3,.73}},{{11.0/6,.35}},
        {{2,.16}},{{2.25,0}},{{yawn_data::duration,0}}
    }};
    static const auto slopes=[](){std::array<double,keys.size()> result{};
        for(std::size_t i=1;i+1<keys.size();++i){
            const auto a=keys[i-1],p=keys[i],b=keys[i+1];
            const double h0=p[0]-a[0],h1=b[0]-p[0],d0=(p[1]-a[1])/h0,d1=(b[1]-p[1])/h1;
            if(d0*d1>0){const double w0=2*h1+h0,w1=h1+2*h0;result[i]=(w0+w1)/(w0/d0+w1/d1);}
        }return result;
    }();
    std::size_t i=0;while(i+2<keys.size()&&time>keys[i+1][0])++i;
    const auto a=keys[i],b=keys[i+1];const double h=b[0]-a[0],u=clamp((time-a[0])/h),u2=u*u,u3=u2*u;
    return (2*u3-3*u2+1)*a[1]+(u3-2*u2+u)*h*slopes[i]
        +(-2*u3+3*u2)*b[1]+(u3-u2)*h*slopes[i+1];
}
inline YawnTailPose recordedYawnTail(double time) {
    time=boundedYawnTime(time);const double amount=yawnTailDrop(time),videoScale=1280.0/749.0;
    const Point root{574*videoScale,696+12*videoScale};
    const Point initial=Point{yawn_data::tailTip[0],yawn_data::tailTip[1]}-root;
    const Point target=Point{1121,574.8}-root,now=initial+(target-initial)*amount;
    double wag=0,bend=0;
    if(time>3&&time<3.85){const double u=(time-3)/.85,sine=std::sin(pi*u),envelope=sine*sine;
        wag=.11*std::sin(2*pi*u)*envelope;bend=.20*std::sin(2*pi*u-.5)*envelope;
    }
    // Keep angle in Mac's y-up convention; bendTail changes its sign once.
    return {-(std::atan2(now.y,now.x)-std::atan2(initial.y,initial.x)+wag),
        std::hypot(now.x,now.y)/std::hypot(initial.x,initial.y),bend};
}
inline Point blendedYawnTailPoint(Point p,double time,double weight,TailPose normal,TailSize size) {
    weight=std::isfinite(weight)?clamp(weight):0;
    if(weight<=0)return bendTail(p,normal,size);
    const auto recorded=recordedYawnTail(time);
    const TailPose mixed{normal.angle+(recorded.angle-normal.angle)*weight,normal.bend+(recorded.bend-normal.bend)*weight};
    return (bendTail(p,mixed,size)-Point{574,280})*(1+(recorded.scale-1)*weight)+Point{574,280};
}
} // namespace dog
