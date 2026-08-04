import AppKit
import Foundation

/// Behavior engine: physics, autonomy, stats, particles, and the coupling between
/// LLM output and on-screen behavior. Ticks at 60Hz on the main actor.
@MainActor
final class PetEngine {

    let core: PetCore
    let brain: Brain
    private let settings = AppSettings.shared

    // wired by AppDelegate
    var moveWindow: ((CGPoint) -> Void)?          // pet center, screen coords
    var bubble: BubbleController?
    var chatMirror: ((String, Bool) -> Void)?     // streamed pet line into chat UI (text, done)

    // position & physics (screen coords, pet center)
    private(set) var petCenter: CGPoint = .zero
    private var velocity = CGVector(dx: 0, dy: 0)
    private var airborne = false
    private var prevFeetY: CGFloat = 0
    private var gravity: CGFloat = 2600   // softened during deliberate jumps for a visible arc

    // window-top platforms (jump on, walk along, ride, fall off)
    private let tracker = PlatformTracker()
    private var currentPlatformID: CGWindowID?
    private var lastPlatformMinX: CGFloat = 0
    private var platformRefreshAt = Date.distantPast
    private var deliberateJump = false

    // walking
    private var walkTargetX: CGFloat = 0
    private var walkDir: CGFloat = 1

    // scheduling
    private var nextDecision = Date().addingTimeInterval(2)
    private var nextBlink = Date().addingTimeInterval(3)
    private var nextEarTwitch = Date().addingTimeInterval(5)
    private var lastChatterAt = Date()
    private var chatterJitter = 1.0
    private var lastWokeAt = Date.distantPast
    private var minSleepUntil = Date.distantPast
    private var pendingSleep: Task<Void, Never>?
    private var nextZzz = Date()
    private var activityEndsAt = Date.distantPast
    private var bubbleHideAt = Date.distantPast
    private var lastStatsSave = Date()
    private var lastHungerNag = Date.distantPast
    private var lastSleepNag = Date.distantPast

    // interaction bookkeeping
    private var recentPokes: [Date] = []
    private var lastPetStroke = Date.distantPast
    private var lastEventLLM = Date.distantPast
    private var blinkUntil = Date.distantPast
    private var dizzyUntil = Date.distantPast
    private var chasingCursor = false

    private var timer: Timer?
    private var lastTick = Date()
    private var lastPulse = Date()
    private var bubbleStreaming = false
    private let sessionStart = Date()
    private var eventLog: [(Date, PetEvent)] = []

    var scale: CGFloat { settings.petScale }
    /// distance from pet center down to feet, in screen px
    private var feetDrop: CGFloat { PetLayout.feetDrop(scale: scale) }

    init(core: PetCore, brain: Brain) {
        self.core = core
        self.brain = brain
    }

    func start(at point: CGPoint?) {
        petCenter = point ?? defaultSpot()
        scheduleChatter(initial: true)
        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        moveWindow?(petCenter)
    }

    private func defaultSpot() -> CGPoint {
        let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGPoint(x: f.midX + f.width * 0.25, y: f.minY + feetDrop)
    }

    private func screenFrame() -> CGRect {
        let s = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(petCenter) }
        return (s ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    private var groundY: CGFloat { screenFrame().minY + feetDrop }

    /// y for the pet center on whatever it currently stands on (platform or ground).
    private var standY: CGFloat {
        if let id = currentPlatformID, let p = tracker.platform(withID: id) {
            return p.y + feetDrop
        }
        return groundY
    }

    /// Horizontal span the pet may walk on for the current surface.
    private func surfaceSpan() -> (lo: CGFloat, hi: CGFloat) {
        if let id = currentPlatformID, let p = tracker.platform(withID: id) {
            return (p.minX + 8, p.maxX - 8)
        }
        let f = screenFrame()
        return (f.minX + 50, f.maxX - 50)
    }

    // MARK: - Main tick

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 1.0 / 15.0)
        lastTick = now

        // refresh every tick while standing on a window so rides stay smooth;
        // cheaper cadence otherwise
        if currentPlatformID != nil || now > platformRefreshAt {
            platformRefreshAt = now.addingTimeInterval(0.12)
            tracker.refresh()
            validatePlatform()
        }
        decayStats(dt)
        updatePhysics(dt)
        updateActivity(now, dt)
        updateAutonomy(now)
        updateFace(now, dt)
        updateParticles(dt)
        updateBubble(now)
        updateChatter(now)

