#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

// Platform-independent motion, shared by the renderer and native tests.
namespace dog {
constexpr double pi = 3.14159265358979323846;
constexpr double sourceScale = 260.0 / 749.0;
inline double clamp(double v, double lo = 0, double hi = 1) { return std::clamp(v, lo, hi); }
inline double smooth(double t) { t = clamp(t); return t*t*(3-2*t); }
struct Point { double x=0, y=0; };
inline Point operator+(Point a, Point b) { return {a.x+b.x,a.y+b.y}; }
inline Point operator-(Point a, Point b) { return {a.x-b.x,a.y-b.y}; }
inline Point operator*(Point a, double b) { return {a.x*b,a.y*b}; }
struct State { double value=0, velocity=0; };
inline State spring(State s, double target, double age, double f) {
    double d=s.value-target, c=s.velocity+f*d, decay=std::exp(-f*age);
    return {target+(d+c*age)*decay, (c-f*(d+c*age))*decay};
}
inline State fall(State s, double age, double duration, double f) {
    if (age>=duration) return {};
    auto base=spring(s,0,age,f);
    double fade=std::min(.2,duration), p=clamp((age-duration+fade)/fade);
    double w=1-smooth(p), v=p>0&&p<1 ? -6*p*(1-p)/fade : 0;
    return {base.value*w,base.velocity*w+base.value*v};
}
struct TailPose { double angle=0,bend=0; };
struct Tail {
    double started=-100,phaseStarted=0; State from; bool settling=false;
    bool moving(double now) const { return now-started<(settling?.45:1.30); }
    State energy(double now) const {
        double age=std::max(0.0,now-started);
        if(settling) return fall(from,age,.45,12);
        if(age<=.42) return spring(from,1,age,25);
        return fall(spring(from,1,.42,25),age-.42,.88,7);
    }
    void wag(double now) { auto s=energy(now); if(!moving(now))phaseStarted=now; started=now; from=s; settling=false; }
    void settle(double now) { if(moving(now)) { from=energy(now); started=now; settling=true; } }
    TailPose pose(double now,bool reduced=false) const {
        if(reduced||!moving(now))return {};
        double age=std::max(0.0,now-phaseStarted), phase=age*15.6+std::sin(age*5.5)*.28,e=energy(now).value;
        return {(std::sin(phase)+.12*std::sin(phase*2))/1.12*.21*e,std::sin(phase-.6)*.36*e};
    }
};
struct Duang {
    double started=-100,strength=0; State from;
    bool moving(double now) const { return now-started<1.25; }
    State sample(double now) const {
        double a=std::max(0.0,now-started); if(a>=1.25)return {};
        double s=std::sin(a*20),c=std::cos(a*20),decay=std::exp(-3.7*a);
        double k=(from.velocity+3.7*from.value)/20, r=from.value*c+k*s;
        double rv=20*(-from.value*s+k*c)-3.7*r,rd=std::exp(-60*a),rise=1-rd;
        double pulse=.17*strength*s*rise,pv=.17*strength*(20*c*rise+60*s*rd-3.7*s*rise);
        double v=decay*(r+pulse),vel=decay*(rv+pv),p=clamp((a-.8)/.45),w=1-smooth(p);
        return {v*w,vel*w+v*(p>0&&p<1?-6*p*(1-p)/.45:0)};
    }
    void kick(double now,double force) { from=sample(now); started=now; strength=force; }
    void cancel() { started=-100; from={}; strength=0; }
    double value(double now) const { return .20*std::tanh(sample(now).value/.20); }
};
struct RestPose { double closed=0,bubble=0,letters=0,settle=0,stretch=0,phaseAge=0; };
struct Rest {
    double started=-100; RestPose from; bool sleeping=false,active=false;
    RestPose pose(double now) const {
        if(!active)return {};
        double a=std::max(0.0,now-started);
        auto blend=[&](double v,double target,double delay,double duration){return v+(target-v)*smooth((a-delay)/duration);};
        double residual=from.stretch*(1-smooth(a/.35));
        if(sleeping)return {blend(from.closed,1,0,1.35),blend(from.bubble,1,.85,.9),blend(from.letters,1,1.45,1),blend(from.settle,1,.15,1.55),residual,from.phaseAge+a};
        double inhale=std::pow(std::sin(clamp((a-.15)/.95)*pi),2)*.014*from.settle;
        return {blend(from.closed,0,.15,.65),blend(from.bubble,0,0,.45),blend(from.letters,0,0,.35),blend(from.settle,0,.1,.95),residual+inhale,from.phaseAge+a};
    }
    void setSleep(bool value,double now) { if((!active&&!value)||(active&&sleeping==value))return; from=pose(now); sleeping=value; active=true; started=now; }
    bool moving(double now) const { return active&&now-started<(sleeping?2.45:1.1); }
};
struct Blush {
    double started=-100,from=0,target=0;
    double value(double now) const {
        double a=now-started;
        if(a<.45)return from+(target-from)*smooth(a/.45);
        return target*(1-smooth((a-2.45)/2.8));
    }
    void touch(double now) { double v=value(now); target=now-started<2.45?std::min(1.0,std::max(v,target)+.2):std::min(1.0,v+.65); from=v; started=now; }
};
inline double blink(double now,bool reduced=false) {
    double a=std::fmod(now,7.3)-5.2;
    return reduced||a<0||a>=.28?0:a<.10?smooth(a/.10):1-smooth((a-.10)/.18);
}
enum class EffectKind:unsigned { heart,flower,paw,star };
struct EffectPicker {
    std::optional<EffectKind> last;
    template<class Choose> std::optional<EffectKind> next(unsigned mask,Choose choose) {
        mask&=15;std::array<EffectKind,4> enabled{},choices{};unsigned count=0,n=0;
        for(unsigned i=0;i<4;++i)if(mask&(1u<<i))enabled[count++]=EffectKind(i);
        if(!count)return std::nullopt;
        for(unsigned i=0;i<count;++i)if(count==1||last!=enabled[i])choices[n++]=enabled[i];
        last=choices[choose(n)];return last;
    }
};
struct Heart { Point origin; double started; unsigned variant; EffectKind effect=EffectKind::heart; };
struct EffectPose { Point origin;double scale,rotation,alpha; };
inline EffectPose effectPose(Heart h,double now,bool reduced=false) {
    double age=std::max(0.0,now-h.started),progress=clamp(age/2);bool idea=h.effect==EffectKind::star;
    double pop=reduced?1:.82+.18*smooth(age/.22);
    if(idea&&!reduced)pop=age<=.13?.42+.74*smooth(age/.13):1+.16*(1-smooth((age-.13)/.19));
    constexpr double widths[]={30,29,29.5,27};
    double a=age>=2?0:smooth(age/(idea?.055:.12))*(1-smooth((age-.7)/1.3));
    double drift=reduced?0:std::sin(progress*pi)*(h.variant%2?3:-3);
    double rise=reduced?0:progress*30*(idea?smooth(age/.18):1);
    return {h.origin+Point{drift,-rise},20/widths[unsigned(h.effect)]*pop,reduced?0:std::sin(progress*pi)*.07,a};
}
struct Hearts {
    std::vector<Heart> items; unsigned serial=0;
    void expire(double now) { items.erase(std::remove_if(items.begin(),items.end(),[&](auto h){return now-h.started>=2;}),items.end()); }
    void add(Point p,double now,EffectKind effect=EffectKind::heart) { expire(now); if(items.size()==6)items.erase(items.begin()); items.push_back({p,now,serial++,effect}); }
};
struct Counts {
    bool enabled=false; std::uint64_t today=0,total=0; int date=0;
    bool roll(int newDate) { if(date==newDate)return false;date=newDate;today=0;return true; }
    void add(int newDate,unsigned n=1) {
        if(!enabled)return;
        roll(newDate); auto max=std::numeric_limits<std::uint64_t>::max();
        today=today>max-n?max:today+n;total=total>max-n?max:total+n;
    }
};
struct Fade {
    double started=-100,from=0,target=0;
    double value(double t)const{return from+(target-from)*smooth((t-started)/.15);}
    void set(double next,double t){if(next==target)return;from=value(t);target=next;started=t;}
    bool moving(double t)const{return t-started<.15;}
};
struct Bounds { double left=0,top=0,right=0,bottom=0; };
constexpr Point pivot {108/sourceScale,268-(42-3.8)/sourceScale};
inline Point rotated(Point p,double angle) {
    return {p.x*std::cos(angle)-p.y*std::sin(angle),p.x*std::sin(angle)+p.y*std::cos(angle)};
}
// Full baseline and conservative head/tail envelope, relative to the stable head pivot.
inline Bounds extent(double angle,double unit) {
    Bounds b{1e9,1e9,-1e9,-1e9};
    constexpr double cap=1.25/sourceScale;
    for(auto p:std::array<Point,4>{{{-cap,40},{749+cap,40},{-cap,268+cap},{749+cap,268+cap}}}) {
        auto q=rotated((p-pivot)*unit,angle);
        b.left=std::min(b.left,q.x);b.right=std::max(b.right,q.x);b.top=std::min(b.top,q.y);b.bottom=std::max(b.bottom,q.y);
    }
    return b;
}
inline Point fit(Point center,Bounds b,Bounds work) {
    auto axis=[](double v,double lo,double hi) {return lo<=hi?clamp(v,lo,hi):(lo+hi)/2;};
    return {axis(center.x,work.left-b.left,work.right-b.right),axis(center.y,work.top-b.top,work.bottom-b.bottom)};
}
struct TurnPose { Point center,velocity; double angle=0,angularVelocity=0; };
struct Turn {
    TurnPose from; Point to,excursion; double target=0,started=-100,duration=.52;
    bool moving(double now) const { return now-started<duration; }
    TurnPose pose(double now) const {
        double t=clamp((now-started)/duration),t2=t*t,t3=t2*t,t4=t3*t,t5=t4*t;
        double e=10*t3-15*t4+6*t5,ev=30*t2*(1-t)*(1-t);
        double carry=t-6*t3+8*t4-3*t5,cv=1-18*t2+32*t3-15*t4;
        double q=t*(1-t),h=64*q*q*q,hv=192*q*q*(1-2*t);
        return {from.center+(to-from.center)*e+from.velocity*(duration*carry)+excursion*h,
                (to-from.center)*(ev/duration)+from.velocity*cv+excursion*(hv/duration),
                from.angle+(target-from.angle)*e+from.angularVelocity*duration*carry,
                (target-from.angle)*ev/duration+from.angularVelocity*cv};
    }
    void begin(TurnPose current,double angle,double now,double unit,Bounds work) {
        from=current;target=angle;started=now;duration=std::abs(target-from.angle)>pi*.75?.65:.52;
        to=fit(from.center,extent(target,unit),work);excursion={};
        Bounds allowed{-1e9,-1e9,1e9,1e9};
        for(int i=1;i<512;++i) {
            double t=i/512.0,q=t*(1-t),h=64*q*q*q;
            auto p=pose(now+t*duration);auto b=extent(p.angle,unit);
            // A subpixel guard covers extrema between planning samples. It fades
            // with the same hump, so neither endpoint moves or changes velocity.
            allowed.left=std::max(allowed.left,(work.left-b.left-p.center.x)/h+.25);
            allowed.right=std::min(allowed.right,(work.right-b.right-p.center.x)/h-.25);
            allowed.top=std::max(allowed.top,(work.top-b.top-p.center.y)/h+.25);
            allowed.bottom=std::min(allowed.bottom,(work.bottom-b.bottom-p.center.y)/h-.25);
        }
        if(allowed.left<=allowed.right)excursion.x=clamp(0,allowed.left,allowed.right);
        if(allowed.top<=allowed.bottom)excursion.y=clamp(0,allowed.top,allowed.bottom);
    }
};
} // namespace dog
