import SwiftUI

/// Branded launch screen with the Arca arch animation.
/// Shown briefly on cold start before the feed loads.
struct LaunchScreenView: View {
    @State private var archScale: CGFloat = 0.8
    @State private var archOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var beaconGlow: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.10, blue: 0.14),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    // Glow behind arch
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.arcaOrange.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .opacity(beaconGlow)

                    // Outer arch
                    ArcaArchShape()
                        .stroke(
                            LinearGradient(
                                colors: [.arcaOrange, .arcaRed],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 70, height: 84)

                    // Inner arch
                    ArcaArchShape()
                        .stroke(
                            LinearGradient(
                                colors: [.arcaOrange.opacity(0.5), .arcaRed.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 38, height: 56)

                    // Beacon dot
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, .arcaOrange.opacity(0.6), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 8
                            )
                        )
                        .frame(width: 14, height: 14)
                        .offset(y: -42)
                        .opacity(beaconGlow)
                }
                .scaleEffect(archScale)
                .opacity(archOpacity)

                // App name
                Text("Arca")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .opacity(textOpacity)

                Text("Tech. Curated.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.5))
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            if reduceMotion {
                archScale = 1.0
                archOpacity = 1.0
                textOpacity = 1.0
                beaconGlow = 1.0
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    archScale = 1.0
                    archOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    beaconGlow = 1.0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                    textOpacity = 1.0
                }
            }
        }
    }
}
