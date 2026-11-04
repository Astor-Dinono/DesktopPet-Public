// Windows-native pipeline regression. Only synthetic RAWINPUT objects: no input
// listener is ever registered, no real keys are read, no settings are saved.
#ifdef NDEBUG
#undef NDEBUG
#endif
#define DESKTOP_PET_NATIVE_UI_TEST
#include "../src/DesktopPet.cpp"
#include <cassert>
#include <iostream>

int main(){
    App app(GetModuleHandleW(nullptr));app.visible=false;app.dirty=true;
    app.settings.counts.enabled=true;app.inputActive=true;
    auto key=[&](USHORT scan,UINT message,USHORT flags=0){
        RAWINPUT input{};input.header.dwType=RIM_TYPEKEYBOARD;
        input.data.keyboard.MakeCode=scan;input.data.keyboard.Message=message;
        input.data.keyboard.Flags=flags;input.data.keyboard.VKey=0xffff; // ignored
        app.countInput(input);
    };
    auto mouse=[&](USHORT flags){
        RAWINPUT input{};input.header.dwType=RIM_TYPEMOUSE;
        input.data.mouse.usButtonFlags=flags;
        input.data.mouse.lLastX=LONG_MAX;input.data.mouse.lLastY=LONG_MIN;
        app.countInput(input); // coordinates are ignored
    };
    key(0x11,WM_KEYDOWN);assert(app.settings.counts.total==1);
    for(unsigned i=0;i<10000;++i)key(0x11,WM_KEYDOWN);
    assert(app.settings.counts.total==1);
    key(0x1e,WM_SYSKEYDOWN);key(0x1e,WM_SYSKEYDOWN);assert(app.settings.counts.total==2);
    key(0x1e,WM_SYSKEYUP,RI_KEY_BREAK);key(0x1e,WM_SYSKEYDOWN);assert(app.settings.counts.total==3);
    key(0x11,WM_KEYUP,RI_KEY_BREAK);key(0x11,WM_KEYDOWN);assert(app.settings.counts.total==4);
    key(0x1c,WM_KEYDOWN);key(0x1c,WM_KEYDOWN,RI_KEY_E0);assert(app.settings.counts.total==6);
    key(0x1c,WM_KEYUP,RI_KEY_BREAK|RI_KEY_E0);key(0x1c,WM_KEYDOWN,RI_KEY_E0);assert(app.settings.counts.total==7);
    for(unsigned i=0;i<3;++i){mouse(RI_MOUSE_LEFT_BUTTON_DOWN);mouse(RI_MOUSE_LEFT_BUTTON_UP);}
    for(unsigned i=0;i<2;++i){mouse(RI_MOUSE_RIGHT_BUTTON_DOWN);mouse(RI_MOUSE_RIGHT_BUTTON_UP);}
    mouse(RI_MOUSE_WHEEL);mouse(0);key(0x11,WM_KEYDOWN);
    assert(app.settings.counts.total==12);
    mouse(RI_MOUSE_MIDDLE_BUTTON_DOWN|RI_MOUSE_BUTTON_4_DOWN|RI_MOUSE_BUTTON_5_DOWN);
    assert(app.settings.counts.total==15);
    // These transitions only unregister an absent listener; never subscribe.
    app.settings.counts.enabled=false;app.registerInput();
    key(0x11,WM_KEYDOWN);mouse(RI_MOUSE_LEFT_BUTTON_DOWN);assert(app.settings.counts.total==15);
    app.settings.counts.enabled=true;app.inputActive=true;key(0x11,WM_KEYDOWN);assert(app.settings.counts.total==16);
    app.locked=true;app.registerInput();key(0x30,WM_KEYDOWN);assert(app.settings.counts.total==16);
    app.locked=false;app.inputActive=true;key(0x11,WM_KEYDOWN);assert(app.settings.counts.total==17);
    app.suspended=true;app.registerInput();key(0x30,WM_KEYDOWN);assert(app.settings.counts.total==17);
    app.suspended=false;app.inputActive=true;key(0x11,WM_KEYDOWN);assert(app.settings.counts.total==18);
    key(0xff,WM_KEYDOWN);assert(app.settings.counts.total==18);
    key(0x11,WM_KEYDOWN);assert(app.settings.counts.total==19);
    key(0x30,WM_CHAR);assert(app.settings.counts.total==19);
    app.settings.counts.enabled=false;app.registerInput();
    std::cout<<"PASS: actual App raw-input pipeline with synthetic key repeats, release/repress, system messages, prefixes, mouse buttons, pause/lock/suspend and overrun; no live input or persistence\n";
}
