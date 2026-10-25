import Foundation
import Testing
@testable import OpenClaw

@Suite(.serialized)
@MainActor
struct CLIInstallerTests {
    @Test func installedLocationFindsExecutable() throws {
        let fm = FileManager()
        let root = fm.temporaryDirectory.appendingPathComponent(
            "openclaw-cli-installer-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let binDir = root.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let cli = binDir.appendingPathComponent("openclaw")
        fm.createFile(atPath: cli.path, contents: Data())
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let found = CLIInstaller.installedLocation(
            searchPaths: [binDir.path],
            fileManager: fm)
        #expect(found == cli.path)

        try fm.removeItem(at: cli)
        fm.createFile(atPath: cli.path, contents: Data())
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cli.path)

        let missing = CLIInstaller.installedLocation(
            searchPaths: [binDir.path],
            fileManager: fm)
        #expect(missing == nil)
    }

    @Test func installCommandVerifiesPinnedDownloadBeforeExecuting() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "openclaw-cli-installer-command-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let mockBin = root.appendingPathComponent("bin")
        let tempRoot = root.appendingPathComponent("tmp")
        try fm.createDirectory(at: mockBin, withIntermediateDirectories: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let version = "2026.10.25 'quoted beta'"
        let prefix = root.appendingPathComponent("prefix with spaces/it's here").path
        let command = CLIInstaller.installScriptCommand(version: version, prefix: prefix)
        #expect(command.count == 3)
        #expect(command[0] == "/bin/bash")
        #expect(command[1] == "-lc")
        #expect(command[2].contains("umask 077"))
        #expect(command[2].contains("--proto '=https'"))
        #expect(command[2].contains("--proto-redir '=https'"))
        #expect(command[2].contains("shasum -a 256"))
        #expect(command[2].contains("7ad6910e76cf692eb60bed987a26637548cc5363164031ddf6ffec480ae1458b"))
        #expect(!command[2].contains("| bash"))
        #expect(!command[2].contains("OPENCLAW_INSTALL_CLI_SHA256"))
        #expect(!command[2].contains("OPENCLAW_INSTALL_SHA256"))

        let fixture = root.appendingPathComponent("installer-fixture.sh")
        let executionLog = root.appendingPathComponent("installer-args")
        let urlLog = root.appendingPathComponent("download-url")
        let downloadPathLog = root.appendingPathComponent("download-path")
        let curl = mockBin.appendingPathComponent("curl")
        let shasum = mockBin.appendingPathComponent("shasum")
        try """
        #!/bin/bash
        set -euo pipefail
        printf '%s\\n' "$@" >"$CLI_INSTALL_EXEC_LOG"
        """.write(to: fixture, atomically: true, encoding: .utf8)
        try """
        #!/bin/bash
        set -euo pipefail
        output=''
        url=''
        while (($#)); do
          case "$1" in
            -fsSL|--tlsv1.2|--globoff) shift ;;
            --max-redirs) [[ "$2" == 5 ]] || exit 91; shift 2 ;;
            --proto) [[ "$2" == '=https' ]] || exit 92; shift 2 ;;
            --proto-redir) [[ "$2" == '=https' ]] || exit 93; shift 2 ;;
            --output) output="$2"; shift 2 ;;
            --) shift; url="${1-}"; shift ;;
            *) exit 94 ;;
          esac
        done
        [[ "$url" == 'https://openclaw.ai/install-cli.sh' ]] || exit 95
        [[ -n "$output" ]] || exit 96
        printf '%s\\n' "$url" >"$CLI_INSTALL_URL_LOG"
        printf '%s\\n' "$output" >"$CLI_INSTALL_DOWNLOAD_PATH_LOG"
        cp -- "$CLI_INSTALL_FIXTURE" "$output"
        if [[ "${CLI_INSTALL_CURL_MODE:-success}" == fail ]]; then exit 23; fi
        """.write(to: curl, atomically: true, encoding: .utf8)
        try """
        #!/bin/bash
        set -euo pipefail
        [[ "$#" == 3 && "$1" == '-a' && "$2" == 256 && -f "$3" ]] || exit 97
        printf '%s  %s\\n' "$CLI_INSTALL_SHA256" "$3"
        """.write(to: shasum, atomically: true, encoding: .utf8)
        for path in [fixture, curl, shasum] {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }

        func runCommand(curlMode: String, digest: String) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command[2]]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "\(mockBin.path):/usr/bin:/bin"
            environment["TMPDIR"] = tempRoot.path
            environment["CLI_INSTALL_FIXTURE"] = fixture.path
            environment["CLI_INSTALL_EXEC_LOG"] = executionLog.path
            environment["CLI_INSTALL_URL_LOG"] = urlLog.path
            environment["CLI_INSTALL_DOWNLOAD_PATH_LOG"] = downloadPathLog.path
            environment["CLI_INSTALL_CURL_MODE"] = curlMode
            environment["CLI_INSTALL_SHA256"] = digest
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        let pinnedDigest = "7ad6910e76cf692eb60bed987a26637548cc5363164031ddf6ffec480ae1458b"
        #expect(try runCommand(curlMode: "success", digest: pinnedDigest) == 0)
        let observedArgs = try String(contentsOf: executionLog, encoding: .utf8)
        #expect(observedArgs == ["--json", "--no-onboard", "--prefix", prefix, "--version", version]
            .joined(separator: "\n") + "\n")
        #expect(try String(contentsOf: urlLog, encoding: .utf8) == "https://openclaw.ai/install-cli.sh\n")
        let downloadedPath = try String(contentsOf: downloadPathLog, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
        #expect(!fm.fileExists(atPath: downloadedPath))
        #expect(!fm.fileExists(atPath: URL(fileURLWithPath: downloadedPath).deletingLastPathComponent().path))

        try fm.removeItem(at: executionLog)
        #expect(try runCommand(
            curlMode: "success",
            digest: "0000000000000000000000000000000000000000000000000000000000000000") != 0)
        #expect(!fm.fileExists(atPath: executionLog.path))
        let rejectedDownloadPath = try String(contentsOf: downloadPathLog, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
        #expect(!fm.fileExists(atPath: rejectedDownloadPath))

        try fm.removeItem(at: urlLog)
        try fm.removeItem(at: downloadPathLog)
        #expect(try runCommand(curlMode: "fail", digest: pinnedDigest) != 0)
        #expect(!fm.fileExists(atPath: executionLog.path))
        let failedDownloadPath = try String(contentsOf: downloadPathLog, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
        #expect(!fm.fileExists(atPath: failedDownloadPath))
    }
}
