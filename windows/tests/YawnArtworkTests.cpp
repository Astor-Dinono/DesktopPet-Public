#include "../src/YawnArtwork.hpp"
#include <cassert>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>

namespace {
bool near(double a,double b,double epsilon=1e-12){return std::abs(a-b)<epsilon;}
void pointNear(dog::Point a,dog::Point b){assert(std::hypot(a.x-b.x,a.y-b.y)<1e-10);}
template<class Transform> std::string segments(const std::vector<dog::Segment>& path,Transform transform){
    std::ostringstream out;out<<std::setprecision(14);
    for(const auto& s:path){out<<s.type;for(int i=0;i<(s.type=='C'?3:s.type=='Z'?0:1);++i){
        auto p=transform(s.points[i]);out<<p.x<<','<<p.y<<' ';}}
    return out.str();
}
template<class Transform> std::string traced(dog::yawn_data::Path path,Transform transform){
    std::ostringstream out;out<<std::setprecision(14);
    for(std::size_t i=path.offset;i<path.offset+path.count;){auto command=dog::yawn_data::commands[i++];
        if(command==2){out<<'Z';continue;}
        auto p=transform(dog::yawnTracedPoint(dog::yawn_data::commands[i],dog::yawn_data::commands[i+1]));i+=2;
        out<<(command==0?'M':'L')<<p.x<<','<<p.y<<' ';
    }return out.str();
}
void preview(const char* destination){
    std::ofstream out(destination);out<<"<svg xmlns='http://www.w3.org/2000/svg' width='1320' height='800' viewBox='0 0 1320 800'>"
        "<style>text{font:15px system-ui}path{stroke-linecap:round;stroke-linejoin:round}</style>";
    constexpr double times[]={0,.5,31.0/24,2,3.2125,3.6375,4.05,1.3};
    for(int i=0;i<16;++i){const int sample=i%8,column=sample%4,row=i/4;const bool dark=i>=8;
        const auto tailSize=sample==7?dog::TailSize::Original:dog::TailSize::Small;
        const double time=times[sample],angle=sample==6?dog::pi:sample==7?dog::pi/2:0,scale=sample>=6?.37:.42;
        const dog::Point origin{165.0+330*column,106.0+200*row};
        auto project=[&](dog::Point p){return dog::rotated((p-dog::pivot)*scale,angle)+origin;};
        auto head=[&](dog::Point p){return project(dog::recordedYawnHead(time).apply(p));};
        auto tail=[&](dog::Point p){return project(dog::blendedYawnTailPoint(p,time,1,{},tailSize));};
        out<<"<rect x='"<<330*column<<"' y='"<<200*row<<"' width='330' height='200' fill='"<<(dark?"#292b35":"#f7f8f3")<<"'/>";
        out<<"<text x='"<<330*column+15<<"' y='"<<200*row+26<<"' fill='"<<(dark?"#e4e5e9":"#4e5751")<<"'>"<<std::fixed<<std::setprecision(3)<<time<<"s";
        if(sample==6)out<<" / 180°";if(sample==7)out<<" / 90° / large tail";out<<"</text>";
        out<<"<clipPath id='c"<<i<<"'><path d='"<<segments(dog::parsePath("M-100 -1000 L850 -1000 L850 268 L-100 268 Z"),project)<<"'/></clipPath><g clip-path='url(#c"<<i<<")'>";
        for(const auto& shape:std::array<std::string,2>{{segments(dog::parsePath(dog::tailPath),tail),segments(dog::parsePath(dog::headPath),head)}})
            out<<"<path d='"<<shape<<"' fill='white' stroke='black' stroke-width='"<<dog::outlineWidth*scale<<"'/>";
        out<<"<path d='"<<segments(dog::earFillSegments(),head)<<"' fill='black'/>";
        const auto& frame=dog::yawn_data::frames[dog::yawnFrameIndex(time)];
        out<<"<path d='"<<traced(frame.face,project)<<"' fill='#090909' fill-rule='evenodd'/>";
        for(std::size_t j=0;j<frame.layerCount;++j){const auto& layer=dog::yawn_data::layers[frame.layerOffset+j];
            out<<"<path d='"<<traced(layer.path,project)<<"' fill='#"<<std::hex<<std::setw(6)<<std::setfill('0')<<layer.fill<<std::dec<<"' fill-rule='evenodd'/>";}
        out<<"</g><path d='"<<segments(dog::parsePath("M30 268 L700 268"),project)<<"' stroke='black' stroke-width='"<<2.5/dog::sourceScale*scale<<"'/>";
    }
    out<<"</svg>";
}
}

