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

enum WorldSeason: String, CaseIterable, Identifiable {
    case spring, summer, fall, winter

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func current(on date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> WorldSeason {
        switch calendar.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .fall
        default: .winter
        }
    }
}

enum WorldLighting { case day, evening, night
    static func current(on date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> WorldLighting {
        switch calendar.component(.hour, from: date) {
        case 7..<17: .day
        case 17..<21: .evening
        default: .night
        }
    }
}

enum WorldStage: Int, CaseIterable, Identifiable {
    case beginning = 1, sprouting, growing, flourishing, thriving
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .beginning: "Beginning"
        case .sprouting: "Sprouting"
        case .growing: "Growing"
        case .flourishing: "Flourishing"
        case .thriving: "Thriving"
        }
    }
    init(level: Int) {
        switch level {
        case ..<5: self = .beginning
        case 5..<12: self = .sprouting
        case 12..<20: self = .growing
        case 20..<30: self = .flourishing
        default: self = .thriving
        }
    }
}

enum WorldObjectType { case background, terrain, path, vegetation, structure, wildlife, effect }
enum WorldMotion { case still, sway, float, pulse }

struct WorldObjectPlacement: Identifiable {
    let id: String
    let rewardID: String?
    let assetName: String
    let type: WorldObjectType
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let depth: Double
    var motion: WorldMotion = .still
}

struct WorldScene {
    let stage: WorldStage
    let season: WorldSeason
    let lighting: WorldLighting
    let objects: [WorldObjectPlacement]
}

