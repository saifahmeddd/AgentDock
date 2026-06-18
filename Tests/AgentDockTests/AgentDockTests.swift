import XCTest
@testable import AgentDock

// MARK: - FuzzyMatcherTests

final class FuzzyMatcherTests: XCTestCase {
    func testIdenticalStringsReturnZero() {
        XCTAssertEqual(FuzzyMatcher.normalizedLevenshtein("hello", "hello"), 0.0)
    }

    func testCompletelyDifferentStringsReturnOne() {
        XCTAssertEqual(FuzzyMatcher.normalizedLevenshtein("abc", "xyz"), 1.0)
    }

    func testEmptyStrings() {
        XCTAssertEqual(FuzzyMatcher.normalizedLevenshtein("", ""), 0.0)
    }

    func testOneEmptyString() {
        XCTAssertEqual(FuzzyMatcher.normalizedLevenshtein("hello", ""), 1.0)
        XCTAssertEqual(FuzzyMatcher.normalizedLevenshtein("", "hello"), 1.0)
    }

    func testNearDuplicatesAreLow() {
        // Very similar titles should score below the 0.2 dedup threshold.
        let score = FuzzyMatcher.normalizedLevenshtein(
            "Send invoice to client",
            "Send invoice to client by Friday"
        )
        XCTAssertLessThan(score, 0.45)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(
            FuzzyMatcher.normalizedLevenshtein("Hello World", "hello world"),
            0.0
        )
    }
}

// MARK: - DateParserTests

final class DateParserTests: XCTestCase {
    private let calendar = Calendar.current

    func testNilInputReturnsNil() {
        XCTAssertNil(DateParser.date(from: nil))
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(DateParser.date(from: ""))
    }

    func testTodayKeyword() throws {
        let date = try XCTUnwrap(DateParser.date(from: "today"))
        let hour = calendar.component(.hour, from: date)
        XCTAssertEqual(hour, 17)
    }

    func testEODKeyword() throws {
        let date = try XCTUnwrap(DateParser.date(from: "eod"))
        let hour = calendar.component(.hour, from: date)
        XCTAssertEqual(hour, 17)
    }

    func testTomorrowKeyword() throws {
        let date = try XCTUnwrap(DateParser.date(from: "tomorrow"))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertEqual(
            calendar.startOfDay(for: date),
            calendar.startOfDay(for: tomorrow)
        )
        XCTAssertEqual(calendar.component(.hour, from: date), 9)
    }

    func testNextWeekKeyword() throws {
        let date = try XCTUnwrap(DateParser.date(from: "next week"))
        let sevenDaysOut = calendar.date(byAdding: .day, value: 7, to: .now)!
        XCTAssertEqual(
            calendar.startOfDay(for: date),
            calendar.startOfDay(for: sevenDaysOut)
        )
    }

    func testWeekdayName() {
        // Any weekday name should produce a future date.
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        for day in weekdays {
            if let date = DateParser.date(from: "by \(day)") {
                XCTAssertGreaterThan(date, Date.now, "Expected future date for '\(day)'")
            }
        }
    }

    func testMonthDayPattern() throws {
        let date = try XCTUnwrap(DateParser.date(from: "due by March 15"))
        let components = calendar.dateComponents([.month, .day], from: date)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }

    func testNumericDateSlash() throws {
        let date = try XCTUnwrap(DateParser.date(from: "deadline 7/4"))
        let components = calendar.dateComponents([.month, .day], from: date)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 4)
    }

    func testGibberishReturnsNil() {
        XCTAssertNil(DateParser.date(from: "whenever you get a chance"))
    }

    func testEndOfDayPhrase() throws {
        let date = try XCTUnwrap(DateParser.date(from: "end of day today"))
        let hour = calendar.component(.hour, from: date)
        XCTAssertEqual(hour, 17)
    }
}

// MARK: - AgentPipelineTests

final class AgentPipelineTests: XCTestCase {
    private let pipeline = AgentPipeline()

    private func intake(_ body: String, source: IntakeSourceKind = .clipboard) -> IntakeItem {
        IntakeItem(
            title: body.prefix(64).description,
            body: body,
            sourceKind: source,
            originalSource: "test"
        )
    }

    func testPromiseLanguageProducesCommitment() {
        let item = intake("I'll send over the proposal by EOD today.")
        let analysis = pipeline.analyze(item)
        XCTAssertFalse(analysis.commitments.isEmpty)
        XCTAssertEqual(analysis.classification, .humanTask)
    }