int main(int argc,char** argv){
    using namespace dog;
    static_assert(yawn_data::frames.size()==97);
    assert(near(yawn_data::duration,4.062548752834467));
    for(std::size_t i=0;i<97;++i){const double time=i/24.0;
        assert(yawnFrameIndex(time)==i);assert(yawnFrameIndex(time+.02)==i);
        if(i)assert(yawnFrameIndex(time-.000001)==i-1);
    }
    assert(yawnFrameIndex(4.05)==96&&yawnFrameIndex(100)==96&&yawnFrameIndex(-1)==0);
    assert(yawnFrameIndex(std::numeric_limits<double>::quiet_NaN())==0);
    // Independent reference JavaScript measurements also used by the macOS tests.
    constexpr double samples[][4]={{.4,-.03512683142937234,.9945832750304672,0},
        {1.3,-.1715046369687948,.9854226334133491,0},{2,-.02702736449967358,.9957181475680419,0},
        {3.2125,-.05499999999999996,1,.08775825618903717},{3.6375,.054999999999999924,1,-.08775825618903722}};
    for(const auto& sample:samples){auto pose=recordedYawnTail(sample[0]);
        assert(near(pose.angle,sample[1])&&near(pose.scale,sample[2])&&near(pose.bend,sample[3]));}
    for(double t=0;t<yawn_data::duration;t+=.001)if(t<=.25||(t>=2.25&&t<=3)||t>=3.85){
        auto p=recordedYawnTail(t);assert(near(p.angle,0)&&near(p.scale,1)&&near(p.bend,0));}
    for(double t:{.25,2.25,3.,3.85}){auto a=recordedYawnTail(t-1e-6),b=recordedYawnTail(t+1e-6);
        assert(std::abs((a.angle-b.angle)/2e-6)<.0001&&std::abs((a.bend-b.bend)/2e-6)<.0001);}
    constexpr double heads[][4]={{0,326,870,547},{.5,309,854,549},{31.0/24,284,839,550.5},{2,299,859,551.5},{4,330,870,547}};
    for(const auto& sample:heads){auto pose=recordedYawnHead(sample[0]);
        assert(near(pose.sx,sample[2]/870)&&near(pose.sy,(696-sample[1])/370));
        assert(near(pose.dx,(sample[3]-547)*749/1280));
        pointNear(pose.inverse(pose.apply({70,284})),{70,284});
        pointNear(pose.apply({305,268}),{305+pose.dx,268});
    }
    const auto head=parsePath(headPath),tail=parsePath(tailPath);
    for(double t=0;t<=yawn_data::duration;t+=.013){
        for(double weight:{0.,.2,.5,.8,1.})for(auto size:{TailSize::Small,TailSize::Original}){
            const TailPose normal{.21,.3};const auto blended=blendedYawnHead(t,weight,.95,1.08);
            for(auto s:tail)for(int i=0;i<(s.type=='C'?3:s.type=='Z'?0:1);++i){
                auto p=blendedYawnTailPoint(s.points[i],t,weight,normal,size);
                assert(std::isfinite(p.x)&&std::isfinite(p.y));
                if(weight==0)pointNear(p,bendTail(s.points[i],normal,size));
                auto small=blendedYawnTailPoint(s.points[i],t,weight,normal,TailSize::Small)-Point{574,280};
                auto large=(blendedYawnTailPoint(s.points[i],t,weight,normal,TailSize::Original)-Point{574,280})*.8;
                pointNear(small,large);
                // The full Bezier convex hull plus pen fits the existing square
                // even at arbitrary rotation, largest tail, and every handoff.
                assert(std::hypot(p.x-pivot.x,p.y-pivot.y)*sourceScale+1.8<162);
            }
            for(auto s:head)for(int i=0;i<(s.type=='C'?3:s.type=='Z'?0:1);++i){
                auto p=blended.apply(s.points[i]);assert(std::isfinite(p.x)&&std::isfinite(p.y));
                if(weight==0)pointNear(p,YawnHeadTransform{.95,1.08,0}.apply(s.points[i]));
                if(weight==1)pointNear(p,recordedYawnHead(t).apply(s.points[i]));
                assert(std::hypot(p.x-pivot.x,p.y-pivot.y)*sourceScale+1.8<162);
            }
        }
    }
    // Recorded face coordinates survive y-down/y-up conversion without drift.
    for(const auto& frame:yawn_data::frames){const auto pose=recordedYawnHead(frame.time);
        auto check=[&](yawn_data::Path path){for(std::size_t i=path.offset;i<path.offset+path.count;){
            const auto command=yawn_data::commands[i++];if(command==2)continue;
            const auto x=yawn_data::commands[i++],y=yawn_data::commands[i++];auto p=yawnTracedPoint(x,y);
            assert(near(p.x*sourceScale,x*260.0/1280,1e-10));
            assert(near((268-p.y)*sourceScale,(696-y)*260.0/1280,1e-10));
            pointNear(pose.apply(pose.inverse(p)),p);
        }};check(frame.face);
        for(std::size_t i=0;i<frame.layerCount;++i)check(yawn_data::layers[frame.layerOffset+i].path);
    }
    if(argc==3&&std::string(argv[1])=="--preview")preview(argv[2]);
    std::cout<<"PASS: 97 frame times, exact reference tail samples, recorded head/face parity, single transform handoffs, tail sizes, rotation-safe canvas bounds\n";
}
