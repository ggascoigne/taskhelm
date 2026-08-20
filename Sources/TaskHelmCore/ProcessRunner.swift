import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ProcessRunning: Sendable {
    func run(executableURL: URL, arguments: [String], environment: [String: String]) throws -> ProcessResult
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data
    ) throws -> ProcessResult
}

public extension ProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data
    ) throws -> ProcessResult {
        try run(executableURL: executableURL, arguments: arguments, environment: environment)
    }
}

public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String], environment: [String: String]) throws -> ProcessResult {
        try execute(executableURL: executableURL, arguments: arguments, environment: environment, standardInput: nil)
    }

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data
    ) throws -> ProcessResult {
        try execute(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            standardInput: standardInput
        )
    }

    private func execute(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        standardInput: Data?
    ) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, configured in configured }
        process.standardOutput = standardOutput
        process.standardError = standardError
        let input = standardInput.map { _ in Pipe() }
        process.standardInput = input

        do {
            try process.run()
        } catch {
            throw TaskwarriorError.executableNotFound(executableURL.path)
        }

        if let standardInput, let input {
            input.fileHandleForWriting.write(standardInput)
            try? input.fileHandleForWriting.close()
        }

        let outputData = LockedData()
        let errorData = LockedData()
        let readers = DispatchGroup()

        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputData.set(standardOutput.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorData.set(standardError.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        process.waitUntilExit()
        readers.wait()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData.value, as: UTF8.self),
            standardError: String(decoding: errorData.value, as: UTF8.self)
        )
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.withLock { data }
    }

    func set(_ value: Data) {
        lock.withLock { data = value }
    }
}
