import Foundation

// MARK: - Emotion (drives face + effects; fed by LLM tags and events)

enum Emotion: String, Codable, CaseIterable {
    case neutral, happy, excited, love, shy, sad, sleepy, curious, surprised, angry, hungry, proud, playful, calm

    /// Parse an LLM tag (English canonical; en/zh/ja synonyms accepted for robustness).
    static func fromTag(_ raw: String) -> Emotion? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let e = Emotion(rawValue: s) { return e }
        let synonyms: [String: Emotion] = [
            "joyful": .happy, "glad": .happy, "cheerful": .happy, "joy": .happy,
            "thrilled": .excited, "energetic": .excited,
            "affectionate": .love, "loving": .love, "adoring": .love,
            "embarrassed": .shy, "bashful": .shy, "timid": .shy,
            "unhappy": .sad, "down": .sad, "gloomy": .sad, "depressed": .sad,
            "tired": .sleepy, "drowsy": .sleepy, "exhausted": .sleepy,
            "interested": .curious, "wondering": .curious, "intrigued": .curious,
            "shocked": .surprised, "amazed": .surprised, "startled": .surprised,
            "mad": .angry, "annoyed": .angry, "grumpy": .angry, "upset": .angry,
            "starving": .hungry, "peckish": .hungry,
            "confident": .proud, "smug": .proud,
            "mischievous": .playful, "silly": .playful, "fun": .playful,
            "relaxed": .calm, "content": .calm, "peaceful": .calm, "neutral": .calm,
            "开心": .happy, "高兴": .happy, "うれしい": .happy, "嬉しい": .happy,
            "兴奋": .excited, "激动": .excited, "わくわく": .excited,
            "爱心": .love, "喜欢": .love, "らぶ": .love, "大好き": .love,
            "害羞": .shy, "てれ": .shy, "照れ": .shy,
            "难过": .sad, "伤心": .sad, "かなしい": .sad, "悲しい": .sad,
            "困": .sleepy, "想睡": .sleepy, "ねむい": .sleepy, "眠い": .sleepy,
            "好奇": .curious, "きになる": .curious, "気になる": .curious,
            "惊讶": .surprised, "吃惊": .surprised, "びっくり": .surprised,
            "生气": .angry, "ぷんぷん": .angry, "怒り": .angry,
            "饿": .hungry, "饿了": .hungry, "はらぺこ": .hungry,
            "得意": .proud, "どや": .proud,
            "调皮": .playful, "淘气": .playful, "いたずら": .playful,
            "平静": .calm, "おちつき": .calm, "落ち着き": .calm,
        ]
        return synonyms[s]
    }
}

// MARK: - Action tags the LLM may emit to trigger behaviors

enum PetAction: String, CaseIterable {
    case dance, spin, jump, stretch, sleep
    case wake, come, walk, climb, down, play, eat, stop

    static func fromTag(_ raw: String) -> PetAction? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let a = PetAction(rawValue: s) { return a }
        let synonyms: [String: PetAction] = [
            "跳舞": .dance, "ダンス": .dance,
            "转圈": .spin, "くるくる": .spin,
            "跳跃": .jump, "ジャンプ": .jump, "跳": .jump,
            "伸懒腰": .stretch, "のび": .stretch,
            "睡觉": .sleep, "ねる": .sleep, "寝る": .sleep,
            "醒来": .wake, "起床": .wake, "起きる": .wake,
            "过来": .come, "おいで": .come, "here": .come,
            "散步": .walk, "散歩": .walk, "wander": .walk,
            "爬窗": .climb, "上窗": .climb, "窓に乗る": .climb,
            "下来": .down, "降りる": .down,
            "玩": .play, "遊ぶ": .play,
            "吃": .eat, "食べる": .eat,
            "停": .stop, "やめる": .stop,
        ]
        return synonyms[s]
    }
}

// MARK: - Activity (whole-body state machine)

enum Activity: Equatable {
    case idle
    case walk
    case sleep
    case eat(food: String)      // emoji shown while munching
    case drag                   // held by cursor
    case fall                   // airborne after release
    case land                   // squash frames right after touchdown
    case think                  // LLM generating
    case talk                   // bubble streaming/showing
    case stretchPose
    case dance
    case spinPose
    case jumpPose
    case play                   // yarn ball
    case sulk

