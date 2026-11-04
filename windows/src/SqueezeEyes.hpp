#pragma once
#include "PetExpression.hpp"

namespace dog {
// The sole petting expression: left > and right <, matching the chosen B draft.
// Keep the historical arc-eye helper available to old, independent design tools.
struct SqueezeEye {
    std::array<Segment,6> normal;
    std::array<Segment,3> squeeze;
    double normalAlpha=1,squeezeAlpha=0;
    double strokeWidth=1.7/sourceScale;
};
inline SqueezeEye squeezeEye(Point center,bool left,double normalClosed,double amount){
    const double a=std::isfinite(amount)?clamp(amount):0;
    SqueezeEye result;
    // Close the original eye before revealing the angled lid. Complementary
    // weights prevent a blank-eye flash during the short hand-off.
    result.normal=eyePath(center,normalClosed+(1-normalClosed)*smooth(a/.40));
    result.squeezeAlpha=smooth((a-.15)/.65);
    result.normalAlpha=1-result.squeezeAlpha;
    const double w=3.7/sourceScale,h=4.6/sourceScale,sign=left?1:-1;
    result.squeeze[0]={'M',{{{center.x-sign*w,center.y-h},{},{}}}};
    result.squeeze[1]={'L',{{{center.x+sign*w,center.y},{},{}}}};
    result.squeeze[2]={'L',{{{center.x-sign*w,center.y+h},{},{}}}};
    return result;
}
} // namespace dog
