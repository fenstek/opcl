import Foundation

@MainActor
enum CLIInstaller {
    static func installedLocation() -> String? {
        self.installedLocation(
            searchPaths: CommandResolver.preferredPaths(),
            fileManager: .default)
    }

    static func installedLocation(
        searchPaths: [String],
        fileManager: FileManager) -> String?
    {
        for basePath in searchPaths {
            let candidate = URL(fileURLWithPath: basePath).appendingPathComponent("openclaw").path
            var isDirectory: ObjCBool = false

            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }

            guard fileManager.isExecutableFile(atPath: candidate) else { continue }

            return candidate
        }

        return nil
    }

    static func isInstalled() -> Bool {
        self.installedLocation() != nil
    }

    static func install(statusHandler: @escaping @MainActor @Sendable (String) async -> Void) async {
        let expected = GatewayEnvironment.expectedGatewayVersionString() ?? "latest"
        let prefix = Self.installPrefix()
        await statusHandler("Installing openclaw CLI…")
        let cmd = self.installScriptCommand(version: expected, prefix: prefix)
        let response = await ShellExecutor.runDetailed(command: cmd, cwd: nil, env: nil, timeout: 900)

        if response.success {
            let parsed = self.parseInstallEvents(response.stdout)
            let installedVersion = parsed.last { $0.event == "done" }?.version
            let summary = installedVersion.map { "Installed openclaw \($0)." } ?? "Installed openclaw."
            await statusHandler(summary)
            return
        }

        let parsed = self.parseInstallEvents(response.stdout)
        if let error = parsed.last(where: { $0.event == "error" })?.message {
            await statusHandler("Install failed: \(error)")
            return
        }

        let detail = response.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = response.errorMessage ?? "install failed"
        await statusHandler("Install failed: \(detail.isEmpty ? fallback : detail)")
    }

    private static func installPrefix() -> String {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw")
            .path
    }

    static func installScriptCommand(version: String, prefix: String) -> [String] {
        let escapedVersion = self.shellEscape(version)
        let escapedPrefix = self.shellEscape(prefix)
        let script = """
        set -e
        umask 077
        downloadDir="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-cli-install.XXXXXXXX")"
        trap 'rm -rf -- "$downloadDir"' EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        curl -fsSL --max-redirs 5 --proto '=https' --proto-redir '=https' --tlsv1.2 --globoff --output "$downloadDir/install-cli.sh" -- https://openclaw.ai/install-cli.sh
        actualSha256="$(shasum -a 256 "$downloadDir/install-cli.sh")"
        actualSha256="${actualSha256%% *}"
        if [ "$actualSha256" != '7ad6910e76cf692eb60bed987a26637548cc5363164031ddf6ffec480ae1458b' ]; then
          echo 'CLI installer SHA256 did not match its pinned digest.' >&2
          exit 1
        fi
        /bin/bash "$downloadDir/install-cli.sh" --json --no-onboard --prefix \(escapedPrefix) --version \(escapedVersion)
        """
        return ["/bin/bash", "-lc", script]
    }

    private static func parseInstallEvents(_ output: String) -> [InstallEvent] {
        let decoder = JSONDecoder()
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        var events: [InstallEvent] = []
        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(InstallEvent.self, from: data) {
                events.append(event)
            }
        }
        return events
    }

    private static func shellEscape(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

private struct InstallEvent: Decodable {
    let event: String
    let version: String?
    let message: String?
}
