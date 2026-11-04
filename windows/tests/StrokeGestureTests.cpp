#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/StrokeGesture.hpp"
#include <cassert>
#include <iostream>
#include <limits>

using dog::Point;
using dog::StrokeGesture;
int main(){
    StrokeGesture g;
    assert(!g.active()&&!g.didStroke());
    assert(!g.move({20,0},1,true)&&!g.finish({0,0},true));

    // A normal click, or an arbitrarily long stationary hold, is still just
    // one click on release. Repeated move messages alone never create pulses.
    g.begin({20,30},0,true);assert(g.active());
    for(int i=1;i<=10000;++i)assert(!g.move({20,30},i*.01,true));
    assert(g.finish({20,30},true));assert(!g.active()&&!g.didStroke());
    assert(!g.finish({20,30},true));
    g.begin({0,0},0,true);
    for(int i=1;i<=10000;++i)assert(!g.move({i%2?1.0:-1.0,0},i*.01,true));
    assert(!g.didStroke()&&g.finish({0,0},true)); // jitter is not a stroke

    // Passing the drag tolerance cancels click feedback even when there was
    // not enough travel for a stroking response.
    g.begin({0,0},0,true);assert(!g.move({4,0},.1,true));
    assert(!g.didStroke());assert(!g.move({5,0},.2,true));assert(g.didStroke());
    assert(!g.finish({0,0},true));
    g.begin({0,0},0,true);assert(!g.finish({5,0},true)); // no final move message

    // Travelling back and forth counts path length, not net displacement.
    g.begin({0,0},0,true);
    assert(!g.move({6,0},.01,true));assert(g.move({1,0},.02,true));
    assert(!g.move({7,0},.05,true));assert(!g.move({1,0},.06,true));
    assert(!g.move({1,0},10,true)); // pending distance does not fire at rest
    assert(g.move({2,0},10.01,true));
    assert(!g.finish({2,0},true));

    // High-frequency input and huge jumps produce at most one response per
    // event, respect the interval, and leave no queued burst behind.
    g.begin({0,0},0,true);int pulses=0;double last=-100;
    for(int i=1;i<=10000;++i){
        double time=i*.001;
        if(g.move({i%2?100000.0:-100000.0,0},time,true)){
            assert(time-last>=StrokeGesture::pulseInterval);last=time;++pulses;
        }
    }
    assert(pulses>70&&pulses<=84);
    assert(!g.move({-100000,0},20,true));
    assert(!g.finish({-100000,0},true));

    // Only movement entirely inside the dog contributes. Crossing empty
    // space or returning from it does not create a stroke pulse or a click.
    g.begin({0,0},0,true);assert(!g.move({6,0},.1,true));
    assert(!g.move({1000,0},.2,false));assert(!g.move({2000,0},.3,false));
    assert(!g.move({0,0},.4,true));assert(!g.move({9,0},.5,true));
    assert(g.move({10,0},.6,true));assert(!g.finish({10,0},true));
    g.begin({0,0},0,true);assert(!g.move({1,0},.1,false));
    assert(!g.move({0,0},.2,true));assert(!g.finish({0,0},true));
    g.begin({0,0},0,true);assert(!g.finish({0,0},false));
    g.begin({0,0},0,false);assert(!g.active());
    assert(!g.move({20,0},1,true)&&!g.finish({20,0},true));

    // Cancellations cover capture loss/hide/suspend at the integration layer.
    // Starting a fresh press resets both the click and rate-limit state.
    g.begin({0,0},0,true);assert(g.move({10,0},.01,true));g.cancel();
    assert(!g.active()&&!g.didStroke()&&!g.move({20,0},1,true));
    assert(!g.finish({20,0},true));
    g.begin({0,0},2,true);assert(g.move({10,0},2.01,true));
    g.begin({0,0},2.02,true);assert(g.finish({0,0},true));

    // The owner divides physical coordinates by DPI. Identical logical
    // strokes at common scaling factors must produce identical decisions.
    for(double dpi:{1.0,1.25,1.5,2.0,3.0}){
        g.begin({100*dpi/dpi,20*dpi/dpi},0,true);
        assert(!g.move({106*dpi/dpi,20*dpi/dpi},.1,true));
        assert(g.move({101*dpi/dpi,20*dpi/dpi},.2,true));
        assert(!g.finish({101*dpi/dpi,20*dpi/dpi},true));
    }

    // Non-finite coordinates/times or a clock reversal cancel safely.
    double nan=std::numeric_limits<double>::quiet_NaN();
    double inf=std::numeric_limits<double>::infinity();
    for(Point bad:{Point{nan,0},Point{0,inf}}){
        g.begin(bad,0,true);assert(!g.active());
        g.begin({0,0},0,true);assert(!g.move(bad,1,true));assert(!g.active());
        g.begin({0,0},0,true);assert(!g.finish(bad,true));assert(!g.active());
    }
    for(double bad:{nan,inf}){
        g.begin({0,0},bad,true);assert(!g.active());
        g.begin({0,0},0,true);assert(!g.move({10,0},bad,true));assert(!g.active());
    }
    g.begin({0,0},10,true);assert(!g.move({10,0},9,true));assert(!g.active());
    double huge=std::numeric_limits<double>::max();
    g.begin({huge,0},0,true);assert(!g.move({-huge,0},1,true));assert(!g.active());

    static_assert(sizeof(StrokeGesture)<=96,"Gesture retains only bounded transient state");
    std::cout<<"PASS: click/hold, jitter, drag suppression, back-and-forth, rate cap, no stationary pulses, leave/reenter, cancellation, DPI and invalid input; "<<sizeof(StrokeGesture)<<" transient bytes\n";
}
