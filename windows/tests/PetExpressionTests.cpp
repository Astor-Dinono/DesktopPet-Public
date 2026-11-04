#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/PetExpression.hpp"
#include <cassert>
#include <iostream>
#include <limits>

int main(){
    dog::PetExpression p;
    assert(p.value(0)==0&&!p.moving(0));
    p.touch(0);assert(p.value(0)==0&&p.moving(0));
    assert(p.value(.18)>.97&&p.value(.35)>.999);
    assert(p.value(.85)==0&&!p.moving(.85));
    // Retouch preserves value and velocity in both attack and release.
    for(double t:{.08,.3,.48,.65,.82}){
        p.clear();p.touch(0);
        double v=p.value(t),before=(v-p.value(t-1e-6))/1e-6;
        p.touch(t);
        assert(std::abs(p.value(t)-v)<1e-12);
        double after=(p.value(t+1e-6)-v)/1e-6;
        assert(std::abs(before-after)<.003);
        for(int i=0;i<=1000;++i){double a=p.value(t+i/1000.0);assert(std::isfinite(a)&&a>=0&&a<=1);}
    }
    p.clear();
    for(int i=0;i<10000;++i){double t=i*.12;p.touch(t);assert(p.value(t)>=0&&p.value(t)<=1);}
    assert(p.value(1201)==0);p.clear();assert(p.value(1201)==0&&!p.moving(1201));
    p.touch(std::numeric_limits<double>::quiet_NaN());assert(p.value(0)==0);
    // With no happy expression, retain each original path point exactly.
    for(double closed:{0.,.25,.5,.75,1.}){
        auto old=dog::eyePath({200,198},closed),same=dog::petEyePath({200,198},closed,0);
        for(unsigned i=0;i<old.size();++i){assert(old[i].type==same[i].type);for(unsigned j=0;j<3;++j){assert(old[i].points[j].x==same[i].points[j].x);assert(old[i].points[j].y==same[i].points[j].y);}}
        for(int step=0;step<=100;++step){auto path=dog::petEyePath({200,198},closed,step/100.0);assert(path.front().type=='M'&&path.back().type=='Z');for(const auto& s:path)for(auto q:s.points)assert(std::isfinite(q.x)&&std::isfinite(q.y));}
    }
    auto happy=dog::petEyePath({200,198},0,1),sleep=dog::eyePath({200,198},1);
    assert(happy[1].points[2].y<happy[3].points[2].y&&happy[3].points[2].y<198);
    assert(sleep[1].points[2].y>198);
    assert(happy[0].points[0].x==sleep[0].points[0].x);
    std::cout<<"PASS: continuous happy eye response, retouch value/velocity, hold/release, finite paths and unchanged original eyes\n";
}
