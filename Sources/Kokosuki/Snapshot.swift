import AppKit
import SwiftUI

/// Offscreen rendering for visual QA and icon generation (no window needed).
/// `kokosuki --snapshot <dir>` dumps PNGs of key states; `--icon <dir>` renders icon art.
@MainActor
enum Snapshot {

    struct FixedPetView: View {
        var state: PetRenderState
        var t: Double
        var body: some View {
            Canvas { ctx, size in
                var painter = PetPainter(s: state, t: t)
                painter.draw(in: &ctx, size: size)
            }
            .frame(width: 230, height: 230)
            .background(Color(red: 0.55, green: 0.65, blue: 0.75))  // neutral backdrop for QA
        }
    }

    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var cases: [(String, (PetCore) -> Void)] = [
            ("idle-neutral", { _ in }),
            ("happy", { $0.emotion = .happy }),
            ("love", { $0.emotion = .love; $0.spawn(.heart, count: 3, near: CGPoint(x: 0, y: 40)) }),
            ("sad", { $0.emotion = .sad }),
            ("angry", { $0.emotion = .angry }),
            ("surprised", { $0.emotion = .surprised }),
            ("sleepy", { $0.emotion = .sleepy }),
            ("hungry", { $0.emotion = .hungry }),
            ("shy", { $0.emotion = .shy }),
            ("curious", { $0.emotion = .curious }),
            ("sleeping", { $0.isSleeping = true; $0.activity = .sleep; $0.spawn(.zzz, count: 2, near: CGPoint(x: 26, y: 40)) }),
            ("walking", { $0.activity = .walk; $0.walkPhase = 1.2 }),
            ("dragged", { $0.activity = .drag; $0.pickupWiggle = 1; $0.emotion = .surprised }),
            ("eating", { $0.activity = .eat(food: "🐟"); $0.emotion = .happy }),
            ("dancing", { $0.activity = .dance; $0.emotion = .excited }),
            ("thinking", { $0.activity = .think; $0.emotion = .curious }),
            ("talking", { $0.activity = .talk; $0.talkLevel = 0.8; $0.emotion = .happy }),
            ("stretching", { $0.activity = .stretchPose; $0.actionPhase = 1.1 }),
            ("playing", { $0.activity = .play; $0.emotion = .playful }),
            ("sulking", { $0.activity = .sulk; $0.emotion = .sad; $0.lookAway = 1 }),
        ]
        cases.append(("dizzy", { c in c.dizzy = 1; c.emotion = .surprised }))

        for (name, setup) in cases {
            let core = PetCore()
            setup(core)
            let view = FixedPetView(state: core.snapshot(), t: 0.9)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage, let png = pngData(img) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
                print("wrote \(name).png")
            } else {
                print("FAILED \(name)")
            }
        }
    }

    /// Icon: the cat on a soft rounded-square pastel background.
    struct IconView: View {
        var state: PetRenderState
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 180, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.87, blue: 0.77),
                                Color(red: 1.0, green: 0.76, blue: 0.72),
                            ],
                            startPoint: .top, endPoint: .bottom))
                    .frame(width: 830, height: 830)
                Canvas { ctx, size in
                    var painter = PetPainter(s: state, t: 0.9)
                    painter.draw(in: &ctx, size: size)
                }
                .frame(width: 780, height: 780)
                .offset(y: 8)
            }
            .frame(width: 1024, height: 1024)
        }
    }

    static func icon(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let core = PetCore()
        core.emotion = .happy
        let renderer = ImageRenderer(content: IconView(state: core.snapshot()))
        renderer.scale = 1
        if let img = renderer.nsImage, let png = pngData(img) {
            try? png.write(to: dir.appendingPathComponent("icon-1024.png"))
            print("wrote icon-1024.png")
        } else {
            print("FAILED icon")
        }

        // menu-bar template icon preview (rendered dark-on-light at 4x for inspection)
        let bar = StatusIcon.make()
        let preview = NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            bar.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72))
            return true
        }
        if let png = pngData(preview) {
            try? png.write(to: dir.appendingPathComponent("statusicon.png"))
            print("wrote statusicon.png")
        }

        // settings UI symmetry check
        let settingsView = SettingsView(settings: AppSettings.shared, onResetStats: {})
        let sr = ImageRenderer(content: settingsView)
        sr.scale = 2
        if let img = sr.nsImage, let png = pngData(img) {
            try? png.write(to: dir.appendingPathComponent("settings.png"))
            print("wrote settings.png")
        }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
