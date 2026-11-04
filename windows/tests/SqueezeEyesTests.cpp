#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/SqueezeEyes.hpp"
#include <cassert>
#include <iostream>

int main(){
    for(bool left:{false,true})for(double closed:{0.,.2,.5,.8,1.}){
        dog::Point center=left?dog::Point{200,198}:dog::Point{398,218};
        auto original=dog::eyePath(center,closed);
        auto still=dog::squeezeEye(center,left,closed,0);
        assert(still.normalAlpha==1&&still.squeezeAlpha==0);
        for(unsigned i=0;i<original.size();++i)for(unsigned j=0;j<3;++j){
            assert(still.normal[i].type==original[i].type);
            assert(still.normal[i].points[j].x==original[i].points[j].x);
            assert(still.normal[i].points[j].y==original[i].points[j].y);
        }
        auto full=dog::squeezeEye(center,left,closed,1);
        assert(full.normalAlpha==0&&full.squeezeAlpha==1);
        assert(full.squeeze[0].type=='M'&&full.squeeze[1].type=='L'&&full.squeeze[2].type=='L');
        assert((full.squeeze[1].points[0].x>center.x)==left);
        assert(full.squeeze[1].points[0].y==center.y);
        assert(full.squeeze[0].points[0].y<center.y&&full.squeeze[2].points[0].y>center.y);
        double lastNormal=1,lastSqueeze=0;
        for(int i=0;i<=1000;++i){
            auto eye=dog::squeezeEye(center,left,closed,i/1000.0);
            assert(eye.normalAlpha>=0&&eye.normalAlpha<=1&&eye.squeezeAlpha>=0&&eye.squeezeAlpha<=1);
            assert(std::abs(eye.normalAlpha+eye.squeezeAlpha-1)<1e-12);
            assert(eye.normalAlpha<=lastNormal&&eye.squeezeAlpha>=lastSqueeze);
            assert(lastNormal-eye.normalAlpha<.005&&eye.squeezeAlpha-lastSqueeze<.005);
            lastNormal=eye.normalAlpha;lastSqueeze=eye.squeezeAlpha;
        }
    }
    std::cout<<"PASS: exact normal/sleep eyes at rest, chosen B chevron direction and dimensions, continuous bounded eyelid transitions\n";
}
