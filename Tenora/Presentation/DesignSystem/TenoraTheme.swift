import SwiftUI

extension Color {
    static let tenoraInk = Color("BrandNavy")
    static let tenoraForest = Color("BrandBlue")
    static let tenoraCopper = Color("BrandPurple")
    static let tenoraSage = Color("BrandLavender")
    static let tenoraSurface = Color("BrandSurface")
    static let tenoraCard = Color("BrandCard")
}

enum TenoraTheme {
    static let accentGradient = LinearGradient(
        colors: [.tenoraForest, .tenoraCopper],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let calmGradient = LinearGradient(
        colors: [.tenoraSage.opacity(0.34), .tenoraCopper.opacity(0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct TenoraScreenBackground: View {
    var body: some View {
        ZStack {
            Color.tenoraSurface

            Circle()
                .fill(Color.tenoraSage.opacity(0.18))
                .frame(width: 330, height: 330)
                .blur(radius: 12)
                .offset(x: 170, y: -310)

            Circle()
                .fill(Color.tenoraCopper.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: -190, y: 340)
        }
        .ignoresSafeArea()
    }
}

struct TenoraNowCardBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.tenoraInk)

            Circle()
                .fill(Color.tenoraSage.opacity(0.34))
                .frame(width: 190, height: 190)
                .blur(radius: 55)
                .offset(x: 130, y: -80)

            Circle()
                .fill(Color.tenoraCopper.opacity(0.38))
                .frame(width: 160, height: 160)
                .blur(radius: 50)
                .offset(x: -125, y: 100)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct TenoraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(TenoraTheme.accentGradient.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TenoraSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.tenoraForest)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.tenoraSage.opacity(configuration.isPressed ? 0.18 : 0.28))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(Color.tenoraForest.opacity(0.18), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct TenoraCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.tenoraCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.tenoraSage.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: Color.tenoraInk.opacity(0.06), radius: 12, y: 5)
    }
}

extension View {
    func tenoraCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(TenoraCardModifier(cornerRadius: cornerRadius))
    }
}
