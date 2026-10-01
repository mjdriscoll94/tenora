import SwiftUI

enum HabitTint {
    static let choices: [(id: String, name: String, color: Color)] = [
        ("forest", "Blue", .tenoraForest),
        ("copper", "Purple", .tenoraCopper),
        ("sage", "Lavender", .tenoraSage),
        ("ink", "Navy", .tenoraInk),
        ("sun", "Gold", Color(red: 0.90, green: 0.62, blue: 0.25)),
        ("rose", "Rose", Color(red: 0.78, green: 0.39, blue: 0.48))
    ]

    static func color(for identifier: String) -> Color {
        choices.first { $0.id == identifier }?.color ?? .tenoraForest
    }
}

struct HabitWorldView: View {
    let unlockedRewardIDs: Set<String>
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color.tenoraInk, Color.tenoraForest.opacity(0.80)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if unlocked("stars") {
                    stars(in: proxy.size).transition(.opacity)
                }
                if unlocked("mountains") { mountains(in: proxy.size).transition(worldTransition) }
                else if unlocked("hills") { hills(in: proxy.size).transition(worldTransition) }
                terrain(in: proxy.size)
                if unlocked("path") { path(in: proxy.size).transition(worldTransition) }
                worldObjects(in: proxy.size)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: unlockedRewardIDs)
        }
        .frame(height: compact ? 145 : 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.tenoraInk.opacity(0.12), radius: 8, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress landscape with \(unlockedRewardIDs.count) world upgrades")
    }

    private var worldTransition: AnyTransition { .scale(scale: 0.75, anchor: .bottom).combined(with: .opacity) }
    private func unlocked(_ id: String) -> Bool { unlockedRewardIDs.contains(id) }

    private func terrain(in size: CGSize) -> some View {
        Ellipse()
            .fill(LinearGradient(colors: [.tenoraSage, .tenoraForest], startPoint: .top, endPoint: .bottom))
            .frame(width: size.width * 1.12, height: size.height * 0.58)
            .offset(y: size.height * 0.30)
    }

    private func path(in size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.42, y: size.height))
            path.addCurve(
                to: CGPoint(x: size.width * 0.60, y: size.height * 0.55),
                control1: CGPoint(x: size.width * 0.55, y: size.height * 0.84),
                control2: CGPoint(x: size.width * 0.42, y: size.height * 0.68)
            )
        }
        .stroke(Color.tenoraSurface.opacity(0.82), style: StrokeStyle(lineWidth: compact ? 16 : 24, lineCap: .round))
    }

    private func hills(in size: CGSize) -> some View {
        HStack(alignment: .bottom, spacing: -35) {
            Circle().fill(Color.tenoraSage.opacity(0.22)).frame(width: size.width * 0.55)
            Circle().fill(Color.tenoraCopper.opacity(0.20)).frame(width: size.width * 0.48)
        }
        .offset(y: size.height * 0.32)
    }

    private func mountains(in size: CGSize) -> some View {
        HStack(alignment: .bottom, spacing: -18) {
            Image(systemName: "mountain.2.fill").resizable().scaledToFit().foregroundStyle(Color.tenoraSage.opacity(0.25))
            Image(systemName: "mountain.2.fill").resizable().scaledToFit().foregroundStyle(Color.tenoraCopper.opacity(0.20))
        }
        .frame(height: size.height * 0.55)
        .offset(y: size.height * 0.08)
    }

    @ViewBuilder
    private func stars(in size: CGSize) -> some View {
        ForEach(0..<8, id: \.self) { index in
            Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                .font(.system(size: index.isMultiple(of: 2) ? 9 : 3))
                .foregroundStyle(.white.opacity(0.72))
                .position(x: size.width * (0.10 + Double(index) * 0.11), y: size.height * (index.isMultiple(of: 3) ? 0.16 : 0.27))
        }
    }

    @ViewBuilder
    private func worldObjects(in size: CGSize) -> some View {
        if unlocked("rocks") { object("circle.hexagongrid.fill", x: 0.19, y: 0.77, size: 24, color: .white.opacity(0.62), in: size) }
        if unlocked("small-plant") { object("leaf.fill", x: 0.30, y: 0.66, size: 24, color: .tenoraSage, in: size) }
        if unlocked("medium-plant") { object("camera.macro", x: 0.73, y: 0.73, size: 28, color: .tenoraCopper, in: size) }
        if unlocked("small-tree") { object("tree.fill", x: 0.22, y: 0.52, size: compact ? 38 : 48, color: .tenoraSage, in: size) }
        if unlocked("large-tree") { object("tree.fill", x: 0.78, y: 0.48, size: compact ? 48 : 64, color: .tenoraForest, in: size) }
        if unlocked("bench") { object("chair.lounge.fill", x: 0.59, y: 0.68, size: 30, color: .tenoraSurface, in: size) }
        if unlocked("lantern") { object("light.beacon.max.fill", x: 0.47, y: 0.57, size: 27, color: Color(red: 1, green: 0.78, blue: 0.38), in: size) }
        if unlocked("cabin") { object("house.fill", x: 0.68, y: 0.45, size: compact ? 38 : 50, color: .tenoraSurface, in: size) }
    }

    private func object(_ symbol: String, x: CGFloat, y: CGFloat, size fontSize: CGFloat, color: Color, in size: CGSize) -> some View {
        Image(systemName: symbol)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(color)
            .shadow(color: Color.black.opacity(0.18), radius: 5, y: 3)
            .position(x: size.width * x, y: size.height * y)
            .transition(worldTransition)
            .accessibilityHidden(true)
    }
}
