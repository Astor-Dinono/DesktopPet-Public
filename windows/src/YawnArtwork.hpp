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

// Keep the last recorded lids as the ordinary sleeping-eye endpoint. Matching
// only their stroke width still shortened and flattened them at the handoff.
// Cache the source-space paths with only the clip's head transform undone.
// They follow the shared head directly, independent of ordinary face settling.
inline const std::array<std::vector<Segment>,2>& yawnSleepEyePaths() {
    static const auto paths=[](){
        std::array<std::vector<Segment>,2> result;
        std::array<double,2> distances{{1e100,1e100}};
        constexpr std::array<Point,2> centers{{{200,198},{398,218}}};
        const auto& frame=yawn_data::frames.back();const auto head=recordedYawnHead(frame.time);
        std::vector<Segment> current;
        Bounds bounds{1e100,1e100,-1e100,-1e100};
        for(std::size_t i=frame.face.offset;i<frame.face.offset+frame.face.count;){
            const auto command=yawn_data::commands[i++];
            if(command==2){
                current.push_back({'Z',{}});
                const Point center{(bounds.left+bounds.right)/2,(bounds.top+bounds.bottom)/2};
                for(std::size_t eye=0;eye<result.size();++eye){
                    const double distance=std::hypot(center.x-centers[eye].x,center.y-centers[eye].y);
                    if(distance<distances[eye]){distances[eye]=distance;result[eye]=current;}
                }
                current.clear();bounds={1e100,1e100,-1e100,-1e100};continue;
            }
            auto p=head.inverse(yawnTracedPoint(yawn_data::commands[i],yawn_data::commands[i+1]));i+=2;
            bounds.left=std::min(bounds.left,p.x);bounds.right=std::max(bounds.right,p.x);
            bounds.top=std::min(bounds.top,p.y);bounds.bottom=std::max(bounds.bottom,p.y);
            current.push_back({command==0?'M':'L',{{p,{},{}}}});
        }
        return result;
    }();
    return paths;
}

inline constexpr int sleepEyeArcSteps=64;
struct SleepEyeArcs {std::array<Point,sleepEyeArcSteps+1> upper,lower;};
inline const std::array<SleepEyeArcs,2>& yawnSleepEyeArcs() {
    static const auto arcs=[](){
        std::array<SleepEyeArcs,2> result;
        const auto& paths=yawnSleepEyePaths();
        for(std::size_t eye=0;eye<paths.size();++eye){
            std::vector<Point> points;
            for(const auto& s:paths[eye])if(s.type=='M'||s.type=='L')points.push_back(s.points[0]);
            const auto less=[](Point a,Point b){return a.x<b.x;};
            const int left=int(std::min_element(points.begin(),points.end(),less)-points.begin());
            const int right=int(std::max_element(points.begin(),points.end(),less)-points.begin());
            auto resample=[&](int direction){
                std::vector<Point> arc{points[left]};int index=left;
                while(index!=right){index=(index+direction+int(points.size()))%int(points.size());arc.push_back(points[index]);}
                std::vector<double> lengths{0};
                for(std::size_t i=1;i<arc.size();++i)lengths.push_back(lengths.back()+std::hypot(arc[i].x-arc[i-1].x,arc[i].y-arc[i-1].y));
                std::array<Point,sleepEyeArcSteps+1> sampled{};std::size_t segment=1;
                for(int step=0;step<=sleepEyeArcSteps;++step){
                    const double distance=lengths.back()*step/sleepEyeArcSteps;
                    while(segment+1<lengths.size()&&lengths[segment]<distance)++segment;
                    const double t=(distance-lengths[segment-1])/std::max(1e-12,lengths[segment]-lengths[segment-1]);
                    sampled[step]=arc[segment-1]+(arc[segment]-arc[segment-1])*t;
                }
                return sampled;
            };
            auto a=resample(1),b=resample(-1);double ay=0,by=0;
            for(int i=0;i<=sleepEyeArcSteps;++i){ay+=a[i].y;by+=b[i].y;}
            result[eye]=ay<by?SleepEyeArcs{a,b}:SleepEyeArcs{b,a};
        }
        return result;
    }();
    return arcs;
}

// A single opaque contour opens from the recorded lid. Both arcs run from
// left to right; the lower arc is reversed only when closing the outline.
// Returned points use the ordinary face transform, compensating its settling
// only in proportion to sleep so both original endpoints stay in place.
inline std::vector<Segment> yawnSleepTransitionEye(std::size_t index,Point center,double sleep,double blink,double settle) {
    const double amount=clamp(sleep),shift=settle*1.1/sourceScale;
    if(amount<=0){const auto eye=eyePath(center,blink);return {eye.begin(),eye.end()};}
    if(amount>=1){auto eye=yawnSleepEyePaths()[index];
        for(auto& s:eye)if(s.type!='Z')s.points[0].y-=shift;return eye;}
    const auto& arcs=yawnSleepEyeArcs()[index];
    const double w=(5.4+blink*.9)/sourceScale,h=(5.4*(1-blink)+blink*1.52)/sourceScale,sag=blink*1.8/sourceScale;
    auto target=[&](int step,bool upper){
        const double u=double(step)/sleepEyeArcSteps;const bool first=u<=.5;
        const double t=first?u*2:(u-.5)*2,v=1-t,y=center.y+sag+(upper?-h:h),k=.55228475;
        const std::array<Point,4> p=first
            ?std::array<Point,4>{{{center.x-w,center.y},{center.x-w,center.y+(y-center.y)*k},{center.x-w*k,y},{center.x,y}}}
            :std::array<Point,4>{{{center.x,y},{center.x+w*k,y},{center.x+w,center.y+(y-center.y)*k},{center.x+w,center.y}}};
        return p[0]*(v*v*v)+p[1]*(3*v*v*t)+p[2]*(3*v*t*t)+p[3]*(t*t*t);
    };
    auto mixed=[&](int step,bool upper){const auto a=target(step,upper);auto b=upper?arcs.upper[step]:arcs.lower[step];b.y-=shift;return a+(b-a)*amount;};
    std::vector<Segment> result;result.reserve(2*sleepEyeArcSteps+2);
    auto add=[&](char type,Point p={}){result.push_back({type,{{p,{},{}}}});};
    add('M',mixed(0,true));for(int step=1;step<=sleepEyeArcSteps;++step)add('L',mixed(step,true));
    for(int step=sleepEyeArcSteps-1;step>=0;--step)add('L',mixed(step,false));add('Z');
    return result;
}

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
