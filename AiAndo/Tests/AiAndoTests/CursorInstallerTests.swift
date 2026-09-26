import XCTest
@testable import AiAndo

final class CursorInstallerTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AiAndo-tests-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("source/AiAndo.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("# hook fixture".utf8).write(to: resources.appendingPathComponent("prompt-mirror.py"))
        return (root, bundle)
    }

    func testInstallPreservesOtherHooksAndIsIdempotent() throws {
        let (root, bundle) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = CursorInstaller(home: root.appendingPathComponent("home with spaces"))
        try FileManager.default.createDirectory(at: installer.hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{\"version\":1,\"custom\":true,\"hooks\":{\"beforeSubmitPrompt\":[{\"command\":\"other-hook\"},{\"command\":\"python3 another-tool/prompt-mirror.py\"},{\"command\":\"python3 prompt-overlay/hooks/prompt-mirror.py\"}],\"unknownEvent\":[{\"command\":\"keep-me\"}]}}".utf8)
        try original.write(to: installer.hooksURL)
        try installer.install(bundle: bundle)
        try installer.install(bundle: bundle)
        XCTAssertTrue(installer.isInstalled)
        let rootJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.hooksURL)) as? [String: Any])
        XCTAssertEqual(rootJSON["custom"] as? Bool, true)
        let hooks = try XCTUnwrap(rootJSON["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(hooks["beforeSubmitPrompt"]?.count, 3)
        XCTAssertEqual(hooks["beforeSubmitPrompt"]?.first?["command"] as? String, "other-hook")
        XCTAssertEqual(hooks["unknownEvent"]?.first?["command"] as? String, "keep-me")
        XCTAssertTrue(installer.command.contains("home with spaces"))
        let files = try FileManager.default.contentsOfDirectory(atPath: installer.hooksURL.deletingLastPathComponent().path)
        let backup = try XCTUnwrap(files.first { $0.hasPrefix("hooks.aiando-backup-") })
        let backups = try files.filter { $0.hasPrefix("hooks.aiando-backup-") }.map {
            try Data(contentsOf: installer.hooksURL.deletingLastPathComponent().appendingPathComponent($0))
        }
        XCTAssertFalse(backup.isEmpty)
        XCTAssertTrue(backups.contains(original))
    }

    func testMalformedConfigurationIsNeverOverwritten() throws {
        let (root, bundle) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = CursorInstaller(home: root.appendingPathComponent("home"))
        try FileManager.default.createDirectory(at: installer.hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("{ broken config".utf8)
        try invalid.write(to: installer.hooksURL)
        XCTAssertThrowsError(try installer.install(bundle: bundle))
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL), invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }
}