enum HabitWorldCatalog {
    static let placements: [WorldObjectPlacement] = [
        .init(id: "distant-mountains", rewardID: "mountains", assetName: "world_background_mountains", type: .background, x: 0.50, y: 0.64, width: 0.90, height: 0.46, depth: 1),
        .init(id: "distant-forest", rewardID: "hills", assetName: "world_background_forest", type: .background, x: 0.50, y: 0.69, width: 1.02, height: 0.40, depth: 2),
        .init(id: "ground", rewardID: nil, assetName: "world_terrain_grass_01", type: .terrain, x: 0.50, y: 1.04, width: 0.92, height: 0.68, depth: 4),
        .init(id: "path", rewardID: "path", assetName: "world_path_straight", type: .path, x: 0.49, y: 1.02, width: 0.34, height: 0.46, depth: 5),
        .init(id: "pond", rewardID: "pond", assetName: "world_water_pond", type: .terrain, x: 0.78, y: 0.94, width: 0.34, height: 0.34, depth: 6),
        .init(id: "sprout", rewardID: "small-plant", assetName: "world_tree_sapling", type: .vegetation, x: 0.28, y: 0.83, width: 0.11, height: 0.22, depth: 8, motion: .sway),
        .init(id: "rocks", rewardID: "rocks", assetName: "world_decor_rock_small", type: .vegetation, x: 0.72, y: 0.82, width: 0.15, height: 0.18, depth: 8),
        .init(id: "young-tree", rewardID: "small-tree", assetName: "world_tree_young", type: .vegetation, x: 0.18, y: 0.82, width: 0.24, height: 0.46, depth: 7, motion: .sway),
        .init(id: "wildflowers", rewardID: "medium-plant", assetName: "world_flower_mixed", type: .vegetation, x: 0.66, y: 0.91, width: 0.16, height: 0.18, depth: 12, motion: .sway),
        .init(id: "bench", rewardID: "bench", assetName: "world_structure_bench", type: .structure, x: 0.65, y: 0.77, width: 0.28, height: 0.28, depth: 9),
        .init(id: "lantern", rewardID: "lantern", assetName: "world_structure_lantern", type: .structure, x: 0.38, y: 0.72, width: 0.15, height: 0.30, depth: 9, motion: .pulse),
        .init(id: "bush", rewardID: "round-bush", assetName: "world_bush_round", type: .vegetation, x: 0.84, y: 0.79, width: 0.23, height: 0.25, depth: 7, motion: .sway),
        .init(id: "shelter-tree", rewardID: "large-tree", assetName: "world_tree_large", type: .vegetation, x: 0.16, y: 0.80, width: 0.37, height: 0.63, depth: 6, motion: .sway),
        .init(id: "fence", rewardID: "fence", assetName: "world_structure_fence_wood", type: .structure, x: 0.78, y: 0.70, width: 0.30, height: 0.24, depth: 7),
        .init(id: "cabin", rewardID: "cabin", assetName: "world_structure_cabin", type: .structure, x: 0.67, y: 0.72, width: 0.42, height: 0.55, depth: 7),
        .init(id: "birdhouse", rewardID: "birdhouse", assetName: "world_structure_birdhouse", type: .structure, x: 0.28, y: 0.69, width: 0.13, height: 0.28, depth: 8),
        .init(id: "butterfly", rewardID: "butterfly", assetName: "world_animal_butterfly", type: .wildlife, x: 0.77, y: 0.58, width: 0.08, height: 0.13, depth: 16, motion: .float),
        .init(id: "garden", rewardID: "garden-bed", assetName: "world_structure_garden_bed", type: .structure, x: 0.79, y: 0.86, width: 0.30, height: 0.28, depth: 10),
        .init(id: "bird", rewardID: "bird", assetName: "world_animal_bird", type: .wildlife, x: 0.34, y: 0.56, width: 0.08, height: 0.13, depth: 16, motion: .float),
        .init(id: "bridge", rewardID: "bridge", assetName: "world_structure_bridge_wood", type: .structure, x: 0.58, y: 0.94, width: 0.32, height: 0.27, depth: 13),
        .init(id: "flowering-tree", rewardID: "flowering-tree", assetName: "world_tree_flowering", type: .vegetation, x: 0.86, y: 0.74, width: 0.34, height: 0.58, depth: 6, motion: .sway),
        .init(id: "rabbit", rewardID: "rabbit", assetName: "world_animal_rabbit", type: .wildlife, x: 0.35, y: 0.91, width: 0.10, height: 0.16, depth: 17, motion: .float),
        .init(id: "sparkles", rewardID: "stars", assetName: "effect_sparkle_02", type: .effect, x: 0.72, y: 0.40, width: 0.12, height: 0.18, depth: 18, motion: .pulse),
        .init(id: "stone-bridge", rewardID: "stone-bridge", assetName: "world_structure_bridge_stone", type: .structure, x: 0.55, y: 0.93, width: 0.36, height: 0.30, depth: 13),
        .init(id: "fountain", rewardID: "fountain", assetName: "world_structure_fountain", type: .structure, x: 0.53, y: 0.73, width: 0.27, height: 0.39, depth: 10, motion: .pulse),
        .init(id: "upgraded-cabin", rewardID: "cabin-upgraded", assetName: "world_structure_cabin_upgraded", type: .structure, x: 0.68, y: 0.72, width: 0.46, height: 0.59, depth: 7),
        .init(id: "fox", rewardID: "fox", assetName: "world_animal_fox", type: .wildlife, x: 0.82, y: 0.91, width: 0.13, height: 0.20, depth: 17, motion: .float),
        .init(id: "gazebo", rewardID: "gazebo", assetName: "world_structure_gazebo", type: .structure, x: 0.68, y: 0.72, width: 0.43, height: 0.57, depth: 7),
        .init(id: "windmill", rewardID: "windmill", assetName: "world_structure_windmill", type: .structure, x: 0.73, y: 0.70, width: 0.40, height: 0.59, depth: 7),
        .init(id: "deer", rewardID: "deer", assetName: "world_animal_deer", type: .wildlife, x: 0.84, y: 0.89, width: 0.15, height: 0.25, depth: 17, motion: .float),
        .init(id: "greenhouse", rewardID: "greenhouse", assetName: "world_structure_greenhouse", type: .structure, x: 0.70, y: 0.71, width: 0.43, height: 0.56, depth: 7),
        .init(id: "observatory", rewardID: "observatory", assetName: "world_structure_observatory", type: .structure, x: 0.69, y: 0.71, width: 0.43, height: 0.58, depth: 7)
    ]