        if now.timeIntervalSince(lastStatsSave) > 60 {
            lastStatsSave = now
            Persistence.saveStats(core.stats)
        }
        // low-frequency UI refresh for the chat header stat bars
        if now.timeIntervalSince(lastPulse) > 0.5 {
            lastPulse = now
            core.uiPulse &+= 1
        }
    }

    // MARK: - Stats

    private func decayStats(_ dt: TimeInterval) {
        var s = core.stats
        let m = dt / 60.0
        s.fullness -= 0.21 * m                        // empty in ~8h
        if core.isSleeping {
            s.energy += 1.4 * m                       // full nap ~70min
        } else {
            s.energy -= 0.17 * m                      // tired after ~10h
        }
        // happiness drifts toward 55; hunger drags it down
        s.happiness += (55 - s.happiness) * 0.004 * m
        if s.fullness < 20 { s.happiness -= 0.10 * m }
        s.clamp()
        core.stats = s
    }

    // MARK: - Physics & platforms

    /// Keep standing on the tracked window: ride it when it moves, fall when it goes away.
    private func validatePlatform() {
        guard let id = currentPlatformID, core.activity != .drag, !airborne else { return }
        guard let p = tracker.platform(withID: id) else {
            currentPlatformID = nil
            startFalling(surprised: true)
            return
        }
        // ride horizontal motion of the window
        let dx = p.minX - lastPlatformMinX
        if abs(dx) > 0.5 { petCenter.x += dx }
        lastPlatformMinX = p.minX

        if !p.contains(x: petCenter.x) {
            petCenter.x = min(max(petCenter.x, p.minX), p.maxX)
            if !p.contains(x: petCenter.x) {
                currentPlatformID = nil
                startFalling(surprised: true)
                return
            }
        }
        let target = p.y + feetDrop
        if abs(petCenter.y - target) > 0.5 || abs(dx) > 0.5 {
            petCenter.y = target
            moveWindow?(petCenter)
            bubble?.reposition(above: petCenter, petScale: scale)
        }
    }

    private func startFalling(surprised: Bool) {
        if core.isSleeping {
            core.isSleeping = false
            lastWokeAt = Date()
        }
        airborne = true
        velocity = .zero
        prevFeetY = petCenter.y - feetDrop
        core.activity = .fall
        if surprised {
            core.setEmotion(.surprised, hold: 3)
            core.spawn(.exclamation, count: 1, near: CGPoint(x: 0, y: 55), spread: 4)
        }
    }

    /// Deliberate jump toward a target x on a target surface (window top or ground).
    /// Crouches briefly first (anticipation), then launches on a soft, visible arc.
    private func jumpTo(targetX: CGFloat, surfaceY: CGFloat, ontoPlatform: Bool) {
        guard core.activity != .drag, !airborne else { return }
        core.squash = 0.26                       // wind-up crouch
        core.setEmotion(.excited, hold: 2.5)
        core.facingRight = targetX >= petCenter.x
        let fromPlatform = currentPlatformID
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard let self, self.core.activity != .drag, !self.airborne,
                self.currentPlatformID == fromPlatform
            else { return }
            let g: CGFloat = 1500
            self.gravity = g
            let targetCenterY = surfaceY + self.feetDrop
            let apex = max(self.petCenter.y, targetCenterY) + 80
            let vy = sqrt(2 * g * (apex - self.petCenter.y))
            let tUp = vy / g
            let tDown = sqrt(2 * max(1, apex - targetCenterY) / g)
            let vx = (targetX - self.petCenter.x) / (tUp + tDown)
            self.prevFeetY = self.petCenter.y - self.feetDrop
            self.velocity = CGVector(dx: vx, dy: vy)
            self.airborne = true
            self.currentPlatformID = nil
            self.deliberateJump = ontoPlatform
            self.core.activity = .jumpPose
            self.core.squash = -0.18             // launch stretch
        }
    }

    private func updatePhysics(_ dt: TimeInterval) {
        guard core.activity != .drag else { return }

        if airborne {
            let feetBefore = petCenter.y - feetDrop
            velocity.dy -= gravity * dt
            petCenter.x += velocity.dx * dt
            petCenter.y += velocity.dy * dt
            let f = screenFrame()
            petCenter.x = min(max(petCenter.x, f.minX + 40), f.maxX - 40)
            if petCenter.x <= f.minX + 40 || petCenter.x >= f.maxX - 40 { velocity.dx *= -0.5 }

            // catch a window top while descending
            if velocity.dy < 0,
                let p = tracker.landingPlatform(
                    x: petCenter.x, feetY: petCenter.y - feetDrop, previousFeetY: feetBefore)
            {
                petCenter.y = p.y + feetDrop
                let impact = -velocity.dy
                velocity = .zero
                airborne = false
                gravity = 2600
                currentPlatformID = p.id
                lastPlatformMinX = p.minX
                land(hard: impact > 1000)
                if deliberateJump {
                    deliberateJump = false
                    logEvent(.climbedWindow)
                    core.setEmotion(.proud, hold: 4)
                    core.spawn(.sparkle, count: 3, near: CGPoint(x: 0, y: 45))
                    maybeCelebratePerch()
                }
            } else if petCenter.y <= groundY {
                petCenter.y = groundY
                let impact = -velocity.dy
                velocity = .zero
                airborne = false
                gravity = 2600
                currentPlatformID = nil
                deliberateJump = false
                land(hard: impact > 900)
            }
            prevFeetY = petCenter.y - feetDrop
            moveWindow?(petCenter)
            bubble?.reposition(above: petCenter, petScale: scale)
            return
        }

        // stick to the current surface (ground or ridden window)
        if abs(petCenter.y - standY) > 1 {
            petCenter.y = standY
            moveWindow?(petCenter)
        }

        if core.activity == .walk {
            var speed: CGFloat = 55 * scale
            if core.stats.happiness > 75 { speed *= 1.25 }
            if core.stats.energy < 30 { speed *= 0.7 }
            if chasingCursor { speed *= 2.1 }
            petCenter.x += walkDir * speed * dt
            core.walkPhase += dt * (chasingCursor ? 14 : 9)
            core.facingRight = walkDir > 0

            let span = surfaceSpan()
            petCenter.x = min(max(petCenter.x, span.lo), span.hi)
            let arrived = abs(petCenter.x - walkTargetX) < 8
                || petCenter.x <= span.lo || petCenter.x >= span.hi
            if arrived {
                if chasingCursor {
                    chasingCursor = false
                    logEvent(.cameWhenCalled)
                    core.activity = .idle
                    hopInPlace()
                    showCanned(.poke, emotion: .happy)
                } else {
                    core.activity = .idle
                }
            }
            moveWindow?(petCenter)
            bubble?.reposition(above: petCenter, petScale: scale)
        }
    }

    /// Occasionally brag (LLM) about having climbed onto a window.
    private func maybeCelebratePerch() {
        let now = Date()
        guard now.timeIntervalSince(lastEventLLM) > 120, brain.isReady, !brain.isGenerating,
            Double.random(in: 0..<1) < 0.45
        else { return }
        lastEventLLM = now
        runLLMEvent(eventText(
            zh: "你刚刚成功跳到了一个应用窗口的顶上,视野很好",
            ja: "アプリのウィンドウの上にジャンプで乗れた。見晴らしがいい",
            en: "you just jumped on top of an app window — great view from up here"))
    }

    /// Pet size changed in settings: re-seat on the current surface without touching activity.
    func rescaled() {
        petCenter.y = standY
        moveWindow?(petCenter)
        bubble?.reposition(above: petCenter, petScale: scale)
    }

    private func land(hard: Bool) {
        if hard {
            core.activity = .land
            core.squash = 0.30
            core.dizzy = 1
            dizzyUntil = Date().addingTimeInterval(1.6)
            core.spawn(.star, count: 3, near: CGPoint(x: 0, y: 30))
            activityEndsAt = Date().addingTimeInterval(0.5)
            core.setEmotion(.surprised, hold: 2)
            logEvent(.hardFall)
            if !bubbleStreaming { showCanned(.landingOuch, emotion: nil) }
            core.stats.happiness -= 1.5
        } else {
            core.activity = .land
            core.squash = 0.18
            activityEndsAt = Date().addingTimeInterval(0.3)
        }
    }

    private func hopInPlace() {
        prevFeetY = petCenter.y - feetDrop
        velocity = CGVector(dx: 0, dy: 520)
        airborne = true
        core.activity = .jumpPose
        core.squash = -0.15
    }

    // MARK: - Timed activities

    private func updateActivity(_ now: Date, _ dt: TimeInterval) {
        core.squash *= pow(0.02, dt)   // relax squash quickly
        if core.dizzy > 0 && now > dizzyUntil { core.dizzy = 0 }

        switch core.activity {
        case .eat, .stretchPose, .dance, .spinPose, .play, .land:
            core.actionPhase += dt
            if now > activityEndsAt {
                finishTimedActivity()
            } else if case .dance = core.activity, Int(core.actionPhase * 3) != Int((core.actionPhase - dt) * 3) {
                core.spawn(.note, count: 1, near: CGPoint(x: 0, y: 40), spread: 30)
            } else if case .play = core.activity, Int(core.actionPhase * 2) != Int((core.actionPhase - dt) * 2) {
                core.spawn(.sparkle, count: 1, near: CGPoint(x: 30, y: -20), spread: 22)
            }
        case .sleep:
            if now > nextZzz {
                nextZzz = now.addingTimeInterval(1.4)
                core.spawn(.zzz, count: 1, near: CGPoint(x: 26, y: 30), spread: 6)
            }
            if core.stats.energy > 96, !isNight(), now > minSleepUntil {
                wake(grumpy: false)
            }
        case .talk:
            // self-heal: never mouth-flap without a visible bubble
            if !bubbleStreaming && bubbleHideAt == .distantPast {
                core.activity = .idle
                core.talkLevel = 0
            } else {
                core.talkLevel = 0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate * 11)
            }
        default:
            core.talkLevel = max(0, core.talkLevel - dt * 4)
        }
    }

    private func finishTimedActivity() {
        let a = core.activity
        core.actionPhase = 0
        core.activity = .idle
        switch a {
        case .eat:
            core.setEmotion(.happy, hold: 5)
            core.spawn(.heart, count: 2, near: CGPoint(x: 0, y: 20))
        case .play:
            logEvent(.playedYarn)
            core.setEmotion(.happy, hold: 6)
            core.stats.happiness += 8
            core.stats.energy -= 6
        case .dance, .spinPose:
            core.setEmotion(.proud, hold: 4)
        case .land where chasingCursor:
            // was called over mid-parkour: resume running to the cursor
            walkDir = walkTargetX > petCenter.x ? 1 : -1
            core.activity = .walk
        default: break
        }
        core.stats.clamp()
    }

    // MARK: - Autonomy

    private func updateAutonomy(_ now: Date) {
        guard now > nextDecision else { return }
        guard !core.activity.isBusy, core.activity != .drag, !airborne else {
            nextDecision = now.addingTimeInterval(1.5)
            return
        }
        if core.isSleeping { nextDecision = now.addingTimeInterval(3); return }

        // nagging about needs (rate-limited; sometimes via LLM for variety)
        if core.stats.fullness < 22, now.timeIntervalSince(lastHungerNag) > 240 {
            lastHungerNag = now
            sayStateLine(canned: .hungry, emotion: .hungry, llmEvent: eventText(zh: "你现在很饿,想吃小鱼干", ja: "おなかが空いてにぼしが食べたい", en: "you are very hungry and craving dried fish"), fallback: (.hungry, .hungry))
            nextDecision = now.addingTimeInterval(8)
            return
        }
        // naps: only when truly tired, and never right after being woken up
        if core.stats.energy < 15 || (settings.autoSleep && isNight() && core.stats.energy < 80) {
            if now.timeIntervalSince(lastSleepNag) > 120,
                now.timeIntervalSince(lastWokeAt) > 600
            {
                lastSleepNag = now
                fallAsleep()
                nextDecision = now.addingTimeInterval(10)
                return
            }
        }
        if core.stats.happiness < 22, core.activity != .sulk {
            core.activity = .sulk
            core.setEmotion(.sad, hold: 30)
            nextDecision = now.addingTimeInterval(20)
            return
        }
        if core.activity == .sulk {
            core.activity = .idle
        }

        // parkour disabled while perched: come back down right away
        if !settings.windowParkour, currentPlatformID != nil {
            let f = screenFrame()
            let tx = min(max(petCenter.x, f.minX + 60), f.maxX - 60)
            jumpTo(targetX: tx, surfaceY: f.minY, ontoPlatform: false)
            nextDecision = now.addingTimeInterval(3)
            return
        }

        // weighted idle behaviors
        let span = surfaceSpan()
        let onPlatform = currentPlatformID != nil
        let ups = settings.windowParkour ? tracker.reachable(from: standY - feetDrop) : []
        let roll = Double.random(in: 0..<10)
        switch roll {
        case ..<3.0 where span.hi - span.lo > 40:  // wander along the current surface
            walkTargetX = .random(in: span.lo...span.hi)
            walkDir = walkTargetX > petCenter.x ? 1 : -1
            core.activity = .walk
        case ..<4.0:  // stretch
            core.activity = .stretchPose
            core.actionPhase = 0
            activityEndsAt = now.addingTimeInterval(2.2)
        case ..<4.5 where core.stats.happiness > 60:  // spontaneous cute spin
            core.activity = .spinPose
            core.actionPhase = 0
            activityEndsAt = now.addingTimeInterval(1.4)
        case ..<5.0 where core.stats.happiness > 70:
            hopInPlace()
        case ..<6.4 where !ups.isEmpty && core.stats.energy > 30:
            // parkour: jump onto a window top (favor lower platforms)
            if let p = ups.min(by: { $0.y < $1.y }) {
                let lo = max(p.minX + 20, petCenter.x - 420)
                let hi = min(p.maxX - 20, petCenter.x + 420)
                if lo < hi {
                    jumpTo(targetX: .random(in: lo...hi), surfaceY: p.y, ontoPlatform: true)
                }
            }
        case ..<7.8 where onPlatform:
            // hop back down to the ground (always, when hungry — food lives down there)
            let f = screenFrame()
            let tx = min(max(petCenter.x + .random(in: -140...140), f.minX + 60), f.maxX - 60)
            jumpTo(targetX: tx, surfaceY: f.minY, ontoPlatform: false)
        default:
            break  // keep idling; eyes will track cursor
        }
        nextDecision = now.addingTimeInterval(.random(in: 4...11))
    }

    private func isNight() -> Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 23 || h < 7
    }

    // MARK: - Face & particles

    private func updateFace(_ now: Date, _ dt: TimeInterval) {
        if now > core.emotionUntil, core.activity != .talk, core.activity != .think {
            core.emotion = core.baselineEmotion
        }

        // blinking
        if core.isSleeping {
            core.blink = 1
        } else if now > nextBlink {
            blinkUntil = now.addingTimeInterval(0.13)
            nextBlink = now.addingTimeInterval(.random(in: 2.4...6.0))
        }
        if !core.isSleeping {
            core.blink = now < blinkUntil ? 1 : 0
        }

        if now > nextEarTwitch {
            core.earTwitch = 1
            nextEarTwitch = now.addingTimeInterval(.random(in: 4...12))
        }
        core.earTwitch = max(0, core.earTwitch - dt * 3)

        // pupils track the cursor when the cat is calm/curious
        let tracking: Bool
        switch core.activity {
        case .idle, .walk, .talk, .think: tracking = !core.isSleeping
        default: tracking = false
        }
        if tracking {
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - petCenter.x
            let dy = mouse.y - petCenter.y
            let mag = max(1, hypot(dx, dy))
            let r: CGFloat = min(3.5, mag / 40)
            let target = CGPoint(x: dx / mag * r, y: dy / mag * r)
            core.eyeOffset.x += (target.x - core.eyeOffset.x) * min(1, dt * 8)
            core.eyeOffset.y += (target.y - core.eyeOffset.y) * min(1, dt * 8)
        } else {
            core.eyeOffset.x *= pow(0.1, dt)
            core.eyeOffset.y *= pow(0.1, dt)
        }

        if core.activity == .drag {
            core.pickupWiggle = min(1, core.pickupWiggle + dt * 3)
        } else {
            core.pickupWiggle = max(0, core.pickupWiggle - dt * 4)
        }

        core.lookAway = core.activity == .sulk
            ? min(1, core.lookAway + dt * 2) : max(0, core.lookAway - dt * 2)
    }

    private func updateParticles(_ dt: TimeInterval) {
        var ps = core.particles
        for i in ps.indices {
            ps[i].age += dt
            ps[i].x += ps[i].vx * dt
            ps[i].y += ps[i].vy * dt
            ps[i].vy *= pow(0.5, dt)
        }
        ps.removeAll { $0.age >= $0.lifetime }
        core.particles = ps
    }

    // MARK: - Bubble & speech

    private func updateBubble(_ now: Date) {
        if !bubbleStreaming, bubbleHideAt != .distantPast, now > bubbleHideAt {
            bubble?.hide()
            bubbleHideAt = .distantPast
            if core.activity == .talk { core.activity = .idle }
        }
    }

    private func bubbleDuration(for text: String) -> TimeInterval {
        min(18, max(3.5, 2.0 + Double(text.count) * 0.055))
    }

    /// Show a non-LLM line in the bubble with a matching emotion.
    /// `remember`: record into chat history (for chatter/nags the owner may reply to).
    @discardableResult
    func showCanned(_ cat: L10n.CannedCategory, emotion: Emotion?, remember: Bool = false) -> String {
        let line = L10n.canned(cat)
        if let emotion { core.setEmotion(emotion, hold: bubbleDuration(for: line) + 1) }
        bubble?.show(text: line, above: petCenter, petScale: scale)
        bubbleHideAt = Date().addingTimeInterval(bubbleDuration(for: line))
        if core.activity == .idle { core.activity = .talk
            activityEndsAt = bubbleHideAt }
        if remember { brain.noteAssistantLine(line) }
        return line
    }

    private func eventText(zh: String, ja: String, en: String) -> String {
        switch settings.lang {
        case .zh: return zh
        case .ja: return ja
        case .en: return en
        }
    }

    /// A state nag: canned 40% / LLM 60% when available.
    private func sayStateLine(
        canned: L10n.CannedCategory, emotion: Emotion, llmEvent: String,
        fallback: (L10n.CannedCategory, Emotion)
    ) {
        if brain.isReady, !brain.isGenerating, Double.random(in: 0..<1) < 0.6 {
            runLLMEvent(llmEvent, fallback: fallback)
        } else {
            showCanned(canned, emotion: emotion, remember: true)
        }
    }

    // MARK: - LLM coupling

    /// Relative-time renderer for the event log ("刚刚" / "5分钟前 …").
    /// Dedupes repeats of the same event kind (keeps the most recent), caps at 3.
    private func renderRecentEvents() -> [String] {
        let now = Date()
        var seen = Set<String>()
        var picked: [(Date, PetEvent)] = []
        for entry in eventLog.reversed() {
            let key = String(describing: entry.1)
            if seen.insert(key).inserted { picked.append(entry) }
            if picked.count == 3 { break }
        }
        return picked.reversed().map { entry in
            let mins = Int(now.timeIntervalSince(entry.0) / 60)
            let what = entry.1.render(settings.lang)
            switch settings.lang {
            case .zh: return mins < 1 ? "刚刚\(what)" : "\(mins)分钟前\(what)"
            case .ja: return mins < 1 ? "さっき\(what)" : "\(mins)分前に\(what)"
            case .en: return mins < 1 ? "just now, \(what)" : "\(mins) min ago, \(what)"
            }
        }
    }

    /// Remember something notable; feeds the LLM's situational awareness.
    func logEvent(_ e: PetEvent) {
        eventLog.append((Date(), e))
        let cutoff = Date().addingTimeInterval(-15 * 60)
        eventLog.removeAll { $0.0 < cutoff }
        if eventLog.count > 6 { eventLog.removeFirst(eventLog.count - 6) }
    }

    func currentContext() -> PetContext {
        let hour = Calendar.current.component(.hour, from: Date())
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let hint: String
        let perched = currentPlatformID != nil
        switch (core.isSleeping, core.activity) {
        case (true, _) where perched:
            hint = eventText(zh: "趴在一个应用窗口顶上打盹(刚被吵醒)", ja: "アプリのウィンドウの上でうたた寝(起こされた)", en: "napping on top of an app window (just disturbed)")
        case (true, _): hint = eventText(zh: "睡觉(刚被吵醒)", ja: "寝ていた(起こされた)", en: "sleeping (just disturbed)")
        case (_, .walk) where perched:
            hint = eventText(zh: "在一个应用窗口的顶边上走来走去", ja: "アプリのウィンドウの上のふちを歩いている", en: "walking along the top edge of an app window")
        case (_, .walk): hint = eventText(zh: "在桌面上散步", ja: "デスクトップを散歩中", en: "strolling around the desktop")
        case (_, .play): hint = eventText(zh: "玩毛线球", ja: "毛糸だまで遊び中", en: "playing with a yarn ball")
        case (_, .eat): hint = eventText(zh: "吃东西", ja: "食事中", en: "eating")
        case (_, .jumpPose), (_, .fall):
            hint = eventText(zh: "在空中跳跃", ja: "ジャンプ中", en: "mid-jump in the air")
        default:
            hint = perched
                ? eventText(zh: "蹲在一个应用窗口顶上,居高临下看着主人", ja: "アプリのウィンドウの上にちょこんと座って見下ろしている", en: "perched on top of an app window, watching your owner from above")
                : eventText(zh: "待在桌面上陪主人", ja: "デスクトップでご主人のそばにいる", en: "hanging out on the desktop with your owner")
        }
        return PetContext(
            lang: settings.lang,
            stats: core.stats,
            activityHint: hint,
            timeOfDay: Persona.timeOfDay(hour: hour, lang: settings.lang),
            clockString: df.string(from: Date()),
            recentEvents: renderRecentEvents(),
            companionMinutes: Int(Date().timeIntervalSince(sessionStart) / 60))
    }

    /// User chat message → think anim → stream into bubble + chat, apply emotion,
    /// and OBEY: commands detected in the message are executed even if the model
    /// forgets to emit the action tag.
    func userSays(_ text: String) {
        guard brain.isReady else { return }
        if core.isSleeping { wake(grumpy: false) }  // being spoken to wakes her

        // priority: goodnight (owner going to bed) > creative asks > motion commands
        let goodnight = Persona.detectGoodnight(text)
        let creative = goodnight ? nil : Persona.detectCreative(text)
        let intent = (goodnight || creative != nil) ? nil : Persona.detectCommand(text)
        let hint = goodnight
            ? Persona.goodnightHint(settings.lang)
            : creative.map { Persona.creativeInstruction($0, lang: settings.lang) }
                ?? intent.map { Persona.commandHint($0, lang: settings.lang) }
        core.activity = .think
        core.setEmotion(.curious, hold: 30)
        bubble?.show(text: "…", above: petCenter, petScale: scale)
        bubbleStreaming = true
        brain.generate(
            userContent: text,
            context: currentContext(),
            recordHistory: true,
            commandHint: hint,
            creative: creative.map { ($0, L10n.creativeCanned($0, lang: settings.lang)) },
            onEmotion: { [weak self] emo in
                guard let self else { return }
                self.core.setEmotion(emo, hold: 20)
                self.applyEmotionBurst(emo)
            },
            onText: { [weak self] text in
                guard let self else { return }
                if self.core.activity == .think { self.core.activity = .talk }
                self.bubble?.update(text: text)
                self.chatMirror?(text, false)
            },
            onDone: { [weak self] parsed in
                guard let self else { return }
                self.bubbleStreaming = false
                if let parsed, !parsed.text.isEmpty {
                    self.bubble?.update(text: parsed.text)
                    self.chatMirror?(parsed.text, true)
                    self.bubbleHideAt = Date().addingTimeInterval(self.bubbleDuration(for: parsed.text) + 2)
                    self.core.stats.happiness += 2.5
                    self.core.stats.clamp()
                    if self.core.activity == .think { self.core.activity = .talk }
                } else {
                    // brain came up empty — react with a cute confused fallback
                    let line = L10n.canned(.confused)
                    self.core.setEmotion(.curious, hold: 4)
                    self.bubble?.update(text: line)
                    self.chatMirror?(line, true)
                    self.bubbleHideAt = Date().addingTimeInterval(4)
                    if self.core.activity == .think { self.core.activity = .talk }
                }
                // owner said goodnight: she says goodnight back, then tucks in too
                if goodnight {
                    self.obey(.sleep)
                    return
                }
                // deterministic intent wins; model tag fills in for uncaught phrasing
                // (except Japanese, whose action tags misfire — intent only there).
                // Random model [sleep] tags are ignored unless the user asked or she's tired.
                var action = intent
                if action == nil, self.settings.lang != .ja { action = parsed?.action }
                if action == .sleep, intent != .sleep, self.core.stats.energy > 30 {
                    action = nil
                }
                if let action { self.obey(action) }
            })
    }

    /// Execute a commanded action, sequenced so it doesn't stomp the reply bubble.
    func obey(_ action: PetAction) {
        if action != .sleep {
            pendingSleep?.cancel()   // a newer command overrides a queued goodnight
            pendingSleep = nil
        }
        switch action {
        case .sleep:
            // let her finish saying goodnight first
            let delay = max(0, bubbleHideAt.timeIntervalSinceNow) + 0.4
            pendingSleep?.cancel()
            pendingSleep = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !self.core.isSleeping, self.core.activity != .drag else { return }
                self.fallAsleep(commanded: true)
            }
        case .wake:
            wake(grumpy: false)
            core.setEmotion(.happy, hold: 4)
            hopInPlace()
        case .come:
            callOver()
        case .walk:
            // .talk is "busy" but walking while finishing the sentence is fine
            guard !core.activity.isBusy || core.activity == .talk, !airborne else { return }
            let span = surfaceSpan()
            if span.hi - span.lo > 40 {
                walkTargetX = .random(in: span.lo...span.hi)
                walkDir = walkTargetX > petCenter.x ? 1 : -1
                core.activity = .walk
            }
        case .climb:
            guard !airborne else { return }
            let ups = tracker.reachable(from: standY - feetDrop)
            if let p = ups.min(by: { $0.y < $1.y }) {
                let lo = max(p.minX + 20, petCenter.x - 460)
                let hi = min(p.maxX - 20, petCenter.x + 460)
                if lo < hi {
                    jumpTo(targetX: .random(in: lo...hi), surfaceY: p.y, ontoPlatform: true)
                    return
                }
            }
            hopInPlace()  // no window in reach — cute attempt anyway
        case .down:
            guard currentPlatformID != nil, !airborne else { return }
            let f = screenFrame()
            let tx = min(max(petCenter.x, f.minX + 60), f.maxX - 60)
            jumpTo(targetX: tx, surfaceY: f.minY, ontoPlatform: false)
        case .play:
            guard !core.activity.isBusy || core.activity == .talk else { return }
            core.activity = .play
            core.actionPhase = 0
            activityEndsAt = Date().addingTimeInterval(6.5)
            core.setEmotion(.playful, hold: 8)
        case .eat:
            guard !airborne else { return }
            feed(fish: true)
        case .stop:
            chasingCursor = false
            if core.activity.isBusy || core.activity == .walk {
                core.actionPhase = 0
                if !airborne { core.activity = .idle }
            }
            core.setEmotion(.calm, hold: 4)
            nextDecision = Date().addingTimeInterval(15)  // stay put for a bit
        case .dance, .spin, .jump, .stretch:
            perform(action)
        }
    }

    /// Spontaneous or event-driven LLM line (not recorded into visible chat history).
    /// Falls back to a canned line if the model returns nothing usable.
    private func runLLMEvent(_ event: String, fallback: (L10n.CannedCategory, Emotion)? = nil) {
        runLLMPrompt(Persona.eventPrompt(event, lang: settings.lang), fallback: fallback)
    }

    private func runLLMPrompt(_ prompt: String, fallback: (L10n.CannedCategory, Emotion)? = nil) {
        core.activity = .think
        bubbleStreaming = true
        bubble?.show(text: "…", above: petCenter, petScale: scale)
        brain.generate(
            userContent: prompt,
            context: currentContext(),
            recordHistory: false,
            onEmotion: { [weak self] emo in
                self?.core.setEmotion(emo, hold: 15)
                self?.applyEmotionBurst(emo)
            },
            onText: { [weak self] text in
                guard let self else { return }
                if self.core.activity == .think { self.core.activity = .talk }
                self.bubble?.update(text: text)
            },
            onDone: { [weak self] parsed in
                guard let self else { return }
                self.bubbleStreaming = false
                if let parsed, !parsed.text.isEmpty {
                    self.bubble?.update(text: parsed.text)
                    self.bubbleHideAt = Date().addingTimeInterval(self.bubbleDuration(for: parsed.text))
                    // remember what she said on her own — later chats build on it
                    self.brain.noteAssistantLine(parsed.text)
                    // spontaneous/event lines: only motion actions. [sleep] misfires,
                    // [eat] would be self-feeding (mouth moves with no bubble context),
                    // and Japanese action tags misfire wholesale.
                    let allowed: Set<PetAction> = [.dance, .spin, .jump, .stretch, .come, .walk, .climb, .down, .play]
                    if let action = parsed.action, allowed.contains(action), self.settings.lang != .ja {
                        self.perform(action)
                    }
                } else if let (cat, emo) = fallback {
                    if self.core.activity == .think { self.core.activity = .idle }
                    self.showCanned(cat, emotion: emo)
                } else {
                    self.bubble?.hide()
                    if self.core.activity == .think || self.core.activity == .talk {
                        self.core.activity = .idle
                    }
                }
            })
    }

    private func applyEmotionBurst(_ emo: Emotion) {
        switch emo {
        case .love: core.spawn(.heart, count: 3, near: CGPoint(x: 0, y: 40))
        case .excited, .happy: core.spawn(.sparkle, count: 3, near: CGPoint(x: 0, y: 45))
        case .surprised: core.spawn(.exclamation, count: 1, near: CGPoint(x: 0, y: 55), spread: 4)
        case .curious: core.spawn(.question, count: 1, near: CGPoint(x: 0, y: 55), spread: 4)
        case .angry: core.spawn(.sweat, count: 1, near: CGPoint(x: 18, y: 45), spread: 4)
        default: break
        }
    }

    func perform(_ action: PetAction) {
        guard core.activity != .drag, !airborne else { return }
        core.actionPhase = 0
        switch action {
        case .dance:
            core.activity = .dance
            activityEndsAt = Date().addingTimeInterval(4.2)
        case .spin:
            core.activity = .spinPose
            activityEndsAt = Date().addingTimeInterval(1.4)
        case .jump:
            hopInPlace()
        case .stretch:
            core.activity = .stretchPose
            activityEndsAt = Date().addingTimeInterval(2.2)
        case .sleep:
            fallAsleep()
        case .wake, .come, .walk, .climb, .down, .play, .eat, .stop:
            obey(action)
        }
    }

    // MARK: - Spontaneous chatter

    /// Due time derives from the last line + current settings, so changing the
    /// chattiness setting takes effect immediately. Once due, we retry every tick
    /// until the pet is actually free to speak — busy moments delay, never skip.
    private func scheduleChatter(initial: Bool = false) {
        chatterJitter = Double.random(in: 0.7...1.5)
        lastChatterAt = initial
            ? Date().addingTimeInterval(-max(2, settings.chatterFreq) * 60 * chatterJitter + .random(in: 60...110))
            : Date()
    }

    private func updateChatter(_ now: Date) {
        guard settings.chatterEnabled else { return }
        let due = lastChatterAt.addingTimeInterval(max(2, settings.chatterFreq) * 60 * chatterJitter)
        guard now > due else { return }
        guard !core.isSleeping, core.activity == .idle || core.activity == .walk,
            bubbleHideAt == .distantPast, !bubbleStreaming, !airborne
        else { return }  // still due — retries next tick

        scheduleChatter()
        let hour = Calendar.current.component(.hour, from: now)
        let timeCat: L10n.CannedCategory = hour < 5 ? .night : hour < 11 ? .morning : hour < 18 ? .afternoon : hour < 23 ? .evening : .night
        if brain.isReady, !brain.isGenerating, Double.random(in: 0..<1) < 0.75 {
            core.activity = .idle
            let prompt = Persona.spontaneousPrompt(currentContext(), lang: settings.lang)
            runLLMPrompt(prompt, fallback: (timeCat, .happy))
        } else {
            showCanned(Double.random(in: 0..<1) < 0.5 ? timeCat : .bored, emotion: nil, remember: true)
        }
    }

    // MARK: - User interactions

    func pokeTap() {
        if core.isSleeping {
            wake(grumpy: true)
            return
        }
        let now = Date()
        recentPokes = recentPokes.filter { now.timeIntervalSince($0) < 3 } + [now]
        core.squash = 0.12
        if recentPokes.count >= 4 {
            recentPokes.removeAll()
            logEvent(.pokedALot)
            core.setEmotion(.angry, hold: 5)
            core.spawn(.sweat, count: 1, near: CGPoint(x: 20, y: 45), spread: 4)
            core.stats.happiness -= 2
            core.stats.clamp()
            showCanned(.pokeAnnoyed, emotion: .angry)
        } else {
            core.setEmotion(.surprised, hold: 2.5)
            if Double.random(in: 0..<1) < 0.55 { showCanned(.poke, emotion: nil) }
        }
    }

    func petStroke() {
        let now = Date()
        guard now.timeIntervalSince(lastPetStroke) > 2.5 else { return }
        lastPetStroke = now
        logEvent(.petted)
        guard !core.isSleeping else {
            core.spawn(.heart, count: 1, near: CGPoint(x: 0, y: 40))
            return
        }
        core.setEmotion(.love, hold: 4)
        core.spawn(.heart, count: 3, near: CGPoint(x: 0, y: 42))
        core.stats.happiness += 4
        core.stats.clamp()
        if now.timeIntervalSince(lastEventLLM) > 90, brain.isReady, !brain.isGenerating,
            Double.random(in: 0..<1) < 0.35
        {
            lastEventLLM = now
            runLLMEvent(
                eventText(zh: "主人温柔地摸了摸你的头", ja: "ご主人が優しく頭をなでてくれた", en: "your owner gently petted your head"),
                fallback: (.petted, .love))
        } else if Double.random(in: 0..<1) < 0.5 {
            showCanned(.petted, emotion: .love)
        }
    }

    func feed(fish: Bool) {
        if core.isSleeping { wake(grumpy: false) }
        guard !core.activity.isBusy || core.activity == .talk else { return }
        if core.stats.fullness > 92 {
            showCanned(.fullTummy, emotion: .shy)
            return
        }
        core.activity = .eat(food: fish ? "🐟" : "🍪")
        logEvent(fish ? .fedFish : .fedCookie)
        core.actionPhase = 0
        activityEndsAt = Date().addingTimeInterval(3.2)
        core.stats.fullness += fish ? 34 : 24
        core.stats.happiness += 6
        core.stats.clamp()
        let now = Date()
        if now.timeIntervalSince(lastEventLLM) > 90, brain.isReady, !brain.isGenerating,
            Double.random(in: 0..<1) < 0.4
        {
            lastEventLLM = now
            let what = fish
                ? eventText(zh: "主人喂了你最爱的小鱼干", ja: "ご主人が大好物のにぼしをくれた", en: "your owner fed you your favorite dried fish")
                : eventText(zh: "主人喂了你小饼干", ja: "ご主人がクッキーをくれた", en: "your owner fed you a cookie")
            // let the munching play out first; delay the LLM line slightly
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3.4))
                self?.runLLMEvent(what, fallback: (fish ? .fedFish : .fedCookie, .happy))
            }
        } else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3.4))
                self?.showCanned(fish ? .fedFish : .fedCookie, emotion: .happy)
            }
        }
    }

    func play() {
        if core.isSleeping { wake(grumpy: false) }
        guard !core.activity.isBusy else { return }
        core.activity = .play
        core.actionPhase = 0
        activityEndsAt = Date().addingTimeInterval(6.5)
        core.setEmotion(.playful, hold: 8)
        showCanned(.playStart, emotion: .playful)
    }

    /// `commanded`: the owner explicitly asked (chat command / menu / quick action).
    /// Commanded naps stick for a while even at full energy — otherwise the
    /// energy>96 auto-wake cancels the nap on the very next tick.
    func fallAsleep(commanded: Bool = false) {
        guard !core.isSleeping else { return }
        core.isSleeping = true
        logEvent(.fellAsleep)
        core.activity = .sleep
        core.setEmotion(.sleepy, hold: 3)
        minSleepUntil = commanded ? Date().addingTimeInterval(300) : .distantPast
        bubble?.hide()
        bubbleHideAt = .distantPast
    }

    func wake(grumpy: Bool) {
        guard core.isSleeping else { return }
        core.isSleeping = false
        core.activity = .idle
        lastWokeAt = Date()
        minSleepUntil = .distantPast
        if grumpy {
            logEvent(.wokenByOwner)
            core.setEmotion(.angry, hold: 4)
            showCanned(.wokenGrumpy, emotion: .sleepy)
            core.stats.happiness -= 1
            core.stats.clamp()
        }
        nextDecision = Date().addingTimeInterval(5)
    }

    func callOver() {
        if core.isSleeping { wake(grumpy: false) }
        let mouse = NSEvent.mouseLocation
        let f = screenFrame()
        let targetX = min(max(mouse.x, f.minX + 60), f.maxX - 60)
        if currentPlatformID != nil {
            // leap down first; walk over after landing
            jumpTo(targetX: min(max(targetX, petCenter.x - 380), petCenter.x + 380),
                   surfaceY: f.minY, ontoPlatform: false)
        }
        walkTargetX = targetX
        walkDir = walkTargetX > petCenter.x ? 1 : -1
        chasingCursor = true
        if !airborne { core.activity = .walk }
        core.setEmotion(.excited, hold: 6)
    }

    // MARK: - Dragging

    func beginDrag() {
        brainInterruptForDrag()
        core.activity = .drag
        airborne = false
        gravity = 2600
        currentPlatformID = nil
        if core.isSleeping {
            core.isSleeping = false
            lastWokeAt = Date()
        }
        core.setEmotion(.surprised, hold: 3)
    }

    private func brainInterruptForDrag() {
        if bubbleStreaming {
            brain.cancelGeneration()
            bubbleStreaming = false
            bubble?.hide()
            bubbleHideAt = .distantPast
        }
    }

    func dragTo(_ point: CGPoint) {
        petCenter = point
        moveWindow?(petCenter)
        bubble?.reposition(above: petCenter, petScale: scale)
    }

    func endDrag(velocity v: CGVector) {
        velocity = CGVector(dx: max(-900, min(900, v.dx)), dy: max(-200, min(1100, v.dy)))
        prevFeetY = petCenter.y - feetDrop
        if petCenter.y > groundY + 2 || abs(velocity.dy) > 50 {
            airborne = true
        } else {
            petCenter.y = groundY
            core.activity = .idle
            moveWindow?(petCenter)
        }
        if core.activity == .drag { core.activity = airborne ? .fall : .idle }
        nextDecision = Date().addingTimeInterval(2)
    }

    // MARK: - Chat window awareness

    func chatOpened() {
        core.attention = 1
        if core.isSleeping { wake(grumpy: false) }
    }

    func chatClosed() {
        core.attention = 0
    }

    func languageChanged() {
        // nothing persistent; next lines just come out in the new language
    }

    func shutdown() {
        timer?.invalidate()
        Persistence.saveStats(core.stats)
    }
}

/// Implemented by the bubble window controller.
@MainActor
protocol BubbleController: AnyObject {
    func show(text: String, above petCenter: CGPoint, petScale: CGFloat)
    func update(text: String)
    func reposition(above petCenter: CGPoint, petScale: CGFloat)
    func hide()
}
