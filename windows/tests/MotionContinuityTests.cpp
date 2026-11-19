#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/DogCore.hpp"
#include "../src/YawnMotion.hpp"
#include "../src/PetExpression.hpp"
#include <cassert>
#include <iostream>

namespace {void near(double a,double b){assert(std::abs(a-b)<1e-10);}}
int main(){
    for(double t:{0.,.02,.08,.2,.6,.9,1.24}){
        dog::Duang duang;duang.kick(0,.75);const auto before=duang.sample(t);const double shape=duang.value(t);
        duang.settle(t);near(duang.sample(t).value,before.value);near(duang.sample(t).velocity,before.velocity);near(duang.value(t),shape);
        near(duang.value(t+1.25),0);
    }
    for(double wake:{.04,.2,1.2,4.1,4.4,5.,8.})for(double reversal:{0.,.02,.12,.23,.5,1.09}){
        dog::YawnMotion yawn;yawn.start(0);yawn.cancel(wake);
        const double t=wake+reversal;const auto before=yawn.pose(t);const double decoration=yawn.sleepDecorationAmount(t);
        yawn.resumeSleep(t);const auto after=yawn.pose(t);
        assert(bool(before)==bool(after));if(before){near(before->time,after->time);near(before->weight,after->weight);}
        near(decoration,yawn.sleepDecorationAmount(t));near(yawn.sleepDecorationAmount(t+.7),1);
        // Wake again during recovery: neither the face fade nor the decoration
        // opacity may restart, including repeated keyboard activity.
        const double amount=yawn.sleepDecorationAmount(t+.1);const auto face=yawn.pose(t+.1);
        yawn.cancel(t+.1);near(yawn.sleepDecorationAmount(t+.1),amount);
        const auto interrupted=yawn.pose(t+.1);assert(bool(face)==bool(interrupted));
        if(face){near(face->time,interrupted->time);near(face->weight,interrupted->weight);}
        yawn.cancel(t+.11);near(yawn.sleepDecorationAmount(t+.11),amount);
    }
    dog::Rest rest;dog::PetExpression expression;expression.touch(0);
    const double before=expression.value(.3);rest.setSleep(true,.3);
    near(expression.value(.3)*(1-rest.pose(.3).closed),before);
    near(expression.value(2)*(1-rest.pose(2).closed),0);
    // A completed wake still permits a full fresh yawn later.
    rest.setSleep(false,3);assert(rest.moving(3.5));assert(!rest.moving(4.11));
    dog::YawnMotion fresh;fresh.start(4.1);near(fresh.pose(4.18)->weight,.5);
    std::cout<<"PASS: drag shape/velocity continuity, 42 rapid sleep reversals, repeated wake/decorations, pleased-eye handoff and fresh nap timing\n";
}