    static func scene(unlockedRewardIDs: Set<String>, level: Int, season: WorldSeason, lighting: WorldLighting) -> WorldScene {
        let stage = WorldStage(level: level)
        var visible = placements.filter { $0.rewardID.map(unlockedRewardIDs.contains) ?? true }
        let replacements: [(new: String, old: [String])] = [
            ("cabin-upgraded", ["cabin"]), ("stone-bridge", ["bridge"]),
            ("gazebo", ["bench"]), ("greenhouse", ["gazebo", "upgraded-cabin"]),
            ("observatory", ["greenhouse", "windmill"])
        ]
        for replacement in replacements where unlockedRewardIDs.contains(replacement.new) {
            visible.removeAll { replacement.old.contains($0.id) }
        }
        return WorldScene(stage: stage, season: season, lighting: lighting, objects: visible)
    }
}

enum KeeperState {
    case idle, walking, watering, reading, celebrating, sitting, sleeping, looking, carrying
    var frames: [String] {
        switch self {
        case .idle: ["keeper_idle_01", "keeper_idle_02", "keeper_idle_03", "keeper_idle_04"]
        case .walking: ["keeper_walk_01", "keeper_walk_02", "keeper_walk_03", "keeper_walk_04"]
        case .watering: ["keeper_water_01", "keeper_water_02"]
        case .reading: ["keeper_read_01", "keeper_read_02"]
        case .celebrating: ["keeper_celebrate_01", "keeper_celebrate_02", "keeper_celebrate_03"]
        case .sitting: ["keeper_sit_01", "keeper_sit_02"]
        case .sleeping: ["keeper_sleep_01", "keeper_sleep_02"]
        case .looking: ["keeper_look_01", "keeper_idle_03"]
        case .carrying: ["keeper_carry_01", "keeper_carry_02"]
        }
    }
}

