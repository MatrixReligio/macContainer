import Darwin
import Foundation

if CommandLine.arguments.contains("--build-smoke-test") {
    exit(EXIT_SUCCESS)
}

FileHandle.standardError.write(Data("MacContainer update service is not available in this build stage.\n".utf8))
exit(EX_UNAVAILABLE)
