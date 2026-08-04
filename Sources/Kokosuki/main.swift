// Kokosuki — a fully offline desktop kitten with a local LLM mind.
import AppKit

MainActor.assumeIsolated {
    let cliArgs = CommandLine.arguments
    if let i = cliArgs.firstIndex(of: "--snapshot"), i + 1 < cliArgs.count {
        Snapshot.run(outDir: cliArgs[i + 1])
        exit(0)
    }
    if let i = cliArgs.firstIndex(of: "--icon"), i + 1 < cliArgs.count {
        Snapshot.icon(outDir: cliArgs[i + 1])
        exit(0)
    }
    if cliArgs.contains("--selftest") {
        SelfTest.run()
        // SelfTest drives the runloop and exits itself
        RunLoop.main.run()
    }
    if let i = cliArgs.firstIndex(of: "--scenarios") {
        let rounds = cliArgs.indices.contains(i + 1) ? Int(cliArgs[i + 1]) ?? 1 : 1
        SelfTest.runScenarios(rounds: rounds)
        RunLoop.main.run()
    }
    if cliArgs.contains("--platforms") {
        let tracker = PlatformTracker()
        tracker.refresh()
        for p in tracker.platforms {
            print("platform id=\(p.id) topY(cocoa)=\(Int(p.y)) x=\(Int(p.minX))..\(Int(p.maxX))")
        }
        print("\(tracker.platforms.count) platforms")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
