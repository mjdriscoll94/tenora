import SwiftUI

extension Color {
    static let tenoraNavy = Color("BrandNavy")
    static let tenoraBlue = Color("BrandBlue")
    static let tenoraPurple = Color("BrandPurple")
    static let tenoraLavender = Color("BrandLavender")
    static let tenoraSurface = Color("BrandSurface")
}

enum TenoraTheme {
    static let accentGradient = LinearGradient(
        colors: [.tenoraBlue, .tenoraPurple],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct TenoraNowCardBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.tenoraNavy)

            Circle()
                .fill(Color.tenoraBlue.opacity(0.32))
                .frame(width: 190, height: 190)
                .blur(radius: 55)
                .offset(x: 130, y: -80)

            Circle()
                .fill(Color.tenoraPurple.opacity(0.28))
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

