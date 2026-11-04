#pragma once
#include "DogCore.hpp"
#include <cstdlib>
#include <string>

namespace dog {
// Same editable vector paths as the macOS DogRenderer. No raster pose swaps.
inline constexpr const char* headPath="M70 284 C57 254 65 211 88 180 C68 174 62 163 64 150 C58 132 62 121 81 112 C91 103 102 102 115 99 C135 87 155 63 170 61 C181 53 185 53 197 58 C208 60 218 72 228 77 C260 64 297 60 330 61 C374 61 410 80 433 93 C451 81 472 78 484 84 C500 87 505 98 516 108 C534 124 555 130 566 141 C575 147 578 152 578 163 C578 175 578 184 573 195 C568 213 563 218 557 219 C545 225 536 219 532 210 C536 231 541 251 543 267 L543 284 Z";
inline constexpr const char* tailPath="M550 282 C588 248 614 230 628 199 C641 168 640 161 649 165 C659 158 671 167 677 181 C695 207 682 238 668 259 L650 282 Z";
inline constexpr const char* earsPath="M145 110 C139 145 113 188 88 180 M478 136 C484 160 499 180 518 191 C522 198 525 205 532 210";
inline constexpr const char* mouthPath="M255 220 C252 242 272 237 281 225 C291 242 307 246 312 225";
// Effect paths use canonical points (y-down), matching the Mac's effect canvas.
inline constexpr const char* bubblePath="M0 0 C6 3 19 3 20 10 C21 14 18 17 13 17 C7 17 4 14 6 10 C6 6 3 3 0 0 Z";
inline constexpr const char* heartPath="M0 0 C-3 -4 -12 -7 -9 -12 C-7 -17 -1 -17 0 -12 C1 -17 7 -17 9 -12 C12 -7 3 -4 0 0 Z";

struct Segment { char type; std::array<Point,3> points{}; };
inline std::array<Segment,6> eyePath(Point center,double closed){
    double w=(5.4+closed*.9)/sourceScale,h=(5.4*(1-closed)+closed*.65)/sourceScale,sag=closed*1.8/sourceScale,k=.55228475;
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
enum class TailSize : int { Small=80, Original=100 };
inline TailSize storedTailSize(int value) { return value==100?TailSize::Original:TailSize::Small; }
inline Point bendTail(Point p,TailPose tail,TailSize size=TailSize::Small) {
    const double tailScale=int(size)/100.0;
    double influence=std::pow(clamp((280-p.y)*sourceScale/45),2);
    p.x-=std::sin(tail.bend)*29/sourceScale*influence;p.y+=std::abs(tail.bend)*2.5/sourceScale*influence;
    return rotated((p-Point{574,280})*tailScale,-tail.angle)+Point{574,280};
}
} // namespace dog
