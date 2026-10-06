import SwiftUI

struct HabitIconOption: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
}

enum HabitIconCatalog {
    static let all: [HabitIconOption] = [
        .init(id: "habit_icon_water", title: "Water", category: "Health"),
        .init(id: "habit_icon_medication", title: "Medication", category: "Health"),
        .init(id: "habit_icon_exercise", title: "Exercise", category: "Health"),
        .init(id: "habit_icon_walk", title: "Walk", category: "Health"),
        .init(id: "habit_icon_sleep", title: "Sleep", category: "Health"),
        .init(id: "habit_icon_stretch", title: "Stretch", category: "Wellness"),
        .init(id: "habit_icon_meditate", title: "Meditate", category: "Wellness"),
        .init(id: "habit_icon_breathe", title: "Breathe", category: "Wellness"),
        .init(id: "habit_icon_therapy", title: "Therapy", category: "Wellness"),
        .init(id: "habit_icon_reflection", title: "Reflection", category: "Wellness"),
        .init(id: "habit_icon_food", title: "Nutrition", category: "Nutrition"),
        .init(id: "habit_icon_vitamins", title: "Vitamins", category: "Nutrition"),
        .init(id: "habit_icon_bible", title: "Bible", category: "Faith"),
        .init(id: "habit_icon_prayer", title: "Prayer", category: "Faith"),
        .init(id: "habit_icon_church", title: "Church", category: "Faith"),
        .init(id: "habit_icon_study", title: "Study", category: "Learning"),
        .init(id: "habit_icon_service", title: "Service", category: "Connection"),
        .init(id: "habit_icon_book", title: "Read", category: "Learning"),
        .init(id: "habit_icon_journal", title: "Journal", category: "Learning"),
        .init(id: "habit_icon_language", title: "Language", category: "Learning"),
        .init(id: "habit_icon_music", title: "Music", category: "Learning"),
        .init(id: "habit_icon_dishes", title: "Dishes", category: "Home"),
        .init(id: "habit_icon_laundry", title: "Laundry", category: "Home"),
        .init(id: "habit_icon_cleaning", title: "Cleaning", category: "Home"),
        .init(id: "habit_icon_trash", title: "Trash", category: "Home"),
        .init(id: "habit_icon_organize", title: "Organize", category: "Home"),
        .init(id: "habit_icon_hygiene", title: "Hygiene", category: "Personal"),
        .init(id: "habit_icon_skincare", title: "Skincare", category: "Personal"),
        .init(id: "habit_icon_call", title: "Call", category: "Connection"),
        .init(id: "habit_icon_finances", title: "Finances", category: "Management"),
        .init(id: "habit_icon_planning", title: "Planning", category: "Management"),
        .init(id: "habit_icon_writing", title: "Writing", category: "Learning"),
        .init(id: "habit_icon_connection", title: "Connect", category: "Connection"),
        .init(id: "habit_icon_home", title: "Home", category: "Home"),
        .init(id: "habit_icon_laptop", title: "Computer", category: "Management"),
        .init(id: "habit_icon_gratitude", title: "Gratitude", category: "Wellness")
    ]

    static func title(for id: String) -> String {
        all.first(where: { $0.id == id })?.title
            ?? id.replacingOccurrences(of: "habit_icon_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct HabitArtworkView: View {
    let iconName: String
    var size: CGFloat = 46
    var tint: Color = .tenoraForest
    var completed = false

    var body: some View {
        Group {
            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(tint)
            } else if iconName.hasPrefix("habit_icon_") {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProductionArtworkView: View {
    let assetName: String?
    let fallbackSymbol: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let assetName {
                Image(assetName).resizable().scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(TenoraTheme.accentGradient)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
