import XCTest
@testable import TripJournal

@MainActor final class AttachmentTests: XCTestCase {
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testOriginalBytesSurviveRestartAndExportIsComplete() async throws {
        let directory = try root(), vault = try AttachmentStore(directory: directory.appending(path: "vault"))
        let original = Data("%PDF-1.4\nprivate original ticket\n%%EOF".utf8)
        let source = directory.appending(path: "my-ticket.pdf"); try original.write(to: source)
        let file = try await vault.importFile(source)
        let reopened = try AttachmentStore(directory: directory.appending(path: "vault"))
        let loaded = try await reopened.data(for: file)
        XCTAssertEqual(original, loaded)
        var ticket = Ticket(); ticket.title = "Ticket"; ticket.reference = "<script>bad</script>"; ticket.files = [file]
        let url = try await reopened.export(ticket: ticket, place: "Gardens")
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains(original.base64EncodedString()))
        XCTAssertFalse(html.contains("<script>bad</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;bad&lt;/script&gt;"))
    }
    func testCorruptionAndMissingFilesNeverExportPartialTicket() async throws {
        let directory = try root(), vault = try AttachmentStore(directory: directory)
        let data = Data("%PDF-1.4\noriginal\n%%EOF".utf8)
        let file = TicketFile(id: AttachmentStore.hash(data), name: "ticket.pdf", type: "application/pdf", size: data.count)
        try await vault.save(data, as: file)
        let path = try await vault.verifiedURL(for: file)
        var altered = data; altered[10] = 99; try altered.write(to: path)
        let available = await vault.available(file); XCTAssertFalse(available)
        var ticket = Ticket(); ticket.title = "bad"; ticket.files = [file]
        do { _ = try await vault.export(ticket: ticket, place: "Test"); XCTFail("Corrupt export must fail") } catch { }
        do { try await vault.save(altered, as: file); XCTFail("Hash mismatch must fail") } catch { }
        let traversal = TicketFile(id: "../../outside", name: "x", type: "application/pdf", size: data.count)
        do { _ = try await vault.verifiedURL(for: traversal); XCTFail("Unsafe identifier") } catch { }
    }
    func testTicketFormDraftSurvivesWorkspaceRestart() throws {
        let directory = try root(), content = try ContentCatalog.load()
        let store = try TripStore(content: content, directory: directory, useKeychain: false)
        var ticket = Ticket(); ticket.title = "Draft before booking"
        store.saveTicketDraft(ticket, placeID: TestTrip.otherPlace)
        let reopened = try TripStore(content: content, directory: directory, useKeychain: false)
        XCTAssertEqual(reopened.ticketDrafts.first?.ticket, ticket)
        XCTAssertNil(reopened.plan.tickets?[TestTrip.otherPlace])
        reopened.discardTicketDraft(ticket.id)
        let discarded = try TripStore(content: content, directory: directory, useKeychain: false)
        XCTAssertTrue(discarded.ticketDrafts.isEmpty)
    }
}
