#include "../src/DogArtwork.hpp"
#include "../src/InstallPlan.hpp"
#include "../src/InteractionEffectArtwork.hpp"
#include <cassert>
#include <iostream>

static void close(double a,double b,double tolerance=1e-8){assert(std::abs(a-b)<tolerance);}
static void restEqual(dog::RestPose a,dog::RestPose b){close(a.closed,b.closed);close(a.bubble,b.bubble);close(a.letters,b.letters);close(a.settle,b.settle);close(a.stretch,b.stretch);}
int main(){
    for(unsigned mask=0;mask<16;++mask){dog::EffectPicker picker;std::optional<dog::EffectKind> previous;unsigned enabled=0;for(unsigned i=0;i<4;++i)enabled+=(mask>>i)&1;
        for(unsigned i=0;i<200;++i){auto effect=picker.next(mask,[&](unsigned n){return i%n;});assert(bool(effect)==bool(enabled));if(effect){assert(mask&(1u<<unsigned(*effect)));if(enabled>1)assert(effect!=previous);previous=effect;}}
    }
    dog::EffectPicker off;assert(!off.next(0,[](unsigned){assert(false);return 0u;}));
    for(unsigned kind=0;kind<4;++kind){dog::Heart effect{{4,5},0,0,dog::EffectKind(kind)};
        for(unsigned i=0;i<240;++i){double t=i/120.0;auto pose=dog::effectPose(effect,t),still=dog::effectPose(effect,t,true);assert(pose.scale>=0&&pose.scale<=1&&pose.alpha>=0&&pose.alpha<=1);assert(pose.origin.x>=1&&pose.origin.x<=7&&pose.origin.y>=-25&&pose.origin.y<=5);close(still.origin.x,4);close(still.origin.y,5);close(still.rotation,0);}
        close(dog::effectPose(effect,2).alpha,0);
        for(const auto& shape:dog::effectArtwork()[kind]){assert(!shape.path.empty());for(auto s:shape.path)for(auto p:s.points)assert(std::isfinite(p.x)&&std::isfinite(p.y));}
    }
    dog::Duang body;
    body.kick(0,1);
    for(double t=.02;t<1;t+=.027){auto before=body.sample(t);body.kick(t,.75);auto after=body.sample(t);close(before.value,after.value);close(before.velocity,after.velocity);assert(std::abs(body.value(t))<.2);}
    close(body.value(5),0);body.cancel();close(body.value(6),0);

    dog::Tail tail;tail.wag(0);
    for(double t=.01;t<1;t+=.031){auto a=tail.energy(t);auto p=tail.pose(t);tail.wag(t);auto b=tail.energy(t);auto q=tail.pose(t);close(a.value,b.value);close(a.velocity,b.velocity);close(p.angle,q.angle);close(p.bend,q.bend);}
    auto before=tail.energy(1);tail.settle(1);auto after=tail.energy(1);close(before.value,after.value);close(before.velocity,after.velocity);close(tail.pose(3).angle,0);assert(!tail.moving(3));close(tail.pose(1,true).angle,0);

    dog::Rest rest;rest.setSleep(true,0);
    assert(rest.pose(.5).closed>0&&rest.pose(.5).bubble==0);
    auto sleepy=rest.pose(3);close(sleepy.closed,1);close(sleepy.bubble,1);close(sleepy.letters,1);
    for(int i=0;i<20;++i){double t=3+i*.13;auto a=rest.pose(t);rest.setSleep(!rest.sleeping,t);restEqual(a,rest.pose(t));}
    rest.setSleep(false,7);auto awake=rest.pose(9);close(awake.closed,0);close(awake.bubble,0);close(awake.settle,0);
    rest.setSleep(false,10);close(rest.started,7); // input does not restart the waking sequence

    dog::Blush blush;blush.touch(0);assert(blush.value(.4)>0);double v=blush.value(1);blush.touch(1);close(blush.value(1),v);assert(blush.value(2)>.65);close(blush.value(8),0);
    dog::Hearts hearts;for(int i=0;i<100;++i)hearts.add({1,2},i*.001);assert(hearts.items.size()==6);hearts.expire(3);assert(hearts.items.empty());

    dog::Counts counts;assert(!counts.enabled);counts.add(20261018);assert(counts.total==0);counts.enabled=true;counts.add(20261018,2);counts.add(20261019,3);assert(counts.today==3&&counts.total==5);counts.total=UINT64_MAX;counts.add(20261019);assert(counts.total==UINT64_MAX&&counts.today==4);

    dog::Bounds work{0,0,1920,1040};double unit=dog::sourceScale*.62;
    dog::Turn turn;
    for(int orientation=0;orientation<4;++orientation){
        double angle=orientation*dog::pi/2;
        auto b=dog::extent(angle,unit);auto center=dog::fit({800,2000},b,work);
        turn.begin({center,{},angle,0},angle+dog::pi/2,0,unit,work);
        for(int i=0;i<=1000;++i){auto p=turn.pose(turn.duration*i/1000);auto e=dog::extent(p.angle,unit);assert(p.center.x+e.left>=work.left-1e-6&&p.center.x+e.right<=work.right+1e-6);assert(p.center.y+e.top>=work.top-1e-6&&p.center.y+e.bottom<=work.bottom+1e-6);}
        auto a=turn.pose(.2);turn.begin(a,angle+dog::pi, .2,unit,work);auto c=turn.pose(.2);close(a.angle,c.angle);close(a.angularVelocity,c.angularVelocity);close(a.center.x,c.center.x);close(a.velocity.y,c.velocity.y);
    }
    // Check corners as well as straight edges at common sizes/scales, including
    // a redirected turn carrying nonzero angular and translation velocity.
    for(double size:{.5,.62,.75})for(double dpi:{1.0,1.25,1.5,2.0})for(int o=0;o<4;++o)for(auto corner:std::array<dog::Point,4>{{{0,0},{1920,0},{0,1040},{1920,1040}}}){
        double u=dog::sourceScale*size*dpi,a=o*dog::pi/2;
        auto p=dog::fit(corner,dog::extent(a,u),work);
        dog::Turn motion;motion.begin({p,{},a,0},a+dog::pi/2,0,u,work);
        for(int repeat=0;repeat<2;++repeat){
            double start=repeat?.2:0;
            if(repeat)motion.begin(motion.pose(start),a+dog::pi,start,u,work);
            for(int i=0;i<=1000;++i){auto pose=motion.pose(start+motion.duration*i/1000);auto e=dog::extent(pose.angle,u);assert(pose.center.x+e.left>=work.left-1e-5&&pose.center.x+e.right<=work.right+1e-5);assert(pose.center.y+e.top>=work.top-1e-5&&pose.center.y+e.bottom<=work.bottom+1e-5);}
        }
    }
    for(auto path:{dog::headPath,dog::tailPath,dog::earsPath,dog::mouthPath,dog::bubblePath,dog::heartPath}){
        auto p=dog::parsePath(path);assert(!p.empty()&&p.front().type=='M');for(auto s:p)for(auto point:s.points)assert(std::isfinite(point.x)&&std::isfinite(point.y));
    }
    for(int value:{0,-1,80,99,101})assert(dog::storedTailSize(value)==dog::TailSize::Small);
    assert(dog::storedTailSize(100)==dog::TailSize::Original);
    for(auto size:{dog::TailSize::Small,dog::TailSize::Original}){
        close(dog::bendTail({574,280},{.2,.3},size).x,574);close(dog::bendTail({574,280},{.2,.3},size).y,280);
    }
    for(double t=0;t<1.4;t+=.01){
        auto pose=tail.pose(t);
        auto small=dog::bendTail({677,181},pose,dog::TailSize::Small),original=dog::bendTail({677,181},pose,dog::TailSize::Original);
        close(small.x-574,(original.x-574)*.8);close(small.y-280,(original.y-280)*.8);
    }
    using dog::InstallDecision;
    using dog::checkInstallVersion;
    const auto exe12 = dog::parseVersion(L"0.1.0.12");
    const auto exe14 = dog::parseVersion(L"0.1.0.14");
    assert(checkInstallVersion(false,L"",std::nullopt,L"0.1.0.13")==InstallDecision::Proceed);
    assert(checkInstallVersion(true,L"0.1.0.9",std::nullopt,L"0.1.0.13")==InstallDecision::Proceed);
    assert(checkInstallVersion(true,L"0.1.0.12",exe12,L"0.1.0.12")==InstallDecision::Proceed);
    assert(checkInstallVersion(true,L"\uFEFF0.1.0.12\r\n",exe12,L"0.1.0.13")==InstallDecision::Proceed);
    assert(checkInstallVersion(true,L"",exe12,L"0.1.0.13")==InstallDecision::Proceed);
    assert(checkInstallVersion(true,L"0.1.0.12",exe14,L"0.1.0.13")==InstallDecision::NewerInstalled);
    assert(checkInstallVersion(true,L"0.1.0.14",exe12,L"0.1.0.13")==InstallDecision::NewerInstalled);
    assert(checkInstallVersion(true,L"",std::nullopt,L"0.1.0.13")==InstallDecision::UnknownInstalledVersion);
    assert(checkInstallVersion(true,L"damaged",std::nullopt,L"0.1.0.13")==InstallDecision::UnknownInstalledVersion);
    assert(checkInstallVersion(false,L"",std::nullopt,L"invalid")==InstallDecision::InvalidTargetVersion);
    for(auto invalid:{L"../0.1.0.2",L"0.1.0.2/",L"0.1.0.-2",L"0.1.0.2.3",L"0.1.0",L"0.1.00.2",L"0.1.0.9999999999999",L"0.1.0.2\r\n"})assert(!dog::parseVersion(invalid));
    dog::Fade fade;fade.set(1,0);double shown=fade.value(.05);fade.set(0,.05);close(fade.value(.05),shown);close(fade.value(.3),0);
    std::cout<<"PASS: continuity, interrupted sleep/turns, screen bounds, bounded effects, privacy-default counts, rollover, overflow, vector paths\n";
}
