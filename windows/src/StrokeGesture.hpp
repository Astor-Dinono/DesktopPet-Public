#pragma once
#include "DogCore.hpp"

namespace dog {
// Local, captured pointer gesture only. Coordinates are logical pixels supplied
// by the owning window; no global listener, timer, history, or persistence.
class StrokeGesture {
    Point origin_{},last_{};
    double distance_=0,lastTime_=0,lastPulse_=0;
    bool active_=false,inside_=false,stroked_=false,pulsed_=false,clickEligible_=false;
    static bool finite(Point p) noexcept { return std::isfinite(p.x)&&std::isfinite(p.y); }
public:
    static constexpr double dragThreshold=4.0;
    static constexpr double pulseDistance=10.0;
    static constexpr double pulseInterval=.12;

    void cancel() noexcept { *this=StrokeGesture{}; }
    bool active() const noexcept { return active_; }
    // True after moving outside the initial click tolerance, even if movement
    // was too brief to produce a pulse. Release must not add a second click.
    bool didStroke() const noexcept { return stroked_; }

    void begin(Point point,double time,bool inside) noexcept {
        cancel();
        if(!inside||!finite(point)||!std::isfinite(time))return;
        origin_=last_=point;lastTime_=time;
        active_=inside_=clickEligible_=true;
    }

    bool move(Point point,double time,bool inside) noexcept {
        if(!active_)return false;
        if(!finite(point)||!std::isfinite(time)||time<lastTime_){cancel();return false;}
        double step=std::hypot(point.x-last_.x,point.y-last_.y);
        double excursion=std::hypot(point.x-origin_.x,point.y-origin_.y);
        if(!std::isfinite(step)||!std::isfinite(excursion)){cancel();return false;}
        bool wasStroke=stroked_;
        if(excursion>dragThreshold)stroked_=true;
        last_=point;lastTime_=time;
        // Captured motion can be over transparent pixels or another app. Drop
        // that distance and the return segment; neither may trigger a pet.
        if(!inside){inside_=false;clickEligible_=false;distance_=0;return false;}
        if(!inside_){inside_=true;distance_=0;return false;}
        if(step==0||!stroked_)return false;
        // Do not collect jitter inside the click tolerance. Once accepted,
        // count travelled distance, so back-and-forth strokes work naturally.
        distance_=std::min(pulseDistance,wasStroke?distance_+step:excursion);
        if(distance_<pulseDistance||(pulsed_&&time-lastPulse_<pulseInterval))return false;
        distance_=0;lastPulse_=time;pulsed_=true;
        return true;
    }

    // Reports one ordinary click only; callers may reuse their existing click
    // feedback. A drag, an out-of-shape release, or cancellation produces none.
    bool finish(Point point,bool inside) noexcept {
        bool click=active_&&clickEligible_&&inside&&finite(point)&&!stroked_
            &&std::hypot(point.x-origin_.x,point.y-origin_.y)<=dragThreshold;
        cancel();
        return click;
    }
};
} // namespace dog
