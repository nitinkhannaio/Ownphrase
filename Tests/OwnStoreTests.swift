import XCTest
@testable import Ownphrase

final class OwnStoreTests: XCTestCase {
    private var folder: URL!
    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        try super.tearDownWithError()
    }

    func testAcceptedChoicesAndRecurringLessonsDoNotCountDuplicateDraftAsNewEvidence() throws {
        let store = OwnStore(directory: folder)
        let option = RewriteOption(text: "We are here.", lesson: "Agreement — Match the verb to its subject.",
                                   preference: "Uses direct openings", context: "work")
        try store.record(original: "We is here.", accepted: option)
        try store.record(original: "We is here.", accepted: option)
        XCTAssertTrue(try store.profile().contains("one example, tentative"))
        try store.record(original: "They is ready.", accepted: RewriteOption(text: "They are ready.",
            lesson: "Agreement — A plural subject takes a plural verb.", preference: "Uses direct openings", context: "Work"))
        XCTAssertTrue(try store.profile().contains("2 distinct drafts"))
        XCTAssertFalse(try store.profile().contains("They is ready."))
        XCTAssertEqual(try store.history().first?.original, "They is ready.")
        XCTAssertEqual(try store.daily().first?.count, 2)
        XCTAssertEqual(try store.daily().first?.corrected, "They are ready.")
        XCTAssertEqual(try store.daily(on: Date(timeIntervalSinceNow: -86400)).count, 0)
    }

    func testOrdinaryWritingStoresOnlyCountersAndDisableStopsLearning() throws {
        let store = OwnStore(directory: folder)
        try store.observe("So I just met Secretname and I'm so happy.")
        try store.observe("So I'm glad to hear.")
        try store.observe("So I'm glad it worked.")
        XCTAssertEqual(try store.history().count, 0)
        XCTAssertEqual(try store.daily().first?.id, "vocabulary/so")
        XCTAssertEqual(try store.daily().first?.count, 4)
        XCTAssertTrue(try store.profile().contains("3 clear contractions"))
        XCTAssertFalse(try store.profile().contains("Secretname"))
        let database = try Data(contentsOf: folder.appendingPathComponent("writing.sqlite"))
        XCTAssertNil(database.range(of: Data("Secretname".utf8)))
        try store.setObservationEnabled(false)
        try store.observe("So you are so kind.")
        XCTAssertEqual(try store.daily().first?.count, 4)
        try store.erase()
        XCTAssertTrue(try store.profile().isEmpty)
        XCTAssertTrue(try store.daily().isEmpty)
        XCTAssertFalse(try store.observationEnabled())
    }

    func testConcurrentObservationTransactionsAcrossIndependentClients() async throws {
        let directory = try XCTUnwrap(folder)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { try OwnStore(directory: directory).observe("So that works.") }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(try OwnStore(directory: directory).daily().first?.count, 12)
    }

    func testStyleOnlyChoicesProduceNoGrammarLessonAndErasureClearsPairs() throws {
        let store = OwnStore(directory: folder)
        try store.record(original: "Hello!", accepted: RewriteOption(text: "Hey!", lesson: "", preference: "informal greeting", context: "casual"))
        XCTAssertTrue(try store.daily().isEmpty)
        try store.erase()
        XCTAssertTrue(try store.history().isEmpty)
        XCTAssertTrue(try store.profile().isEmpty)
    }

    func testOrdinaryGrammarLessonsDoNotStoreRawWritingOrClassifyPrepositionsByFrequency() throws {
        let store = OwnStore(directory: folder)
        try store.observe("I didn’t went to the cafe.")
        try store.observe("I need an advice about the project.")
        try store.observe("I am in the school. Please wait at school.")
        XCTAssertEqual(Set(try store.daily().map(\.id)), ["grammar/didBase", "grammar/massNoun"])
        XCTAssertTrue(try store.history().isEmpty)
        XCTAssertTrue(try store.daily().allSatisfy { $0.original.isEmpty })
    }

    func testReflectionRequiresIndependentEvidenceAndNeverRestoresAnErasedOrDisabledGeneration() throws {
        let store = OwnStore(directory: folder)
        let generation = try XCTUnwrap(store.beginReflection())
        let sameFile = OwnStore(directory: folder)
        XCTAssertEqual(try sameFile.beginReflection(), generation)
        func apply(_ evidence: String, generation: String) throws {
            try sameFile.recordReflection(trait: "uses affectionate greetings", context: "Family",
                                          evidence: evidence, generation: generation)
        }
        try apply("Dear SecretPerson!", generation: generation)
        try apply("Dear SecretPerson!", generation: generation)
        XCTAssertTrue(try store.profile().isEmpty)
        try apply("Hey SecretPerson!", generation: generation)
        XCTAssertTrue(try store.profile().contains("Observed family voice"))
        XCTAssertTrue(try store.profile().contains("2 distinct passages"))
        let data = try Data(contentsOf: folder.appendingPathComponent("writing.sqlite"))
        XCTAssertNil(data.range(of: Data("SecretPerson".utf8)))
        try store.setObservationEnabled(false)
        XCTAssertNil(try store.beginReflection())
        try store.setObservationEnabled(true)
        let newGeneration = try XCTUnwrap(store.beginReflection())
        XCTAssertNotEqual(newGeneration, generation)
        try apply("Another unique message", generation: generation)
        XCTAssertTrue(try store.profile().contains("2 distinct passages"))
        try store.erase()
        let cleared = try XCTUnwrap(store.beginReflection())
        XCTAssertNotEqual(newGeneration, cleared)
        try apply("One late result", generation: newGeneration)
        try apply("A second late result", generation: newGeneration)
        XCTAssertTrue(try store.profile().isEmpty)
    }

    func testReminderOnlyTargetsUpcomingTimeOnEvidenceDay() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let request = try XCTUnwrap(LessonNotice.request(for: day, hour: 19, minute: 0))
        XCTAssertFalse(request.content.body.contains("original"))
        let privateLesson = DailyLesson(id: "prepositions confidential sample", lesson: "My secret message", count: 2,
                                        original: "secret original", corrected: "secret correction")
        let preview = try XCTUnwrap(LessonNotice.request(for: day, hour: 19, minute: 0, lessons: [privateLesson]))
        XCTAssertTrue(preview.content.body.contains("prepositions"))
        XCTAssertFalse(preview.content.body.contains("confidential"))
        XCTAssertFalse(preview.content.body.contains("secret"))
        let late = try XCTUnwrap(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: day))
        XCTAssertNil(LessonNotice.request(for: late, hour: 19, minute: 0))
    }
}
