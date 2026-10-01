import SwiftUI

struct HabitCollectionView: View {
    @EnvironmentObject private var store: HabitStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HabitWorldView(unlockedRewardIDs: store.rewardIDs)
                collectionSection("WORLD UPGRADES") {
                    ForEach(HabitRewardCatalog.all) { reward in rewardRow(reward) }
                }
                collectionSection("ACHIEVEMENTS") {
                    ForEach(HabitAchievementEngine.all) { achievement in achievementRow(achievement) }
                }
                collectionSection("MILESTONES") {
                    milestone("Total XP", value: "\(store.progress.totalXP)", symbol: "sparkles")
                    milestone("Completions", value: "\(store.progress.totalCompletions)", symbol: "checkmark.circle.fill")
                    milestone("Longest Momentum", value: "\(store.progress.longestMomentum) days", symbol: "flame.fill")
                    milestone("Perfect Days", value: "\(store.progress.perfectDays)", symbol: "sun.max.fill")
                }
            }.padding()
        }.background(TenoraScreenBackground()).navigationTitle("Your Collection")
    }

    private func collectionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
            VStack(spacing: 0) { content() }.padding(.horizontal).tenoraCard(cornerRadius: 18)
        }
    }

    private func rewardRow(_ reward: GameReward) -> some View {
        let unlocked = store.rewardIDs.contains(reward.id)
        return HStack(spacing: 14) {
            Image(systemName: unlocked ? reward.symbol : "questionmark").font(.title3).foregroundStyle(unlocked ? Color.tenoraForest : .secondary)
                .frame(width: 36, height: 36).background(Color.tenoraSage.opacity(unlocked ? 0.20 : 0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(unlocked ? reward.title : "Level \(reward.levelRequired) · ???").font(.body.weight(.semibold))
                Text(unlocked ? reward.detail : "New world upgrade").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if unlocked { Image(systemName: "checkmark").foregroundStyle(Color.tenoraForest) }
        }.padding(.vertical, 11).accessibilityElement(children: .combine)
    }

    private func achievementRow(_ achievement: HabitAchievement) -> some View {
        let unlocked = store.achievementIDs.contains(achievement.id)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(unlocked ? TenoraTheme.accentGradient : LinearGradient(colors: [.gray.opacity(0.20)], startPoint: .top, endPoint: .bottom)).frame(width: 42, height: 42)
                Image(systemName: achievement.symbol).foregroundStyle(unlocked ? .white : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title).font(.body.weight(.semibold))
                Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill").foregroundStyle(unlocked ? Color.tenoraForest : .secondary)
        }.padding(.vertical, 11).opacity(unlocked ? 1 : 0.68).accessibilityElement(children: .combine)
    }

    private func milestone(_ title: String, value: String, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Text(value).fontWeight(.semibold) }.padding(.vertical, 11)
    }
}
