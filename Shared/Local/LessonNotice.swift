import Foundation
import UserNotifications

enum LessonNotice {
    private static let id = "ownphrase.daily-lesson"

    // One privacy-preserving reminder for the current learning day. Late writing stays in the day's report.
    static func request(for date: Date, hour: Int, minute: Int, lessons: [DailyLesson] = []) -> UNNotificationRequest? {
        let calendar = Calendar.current
        guard let next = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date),
              next > date, calendar.isDate(next, inSameDayAs: date) else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Your daily writing lesson"
        content.body = summary(lessons)
        content.sound = .default
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    private static func summary(_ lessons: [DailyLesson]) -> String {
        guard let first = lessons.first else { return "Open Ownphrase to review today’s writing patterns." }
        // Only allow fixed labels into lock-screen text. The source and model output can contain private details.
        for word in Observation.guidance.keys where first.id == "vocabulary/" + word {
            return "You used “\(word)” \(first.count) times today. Explore when to keep it and when another word might fit."
        }
        let knownTopics = [("grammar/didBase", "verb forms after “didn’t”"), ("grammar/massNoun", "uncountable nouns"),
                           ("preposition", "prepositions"), ("subject–verb", "subject–verb agreement"),
                           ("subject-verb", "subject–verb agreement"), ("article", "articles"),
                           ("verb tense", "verb tense"), ("punctuation", "punctuation")]
        if let topic = knownTopics.first(where: { first.id.contains($0.0) }) {
            return "Today’s lesson covers " + topic.1 + ". Open Ownphrase to review."
        }
        return lessons.count == 1 ? "One writing pattern is ready to review." : "\(lessons.count) writing patterns are ready to review."
    }

    static func schedule(for date: Date, hour: Int, minute: Int, lessons: [DailyLesson]) {
        guard let request = request(for: date, hour: hour, minute: minute, lessons: lessons) else { return }
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
