import Foundation
import UserNotifications

enum DailyReminders {
    static func enable(hour: Int, minute: Int) async throws {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { throw LocalStoreError.invalidTime }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw LocalStoreError.permission }
        let store = OwnStore()
        try store.setReminder(hour: hour, minute: minute)
        LessonNotice.cancel()
        let lessons = try store.daily()
        if !lessons.isEmpty, let request = LessonNotice.request(for: Date(), hour: hour, minute: minute, lessons: lessons) {
            try await center.add(request)
        }
    }

    static func disable() throws {
        try OwnStore().clearReminder()
        LessonNotice.cancel()
    }

    static func settings() throws -> (hour: Int, minute: Int)? { try OwnStore().reminderTime() }
}
