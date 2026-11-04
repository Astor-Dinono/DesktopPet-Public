#pragma once
#include <windows.h>

namespace dog {
// Only the dog's own window is changed, and only after an explicit selection.
inline void passiveWindow(HWND window,bool passive) {
    auto style=GetWindowLongPtrW(window,GWL_EXSTYLE);
    auto wanted=passive?(style|WS_EX_NOACTIVATE):(style&~LONG_PTR(WS_EX_NOACTIVATE));
    if(style==wanted)return;
    SetWindowLongPtrW(window,GWL_EXSTYLE,wanted);
    SetWindowPos(window,nullptr,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED);
}
inline bool focusForRotation(HWND window) {
    passiveWindow(window,false);
    SetForegroundWindow(window);
    SetActiveWindow(window);
    SetFocus(window);
    bool focused=GetFocus()==window;
    if(!focused)passiveWindow(window,true);
    return focused;
}
} // namespace dog
