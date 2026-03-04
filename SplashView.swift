import SwiftUI

// A subtle dotted slate-indigo background matching the brand style
struct BrandedDottedBackground: View {
    var body: some View {
        GeometryReader { geo in
            // Original dark purple/blue splash gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 166.0/255.0, green: 51.0/255.0, blue: 185.0/255.0),
                    Color(red: 93.0/255.0, green: 45.0/255.0, blue: 201.0/255.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Dotted pattern using Canvas for performance and scalability
            Canvas { context, size in
                // Denser pattern and slightly larger dots to match app icon
                let step: CGFloat = 28
                let cols = Int(size.width / step) + 2
                let rows = Int(size.height / step) + 2

                for col in 0..<cols {
                    for row in 0..<rows {
                        let x = CGFloat(col) * step + (step/2)
                        let y = CGFloat(row) * step + (step/2)

                        // deterministic pseudo-random radius/offset
                        var seed = col &* 73856093 &+ row &* 19349663
                        seed = seed ^ 0x9e3779b9
                        let jitterX = CGFloat((seed & 0xff) % 9) - 4.0
                        let jitterY = CGFloat(((seed >> 8) & 0xff) % 9) - 4.0
                        let r = CGFloat(((seed & 7) % 8) + 6) // sizes 6-13

                        let rect = CGRect(x: x + jitterX - r/2, y: y + jitterY - r/2, width: r, height: r)
                        var path = Path()
                        path.addEllipse(in: rect)
                        // Dots colored to match the original splash palette
                        context.fill(path, with: .color(Color(red: 95.0/255.0, green: 33.0/255.0, blue: 120.0/255.0).opacity(0.25)))
                    }
                }
            }
            .blendMode(.normal)
            .ignoresSafeArea()
        }
    }
}

struct SplashView: View {
    @State private var leftOpen = false
    @State private var rightOpen = false
    @State private var giftRevealed = false
    @State private var wrapBack = false
    @State private var showTitle = false
    @State private var charOffsets: [CGFloat] = []
    @State private var showFilled = false
    @State private var iconOffsetX: CGFloat = 120
    @State private var titleOffsetX: CGFloat = -80
    @State private var finalZoom = false
    @State private var hideIcon = false
    var onComplete: (() -> Void)? = nil

    private let title = Array("GiftMinder")

    var body: some View {
        ZStack {
            BrandedDottedBackground()

            VStack(spacing: 24) {
                // Gift icon that crossfades from outline to filled (matches SF symbol)
                ZStack {
                    // Outline symbol (appears first) in white
                    Image(systemName: "gift")
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(hideIcon ? 0 : (showFilled ? 0 : 1))
                        .scaleEffect(showFilled ? 0.92 : 1.0)

                    // Filled symbol (white) that fades in to simulate wrapping
                    Image(systemName: "gift.fill")
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(hideIcon ? 0 : (showFilled ? 1 : 0))
                        .scaleEffect(showFilled ? 1.0 : 1.06)
                        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: showFilled)
                }
                .offset(x: iconOffsetX)
                // Reduce extreme zoom to avoid enlarging the app UI at runtime.
                // Keep a subtle pop effect but do not scale to massive values.
                .scaleEffect(finalZoom ? 1.6 : 1)
                .zIndex(finalZoom ? 2 : 1)

                // Title with ® superscript, larger modern rounded font
                HStack(spacing: 0) {
                    ForEach(0..<title.count, id: \.self) { i in
                        Text(String(title[i]))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .offset(y: i < charOffsets.count ? charOffsets[i] : 12)
                            .opacity(showTitle ? 1 : 0)
                    }

                    Text("™")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .baselineOffset(14)
                        .opacity(showTitle ? 1 : 0)
                        .padding(.leading, 6)
                }
                .offset(x: titleOffsetX)
                .opacity(finalZoom ? 0 : 1)
            }
            
            .onAppear {
                // Slide icon in from right
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        iconOffsetX = 0
                    }
                }
                // Gift appears unwrapped
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.76)) {
                        giftRevealed = true
                    }
                }

                // Show filled symbol after a short delay to simulate wrapping
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeIn(duration: 0.28)) { showFilled = true }
                }

                // Show title and do single wave (title slides in from left)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    charOffsets = Array(repeating: 12, count: title.count)
                    withAnimation(.easeOut(duration: 0.35)) {
                        showTitle = true
                        titleOffsetX = 0
                    }

                    for i in 0..<title.count {
                        let delay = 0.06 * Double(i)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 + delay) {
                            withAnimation(.easeOut(duration: 0.26)) {
                                charOffsets[i] = (i % 2 == 0) ? -8 : -4
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                                withAnimation(.easeIn(duration: 0.22)) {
                                    charOffsets[i] = 0
                                }
                            }
                        }
                    }
                    // after wave finishes, do final zoom; hide the icon right before completing
                    let totalWaveDuration = 0.18 + 0.26 + 0.06 * Double(title.count - 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + totalWaveDuration + 0.12) {
                        withAnimation(.easeIn(duration: 0.45)) {
                            finalZoom = true
                        }
                        // fade out the icon just before finishing so the giant scaled icon isn't visible
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                hideIcon = true
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                            onComplete?()
                        }
                    }
                }
            }
        }
    #if os(iOS)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        _ = proxy.size // force layout
                    }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    #endif
        // No debug overlays in production build — keep view full-screen
    }

}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SplashView()
                .preferredColorScheme(.light)
            SplashView()
                .preferredColorScheme(.dark)
        }
    }
}

