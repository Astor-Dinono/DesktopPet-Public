#include "../src/HoverStrokeGesture.hpp"
#include <cassert>
#include <iostream>
#include <limits>
int main(){
    dog::HoverStrokeGesture h;
    assert(!h.move({0,0},0,true,false));
    // Moving during dwell does not restart it or add early stroke distance.
    assert(!h.move({30,0},.1,true,false));assert(!h.move({0,0},.3,true,false));
    h.validate({0,0},.35,true,false);assert(h.armed());
    // Gentle wiggles need no >4px excursion: cumulative 10px is sufficient.
    for(int i=1;i<=4;++i)assert(!h.move({i%2?2.0:0.0,0},.35+i*.01,true,false));
    assert(h.move({2,0},.4,true,false));
    assert(!h.move({20,0},.41,true,false)); // rate limited
    h.validate({20,0},3,true,false);assert(!h.move({20,0},3.1,true,false)); // no stationary pulse
    assert(h.move({21,0},3.2,true,false)); // actual movement can release capped distance
    assert(!h.move({50,0},4,false,false));assert(!h.active());
    assert(!h.move({0,0},4.1,true,false));assert(!h.move({20,0},4.2,true,false));
    assert(!h.move({0,0},4.45,true,false)); // arms, no re-entry/early travel
    assert(h.move({10,0},4.6,true,false));
    for(bool viaValidation:{false,true}){
        h.cancel();assert(!h.move({0,0},10,true,false));h.validate({0,0},10.4,true,false);
        if(viaValidation)h.validate({0,0},10.5,true,true);else assert(!h.move({0,0},10.5,true,true));
        assert(!h.active());assert(!h.move({20,0},10.6,true,false));assert(!h.armed());
    }
    h.cancel();h.validate({0,0},50,true,false);assert(!h.active()); // timer never starts hover
    assert(!h.move({0,0},50,true,false));h.validate({0,0},50.4,true,false);
    h.validate({0,0},50.5,false,false);assert(!h.active());
    assert(!h.move({0,0},60,true,false));h.validate({0,0},59,true,false);assert(!h.active());
    assert(!h.move({0,0},60,true,false));assert(!h.move({std::numeric_limits<double>::infinity(),0},61,true,false));assert(!h.active());
    std::cout<<"PASS: 0.35s dwell while moving, pre-dwell exclusion, gentle cumulative strokes, rate limit, no stationary/timer feedback, leave/button cancellation and finite samples\n";
}