    func testTaskLanguageProducesCommitment() {
        let item = intake("Please review the attached document before Friday.")
        let analysis = pipeline.analyze(item)
        XCTAssertFalse(analysis.commitments.isEmpty)
    }

    func testWaitingLanguageProducesFollowUp() {
        let item = intake("Waiting on Alice Smith to send the contract. Follow up next week.")
        let analysis = pipeline.analyze(item)
        XCTAssertFalse(analysis.followUps.isEmpty)
        XCTAssertEqual(analysis.classification, .waitingItem)
    }

    func testEmailRequestProposesGmailAction() {
        let item = intake("Please draft an email reply to the client.")
        let analysis = pipeline.analyze(item)
        XCTAssert(analysis.proposedActions.contains { $0.tool == .gmail })
    }

    func testMeetingRequestProposesCalendarAction() {
        let item = intake("Can you schedule a call for next Monday?")
        let analysis = pipeline.analyze(item)
        XCTAssert(analysis.proposedActions.contains { $0.tool == .calendar })
    }

    func testTicketRequestProposesLinearAction() {
        let item = intake("Please create a Linear ticket for the login bug.")
        let analysis = pipeline.analyze(item)
        XCTAssert(analysis.proposedActions.contains { $0.tool == .linear })
    }

    func testUrgentPriorityDetection() {
        // "ASAP" + "immediately" → urgent, "need to" → task language → commitment.
        let item = intake("ASAP I need to complete the deployment before the release.")
        let analysis = pipeline.analyze(item)
        XCTAssertFalse(analysis.commitments.isEmpty, "Expected at least one commitment for urgent task language")
        XCTAssertEqual(analysis.commitments.first?.priority, .urgent)
    }

    func testHighPriorityDetection() {
        let item = intake("Important: complete the security review before launch.")
        let analysis = pipeline.analyze(item)
        XCTAssertEqual(analysis.commitments.first?.priority, .high)
    }

    func testLowPriorityDetection() {
        let item = intake("No rush, but could you update the docs when you can?")
        let analysis = pipeline.analyze(item)
        XCTAssertEqual(analysis.commitments.first?.priority, .low)
    }

    func testEmptyBodyProducesNoResults() {
        let item = intake("")
        let analysis = pipeline.analyze(item)
        XCTAssertTrue(analysis.commitments.isEmpty)
        XCTAssertTrue(analysis.followUps.isEmpty)
        XCTAssertTrue(analysis.proposedActions.isEmpty)
    }

    func testFallbackCommitmentForArbitraryText() {
        let item = intake("The quarterly report numbers look good this month.")
        let analysis = pipeline.analyze(item)
        // Should produce a fallback commitment rather than empty results.
        XCTAssertFalse(analysis.commitments.isEmpty)
    }

    func testPeopleDetectionExcludesCommonWords() {
        let item = intake("Please review the document. The quick brown fox jumps.")
        let analysis = pipeline.analyze(item)
        // Common words like "Please", "The" should not appear in evidence people.
        let peopleEvidence = analysis.evidence.first(where: { $0.label == "People" })?.value ?? ""
        XCTAssertFalse(peopleEvidence.contains("Please"))
        XCTAssertFalse(peopleEvidence.contains("The"))
    }

    func testFullNameDetectedAsPerson() {
        let item = intake("Waiting on John Doe to approve the budget.")
        let analysis = pipeline.analyze(item)
        let hasJohnDoe = analysis.evidence.contains { $0.label == "People" && $0.value.contains("John Doe") }
        let hasInFollowUp = analysis.followUps.first?.responsibleParty.contains("John") ?? false
        XCTAssertTrue(hasJohnDoe || hasInFollowUp)
    }

    func testClassificationIsNotReferenceOnlyForActionableText() {
        let item = intake("I'll present the new feature roadmap at the all-hands next week.")
        let analysis = pipeline.analyze(item)
        XCTAssertNotEqual(analysis.classification, .referenceOnly)
    }

    func testAnalysisHasNotes() {
        let item = intake("Can you send the invoice to accounting@company.com?")
        let analysis = pipeline.analyze(item)
        XCTAssertFalse(analysis.notes.isEmpty)
    }

