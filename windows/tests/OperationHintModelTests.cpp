#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/OperationHintModel.hpp"
#include <cassert>
#include <iostream>

int main(){
    dog::OperationHintState state;
    auto available=[&](){return state.available(true,false,false,false,false);};
    assert(!available());state.beginSession(true);assert(available());
    for(int blocked=0;blocked<5;++blocked){
        assert(!state.available(blocked!=0,blocked==1,blocked==2,blocked==3,blocked==4));
        assert(available()); // temporary hiding never dismisses the request
    }
    state.dismiss();assert(!available());assert(!state.available(false,false,false,false,false));assert(!available());
    state.beginSession(true);assert(available());state.beginSession(false);assert(!available());
    state.openManually();assert(available());state.dismiss();assert(!available());
    state.beginSession(false);assert(!available());

    std::size_t checked=0;
    for(double scale:{.75,1.0,1.25,1.5,2.0,3.0,4.0})for(double origin:{-1920.0,0.0,1920.0}){
        dog::Bounds area{origin,-300,origin+1280*scale,-300+720*scale};
        for(bool vertical:{false,true})for(double x:{0.0,.5,1.0})for(double y:{0.0,.5,1.0}){
            double w=(vertical?60:160)*scale,h=(vertical?160:60)*scale;
            double left=area.left+x*(area.right-area.left-w),top=area.top+y*(area.bottom-area.top-h);
            dog::Bounds pet{left,top,left+w,top+h};
            dog::Bounds badge{left+w/2-20*scale,top+h+5*scale,left+w/2+20*scale,top+h+23*scale};
            if(badge.bottom>area.bottom)badge={left+w/2-20*scale,top-23*scale,left+w/2+20*scale,top-5*scale};
            auto result=dog::operationHintPlacement(pet,badge,area,scale);
            assert(result&&dog::hintFits(result->frame,area));
            assert(!dog::hintIntersects(result->frame,pet)&&!dog::hintIntersects(result->frame,badge));
            if(y==0)assert(result->side==dog::HintSide::Below);
            if(y==1)assert(result->side==dog::HintSide::Above);
            auto same=dog::operationHintPlacement(pet,badge,area,scale,result);
            assert(same&&same->frame.left==result->frame.left&&same->frame.top==result->frame.top);++checked;
        }
    }
    dog::Bounds work{0,0,1000,700},pet{400,600,560,660};
    auto placed=dog::operationHintPlacement(pet,{},work,1);assert(placed);
    auto breathe=dog::operationHintPlacement({399,599,561,660},{},work,1,placed);
    assert(breathe&&breathe->frame.top==placed->frame.top&&breathe->frame.left==placed->frame.left);
    assert(!dog::operationHintPlacement({0,0,100,100},{},{0,0,100,100},1));
    assert(!dog::operationHintPlacement(pet,{},work,0));
    assert(!dog::operationHintPlacement({0,0,std::numeric_limits<double>::infinity(),10},{},work,1));
    // Narrow fractional work areas must not feed reversed bounds to std::clamp.
    for(int i=0;i<1000;++i){
        auto small=dog::operationHintPlacement({0,200,20,220},{},{.1,0,191.0+i*.01,500},1);
        if(small)assert(dog::hintFits(small->frame,{.1,0,191.0+i*.01,500}));
    }
    std::cout<<"PASS: hint session/opt-out semantics and "<<checked<<" edge/DPI/negative-origin placements, collisions, stable breathing and insufficient space\n";
}
