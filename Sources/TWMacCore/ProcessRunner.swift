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
}

public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String], environment: [String: String]) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, configured in configured }
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw TaskwarriorError.executableNotFound(executableURL.path)
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
