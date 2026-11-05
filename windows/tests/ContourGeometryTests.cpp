#include "../src/DogArtwork.hpp"
#include <cassert>
#include <iostream>
#include <iomanip>
#include <string>
namespace {
void dump(const char* name,const std::vector<dog::Segment>& path){
    std::cout<<'"'<<name<<"\":[";bool first=true;
    for(const auto& s:path){if(!first)std::cout<<',';first=false;std::cout<<"[\""<<s.type<<'"';
        for(int i=0;i<(s.type=='C'?3:s.type=='Z'?0:1);++i)std::cout<<','<<s.points[i].x<<','<<s.points[i].y;
        std::cout<<']';}
    std::cout<<']';
}
}
int main(int argc,char** argv){
    const auto& ears=dog::earFillSegments();assert(&ears==&dog::earFillSegments());
    assert(ears.size()==550);unsigned moves=0,closes=0;
    for(const auto& s:ears){moves+=s.type=='M';closes+=s.type=='Z';for(auto p:s.points)assert(std::isfinite(p.x)&&std::isfinite(p.y));}
    assert(moves==2&&closes==2);
    assert(dog::baselineStart.x==30&&dog::baselineEnd.x==700);
    assert(dog::baselineStart.y==268&&dog::baselineEnd.y==268);
    assert(std::abs(dog::mouthWidth*dog::sourceScale-3.1)<1e-12);
    // Tail tips keep the same 80% root-anchored relationship at moving poses.
    for(double t=0;t<2;t+=.031){dog::Tail tail;tail.wag(0);auto pose=tail.pose(t);
        for(auto s:dog::parsePath(dog::tailPath))for(int i=0;i<(s.type=='C'?3:s.type=='Z'?0:1);++i){
            auto a=dog::bendTail(s.points[i],pose,dog::TailSize::Small)-dog::Point{574,280};
            auto b=(dog::bendTail(s.points[i],pose,dog::TailSize::Original)-dog::Point{574,280})*.8;
            assert(std::hypot(a.x-b.x,a.y-b.y)<1e-10);
        }
    }
    if(argc==2&&std::string(argv[1])=="--dump"){
        std::cout<<std::setprecision(16)<<'{';dump("head",dog::parsePath(dog::headPath));std::cout<<',';
        dump("tail",dog::parsePath(dog::tailPath));std::cout<<',';dump("ears",ears);std::cout<<',';
        dump("mouth",dog::parsePath(dog::mouthPath));
        std::cout<<",\"baseline\":[[\"M\","<<dog::baselineStart.x<<','<<dog::baselineStart.y<<"],[\"L\","<<dog::baselineEnd.x<<','<<dog::baselineEnd.y<<"]]}\n";
    }else std::cout<<"PASS: cached closed ear fills, baseline limits, mouth width and moving-tail size invariance\n";
}
