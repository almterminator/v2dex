import Foundation
import V2DexCore

enum CLIError: Error {
    case missingArgument
    case invalidImport
}

func run() async throws {
    let arguments = CommandLine.arguments

    guard arguments.count >= 2 else {
        fputs("usage: v2dex-cli '<proxy-uri>'\n", stderr)
        throw CLIError.missingArgument
    }

    let raw = arguments[1]
    let nodes = try await SubscriptionImporter.importRaw(raw)
    guard let node = nodes.first else {
        throw CLIError.invalidImport
    }

    let data = try SingboxConfigBuilder.build(
        node: node,
        mode: .full,
        appRules: []
    )

    FileHandle.standardOutput.write(data)
}

Task {
    do {
        try await run()
        exit(0)
    } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()