    var isBusy: Bool {          // states the autonomy loop must not interrupt
        switch self {
        case .idle, .walk, .sulk: return false
        default: return true
        }
    }
}

// MARK: - Stats

struct PetStats: Codable {
    var fullness: Double = 78    // 0 starving … 100 stuffed
    var energy: Double = 90      // 0 exhausted … 100 fresh
    var happiness: Double = 72   // 0 miserable … 100 blissful
    var lastSaved: Date = .now

    mutating func clamp() {
        fullness = min(100, max(0, fullness))
        energy = min(100, max(0, energy))
        happiness = min(100, max(0, happiness))
    }

    var moodWord: String {       // coarse mood for LLM context
        if happiness >= 75 { return "great" }
        if happiness >= 45 { return "okay" }
        if happiness >= 25 { return "grumpy" }
        return "sad"
    }
}

// MARK: - Particles (hearts, zzz, notes, sparkles…)

struct Particle: Identifiable {
    enum Kind { case heart, zzz, note, sparkle, crumb, star, sweat, question, exclamation }
    let id = UUID()
    var kind: Kind
    var x: Double      // canvas-space (200x200 design units), relative to pet center
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double = 0
    var lifetime: Double
    var scale: Double = 1
}

// MARK: - Recent-event memory (feeds the LLM's state awareness)

enum PetEvent {
    case petted, fedFish, fedCookie, hardFall, climbedWindow, wokenByOwner
    case pokedALot, playedYarn, fellAsleep, wokeUp, cameWhenCalled

    /// Pronoun-free renderings: the 1B model sometimes recites context verbatim,
    /// and "你摔了一跤" coming out of the pet's own mouth reads broken — these read
    /// fine in first person even when leaked.
    func render(_ lang: Lang) -> String {
        let zh: [PetEvent: String] = [
            .petted: "被主人摸了头", .fedFish: "吃到了主人给的小鱼干", .fedCookie: "吃到了主人给的小饼干",
            .hardFall: "重重摔了一跤", .climbedWindow: "跳上了一个窗口顶",
            .wokenByOwner: "被主人叫醒", .pokedALot: "被主人戳了好多下",
            .playedYarn: "玩了毛线球", .fellAsleep: "睡着了", .wokeUp: "醒来了",
            .cameWhenCalled: "跑到了主人身边",
        ]
        let en: [PetEvent: String] = [
            .petted: "got head pats", .fedFish: "ate some dried fish",
            .fedCookie: "ate a cookie", .hardFall: "took a hard tumble",
            .climbedWindow: "climbed onto a window", .wokenByOwner: "got woken up",
            .pokedALot: "got poked a lot", .playedYarn: "played with the yarn ball",
            .fellAsleep: "fell asleep", .wokeUp: "woke up",
            .cameWhenCalled: "ran over when called",
        ]
        let ja: [PetEvent: String] = [
            .petted: "頭をなでてもらった", .fedFish: "にぼしをもらって食べた",
            .fedCookie: "クッキーをもらって食べた", .hardFall: "ドスンと転んだ",
            .climbedWindow: "ウィンドウの上に飛び乗った", .wokenByOwner: "起こされた",
            .pokedALot: "いっぱいつつかれた", .playedYarn: "毛糸だまで遊んだ",
            .fellAsleep: "眠った", .wokeUp: "目が覚めた",
            .cameWhenCalled: "呼ばれて駆けつけた",
        ]
        switch lang {
        case .zh: return zh[self] ?? ""
        case .en: return en[self] ?? ""
        case .ja: return ja[self] ?? ""
        }
    }
}

// MARK: - Context snapshot handed to the LLM

struct PetContext {
    var lang: Lang
    var stats: PetStats
    var activityHint: String     // "sleeping", "walking around", …
    var timeOfDay: String        // "morning" | "afternoon" | "evening" | "late night"
    var clockString: String      // "22:41"
    var recentEvents: [String] = []   // rendered with relative time, newest last
    var companionMinutes: Int = 0     // how long the app has been running this session
}
