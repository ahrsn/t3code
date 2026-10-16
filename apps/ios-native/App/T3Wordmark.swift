import SwiftUI

// Geometry from apps/mobile/src/components/T3Wordmark.tsx.
struct T3Wordmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 33.4509, y: 93))
        p.addLine(to: CGPoint(x: 33.4509, y: 47.56))
        p.addLine(to: CGPoint(x: 15.5309, y: 47.56))
        p.addLine(to: CGPoint(x: 15.5309, y: 37))
        p.addLine(to: CGPoint(x: 64.3309, y: 37))
        p.addLine(to: CGPoint(x: 64.3309, y: 47.56))
        p.addLine(to: CGPoint(x: 46.4109, y: 47.56))
        p.addLine(to: CGPoint(x: 46.4109, y: 93))
        p.addLine(to: CGPoint(x: 33.4509, y: 93))
        p.closeSubpath()
        p.move(to: CGPoint(x: 86.7253, y: 93.96))
        p.addCurve(to: CGPoint(x: 75.1253, y: 92.44), control1: CGPoint(x: 82.832, y: 93.96), control2: CGPoint(x: 78.9653, y: 93.4533))
        p.addCurve(to: CGPoint(x: 65.3653, y: 87.96), control1: CGPoint(x: 71.2853, y: 91.3733), control2: CGPoint(x: 68.032, y: 89.88))
        p.addLine(to: CGPoint(x: 70.4053, y: 78.04))
        p.addCurve(to: CGPoint(x: 77.8453, y: 81.72), control1: CGPoint(x: 72.5386, y: 79.5867), control2: CGPoint(x: 75.0186, y: 80.8133))
        p.addCurve(to: CGPoint(x: 86.4053, y: 83.08), control1: CGPoint(x: 80.672, y: 82.6267), control2: CGPoint(x: 83.5253, y: 83.08))
        p.addCurve(to: CGPoint(x: 94.0853, y: 81.16), control1: CGPoint(x: 89.6586, y: 83.08), control2: CGPoint(x: 92.2186, y: 82.44))
        p.addCurve(to: CGPoint(x: 96.8853, y: 75.88), control1: CGPoint(x: 95.952, y: 79.88), control2: CGPoint(x: 96.8853, y: 78.12))
        p.addCurve(to: CGPoint(x: 94.4053, y: 70.84), control1: CGPoint(x: 96.8853, y: 73.7467), control2: CGPoint(x: 96.0586, y: 72.0667))
        p.addCurve(to: CGPoint(x: 86.4053, y: 69), control1: CGPoint(x: 92.752, y: 69.6133), control2: CGPoint(x: 90.0853, y: 69))
        p.addLine(to: CGPoint(x: 80.4853, y: 69))
        p.addLine(to: CGPoint(x: 80.4853, y: 60.44))
        p.addLine(to: CGPoint(x: 96.0853, y: 42.76))
        p.addLine(to: CGPoint(x: 97.5253, y: 47.4))
        p.addLine(to: CGPoint(x: 68.1653, y: 47.4))
        p.addLine(to: CGPoint(x: 68.1653, y: 37))
        p.addLine(to: CGPoint(x: 107.365, y: 37))
        p.addLine(to: CGPoint(x: 107.365, y: 45.4))
        p.addLine(to: CGPoint(x: 91.8453, y: 63.08))
        p.addLine(to: CGPoint(x: 85.2853, y: 59.32))
        p.addLine(to: CGPoint(x: 89.0453, y: 59.32))
        p.addCurve(to: CGPoint(x: 104.645, y: 63.96), control1: CGPoint(x: 95.9253, y: 59.32), control2: CGPoint(x: 101.125, y: 60.8667))
        p.addCurve(to: CGPoint(x: 109.925, y: 75.88), control1: CGPoint(x: 108.165, y: 67.0533), control2: CGPoint(x: 109.925, y: 71.0267))
        p.addCurve(to: CGPoint(x: 107.445, y: 84.76), control1: CGPoint(x: 109.925, y: 79.0267), control2: CGPoint(x: 109.099, y: 81.9867))
        p.addCurve(to: CGPoint(x: 99.8453, y: 91.4), control1: CGPoint(x: 105.792, y: 87.48), control2: CGPoint(x: 103.259, y: 89.6933))
        p.addCurve(to: CGPoint(x: 86.7253, y: 93.96), control1: CGPoint(x: 96.432, y: 93.1067), control2: CGPoint(x: 92.0586, y: 93.96))
        p.closeSubpath()
        let sx = rect.width / 94.3941, sy = rect.height / 56.96
        return p.applying(CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: -15.5309 * sx, ty: -37 * sy))
    }
}

struct T3BrandTitle: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            T3Wordmark().frame(width: 25, height: 15).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            Text("Code").font(T3Font.scaled(21, weight: .medium, relativeTo: .title3)).tracking(-0.5)
        }.accessibilityElement(children: .ignore).accessibilityLabel("T3 Code")
    }
}
