#pragma once
#include <bitset>
#include <cstdint>

namespace dog {
// Fixed unordered down/up bits only: no characters, VKeys, device identities,
// event sequence, timestamps, persistence, or timers. The owner explicitly
// approved temporary physical scan-code use for repeat suppression (2026-10-20).
class HeldKeys {
    std::bitset<3*128> down_;
public:
    void clear() noexcept { down_.reset(); }
    bool transition(std::uint16_t makeCode, bool e0, bool e1, bool down) noexcept {
        // 0xff signals keyboard overflow, not another user press. Discard stale
        // state because releases may have been lost. Invalid prefixes never index.
        if(makeCode==0xff){clear();return false;}
        if(makeCode>0xff||(e0&&e1))return false;
        // RAWKEYBOARD stores extension prefixes separately. Some make codes also
        // contain the break bit; normalize it as in the documented raw-input API.
        // Scan-code zero is one shared unknown-key slot, never a VKey fallback.
        const auto slot=(makeCode&0x7fu)+(e0?128u:e1?256u:0u);
        if(!down){down_.reset(slot);return false;}
        if(down_.test(slot))return false;
        down_.set(slot);return true;
    }
};
static_assert(sizeof(HeldKeys)<=64,"Repeat state must stay small and bounded");
}
