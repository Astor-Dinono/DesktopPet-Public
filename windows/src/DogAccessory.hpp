#pragma once
#include "DogArtwork.hpp"
#include <cstdint>

namespace dog {
enum class Accessory : int { None=0, Scarf=1, Collar=2 };
inline Accessory storedAccessory(int value) {
    return value==1?Accessory::Scarf:value==2?Accessory::Collar:Accessory::None;
}

// Source-space paths (749-wide, y-down), exactly matching DogAccessory.swift.
// The model has no exposed neck; the collar is only a shallow arc and tiny
// side buckle. Neither option changes the silhouette, placement or hit region.
struct AccessoryLayer {
    std::vector<Segment> path;
    std::uint32_t fill; // ARGB; zero means no fill.
    double strokeWidth; // Source units; multiply by the existing unit().
};
inline const std::vector<AccessoryLayer>& accessoryLayers(Accessory accessory) {
    static const std::vector<AccessoryLayer> none;
    if(accessory==Accessory::None)return none;
    static const std::vector<AccessoryLayer> scarf{
        {parsePath("M124 248 C165 257 210 262 246 263 C278 265 328 265 361 263 C410 262 457 256 493 247 L493 254 C449 262 409 266 361 267 C320 268 275 268 246 267 C202 266 155 260 124 255 Z"),0xff9aafb5,1.35/sourceScale},
        {parsePath("M146 250 C160 248 178 247 191 248 C191 253 181 263 172 266 L152 260 Z"),0xff9aafb5,1.35/sourceScale},
        {parsePath("M146 252 C158 253 170 257 178 263 L160 266 C149 262 140 258 136 255 Z"),0xff9aafb5,1.35/sourceScale},
        {parsePath("M126 241 C133 239 140 241 144 245 C149 239 156 241 158 245 C161 251 154 256 146 256 L134 255 C126 255 122 248 126 241 Z"),0xff9aafb5,1.35/sourceScale}
    };
    static const std::vector<AccessoryLayer> collar{
        {parsePath("M128 252 C197 264 249 266 308 266 C380 266 438 262 490 251"),0,1.45/sourceScale},
        {parsePath("M128 248 C162 255 195 260 221 262 L220 266 C189 265 157 261 128 256 Z"),0xffd3dcd8,1.1/sourceScale},
        {parsePath("M388 262 C426 260 465 254 490 247 L490 255 C461 261 426 265 389 266 Z"),0xffd3dcd8,1.1/sourceScale},
        {parsePath("M177 257 L188 259 L186 266 L175 264 Z"),0xffffffff,1.15/sourceScale}
    };
    switch(accessory){case Accessory::Scarf:return scarf;case Accessory::Collar:return collar;default:return none;}
}

// Pure drawing dispatch: callback(path, opaqueBlackStroke, strokeWidth, fill).
// Invoke after the head/ears and before face compositing; use the existing
// headTransform and baseline clip, including the blended yawn head. Cached
// paths are built once, never during a timer or from user data.
template<class DrawLayer> inline void drawAccessory(Accessory accessory,DrawLayer&& drawLayer) {
    if(accessory==Accessory::None)return;
    for(const auto& layer:accessoryLayers(accessory))
        drawLayer(layer.path,0xff000000u,layer.strokeWidth,layer.fill);
}
} // namespace dog
