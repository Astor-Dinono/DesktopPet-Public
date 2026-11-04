#pragma once
#include "DogCore.hpp"

namespace dog {
// Dwell and distance for this window's hover only. No input subscription,
// history or persistence. Validation can arm a dwell but never produce a pet.
class HoverStrokeGesture {
    Point last_{};
    double entered_=0,lastTime_=0,distance_=0,lastPulse_=0;
    bool active_=false,armed_=false,pulsed_=false;
    static bool finite(Point p) noexcept{return std::isfinite(p.x)&&std::isfinite(p.y);}
    bool valid(Point p,double time,bool inside,bool blocked) noexcept{
        if(!inside||blocked||!finite(p)||!std::isfinite(time)||(active_&&time<lastTime_)){
            cancel();return false;
        }
        return true;
    }
    void arm(Point p,double time) noexcept{
        if(!armed_&&time-entered_>=dwell){armed_=true;last_=p;distance_=0;}
    }
public:
    static constexpr double dwell=.35,pulseDistance=10,pulseInterval=.12;
    void cancel() noexcept{*this=HoverStrokeGesture{};}
    bool active()const noexcept{return active_;}
    bool armed()const noexcept{return armed_;}
    void validate(Point p,double time,bool inside,bool blocked) noexcept{
        if(!valid(p,time,inside,blocked)||!active_)return;
        arm(p,time);lastTime_=time;
    }
    bool move(Point p,double time,bool inside,bool blocked) noexcept{
        if(!valid(p,time,inside,blocked))return false;
        if(!active_){active_=true;entered_=lastTime_=time;last_=p;return false;}
        lastTime_=time;
        // All pre-dwell travel, including the event that crosses the threshold,
        // is discarded. Continued gentle movement need not stay in a tiny box.
        if(!armed_){arm(p,time);last_=p;return false;}
        double step=std::hypot(p.x-last_.x,p.y-last_.y);last_=p;
        if(!std::isfinite(step)){cancel();return false;}
        if(step==0)return false;
        distance_=std::min(pulseDistance,distance_+step);
        if(distance_<pulseDistance||(pulsed_&&time-lastPulse_<pulseInterval))return false;
        distance_=0;lastPulse_=time;pulsed_=true;return true;
    }
};
} // namespace dog
