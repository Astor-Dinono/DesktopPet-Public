#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/FrameSchedule.hpp"
#include "../src/DogCore.hpp"
#include <cassert>
#include <cmath>
#include <iostream>

namespace {void near(double a,double b){assert(std::abs(a-b)<1e-10);}}
int main(){
    dog::FrameSchedule clock;
    assert(clock.begin(0));clock.finish(0,false);clock.arm();
    near(clock.next,1.0/30);assert(!clock.needsArm());
    clock.request(.001);near(clock.next,1.0/60);assert(clock.needsArm());clock.arm();
    for(int i=1;i<=10000;++i){clock.request(i/1000000.0);assert(!clock.needsArm());near(clock.next,1.0/60);}
    // Early or duplicated timer messages must never redraw the same interval.
    assert(!clock.begin(.001));assert(clock.needsArm());near(clock.last,0);clock.arm();
    assert(clock.begin(clock.next));const double last=clock.last;clock.finish(last,true);clock.arm();
    assert(!clock.begin(last));near(clock.last,last);
    // A late message renders the current pose once, without catch-up frames.
    assert(clock.begin(5));clock.finish(5,true);near(clock.next,5+1.0/60);
    clock.arm();clock.disarm();assert(clock.needsArm());
    clock.request(100);near(clock.next,5+1.0/60);assert(clock.begin(100));
    clock.finish(100,false);near(clock.next,100+1.0/30);

    for(int cycle=0;cycle<100;++cycle){
        const double offset=cycle*7.3;
        assert(!dog::blinkNeedsFastFrames(offset+5.15,false,false));
        assert(dog::blinkNeedsFastFrames(offset+5.18,false,false));
        for(int ms=0;ms<280;++ms){
            const double t=offset+5.2+ms/1000.0;
            assert(dog::blinkNeedsFastFrames(t,false,false));
            assert(!dog::blinkNeedsFastFrames(t,true,false));
            assert(!dog::blinkNeedsFastFrames(t,false,true));
        }
        assert(!dog::blinkNeedsFastFrames(offset+5.49,false,false));
    }
    // Complete only an invisible transition; subsequent wakes must still
    // begin at the same stable eye/decorations and preserve their phase.
    for(double time:{0.,.04,.2,1.,3.5}){
        dog::Rest rest;rest.setSleep(true,0);const auto before=rest.pose(time);
        rest.finishTransition(time);const auto asleep=rest.pose(time);
        near(asleep.closed,1);near(asleep.bubble,1);near(asleep.letters,1);
        near(asleep.settle,1);near(asleep.stretch,0);near(asleep.phaseAge,before.phaseAge);
        assert(rest.sleeping&&!rest.moving(time));near(rest.pose(time+3).phaseAge,before.phaseAge+3);
        rest.setSleep(false,time);const auto waking=rest.pose(time);
        near(waking.closed,asleep.closed);near(waking.phaseAge,asleep.phaseAge);assert(rest.moving(time));
        near(rest.pose(time+1.2).closed,0);
    }
    std::cout<<"PASS: shared deadlines, 10000 coalesced requests, early/stale/late timer messages, 60 Hz short blinks and hidden-sleep restoration\n";
}
