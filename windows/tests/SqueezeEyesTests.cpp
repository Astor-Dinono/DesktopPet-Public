#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/SqueezeEyes.hpp"
#include <cassert>
#include <iostream>

namespace {
double cross(dog::Point a,dog::Point b,dog::Point c){return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);}
void checkContour(const std::vector<dog::Segment>& outline,bool left,double closed,double amount){
    assert(outline.size()==dog::squeezeMorphSteps+1);assert(outline.front().type=='M'&&outline.back().type=='Z');
    const std::size_t count=outline.size()-1;double area=0;
    for(std::size_t i=0;i<count;++i){const auto a=outline[i].points[0],b=outline[(i+1)%count].points[0];
        assert(std::isfinite(a.x)&&std::isfinite(a.y));area+=a.x*b.y-b.x*a.y;
        for(std::size_t j=i+2;j<count;++j){if(i==0&&j+1==count)continue;
            const auto c=outline[j].points[0],d=outline[(j+1)%count].points[0];
            const bool crossed=cross(a,b,c)*cross(a,b,d)<-1e-10&&cross(c,d,a)*cross(c,d,b)<-1e-10;
            if(crossed)std::cerr<<"crossing left="<<left<<" closed="<<closed<<" amount="<<amount<<" edges="<<i<<","<<j<<"\n";
            assert(!crossed);
        }
    }
    assert(area<0);
}
}

int main(){
    for(bool left:{false,true})for(double closed:{0.,.2,.5,.8,1.}){
        dog::Point center=left?dog::Point{200,198}:dog::Point{398,218};
        auto original=dog::eyePath(center,closed);
        auto still=dog::squeezeEye(center,left,closed,0);
        assert(still.normalAlpha==1&&still.squeezeAlpha==0&&still.outline.empty());
        for(unsigned i=0;i<original.size();++i)for(unsigned j=0;j<3;++j){
            assert(still.normal[i].type==original[i].type);
            assert(still.normal[i].points[j].x==original[i].points[j].x);
            assert(still.normal[i].points[j].y==original[i].points[j].y);
        }
        auto full=dog::squeezeEye(center,left,closed,1);
        assert(full.normalAlpha==0&&full.squeezeAlpha==1&&full.outline.empty());
        assert(full.squeeze[0].type=='M'&&full.squeeze[1].type=='L'&&full.squeeze[2].type=='L');
        assert((full.squeeze[1].points[0].x>center.x)==left);
        assert(full.squeeze[1].points[0].y==center.y);
        assert(full.squeeze[0].points[0].y<center.y&&full.squeeze[2].points[0].y>center.y);
        for(int i=1;i<100;++i){
            auto eye=dog::squeezeEye(center,left,closed,i/100.0);
            // Intermediate frames fill exactly one outline at full opacity;
            // neither historical eye layer contributes a translucent ghost.
            assert(eye.normalAlpha==0&&eye.squeezeAlpha==0);checkContour(eye.outline,left,closed,i/100.0);
        }
    }
    for(bool left:{false,true}){const double sign=left?1:-1;const dog::Point apex{sign*3.7,0};
        auto distance=[](dog::Point p,dog::Point a,dog::Point b){const auto d=b-a,q=p-a;
            const double t=dog::clamp((q.x*d.x+q.y*d.y)/(d.x*d.x+d.y*d.y));const auto e=q-d*t;return std::hypot(e.x,e.y);};
        for(auto p:dog::squeezeMorphBoundary(left)){p=p*dog::sourceScale;
            // The near-full contour lies on the original two round-capped
            // strokes, so the exact endpoint cannot change thickness or size.
            assert(std::abs(std::min(distance(p,apex,{-sign*3.7,-4.6}),distance(p,apex,{-sign*3.7,4.6}))-.85)<1e-8);
        }
    }
    // Fine sampling where the closed-eye crescent cusp used to form a loop.
    for(bool left:{false,true})for(int blink=900;blink<=1000;blink+=5)for(int frame=1;frame<100;++frame){
        const double closed=blink/1000.,amount=frame/1000.;
        checkContour(dog::squeezeMorphPath({0,0},left,closed,amount),left,closed,amount);
    }
    std::cout<<"PASS: exact normal and B chevron endpoints, 5,148 single opaque non-crossing transition contours, sampled boundary matches original rounded stroke\n";
}