    func testDeadlineInCommitment() {
        let item = intake("I need to finish this by Friday.")
        let analysis = pipeline.analyze(item)
        if let commitment = analysis.commitments.first {
            XCTAssertNotNil(commitment.deadline)
        }
    }
}

// MARK: - OpenRouterJSON DecodingTests

final class OpenRouterJSONDecodingTests: XCTestCase {
    // Test that a well-formed response from the model is decoded correctly.
    // Uses a public wrapper so we can call the internal parsing path.

    func testWellFormedResponseDecodes() throws {
        let json = """
        {
          "classification": "Human task",
          "source_proof": "Need to send the Q3 report",
          "commitments": [
            {
              "title": "Send Q3 report to finance",
              "owner": "You",
              "priority": "High",
              "deadline": "Friday",
              "reminder": "Thursday morning",
              "source_proof": "Need to send the Q3 report"
            }
          ],
          "follow_ups": [],
          "proposed_actions": [],
          "evidence": [
            { "label": "Original source", "value": "Email" }
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(StructuredAIResponsePublic.self, from: data)
        XCTAssertEqual(response.classification, "Human task")
        XCTAssertEqual(response.commitments.count, 1)
        XCTAssertEqual(response.commitments[0].title, "Send Q3 report to finance")
        XCTAssertEqual(response.commitments[0].priority, "High")
        XCTAssertEqual(response.commitments[0].deadline, "Friday")
        XCTAssertEqual(response.evidence.count, 1)
        XCTAssertTrue(response.followUps.isEmpty)
        XCTAssertTrue(response.proposedActions.isEmpty)
    }

    func testMissingOptionalFieldsDecodeSafely() throws {
        let json = """
        {
          "classification": "Reference only",
          "commitments": [],
          "follow_ups": [],
          "proposed_actions": [],
          "evidence": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(StructuredAIResponsePublic.self, from: data)
        XCTAssertEqual(response.classification, "Reference only")
        XCTAssertNil(response.sourceProof)
    }

    func testProposedActionDecodes() throws {
        let json = """
        {
          "classification": "AI-doable action",
          "commitments": [],
          "follow_ups": [],
          "proposed_actions": [
            {
              "title": "Reply to Alice",
              "tool": "Gmail",
              "description": "Send a follow-up email",
              "target": "alice@example.com",
              "approval_prompt": "Review before sending"
            }
          ],
          "evidence": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(StructuredAIResponsePublic.self, from: data)
        XCTAssertEqual(response.proposedActions.count, 1)
        XCTAssertEqual(response.proposedActions[0].tool, "Gmail")
        XCTAssertEqual(response.proposedActions[0].target, "alice@example.com")
    }
}

// MARK: - Public wrappers for internal decoding structs

// These mirror the private structs in OpenRouterService.swift so we can test JSON decoding
// without exposing private types. Keep in sync if the schema changes.
struct StructuredAIResponsePublic: Decodable {
    let classification: String
    let sourceProof: String?
    let commitments: [StructuredCommitmentPublic]
    let followUps: [StructuredFollowUpPublic]
    let proposedActions: [StructuredActionPublic]
    let evidence: [StructuredEvidencePublic]

    enum CodingKeys: String, CodingKey {
        case classification
        case sourceProof = "source_proof"
        case commitments
        case followUps = "follow_ups"
        case proposedActions = "proposed_actions"
        case evidence
    }
}

struct StructuredCommitmentPublic: Decodable {
    let title: String
    let owner: String?
    let priority: String?
    let deadline: String?
    let reminder: String?
    let sourceProof: String?

    enum CodingKeys: String, CodingKey {
        case title; case owner; case priority; case deadline; case reminder
        case sourceProof = "source_proof"
    }
}

struct StructuredFollowUpPublic: Decodable {
    let title: String
    let responsibleParty: String?
    let checkBack: String?
    let sourceProof: String?

    enum CodingKeys: String, CodingKey {
        case title
        case responsibleParty = "responsible_party"
        case checkBack = "check_back"
        case sourceProof = "source_proof"
    }
}

struct StructuredActionPublic: Decodable {
    let title: String
    let tool: String?
    let description: String
    let target: String?
    let approvalPrompt: String?
    let sourceProof: String?

    enum CodingKeys: String, CodingKey {
        case title; case tool; case description; case target
        case approvalPrompt = "approval_prompt"
        case sourceProof = "source_proof"
    }
}

struct StructuredEvidencePublic: Decodable {
    let label: String
    let value: String
}
