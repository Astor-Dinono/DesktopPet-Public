#pragma once
#include <algorithm>
#include <optional>

namespace dog {
struct YawnPose { double time=0,weight=0; };

// The same one-shot clip and interruption envelope as Mac DogYawnMotion.
// Only animation state lives here; no activity history is stored.
class YawnMotion {
    struct Interruption { double started;YawnPose pose; };
    std::optional<double> started;
    std::optional<Interruption> interruption;
    enum class Decoration { followingYawn,held,recovering };
    Decoration decoration=Decoration::followingYawn;
    double decorationFrom=1,decorationStarted=0;
    static double ease(double value) {
        const double x=std::clamp(value,0.0,1.0);
        return x*x*(3-2*x);
    }
public:
    static constexpr double duration=4.062548752834467;
    static constexpr double handoff=.24;
    void start(double now) { started=now;interruption.reset();decoration=Decoration::followingYawn; }
    void cancel(double now) {
        const double amount=sleepDecorationAmount(now);
        if(!interruption)if(auto current=pose(now))interruption=Interruption{now,*current};
        started.reset();
        decoration=Decoration::held;decorationFrom=amount;
    }
    // Reversing a wake continues the current yawn handoff instead of replacing
    // its face with a brand-new first frame. Sleep decorations recover softly.
    void resumeSleep(double now) {
        decorationFrom=sleepDecorationAmount(now);decorationStarted=now;decoration=Decoration::recovering;
    }
    // Hidden/suspended views need no handoff frame. Restore ordinary sleep
    // decorations when shown again, even if the clip was hidden before them.
    void clear() { started.reset();interruption.reset();decoration=Decoration::followingYawn; }
    std::optional<YawnPose> pose(double now) const {
        if(interruption){
            const double weight=interruption->pose.weight*(1-ease((now-interruption->started)/handoff));
            if(weight>0)return YawnPose{interruption->pose.time,weight};
            return std::nullopt;
        }
        if(!started)return std::nullopt;
        const double age=std::max(0.0,now-*started);
        if(age>=duration+handoff)return std::nullopt;
        return YawnPose{std::min(age,duration),ease(age/.16)*(1-ease((age-duration)/handoff))};
    }
    bool moving(double now) const { return pose(now).has_value(); }
    double sleepDecorationAmount(double now) const {
        if(decoration==Decoration::held)return decorationFrom;
        if(decoration==Decoration::recovering)return decorationFrom+(1-decorationFrom)*ease((now-decorationStarted)/.7);
        if(!started)return 1;
        return ease((now-*started-duration)/.7);
    }
};
}
