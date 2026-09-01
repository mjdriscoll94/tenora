import SwiftUI

struct TodayView: View {
    var body: some View {
        ContentUnavailableView(
            "Your day, held in place",
            systemImage: "sun.max",
            description: Text("Tenora will bring the right task forward here.")
        )
        .navigationTitle("Today")
    }
}

