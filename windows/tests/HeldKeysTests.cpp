#include "../src/HeldKeys.hpp"
#include "../src/DogCore.hpp"
#include <cassert>
#include <iostream>

int main(){
    dog::HeldKeys keys;dog::Counts counts;counts.enabled=true;
    auto event=[&](unsigned scan,bool down,bool e0=false,bool e1=false){
        bool fresh=keys.transition(std::uint16_t(scan),e0,e1,down);
        if(fresh)counts.add(20261020);
        return fresh;
    };
    // The first physical press counts once, however long the repeat stream.
    assert(event(0x1e,true));
    for(unsigned i=0;i<10000;++i)assert(!event(0x1e,true));
    assert(counts.total==1);assert(!event(0x1e,false));
    assert(event(0x1e,true));assert(!event(0x1e,false));assert(counts.total==2);

    // Fast release/press cycles are not time-debounced or rate-limited.
    for(unsigned i=0;i<1000;++i){assert(event(0x1e,true));assert(!event(0x1e,false));}
    assert(counts.total==1002);
    // Holding one key must not suppress another key, including modifiers.
    keys.clear();assert(event(0x11,true));assert(event(0x1e,true));
    assert(!event(0x11,true));assert(event(0x2a,true));assert(!event(0x1e,false));
    assert(event(0x1e,true));assert(!event(0x11,true));
    assert(!event(0x2a,false));assert(!event(0x1e,false));assert(!event(0x11,false));

    // Same base code, distinct physical extensions (e.g. main/keypad Enter).
    assert(event(0x1c,true));assert(event(0x1c,true,true));assert(event(0x1c,true,false,true));
    assert(!event(0x1c,false,true));assert(!event(0x1c,true));assert(event(0x1c,true,true));
    assert(!event(0x1c,true,false,true));keys.clear();
    assert(event(0x1c,true));assert(event(0x1c,true,true));keys.clear();

    // Clear on pause/lock/suspend/exit, including multiple held keys. A new
    // listening interval starts without inheriting the old down bits.
    for(unsigned i=0;i<6;++i){
        assert(event(0x1e,true));assert(event(0x30,true));keys.clear();
        assert(!event(0x1e,false));assert(event(0x30,true));keys.clear();
    }
    // Ordinary and prefixed unknown codes share only their own unknown slot;
    // do not silently derive virtual-key or character identities.
    assert(event(0,true));assert(!event(0,true));assert(event(0,true,true));
    assert(!event(0,false));assert(event(0,true));keys.clear();
    // Overrun isn't a press and flushes possibly stale state. Invalid records
    // do not mutate valid held keys or count as fresh presses.
    assert(event(0x1e,true));assert(!event(0x100,true));assert(!event(0xffff,true));
    assert(!event(0x1e,true,true,true));assert(!event(0x1e,true));
    assert(!event(0xff,true));assert(event(0x1e,true));keys.clear();
    assert(event(0x1e,true));assert(!event(0x9e,false));assert(event(0x1e,true));keys.clear();

    // Mouse clicks continue to add while a keyboard key remains held; keyboard
    // repeats do not affect the same existing aggregate or its daily rollover.
    dog::Counts mixed;mixed.enabled=true;
    if(keys.transition(0x11,false,false,true))mixed.add(20261020);
    for(unsigned i=0;i<5;++i)mixed.add(20261020); // 3 left + 2 right presses
    assert(!keys.transition(0x11,false,false,true));assert(mixed.total==6);
    mixed.roll(20261021);assert(mixed.today==0&&mixed.total==6);
    assert(!keys.transition(0x11,false,false,false));
    if(keys.transition(0x11,false,false,true))mixed.add(20261021);
    assert(mixed.today==1&&mixed.total==7);
    keys.clear();mixed.enabled=false;
    if(keys.transition(0x11,false,false,true))mixed.add(20261021);
    assert(mixed.total==7);keys.clear();
    mixed.enabled=true;
    if(keys.transition(0x11,false,false,true))mixed.add(20261021);
    assert(mixed.total==8);
    std::cout<<"PASS: long holds, rapid represses, chords, prefixes, clear/restart, unknown codes, overflow, invalid records, mixed counts and rollover; state "<<sizeof(dog::HeldKeys)<<" bytes\n";
}
