import Foundation

#if DEBUG
enum ToolFixtures {
    static var rows: [JSONValue] {
        [
            .object(["id": .string("tool-command"), "type": .string("command_execution"), "title": .string("Run native checks"),
                     "input": .string("xcodebuild -scheme T3Native test"), "outputOmitted": .bool(true), "status": .string("completed")]),
            .object(["id": .string("tool-json"), "type": .string("dynamic_tool"), "title": .string("Inspect build result"), "toolName": .string("read_build"),
                     "input": .object(["path": .string("native/build.json"), "includeWarnings": .bool(false)]),
                     "output": .object(["passed": .number(64), "warnings": .array([.string("Fixture data only")]), "artifact": .object(["platform": .string("iOS"), "signed": .bool(true)])]), "status": .string("completed")]),
            .object(["id": .string("tool-retry"), "type": .string("command_execution"), "title": .string("Retry failed command output"),
                     "input": .string("swift test"), "outputOmitted": .bool(true), "status": .string("failed")]),
            .object(["id": .string("tool-large"), "type": .string("dynamic_tool"), "title": .string("Read a long result"),
                     "input": .object(["summary": .string("Read file"), "truncated": .bool(true)]), "outputOmitted": .bool(true), "status": .string("completed")]),
            .object(["id": .string("tool-gone"), "type": .string("command_execution"), "title": .string("Removed output"),
                     "input": .string("old task"), "outputOmitted": .bool(true), "status": .string("completed")]),
            .object(["id": .string("tool-live"), "type": .string("command_execution"), "title": .string("Inspect an active command"),
                     "input": .string("long-running fixture"), "outputOmitted": .bool(true), "status": .string("running")])
        ]
    }
    static func detail(_ item: JSONValue, attempts: inout Set<String>) throws -> JSONValue {
        if item.id == "tool-gone" { throw ClientError("Output is no longer available.") }
        if item.id == "tool-retry", attempts.insert(item.id).inserted { throw ClientError("Could not load output. The connection was interrupted.") }
        var full = item; full["outputOmitted"] = .bool(false)
        switch item.id {
        case "tool-command": full["output"] = .string("All native checks passed.\nThis is fixture output."); full["exitCode"] = .number(0)
        case "tool-retry": full["output"] = .string("error: fixture module was not found\n"); full["exitCode"] = .number(1)
        case "tool-large":
            full["input"] = .object(["path": .string("native/long-log.txt")])
            full["output"] = .string(String(repeating: "Long fixture output line.\n", count: 4000))
        case "tool-live":
            let first = attempts.insert(item.id).inserted
            full["output"] = .string(first ? "Running fixture output snapshot 1" : "Running fixture output snapshot 2")
        default: break
        }
        return full
    }
}
#endif
