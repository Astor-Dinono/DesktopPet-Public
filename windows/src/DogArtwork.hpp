#pragma once
#include "DogCore.hpp"
#include <cstdlib>
#include <string>

namespace dog {
// Same editable vector paths as the macOS DogRenderer. No raster pose swaps.
inline constexpr const char* headPath="M 70 284 C 57 254 65 211 88 180 C 69 180 62 165 64 146 C 66 127 68 117 83 111 C 98 105 108 103 115 99 C 136 87 154 67 170 61 C 179 55 188 54 197 58 C 208 60 218 72 228 77 C 260 65 297 60 330 61 C 374 61 410 80 433 93 C 451 83 471 80 484 84 C 497 88 504 98 516 108 C 528 118 552 126 566 141 C 580 156 578 180 570 198 C 562 216 544 226 532 210 C 536 231 541 251 543 267 L 543 284 Z";
inline constexpr const char* tailPath="M550 282 C588 248 614 230 628 199 C639 176 640 165 650 165 C661 165 671 171 677 181 C695 207 682 238 668 259 L650 282 Z";
inline constexpr const char* earsPath="M145 110 C139 145 112 180 88 180 M478 136 C486 166 518 193 532 210";
inline constexpr const char* mouthPath="M255 220 C252 242 272 237 281 225 C291 242 307 246 312 225";
// Effect paths use canonical points (y-down), matching the Mac's effect canvas.
inline constexpr const char* bubblePath="M0 0 C6 3 19 3 20 10 C21 14 18 17 13 17 C7 17 4 14 6 10 C6 6 3 3 0 0 Z";
inline constexpr const char* heartPath="M0 0 C-3 -4 -12 -7 -9 -12 C-7 -17 -1 -17 0 -12 C1 -17 7 -17 9 -12 C12 -7 3 -4 0 0 Z";

struct Segment { char type; std::array<Point,3> points{}; };
inline std::array<Segment,6> eyePath(Point center,double closed){
    // Match the ~3.04 pt lid thickness at the end of the shared yawn clip.
    double w=(5.4+closed*.9)/sourceScale,h=(5.4*(1-closed)+closed*1.52)/sourceScale,sag=closed*1.8/sourceScale,k=.55228475;
    double top=center.y-h+sag,bottom=center.y+h+sag;
    std::array<Segment,6> s{};
    s[0].type='M';s[0].points[0]={center.x-w,center.y};
    s[1].type='C';s[1].points={{{center.x-w,center.y+(top-center.y)*k},{center.x-w*k,top},{center.x,top}}};
    s[2].type='C';s[2].points={{{center.x+w*k,top},{center.x+w,center.y+(top-center.y)*k},{center.x+w,center.y}}};
    s[3].type='C';s[3].points={{{center.x+w,center.y+(bottom-center.y)*k},{center.x+w*k,bottom},{center.x,bottom}}};
    s[4].type='C';s[4].points={{{center.x-w*k,bottom},{center.x-w,center.y+(bottom-center.y)*k},{center.x-w,center.y}}};
    s[5].type='Z';return s;
}
inline std::vector<Segment> parsePath(const char* text) {
    std::vector<Segment> segments;
    auto number=[&](){while(*text==' '||*text==',')++text;char* end;double x=std::strtod(text,&end);text=end;return x;};
    while(*text) {
        if(*text==' '||*text==','){++text;continue;}
        char c=*text++;Segment s{c,{}};int n=c=='C'?3:(c=='M'||c=='L')?1:0;
        for(int i=0;i<n;++i){s.points[i].x=number();s.points[i].y=number();}
        segments.push_back(s);
    }
    return segments;
}
// Source-space shape constants; the stable rotation pivot/placement anchor
// remain in DogCore. Ear seams are filled ribbons, not stacked round caps.
inline constexpr double outlineWidth=3.6/sourceScale,mouthWidth=3.1/sourceScale;
inline constexpr Point baselineStart{30,268},baselineEnd{700,268};
inline const std::vector<Segment>& earFillSegments(){
    static const std::vector<Segment> cached=[](){
        std::vector<Segment> result;result.reserve(550);
        const std::array<std::array<Point,4>,2> curves{{
            {{{145,110},{139,145},{112,180},{88,180}}},
            {{{478,136},{486,166},{518,193},{532,210}}}
        }};
        auto add=[&](char type,Point p={}){Segment s{type,{}};s.points[0]=p;result.push_back(s);};
        for(const auto& c:curves){
            std::array<Point,129> left{},right{};
            for(int i=0;i<=128;++i){
                double t=i/128.0,u=1-t;
                Point p=c[0]*(u*u*u)+c[1]*(3*u*u*t)+c[2]*(3*u*t*t)+c[3]*(t*t*t);
                Point tangent=(c[1]-c[0])*(3*u*u)+(c[2]-c[1])*(6*u*t)+(c[3]-c[2])*(3*t*t);
                double length=std::hypot(tangent.x,tangent.y);
                Point normal{-tangent.y/length,tangent.x/length};
                double blend=clamp((t-.58)/.28);blend=blend*blend*(3-2*blend);
                double radius=(2.85+(3.6-2.85)*blend)/sourceScale/2;
                left[i]=p+normal*radius;right[i]=p-normal*radius;
            }
            add('M',left[0]);for(int i=1;i<=128;++i)add('L',left[i]);
            for(int i=128;i>=0;--i)add('L',right[i]);
            double a=std::atan2(left[0].y-c[0].y,left[0].x-c[0].x),r=2.85/sourceScale/2;
            for(int i=1;i<=16;++i){double angle=a+pi-pi*i/16;add('L',c[0]+Point{r*std::cos(angle),r*std::sin(angle)});}
            add('Z');
        }
        return result;
    }();
    return cached;
}
enum class TailSize : int { Small=80, Original=100 };
inline TailSize storedTailSize(int value) { return value==100?TailSize::Original:TailSize::Small; }
inline Point bendTail(Point p,TailPose tail,TailSize size=TailSize::Small) {
    const double tailScale=int(size)/100.0;
    double influence=std::pow(clamp((280-p.y)*sourceScale/45),2);
    p.x-=std::sin(tail.bend)*29/sourceScale*influence;p.y+=std::abs(tail.bend)*2.5/sourceScale*influence;
    return rotated((p-Point{574,280})*tailScale,-tail.angle)+Point{574,280};
}
} // namespace dog
