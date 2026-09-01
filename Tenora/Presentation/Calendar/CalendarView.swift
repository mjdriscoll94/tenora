import SwiftUI

struct CalendarView: View {
    var body: some View {
        ContentUnavailableView(
            "Calendar not connected",
            systemImage: "calendar",
            description: Text("Calendar access arrives in the next foundation phase.")
        )
        .navigationTitle("Calendar")
    }
}

