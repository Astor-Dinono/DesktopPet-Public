import AppKit

@MainActor
enum DogEffectsRenderer {
    private static let ink = NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.34, alpha: 1)

    static func drawSleep(_ pose: PetPose) {
        // A sparse staggered trio. No particles or growing queue.
        for index in 0..<3 {
            let phase = (pose.sleepAge / 4.8 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let alpha = sin(phase * .pi) * pose.sleepLetters * 0.42
            let drift = pose.reducedMotion ? 0 : phase * 25
            let text = index == 2 ? "Z" : "z"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12 + Double(index) * 3, weight: .medium),
                .foregroundColor: ink.withAlphaComponent(alpha)
            ]
            (text as NSString).draw(at: NSPoint(x: 168 + Double(index) * 12, y: 140 + Double(index) * 14 + drift), withAttributes: attributes)
        }
    }

    static func drawHearts(_ pose: PetPose, in context: CGContext) {
        for particle in pose.hearts {
            context.saveGState()
            context.translateBy(x: particle.x, y: particle.y)
            context.rotate(by: particle.rotation)
            context.scaleBy(x: particle.scale, y: particle.scale)
            context.setAlpha(particle.alpha)
            let heart = NSBezierPath()
            heart.move(to: .zero)
            heart.curve(to: NSPoint(x: -9, y: 12), controlPoint1: NSPoint(x: -3, y: 4), controlPoint2: NSPoint(x: -12, y: 7))
            heart.curve(to: NSPoint(x: 0, y: 12), controlPoint1: NSPoint(x: -7, y: 17), controlPoint2: NSPoint(x: -1, y: 17))
            heart.curve(to: NSPoint(x: 9, y: 12), controlPoint1: NSPoint(x: 1, y: 17), controlPoint2: NSPoint(x: 7, y: 17))
            heart.curve(to: .zero, controlPoint1: NSPoint(x: 12, y: 7), controlPoint2: NSPoint(x: 3, y: 4))
            heart.close()
            NSGradient(colors: [
                NSColor(calibratedRed: 0.91, green: 0.24, blue: 0.49, alpha: 1),
                NSColor(calibratedRed: 1, green: 0.57, blue: 0.76, alpha: 1)
            ])!.draw(in: heart, angle: 90)
            let shine = NSBezierPath()
            shine.move(to: NSPoint(x: -6, y: 10))
            shine.curve(to: NSPoint(x: -3.5, y: 13), controlPoint1: NSPoint(x: -7, y: 12), controlPoint2: NSPoint(x: -5, y: 14))
            stroke(shine, color: .white.withAlphaComponent(0.65), width: 1.1)
            drawSparkle(at: NSPoint(x: 10.5, y: 16.5), radius: 4.3, alpha: particle.sparkle)
            drawSparkle(at: NSPoint(x: -10.5, y: 7), radius: 2.6, alpha: particle.sparkle * 0.8)
            context.restoreGState()
        }
    }

    private static func drawSparkle(at center: NSPoint, radius: CGFloat, alpha: Double) {
        let star = NSBezierPath()
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            let distance = index.isMultiple(of: 2) ? radius : radius * 0.25
            let point = NSPoint(x: center.x + sin(angle) * distance, y: center.y + cos(angle) * distance)
            if index == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close()
        NSColor(calibratedRed: 1, green: 0.78, blue: 0.27, alpha: alpha).setFill()
        star.fill()
    }

    private static func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

}
