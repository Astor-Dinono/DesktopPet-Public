import AppKit

@MainActor
enum InteractionEffectRenderer {
    struct Shape {
        let path: CGPath
        let fill: UInt32?
        let stroke: UInt32?
        let width: CGFloat
    }

    private static func color(_ rgb: UInt32) -> CGColor {
        CGColor(red: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    static func draw(_ effects: [ClickEffectPose], in context: CGContext) {
        for item in effects {
            let pose = item.pose
            context.saveGState()
            context.translateBy(x: pose.x, y: pose.y)
            // Artwork is y-down; the passive screen-space panel is y-up.
            context.rotate(by: -pose.rotation)
            context.scaleBy(x: pose.scale, y: -pose.scale)
            context.setAlpha(pose.alpha)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for shape in InteractionEffectArtwork.shapes[item.effect.rawValue] {
                if let fill = shape.fill {
                    context.addPath(shape.path)
                    context.setFillColor(color(fill))
                    context.fillPath()
                }
                if let stroke = shape.stroke, shape.width > 0 {
                    context.addPath(shape.path)
                    context.setStrokeColor(color(stroke))
                    context.setLineWidth(shape.width)
                    context.strokePath()
                }
            }
            context.restoreGState()
        }
    }
}