struct HabitWorldView: View {
    let unlockedRewardIDs: Set<String>
    var level = 1
    var compact = false
    var celebration: HabitCelebration?
    var seasonOverride: WorldSeason?
    var date = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 0.18)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let scene = HabitWorldCatalog.scene(unlockedRewardIDs: unlockedRewardIDs, level: level, season: season, lighting: WorldLighting.current(on: date))
                ZStack {
                    worldBackground(scene.lighting)
                    ForEach(scene.objects.sorted(by: { $0.depth < $1.depth })) { object in
                        WorldSpriteView(object: seasonal(object, season: scene.season), size: proxy.size, phase: phase, reduceMotion: reduceMotion)
                            .zIndex(object.depth)
                    }
                    KeeperSpriteView(state: keeperState(lighting: scene.lighting, phase: phase), phase: phase, reduceMotion: reduceMotion)
                        .frame(width: proxy.size.width * (compact ? 0.17 : 0.19), height: proxy.size.height * 0.33, alignment: .bottom)
                        .position(x: proxy.size.width * 0.45, y: proxy.size.height * 0.84)
                        .zIndex(15)
                    if celebration != nil { WorldCelebrationEffect(phase: phase, reduceMotion: reduceMotion).zIndex(30) }
                    lightingOverlay(scene.lighting).zIndex(40)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: unlockedRewardIDs)
            }
        }
        .frame(height: compact ? 190 : 270)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 1) }
        .shadow(color: Color.tenoraInk.opacity(0.14), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WorldStage(level: level).title) Tenora world in \(season.title), with \(unlockedRewardIDs.count) upgrades")
    }

    private var season: WorldSeason { seasonOverride ?? WorldSeason.current(on: date) }

    private func seasonal(_ object: WorldObjectPlacement, season: WorldSeason) -> WorldObjectPlacement {
        let replacement = object.id == "shelter-tree" ? "season_\(season.rawValue)_tree" : object.id == "bush" ? "season_\(season.rawValue)_bush" : nil
        guard let replacement else { return object }
        return .init(id: object.id, rewardID: object.rewardID, assetName: replacement, type: object.type, x: object.x, y: object.y, width: object.width, height: object.height, depth: object.depth, motion: object.motion)
    }

    private func keeperState(lighting: WorldLighting, phase: TimeInterval) -> KeeperState {
        if celebration != nil { return .celebrating }
        if lighting == .night { return Int(phase / 12).isMultiple(of: 2) ? .sleeping : .sitting }
        switch Int(phase / 8) % 6 {
        case 1: return .looking
        case 2: return .walking
        case 3: return .reading
        case 4 where unlockedRewardIDs.contains("small-plant"): return .watering
        case 5 where unlockedRewardIDs.contains("cabin"): return .carrying
        default: return .idle
        }
    }

    @ViewBuilder private func worldBackground(_ lighting: WorldLighting) -> some View {
        switch lighting {
        case .day: LinearGradient(colors: [Color(red: 0.52, green: 0.78, blue: 0.91), Color(red: 0.82, green: 0.91, blue: 0.75)], startPoint: .top, endPoint: .bottom)
        case .evening: LinearGradient(colors: [Color(red: 0.35, green: 0.35, blue: 0.60), Color(red: 0.94, green: 0.62, blue: 0.38)], startPoint: .top, endPoint: .bottom)
        case .night: LinearGradient(colors: [Color.tenoraInk, Color(red: 0.10, green: 0.22, blue: 0.28)], startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private func lightingOverlay(_ lighting: WorldLighting) -> some View {
        switch lighting {
        case .day: Color.clear
        case .evening: Color.orange.opacity(0.07).blendMode(.softLight).allowsHitTesting(false)
        case .night: Color.indigo.opacity(0.18).blendMode(.multiply).allowsHitTesting(false)
        }
    }
}

private struct WorldSpriteView: View {
    let object: WorldObjectPlacement
    let size: CGSize
    let phase: TimeInterval
    let reduceMotion: Bool
    var body: some View {
        let width = size.width * object.width
        let height = size.height * object.height
        Image(object.assetName).resizable().scaledToFit()
            .frame(width: width, height: height, alignment: .bottom)
            .rotationEffect(.degrees(rotation)).scaleEffect(scale, anchor: .bottom).offset(y: verticalOffset)
            .position(x: size.width * object.x, y: size.height * object.y - height / 2)
            .accessibilityHidden(true)
    }
    private var rotation: Double { !reduceMotion && object.motion == .sway ? sin(phase * 1.25 + object.x * 9) * 1.2 : 0 }
    private var verticalOffset: CGFloat { !reduceMotion && object.motion == .float ? CGFloat(sin(phase * 1.6 + object.x * 8) * 3.5) : 0 }
    private var scale: CGFloat { !reduceMotion && object.motion == .pulse ? 1 + CGFloat(sin(phase * 1.8) * 0.025) : 1 }
}

private struct KeeperSpriteView: View {
    let state: KeeperState
    let phase: TimeInterval
    let reduceMotion: Bool
    var body: some View {
        let frames = state.frames
        let index = reduceMotion ? 0 : Int(phase * 2.2) % frames.count
        Image(frames[index]).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).accessibilityHidden(true)
    }
}

private struct WorldCelebrationEffect: View {
    let phase: TimeInterval
    let reduceMotion: Bool
    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<7, id: \.self) { index in
                Image(index.isMultiple(of: 2) ? "effect_sparkle_01" : "effect_star").resizable().scaledToFit()
                    .frame(width: CGFloat(18 + (index % 3) * 6))
                    .position(x: proxy.size.width * (0.20 + CGFloat(index) * 0.10), y: proxy.size.height * (0.22 + CGFloat(index % 3) * 0.12))
                    .scaleEffect(reduceMotion ? 1 : 0.86 + CGFloat(sin(phase * 3 + Double(index))) * 0.16)
                    .opacity(reduceMotion ? 0.9 : 0.65 + sin(phase * 2.5 + Double(index)) * 0.25)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

#if DEBUG
private func previewUnlocks(through level: Int) -> Set<String> { Set(HabitRewardCatalog.all.filter { $0.levelRequired <= level }.map(\.id)) }
#Preview("World · Stage 1") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 1), level: 1).padding() }
#Preview("World · Stage 2") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 8), level: 8).padding() }
#Preview("World · Stage 3") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 16), level: 16).padding() }
#Preview("World · Stage 4") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 25), level: 25).padding() }
#Preview("World · Stage 5") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 50), level: 50).padding() }
#Preview("World · Spring") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 15), level: 15, seasonOverride: .spring).padding() }
#Preview("World · Summer") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 15), level: 15, seasonOverride: .summer).padding() }
#Preview("World · Fall") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 15), level: 15, seasonOverride: .fall).padding() }
#Preview("World · Winter") { HabitWorldView(unlockedRewardIDs: previewUnlocks(through: 15), level: 15, seasonOverride: .winter).padding() }
#endif
