import Foundation

/// The two shared files in the App Group container. Each has exactly one writer,
/// so an atomic replace is enough (KTD6).
public struct FlowFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func appGroup() -> FlowFiles? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)
            .map(FlowFiles.init)
    }

    var commandURL: URL { directory.appending(path: "command.json") }
    var stateURL: URL { directory.appending(path: "state.json") }

    public func readCommand() -> FlowCommand {
        read(commandURL) ?? FlowCommand()
    }

    public func readState() -> FlowState {
        read(stateURL) ?? FlowState()
    }

    public func write(_ command: FlowCommand) throws {
        try JSONEncoder().encode(command).write(to: commandURL, options: .atomic)
    }

    public func write(_ state: FlowState) throws {
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    private func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
