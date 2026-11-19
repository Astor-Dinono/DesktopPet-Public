#pragma once
#include <algorithm>
#include <cmath>
#include <optional>

namespace dog {
// One-shot timer policy. Requests may advance a deadline, never postpone it.
// Repeated activity before that deadline shares the same timer and drawing.
struct FrameSchedule {
    static constexpr double activeInterval=1.0/60,idleInterval=1.0/30;
    double next=0,last=-100;
    std::optional<double> armed;
    void request(double t){next=std::min(next,std::max(t,last+activeInterval));}
    bool needsArm()const{return !armed||*armed!=next;}
    void arm(){armed=next;}
    void disarm(){armed.reset();}
    bool begin(double t){
        disarm();
        if(t<next)return false;
        last=t;return true;
    }
    void finish(double t,bool fast){next=t+(fast?activeInterval:idleInterval);}
};

inline bool blinkNeedsFastFrames(double t,bool reduced,bool sleeping){
    if(reduced||sleeping)return false;
    // Enter 60 Hz before the first visible eyelid movement, so an idle 30 Hz
    // frame cannot skip the beginning of the original 0.28-second blink.
    const double age=std::fmod(t,7.3)-5.2;
    return age>=-FrameSchedule::idleInterval&&age<.28;
}
}
