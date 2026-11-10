import Foundation
import Testing
@testable import CachePop

@Suite("Safari, Mail, device logs, login items, AI models and snapshots")
struct MoreCleanupTests {
    // MARK: Safari

    @Test func safariCacheIsOfferedOnItsOwnAndBlockedWhileSafariIsOpen() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.apple.Safari/WebKitCache/blob", bytes: 50_000)

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let safari = try #require(group.item("general.safariCache"))
        #expect(safari.isRecommended)
        #expect(!safari.isBlocked)
        #expect(safari.defaultAction.operation.paths == [canonical(fixture.url("Library/Caches/com.apple.Safari"))])
        #expect(group.item("general.appCaches") == nil, "Safari's cache isn't counted twice")

        let open = ProcessSnapshot(runningAppBundleIDs: ["com.apple.safari"])
        let whileOpen = GeneralScanner.scan(await fixture.context(fixture.environment(), processes: open))
        #expect(whileOpen.item("general.safariCache")?.isBlocked == true)
    }

    @Test func unreadableSafariCacheAsksForFullDiskAccess() async throws {
        let fixture = try Fixture()
        try fixture.file("Library/Caches/com.apple.Safari/Cache.db")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.url("Library/Caches/com.apple.Safari").path)

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let safari = try #require(group.item("general.safariCache"))
        #expect(safari.needsFullDiskAccess)
        #expect(safari.isBlocked)
    }

    // MARK: Mail

    @Test func mailAttachmentsKeepOnesYouEdited() async throws {
        let fixture = try Fixture()
        let base = "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        try fixture.file("\(base)/AAA/invoice.pdf", bytes: 40_000)
        let edited = try fixture.file("\(base)/BBB/draft.docx", bytes: 40_000)
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: edited.path)

        let group = GeneralScanner.scan(await fixture.context(fixture.environment()))

        let mail = try #require(group.item("general.mailAttachments"))
        #expect(mail.isRecommended)
        #expect(mail.defaultAction.operation.paths == [canonical(fixture.url("\(base)/AAA"))])
        #expect(mail.detail == "1 attachment · 1 you changed is kept")

        let open = ProcessSnapshot(runningAppBundleIDs: ["com.apple.mail"])
        let whileOpen = GeneralScanner.scan(await fixture.context(fixture.environment(), processes: open))
        #expect(whileOpen.item("general.mailAttachments")?.isBlocked == true)
    }

    @Test func onlyInsideMailDownloadsIsCleanable() throws {
        let fixture = try Fixture()
        let base = "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        let attachment = try fixture.dir("\(base)/AAA")
        let messages = try fixture.dir("Library/Containers/com.apple.mail/Data/Library/Mail/V10")

        #expect(PathSafety.violation(for: attachment, mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: fixture.url(base), mode: .delete, home: fixture.home) != nil)
        #expect(PathSafety.violation(for: messages, mode: .delete, home: fixture.home) != nil)
    }

    // MARK: Xcode device logs

    @Test func oldDeviceCrashLogsAreOffered() async throws {
        let fixture = try Fixture()
        let old = try fixture.file("Library/Developer/Xcode/DeviceLogs/iPhone-1/App-old.ips", bytes: 20_000, modified: daysAgo(30))
        try fixture.file("Library/Developer/Xcode/DeviceLogs/iPhone-1/App-new.ips", bytes: 20_000, modified: daysAgo(1))
        let legacy = try fixture.file("Library/Developer/Xcode/iOS Device Logs/App.crash", bytes: 20_000, modified: daysAgo(60))

        let group = XcodeScanner.scan(await fixture.context(fixture.environment()))

        let logs = try #require(group.item("xcode.deviceLogs"))
        #expect(logs.isRecommended)
        #expect(Set(logs.defaultAction.operation.paths) == [canonical(old), canonical(legacy)])
        #expect(logs.detail == "2 reports")
        #expect(PathSafety.violation(for: old, mode: .delete, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: legacy, mode: .delete, home: fixture.home) == nil)
    }

    // MARK: Broken login items

    @Test func brokenLoginItemsGoToTheTrash() async throws {
        let fixture = try Fixture()
        let agents = try fixture.dir("Library/LaunchAgents")
        let gone = agents.appendingPathComponent("com.gone.agent.plist")
        try writePlist(["Label": "com.gone.agent", "ProgramArguments": [fixture.url("Applications/Gone.app/Contents/MacOS/gone").path, "--run"]], to: gone)
        try writePlist(["Label": "com.works.agent", "Program": "/bin/ls"], to: agents.appendingPathComponent("com.works.agent.plist"))
        try writePlist(["Label": "com.external.agent", "Program": "/Volumes/External/tool"], to: agents.appendingPathComponent("com.external.agent.plist"))
        try writePlist(["Label": "com.relative.agent", "Program": "tool"], to: agents.appendingPathComponent("com.relative.agent.plist"))
        try writePlist([:], to: agents.appendingPathComponent("com.empty.agent.plist"))

        let group = await LeftoversScanner.scan(await fixture.context(fixture.environment()))

        let broken = try #require(group.item("leftovers.brokenLoginItems"))
        #expect(broken.isRecommended)
        #expect(broken.defaultAction.operation.paths == [canonical(gone)])
        #expect(broken.detail == "1 item · com.gone.agent")
        guard case .moveToTrash = broken.defaultAction.operation else { Issue.record("Login items must go to the Trash"); return }
        #expect(PathSafety.violation(for: gone, mode: .trash, home: fixture.home) == nil)
        #expect(PathSafety.violation(for: gone, mode: .delete, home: fixture.home) != nil)
    }

    // MARK: Ollama

    @Test func ollamaModelsKeepFilesOtherModelsShare() async throws {
        let fixture = try Fixture()
        let llama = try ollamaManifest(fixture, "registry.ollama.ai/library/llama3.2/3b", digests: ["sha256:aaa", "sha256:shared"])
        try ollamaManifest(fixture, "registry.ollama.ai/library/qwen3/8b", digests: ["sha256:bbb", "sha256:shared"])
        let own = try fixture.file(".ollama/models/blobs/sha256-aaa", bytes: 100_000)
        try fixture.file(".ollama/models/blobs/sha256-bbb", bytes: 200_000)
        try fixture.file(".ollama/models/blobs/sha256-shared", bytes: 50_000)
        let orphan = try fixture.file(".ollama/models/blobs/sha256-orphan", bytes: 30_000)
        let partial = try fixture.file(".ollama/models/blobs/sha256-ccc-partial", bytes: 10_000)

        let items = LocalModelsScanner.ollama(await fixture.context(fixture.environment()))

        let model = try #require(items.first { $0.id == "dev.ollama.llama3.2:3b" })
        #expect(model.title == "Ollama: llama3.2:3b")
        #expect(!model.isRecommended)
        #expect(model.defaultAction.regeneration == .redownloaded)
        #expect(Set(model.defaultAction.operation.paths) == [canonical(llama), canonical(own)])
        #expect(model.detail?.contains("shares") == true)

        let unused = try #require(items.first { $0.id == "dev.ollama.unused" })
        #expect(unused.isRecommended)
        #expect(Set(unused.defaultAction.operation.paths) == [canonical(orphan), canonical(partial)])
        #expect(PathSafety.violation(for: own, mode: .delete, home: fixture.home) == nil)

        let running = ProcessSnapshot(executableNames: ["ollama"])
        let whileRunning = LocalModelsScanner.ollama(await fixture.context(fixture.environment(), processes: running))
        let allBlocked = !whileRunning.isEmpty && whileRunning.allSatisfy { $0.isBlocked }
        #expect(allBlocked)
    }

    @Test func unreadableOllamaManifestKeepsEveryDownload() async throws {
        let fixture = try Fixture()
        try ollamaManifest(fixture, "registry.ollama.ai/library/llama3.2/3b", digests: ["sha256:aaa"])
        try fixture.file(".ollama/models/manifests/registry.ollama.ai/library/broken/latest", bytes: 10)
        try fixture.file(".ollama/models/blobs/sha256-aaa", bytes: 100_000)
        try fixture.file(".ollama/models/blobs/sha256-bbb", bytes: 100_000)

        let items = LocalModelsScanner.ollama(await fixture.context(fixture.environment()))

        #expect(items.contains { $0.id == "dev.ollama.llama3.2:3b" })
        #expect(!items.contains { $0.id == "dev.ollama.unused" }, "the unreadable model may be using them")
    }

    @Test func ollamaNamesFollowItsOwnStyle() {
        #expect(LocalModelsScanner.ollamaName(host: "registry.ollama.ai", namespace: "library", model: "llama3.2", tag: "3b") == "llama3.2:3b")
        #expect(LocalModelsScanner.ollamaName(host: "registry.ollama.ai", namespace: "jane", model: "tiny", tag: "latest") == "jane/tiny:latest")
        #expect(LocalModelsScanner.ollamaName(host: "hf.co", namespace: "bartowski", model: "Qwen3", tag: "Q4_K_M") == "hf.co/bartowski/Qwen3:Q4_K_M")
    }

    // MARK: LM Studio

    @Test func lmStudioModelsGetARowEachAndChatsStay() async throws {
        let fixture = try Fixture()
        let qwen = try fixture.file(".lmstudio/models/lmstudio-community/Qwen3-8B-GGUF/q4.gguf", bytes: 100_000)
        try fixture.file(".cache/lm-studio/models/TheBloke/Mistral-7B/m.gguf", bytes: 50_000)
        try fixture.file(".cache/lm-studio/conversations/chat.json", bytes: 1_000)

        let group = await DeveloperCacheScanner.scan(await fixture.context(fixture.environment()))

        let new = try #require(group.item("dev.lmstudio.lmstudio-community/Qwen3-8B-GGUF"))
        #expect(!new.isRecommended)
        #expect(new.defaultAction.operation.paths == [canonical(qwen.deletingLastPathComponent())])
        #expect(group.item("dev.lmstudio.TheBloke/Mistral-7B") != nil)
        #expect(group.item("dev.xdg.lm-studio") == nil, "the rest of ~/.cache/lm-studio holds chats")
        #expect(PathSafety.violation(for: qwen.deletingLastPathComponent(), mode: .delete, home: fixture.home) == nil)
    }

    // MARK: Time Machine

    @Test func timeMachineSnapshotsAreDeletedWithTmutil() async throws {
        let fixture = try Fixture()
        let runner = FakeCommandRunner { command in
            if command.arguments == ["listlocalsnapshotdates", "/"] {
                return CommandOutput(status: 0, stdout: "Snapshot dates for disk /:\n2026-11-04-101530\n2026-11-05-091000\n", stderr: "")
            }
            return CommandOutput(status: 0, stdout: "", stderr: "")
        }

        let group = await TimeMachineScanner.scan(await fixture.context(fixture.environment(runner: runner)))

        let snapshots = try #require(group.item("general.timeMachineSnapshots"))
        #expect(!snapshots.isRecommended)
        #expect(snapshots.sizeIsUpperBound)
        #expect(snapshots.defaultAction.regeneration == .permanent)
        #expect(snapshots.detail?.hasPrefix("2 snapshots") == true)
        #expect(snapshots.defaultAction.operation == .command(ToolCommand(executable: URL(fileURLWithPath: "/usr/bin/tmutil"),
                                                                           arguments: ["deletelocalsnapshots", "/"])))
    }

    @Test func noSnapshotsNoRow() async throws {
        let fixture = try Fixture()
        let runner = FakeCommandRunner { _ in CommandOutput(status: 0, stdout: "Snapshot dates for disk /:\n", stderr: "") }

        let group = await TimeMachineScanner.scan(await fixture.context(fixture.environment(runner: runner)))

        #expect(group.items.isEmpty)
    }

    // MARK: Helpers

    private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url)
    }

    @discardableResult
    private func ollamaManifest(_ fixture: Fixture, _ path: String, digests: [String]) throws -> URL {
        let manifest: [String: Any] = [
            "schemaVersion": 2,
            "config": ["digest": digests[0], "size": 100],
            "layers": digests.dropFirst().map { ["digest": $0, "size": 100] }
        ]
        let url = fixture.url(".ollama/models/manifests/\(path)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        return url
    }
}
