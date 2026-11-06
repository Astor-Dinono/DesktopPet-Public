#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/YawnMotion.hpp"
#include <cassert>
#include <cmath>
#include <iostream>

namespace {
void near(double a,double b) { assert(std::abs(a-b)<1e-12); }
}
int main(){
    dog::YawnMotion yawn;
    assert(!yawn.pose(0)&&!yawn.moving(0));near(yawn.sleepDecorationAmount(0),1);
    yawn.start(1);
    assert(yawn.pose(1));near(yawn.pose(1)->time,0);near(yawn.pose(1)->weight,0);
    near(yawn.pose(1.08)->weight,.5);near(yawn.pose(1.16)->weight,1);
    near(yawn.pose(4.4)->time,3.4);near(yawn.sleepDecorationAmount(4.4),0);
    const double end=1+dog::YawnMotion::duration;
    near(yawn.pose(end)->time,dog::YawnMotion::duration);near(yawn.pose(end)->weight,1);
    near(yawn.pose(end+.12)->weight,.5);near(yawn.sleepDecorationAmount(end),0);
    assert(!yawn.pose(end+.25));near(yawn.sleepDecorationAmount(end+.35),.5);
    near(yawn.sleepDecorationAmount(end+.7),1);assert(!yawn.moving(end+.8));
    // A late frame advances directly to sleep; it never restarts the clip.
    assert(!yawn.pose(100));near(yawn.sleepDecorationAmount(100),1);

    // Interruptions retain the displayed frame and decoration level exactly.
    // Retouching throughout the handoff must not reset its original fade.
    for(double age:{0.,.04,.08,.16,1.2,4.1,4.2}){
        yawn.start(10);
        const double time=10+age;
        const auto before=*yawn.pose(time);
        const double decoration=yawn.sleepDecorationAmount(time);
        yawn.cancel(time);
        if(before.weight>0){
            assert(yawn.pose(time));near(yawn.pose(time)->time,before.time);
            near(yawn.pose(time)->weight,before.weight);
        }else assert(!yawn.pose(time));
        near(yawn.sleepDecorationAmount(time),decoration);
        for(double dt:{.04,.08,.12,.2,.3}){
            auto fading=yawn.pose(time+dt);
            yawn.cancel(time+dt);
            auto repeated=yawn.pose(time+dt);
            assert(bool(fading)==bool(repeated));
            if(fading){near(repeated->time,before.time);near(repeated->weight,fading->weight);assert(repeated->weight<=before.weight);}
            near(yawn.sleepDecorationAmount(time+dt),decoration);
        }
        assert(!yawn.pose(time+.3));
    }

    // Once the clip is complete, waking cannot revive an old frame.
    yawn.start(0);yawn.cancel(10);assert(!yawn.pose(10));near(yawn.sleepDecorationAmount(10),1);
    // Lifecycle cancellation ends both the frame and a suppressed decoration.
    yawn.start(0);yawn.cancel(1);near(yawn.sleepDecorationAmount(2),0);
    yawn.clear();assert(!yawn.pose(2));near(yawn.sleepDecorationAmount(2),1);
    yawn.start(3);near(yawn.pose(4)->time,1);near(yawn.pose(4)->weight,1);
    // A fresh nap after an interrupted one owns a new, complete timeline.
    yawn.cancel(4);yawn.start(5);near(yawn.pose(5.08)->weight,.5);
    near(yawn.sleepDecorationAmount(6),0);
    for(int frame=0;frame<=1200;++frame){
        const double time=5+frame/120.0;
        if(auto pose=yawn.pose(time)){
            assert(std::isfinite(pose->time)&&pose->time>=0&&pose->time<=dog::YawnMotion::duration);
            assert(std::isfinite(pose->weight)&&pose->weight>=0&&pose->weight<=1);
        }
        const double decoration=yawn.sleepDecorationAmount(time);
        assert(std::isfinite(decoration)&&decoration>=0&&decoration<=1);
    }
    std::cout<<"PASS: Mac yawn timing, smooth entry/exit, decoration delay, frozen interruption frame, repeated activity, lifecycle clear and replay boundaries\n";
}
