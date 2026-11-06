#pragma once
#include "YawnArtwork.hpp"
#include <gdiplus.h>
#include <memory>

namespace dog {
// All recorded faces are native, immutable GDI+ paths. The two small buffers are
// reused only during handoffs, so overlapping face features add their weighted
// premultiplied colors once, just like the Mac's isolated plus-lighter group.
// Head, ears and tail stay outside these layers and remain one opaque shape.
class YawnDrawing {
    struct Layer {std::uint32_t fill;std::unique_ptr<Gdiplus::GraphicsPath> path;};
    struct Frame {std::unique_ptr<Gdiplus::GraphicsPath> face;std::vector<Layer> layers;};
    std::array<Frame,yawn_data::frames.size()> frames;
    struct FaceBuffer {
        int side=0;std::vector<std::uint32_t> pixels;
        std::unique_ptr<Gdiplus::Bitmap> bitmap;
        std::unique_ptr<Gdiplus::Graphics> graphics;
        bool resize(int value) {
            if(side==value&&graphics)return true;
            graphics.reset();bitmap.reset();side=0;
            pixels.assign(std::size_t(value)*value,0);
            bitmap=std::make_unique<Gdiplus::Bitmap>(value,value,value*4,PixelFormat32bppPARGB,
                reinterpret_cast<BYTE*>(pixels.data()));
            if(bitmap->GetLastStatus()!=Gdiplus::Ok)return false;
            graphics=std::make_unique<Gdiplus::Graphics>(bitmap.get());
            if(graphics->GetLastStatus()!=Gdiplus::Ok)return false;
            graphics->SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
            graphics->SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
            graphics->SetCompositingQuality(Gdiplus::CompositingQualityHighQuality);
            side=value;return true;
        }
        void clear(const Gdiplus::GraphicsPath& clip) {
            graphics->ResetTransform();graphics->ResetClip();graphics->Clear(Gdiplus::Color(0,0,0,0));
            graphics->SetClip(&clip);
        }
    } normalBuffer,recordedBuffer;

    static std::unique_ptr<Gdiplus::GraphicsPath> trace(yawn_data::Path source) {
        auto result=std::make_unique<Gdiplus::GraphicsPath>(Gdiplus::FillModeAlternate);
        Gdiplus::PointF current{};
        const auto end=source.offset+source.count;
        for(std::size_t i=source.offset;i<end;){
            const auto command=yawn_data::commands[i++];
            if(command==2){result->CloseFigure();continue;}
            const auto p=yawnTracedPoint(yawn_data::commands[i],yawn_data::commands[i+1]);i+=2;
            const Gdiplus::PointF point{Gdiplus::REAL(p.x),Gdiplus::REAL(p.y)};
            if(command==0)result->StartFigure();else result->AddLine(current,point);
            current=point;
        }
        return result;
    }

    template<class Transform> void recorded(Gdiplus::Graphics& g,double time,Transform sharedHead) const {
        const auto index=yawnFrameIndex(time);const auto pose=recordedYawnHead(time);
        const auto origin=sharedHead(pose.inverse({0,0})),x=sharedHead(pose.inverse({1,0}))-origin,
            y=sharedHead(pose.inverse({0,1}))-origin;
        Gdiplus::Matrix transform(Gdiplus::REAL(x.x),Gdiplus::REAL(x.y),Gdiplus::REAL(y.x),
            Gdiplus::REAL(y.y),Gdiplus::REAL(origin.x),Gdiplus::REAL(origin.y));
        const auto saved=g.Save();g.MultiplyTransform(&transform);
        Gdiplus::SolidBrush black(Gdiplus::Color(255,9,9,9));g.FillPath(&black,frames[index].face.get());
        for(const auto& layer:frames[index].layers){Gdiplus::SolidBrush fill(Gdiplus::Color(0xff000000u|layer.fill));
            g.FillPath(&fill,layer.path.get());}
        g.Restore(saved);
    }

public:
    YawnDrawing() {
        for(std::size_t i=0;i<frames.size();++i){const auto& source=yawn_data::frames[i];
            auto& frame=frames[i];frame.face=trace(source.face);frame.layers.reserve(source.layerCount);
            for(std::size_t j=0;j<source.layerCount;++j){const auto& layer=yawn_data::layers[source.layerOffset+j];
                frame.layers.push_back({layer.fill,trace(layer.path)});}
        }
    }
    template<class Transform,class Normal> bool drawFaces(Gdiplus::Graphics& g,int side,
            const Gdiplus::GraphicsPath& clip,double time,double weight,Transform sharedHead,Normal normal) {
        weight=std::isfinite(weight)?clamp(weight):0;
        if(weight<=0){normal(g);return true;}
        if(weight>=1){recorded(g,time,sharedHead);return true;}
        if(!normalBuffer.resize(side)||!recordedBuffer.resize(side))return false;
        normalBuffer.clear(clip);recordedBuffer.clear(clip);
        normal(*normalBuffer.graphics);recorded(*recordedBuffer.graphics,time,sharedHead);
        normalBuffer.graphics->Flush(Gdiplus::FlushIntentionSync);
        recordedBuffer.graphics->Flush(Gdiplus::FlushIntentionSync);
        const unsigned w=unsigned(std::lround(weight*65535)),inverse=65535-w;
        for(std::size_t i=0;i<normalBuffer.pixels.size();++i){
            const auto a=normalBuffer.pixels[i],b=recordedBuffer.pixels[i];std::uint32_t mixed=0;
            for(unsigned shift=0;shift<32;shift+=8)
                mixed|=((((a>>shift)&255)*inverse+((b>>shift)&255)*w+32767)/65535)<<shift;
            normalBuffer.pixels[i]=mixed;
        }
        // Explicit pixel units keep the handoff aligned on 125%/150% displays;
        // the bitmap's nominal DPI must never resize the face independently.
        return g.DrawImage(normalBuffer.bitmap.get(),Gdiplus::Rect(0,0,side,side),
            0,0,side,side,Gdiplus::UnitPixel)==Gdiplus::Ok;
    }
};
} // namespace dog
