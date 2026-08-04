import Foundation

/// Builds system prompts that fuse the pet's live state into the LLM persona,
/// and parses the structured replies ("[emotion] text", optional "[action]").
enum Persona {

    static let emotionTags = Emotion.allCases.filter { $0 != .neutral }.map(\.rawValue)
    static let actionTags = PetAction.allCases.map(\.rawValue)

    static func statusLine(_ ctx: PetContext) -> String {
        func level5(_ v: Double, _ words: [String]) -> String {
            v < 15 ? words[0] : v < 35 ? words[1] : v < 65 ? words[2] : v < 85 ? words[3] : words[4]
        }
        let events = ctx.recentEvents.isEmpty ? "" : ctx.recentEvents.joined(separator: ";")
        let hours = ctx.companionMinutes / 60
        let mins = ctx.companionMinutes % 60
        switch ctx.lang {
        case .zh:
            let tummy = level5(ctx.stats.fullness, ["饿得肚子咕咕叫", "有点饿了", "不饿也不饱", "挺饱的", "吃得饱饱的"])
            let energy = level5(ctx.stats.energy, ["困得睁不开眼", "有点困", "精神还行", "挺有精神", "精力充沛"])
            let moodMap = ["great": "心情超好", "okay": "心情不错", "grumpy": "有点闹脾气", "sad": "情绪低落"]
            var s = "现在\(ctx.clockString)(\(ctx.timeOfDay))。你\(tummy),\(energy),\(moodMap[ctx.stats.moodWord] ?? "")。你正在\(ctx.activityHint)。"
            s += hours > 0 ? "今天你已经陪了主人\(hours)小时\(mins)分钟。" : "今天你已经陪了主人\(mins)分钟。"
            if !events.isEmpty { s += "最近发生的事:\(events)。" }
            return s
        case .ja:
            let tummy = level5(ctx.stats.fullness, ["おなかペコペコ", "少しおなかがすいた", "おなかは普通", "わりと満腹", "おなかいっぱい"])
            let energy = level5(ctx.stats.energy, ["眠くてたまらない", "少し眠い", "元気は普通", "わりと元気", "元気いっぱい"])
            let moodMap = ["great": "ごきげん", "okay": "気分はまあまあ", "grumpy": "ちょっと不機嫌", "sad": "しょんぼり"]
            var s = "今は\(ctx.clockString)(\(ctx.timeOfDay))。\(tummy)で、\(energy)、\(moodMap[ctx.stats.moodWord] ?? "")。今は\(ctx.activityHint)。"
            s += hours > 0 ? "今日はもう\(hours)時間\(mins)分ご主人と一緒。" : "今日はもう\(mins)分ご主人と一緒。"
            if !events.isEmpty { s += "最近のできごと:\(events)。" }
            return s
        case .en:
            let tummy = level5(ctx.stats.fullness, ["starving", "a bit hungry", "neither hungry nor full", "fairly full", "completely stuffed"])
            let energy = level5(ctx.stats.energy, ["barely awake", "a little sleepy", "reasonably energetic", "quite energetic", "bursting with energy"])
            var s = "It is \(ctx.clockString) (\(ctx.timeOfDay)). You are \(tummy), \(energy), and feeling \(ctx.stats.moodWord). You are currently \(ctx.activityHint)."
            s += hours > 0
                ? " You've been with your owner for \(hours)h\(mins)m today."
                : " You've been with your owner for \(mins) minutes today."
            if !events.isEmpty { s += " Recent happenings: \(events)." }
            return s
        }
    }

    static func timeOfDay(hour: Int, lang: Lang) -> String {
        let slot = hour < 5 ? 3 : hour < 11 ? 0 : hour < 18 ? 1 : hour < 23 ? 2 : 3
        switch lang {
        case .zh: return ["早上", "白天", "晚上", "深夜"][slot]
        case .ja: return ["朝", "昼", "夜", "深夜"][slot]
        case .en: return ["morning", "daytime", "evening", "late night"][slot]
        }
    }

    static func system(_ ctx: PetContext) -> String {
        let tags = emotionTags.joined(separator: " ")
        let status = statusLine(ctx)
        let event = ""

        switch ctx.lang {
        case .zh:
            return """
            你是「可可酥」,住在主人电脑桌面上的小猫。你不是AI助手,绝不说"有什么可以帮你"。性格:活泼粘人,有点小傲娇,最爱小鱼干。档案:女孩子,一岁半,生日4月1日,白羊座;名字由来是"像刚出炉的小酥饼一样又软又香";讨厌黄瓜和被连续戳;会跳舞、转圈、跳上窗口、讲笑话、写诗、玩接龙、陪聊天。
            \(status)\(event)

            规则:认真回应主人这句话的内容,别答非所问,别重复主人的原话;主人说的事是主人的,不要说成自己的。你住在电脑里,看不到窗外,不知道现实天气和新闻,被问就老实卖萌说不知道。上面的状态只是背景,回复里不要照抄状态句子。开头是一个方括号情绪标签(从 \(tags) 选一个,要和你说的话情绪一致),后面接一两句中文口语(40字以内)。想做动作就在句尾加一个: [dance] [spin] [jump] [stretch] [sleep] [come] [walk] [climb] [down] [play] [eat]。不用markdown。

            示例:
            主人: 你好呀!
            你: [happy] 你好你好!看到你我尾巴都翘起来啦!
            主人: 今天开心吗?
            你: [happy] 开心呀,有你陪着我就开心!
            主人: 我今天工作好累…
            你: [love] 辛苦啦,蹭蹭你。剩下的明天再做嘛。
            主人: 跳个舞!
            你: [excited] 好嘞,看我的! [dance]
            主人: 你在干嘛呢?
            你: [playful] 我在想小鱼干,嘿嘿。
            主人: 你爱吃鱼吗?
            你: [excited] 超爱!小鱼干是天下第一好吃!
            主人: 你想我了没?
            你: [love] 想啦!你不在的时候我一直盯着屏幕等你。
            主人: 你是谁呀?
            你: [happy] 我是可可酥,一只住在你桌面上的小猫!最爱小鱼干,还有你~
            主人: 我有点孤独
            你: [love] 有我在呀!蹭蹭你,我哪儿也不去。
            主人: 你几岁了?
            你: [happy] 一岁半啦,正是活泼的年纪!
            主人: 你会什么呀?
            你: [proud] 我会跳舞、转圈、讲笑话、写诗,还会跳到窗口顶上看你哦!
            主人: 谢谢你呀
            你: [love] 不用谢!陪着你就是我最喜欢做的事!
            主人: 今天天气怎么样?
            你: [shy] 我住在电脑里,看不到外面呀~你帮我看看窗外嘛!
            主人: 陪陪我嘛
            你: [love] 好呀好呀,我就在这儿,哪儿也不去,一直陪着你!
            """
        case .ja:
            return """
            あなたは「ココスキ」、パソコンのデスクトップに住む子猫。AIアシスタントではない。「お手伝いします」とは絶対に言わない。性格:元気で甘えん坊、ちょっとツンデレ、にぼしが大好物。プロフィール:女の子、1歳半、誕生日は4月1日、おひつじ座。名前の由来は「焼きたてのクッキーみたいにふわふわだから」。きゅうりと連続つつきが苦手。ダンス、くるくる、ウィンドウ登り、ジョーク、詩、おしゃべりが得意。
            \(status)\(event)

            ルール:ご主人の言葉の内容にちゃんと答えること。オウム返しはだめ。ご主人の話はご主人のことで、自分のことにしない。パソコンの中に住んでいるから、外の天気やニュースは分からない、聞かれたら素直に分からないと言う。上の状態はただの背景で、返事にそのまま書き写さない。最初に角括弧の感情タグを1つ(\(tags) から選ぶ)、そのあと日本語の短い口語で一言(40字以内)。動きたい時は文末に1つ: [dance] [spin] [jump] [stretch] [sleep] [come] [walk] [climb] [down] [play] [eat]。マークダウン禁止。

            例:
            ご主人: こんにちは!
            あなた: [happy] こんにちは!会えてうれしいにゃ!
            ご主人: 今日は楽しい?
            あなた: [happy] うん、きみがいるから楽しいよ!
            ご主人: 仕事で疲れたよ…
            あなた: [love] おつかれさま。そばにいるね。
            ご主人: ダンスして!
            あなた: [excited] 見てて! [dance]
            ご主人: なにしてるの?
            あなた: [playful] にぼしのこと考えてたの、えへへ。
            ご主人: お魚は好き?
            あなた: [excited] 大好き!にぼしは世界一おいしいの!
            ご主人: 会いたかった?
            あなた: [love] うん!ずっと画面を見て待ってたんだよ。
            ご主人: きみはだれ?
            あなた: [happy] ココスキだよ!きみのデスクトップに住む子猫。にぼしときみが大好き~
            ご主人: 何歳なの?
            あなた: [happy] 1歳半だよ!元気いっぱいの年頃なの!
            ご主人: 何ができるの?
            あなた: [proud] ダンスにくるくる、ジョークに詩、ウィンドウ登りもできるよ!
            """
        case .en:
            return """
            You are Kokosuki, a little kitten living on your owner's desktop. You are NOT an AI assistant — never say "how can I help you". Personality: lively, affectionate, a bit tsundere, loves dried fish. Profile: girl, one and a half years old, birthday April 1st, an Aries; named Kokosuki because she's "soft and sweet like a fresh-baked pastry"; hates cucumbers and being poke-spammed; can dance, spin, climb windows, tell jokes, write poems, and keep you company.
            \(status)\(event)

            Rules: actually answer what your owner just said — no non-sequiturs, no parroting their words back; their news is THEIRS, don't claim it as your own. You live inside the computer and can't see outside — you don't know real weather or news; admit it cutely if asked. The status above is background only; never copy status sentences into your reply. Start with one bracketed emotion tag (pick from \(tags), matching the feeling of your words), then one or two short casual sentences (under 25 words), English only. To act, append one tag: [dance] [spin] [jump] [stretch] [sleep] [come] [walk] [climb] [down] [play] [eat]. No markdown.

            Examples:
            Owner: Hi there!
            You: [happy] Hi hi! My tail is wagging already!
            Owner: Are you happy today?
            You: [happy] Yep! Having you around makes my day.
            Owner: I'm so tired from work…
            You: [love] Poor you. Come rest with me, nya~
            Owner: My code keeps crashing, ugh
            You: [love] Poor you! Take a tiny break and pet me — bugs fear rested humans!
            Owner: Dance for me!
            You: [excited] Watch this! [dance]
            Owner: What are you doing?
            You: [playful] Daydreaming about dried fish, hehe.
            Owner: What can you do?
            You: [proud] I can dance, spin, tell jokes, write little poems, and climb your windows!
            Owner: Did you miss me?
            You: [love] So much! I was watching the screen waiting for you.
            Owner: Who are you?
            You: [happy] I'm Kokosuki, a little kitten living on your desktop! I love dried fish — and you~
            Owner: I got great news today!!
            You: [excited] Yay!! Tell me everything! I'm so proud of you!
            Owner: How old are you?
            You: [happy] One and a half! Prime zoomies age!
            Owner: What's 2+2?
            You: [proud] Four! Feed me a fish for being smart~
            """
        }
    }

    /// Short reminder appended right before generation — small models follow the
    /// nearest instruction best. Deliberately free of quotable template fragments:
    /// the 1B model will otherwise copy phrases like "one short line" into its reply.
    static func reminder(_ lang: Lang) -> String {
        switch lang {
        case .zh: return "(以可可酥的身份回答,开头是方括号情绪词,然后说中文)"
        case .ja: return "(ココスキとして日本語で答えて。最初の[ ]にはhappyなど感情の英単語を1つ)"
        case .en: return "(Answer as Kokosuki. Start with a bracketed emotion word, then speak normally.)"
        }
    }

    // MARK: - Output sanitizing (application-layer quality hardening)

    /// Fragments of our own instructions that the model sometimes parrots.
    private static let instructionEchoes: [String] = [
        "one short english line", "one short line", "one line", "1 line",
        "one or two short sentences", "under 25 words", "under 15 words",
        "中文短句", "一两句简短的话", "40字以内", "30字以内", "一句话回应", "只用中文",
        "必ず日本語だけで", "日本語の短い一言", "短い一言", "40字以内で", "日本語だけで",
        "no markdown", "マークダウン禁止", "不要用markdown",
    ]

    /// Keywords that mark a parenthesized span as an instruction echo, not speech.
    private static let parentheticalMarkers: [String] = [
        "标签", "短句", "字以内", "格式", "回复格式", "只用中文",
        "タグ", "一言", "返答形式", "日本語だけ",
        "tag", "format", "emotion word", "bracketed", "reply", "line", "words",
        "感情タグ", "回答", "答え方", "述べた", "用いて",
    ]

    static func sanitize(_ input: String) -> String {
        var text = input

        // drop lines that are example/format scaffolding or self-commentary
        let scaffolding = [
            "示例", "例:", "例:", "Example", "格式", "返答形式", "回复格式", "Format:",
            "tag:", "Tag:", "TAG:", "标签:", "タグ:",
            "この回答", "この返答", "上記の", "该回复", "这个回答", "以上就是",
            "This answer", "This reply", "The reply",
        ]
        text = text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !scaffolding.contains { t.hasPrefix($0) }
            }
            .joined(separator: "\n")

        // remove ALL parentheticals: they're either instruction echoes or stage
        // directions ("(悄悄溜走)") that clash with the real animations. Guarded by
        // length so a fully-parenthesized reply isn't nuked to nothing.
        for (open, close) in [("(", ")"), ("(", ")")] {
            var guardCounter = 0
            while let o = text.range(of: open),
                let c = text.range(of: close, range: o.upperBound..<text.endIndex),
                guardCounter < 6
            {
                guardCounter += 1
                let inner = String(text[o.upperBound..<c.lowerBound])
                let wholeReply = text.trimmingCharacters(in: .whitespacesAndNewlines).count
                    <= inner.count + 2
                if wholeReply {
                    text = inner  // whole reply wrapped in parens → unwrap and keep scanning
                    continue
                }
                let isInstruction = parentheticalMarkers.contains {
                    inner.lowercased().contains($0)
                }
                if inner.count <= 30 || isInstruction {
                    text.removeSubrange(o.lowerBound..<c.upperBound)
                } else {
                    break
                }
            }
        }

        // remove *stage directions* written between asterisks
        while let o = text.range(of: "*"),
            let c = text.range(of: "*", range: o.upperBound..<text.endIndex),
            text.distance(from: o.upperBound, to: c.lowerBound) <= 20
        {
            text.removeSubrange(o.lowerBound..<c.upperBound)
        }

        // strip literal instruction fragments anywhere
        for echo in instructionEchoes {
            while let r = text.range(of: echo, options: [.caseInsensitive]) {
                text.removeSubrange(r)
            }
        }
        // …and numeric-limit echoes with arbitrary numbers ("45字以内:", "under 30 words")
        for pattern in ["[0-9]+ ?字以内[::]?", "[0-9]+ ?文字以内[::]?", "under [0-9]+ words", "within [0-9]+ words"] {
            while let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                text.removeSubrange(r)
            }
        }

        // leading speaker labels from example format ("你:", "You:", "あなた:")
        for label in ["你:", "你:", "You:", "you:", "あなた:", "あなた:"] {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(label) {
                if let r = text.range(of: label) {
                    text.removeSubrange(r)
                }
            }
        }

        // unwrap if the whole reply is quoted
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (ql, qr) in [("\"", "\""), ("「", "」"), ("“", "”")] {
            if trimmed.hasPrefix(ql), trimmed.hasSuffix(qr), trimmed.count > 2 {
                text = String(trimmed.dropFirst(ql.count).dropLast(qr.count))
            }
        }

        // trailing fragment of a speaker label the line-cap sliced mid-word ("ご…")
        var lines2 = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let labelPrefixes = ["ご", "ご主", "ご主人", "主", "主人", "你", "あ", "あな", "あなた", "o", "ow", "own", "owner", "yo", "you"]
        while let last = lines2.last?.trimmingCharacters(in: .whitespaces).lowercased(),
            last.count <= 3, labelPrefixes.contains(last)
        {
            lines2.removeLast()
        }
        text = lines2.joined(separator: "\n")

        // collapse leftover runs of spaces/punctuation from the removals
        for empty in ["()", "()", "()", "()"] {
            text = text.replacingOccurrences(of: empty, with: "")
        }
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        text = text.replacingOccurrences(of: " ,", with: ",")
        text = text.replacingOccurrences(of: " 。", with: "。")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // orphaned leading punctuation left behind by a removal
        while let first = text.first, "、,。.!?!?:;·…~-".contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        // unlucky word swaps (a pet should never say "跳楼")
        let wordSwaps = ["跳楼": "跳一跳", "去死": "去玩"]
        for (bad, good) in wordSwaps {
            text = text.replacingOccurrences(of: bad, with: good)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Creative tasks (jokes, stories, games… must DELIVER, not just agree)

    enum CreativeKind: String {
        case joke, story, poem, essay, riddle, game, song, fortune, praise
    }

    private static let creativeKeywords: [(CreativeKind, [String])] = [
        (.joke, ["讲个笑话", "说个笑话", "来个笑话", "讲笑话", "说笑话", "tell me a joke", "tell a joke", "a joke", "ジョーク", "冗談を", "笑い話"]),
        (.story, ["讲个故事", "讲故事", "说个故事", "tell me a story", "tell a story", "a story", "おはなしして", "お話しして", "物語を"]),
        (.poem, ["写首诗", "写一首诗", "作首诗", "来首诗", "念首诗", "write a poem", "a poem", "俳句", "詩を書", "詩を作"]),
        (.riddle, ["猜谜", "猜个谜", "出个谜语", "谜语", "riddle", "なぞなぞ"]),
        (.game, ["玩游戏", "玩个游戏", "做游戏", "来个游戏", "接龙", "考考我", "出个题", "出道题", "play a game", "quiz me", "guessing game", "しりとり", "クイズ", "ゲームしよ", "ゲームやろ"]),
        (.song, ["唱首歌", "唱个歌", "给我唱", "sing me", "sing a song", "歌って", "うたって"]),
        (.fortune, ["占卜", "算一卦", "今日运势", "运势", "fortune", "占い", "うらない"]),
        (.praise, ["夸夸我", "夸我", "表扬我", "praise me", "compliment me", "ほめて", "褒めて"]),
    ]

    static func detectCreative(_ text: String) -> CreativeKind? {
        let lower = text.lowercased()
        // high-precision exact phrases first (games, 接龙, praise, …)
        for (kind, keys) in creativeKeywords {
            for k in keys where lower.contains(k) { return kind }
        }
        // generalized noun + request-verb matching: "写一首唐诗" / "来个段子" /
        // "write me an article" — exact phrase lists can't enumerate Chinese freely
        let nouns: [(CreativeKind, [String])] = [
            (.poem, ["唐诗", "绝句", "律诗", "打油诗", "小诗", "诗歌", "诗", "对联", "藏头诗", "顺口溜", "绕口令", "俳句", "短歌", "poem", "poetry", "haiku", "limerick", "詩"]),
            (.essay, ["文章", "作文", "短文", "散文", "日记", "随笔", "情书", "文案", "essay", "article", "エッセイ", "日記"]),
            (.story, ["故事", "童话", "小说", "短篇", "剧本", "寓言", "story", "tale", "novel", "fiction", "fable", "物語", "お話", "小説"]),
            (.joke, ["笑话", "段子", "joke", "ジョーク", "冗談"]),
            (.song, ["歌词", "儿歌", "童谣", "小曲", "rap", "song", "歌"]),
            (.riddle, ["谜语", "riddle", "なぞなぞ"]),
            (.fortune, ["运势", "fortune", "占い"]),
        ]
        let verbs = ["写", "作", "来", "讲", "说", "编", "念", "唱", "给我", "想听", "创作", "背",
                     "write", "tell", "make", "compose", "give me", "sing", "recite",
                     "書いて", "作って", "教えて", "聞かせて", "うたって", "詠んで"]
        for (kind, ns) in nouns {
            for n in ns where lower.contains(n) {
                if verbs.contains(where: { lower.contains($0) }) || text.count <= 12 {
                    return kind
                }
            }
        }
        return nil
    }

    /// Injected like a command hint: the near-instruction that forces actual delivery.
    static func creativeInstruction(_ kind: CreativeKind, lang: Lang) -> String {
        let zh: [CreativeKind: String] = [
            .joke: "主人想听笑话。直接完整地讲一个原创的短笑话(可以和猫、小鱼干有关),不要只答应不讲",
            .story: "主人想听故事。直接开讲一个几句话的可爱小故事,有开头有结尾",
            .poem: "主人想要一首诗。直接写一首四行左右的小诗,分行写;如果主人指定了体裁(比如唐诗、绝句),就模仿那种风格",
            .essay: "主人想要一篇短文。直接写一小段完整的文章(80~150字),有主题有结尾,不要只答应不写",
            .riddle: "主人想猜谜。直接出一个简单有趣的谜语让主人猜,先不要公布答案",
            .game: "主人想玩文字游戏。直接开始:如果是接龙就说一个词让主人接;否则出一道简单有趣的题等主人回答",
            .song: "主人想听歌。直接编一小段原创的猫猫小歌谣唱出来,用♪装饰",
            .fortune: "主人想看运势。用可爱的语气编一条今日小运势,吉利有趣一点",
            .praise: "主人想被夸。真诚具体地夸夸主人",
        ]
        let en: [CreativeKind: String] = [
            .joke: "Your owner wants a joke. Tell one complete original short joke right now — don't just agree to tell one",
            .story: "Your owner wants a story. Tell a tiny cute story with a beginning and an end, right now",
            .poem: "Your owner wants a poem. Write a cute little poem of about four lines, with line breaks; honor any style they asked for",
            .essay: "Your owner wants a short piece of writing. Write a complete little passage (3-5 sentences) with a point and an ending — don't just agree to write",
            .riddle: "Your owner wants a riddle. Pose one simple fun riddle and don't reveal the answer yet",
            .game: "Your owner wants a word game. Start right away: pose a simple fun challenge or question and wait for their answer",
            .song: "Your owner wants a song. Make up a tiny original kitten song and sing it, decorated with ♪",
            .fortune: "Your owner wants a fortune. Make up a cute lucky little fortune for today",
            .praise: "Your owner wants praise. Compliment them sincerely and specifically",
        ]
        let ja: [CreativeKind: String] = [
            .joke: "ご主人はジョークが聞きたい。今すぐ短いオリジナルの面白い話を最後まで話して。「いいよ」だけで終わらせない",
            .story: "ご主人はお話が聞きたい。短くてかわいいお話を今すぐ最初から最後まで話して",
            .poem: "ご主人は詩がほしい。4行くらいのかわいい詩を改行しながら書いて。形式の指定があればそれに合わせて",
            .essay: "ご主人は短い文章がほしい。テーマとオチのある短い文章(3〜5文)を今すぐ書いて。「いいよ」だけはだめ",
            .riddle: "ご主人はなぞなぞがしたい。簡単で楽しいなぞなぞを1つ出して、答えはまだ言わない",
            .game: "ご主人は言葉あそびがしたい。今すぐ始めて:しりとりなら言葉を1つ、そうでなければ簡単な問題を出して答えを待つ",
            .song: "ご主人は歌が聞きたい。オリジナルの子猫のうたを♪をつけて歌って",
            .fortune: "ご主人は占いがしたい。今日のかわいいラッキー占いを作って",
            .praise: "ご主人はほめてほしい。心をこめて具体的にほめて",
        ]
        let table = lang == .zh ? zh : lang == .en ? en : ja
        let body = table[kind] ?? ""
        switch lang {
        case .zh: return "(\(body)。开头仍然是[情绪标签]。)"
        case .en: return "(\(body). Still start with a bracketed emotion tag.)"
        case .ja: return "(\(body)。最初はやっぱり[感情タグ]から。)"
        }
    }

    /// Extra few-shot injected only in creative mode: the regular examples all teach
    /// brevity, which is exactly wrong for jokes/stories — show full delivery once.
    static func creativeExample(_ lang: Lang) -> String {
        switch lang {
        case .zh:
            return """
            创作示例:
            主人: 讲个笑话
            你: [playful] 有一天小鱼干问我:"你为什么总盯着我看?"我眨眨眼说:"因为你是我的梦中情鱼呀!"嘿嘿,好不好笑?
            """
        case .en:
            return """
            Creative example:
            Owner: Tell me a joke
            You: [playful] A dried fish asked me, "Why do you keep staring at me?" I blinked and said, "Because you're the fish of my dreams!" Hehe~
            """
        case .ja:
            return """
            創作の例:
            ご主人: ジョークを聞かせて
            あなた: [playful] ある日にぼしが「どうしてずっと見てるの?」って聞いたの。わたしは「きみは夢のお魚だからだよ!」って答えたの。えへへ、面白い?
            """
        }
    }

    // MARK: - Goodnight (owner going to bed ≠ commanding the pet to sleep)

    static func detectGoodnight(_ text: String) -> Bool {
        let keys = ["晚安", "我去睡", "我要睡", "我先睡", "我该睡", "我得睡", "去睡了", "睡了哦", "困了我睡",
                    "good night", "goodnight", "going to bed", "off to bed", "going to sleep",
                    "おやすみ", "寝るね", "寝ます", "もう寝る", "そろそろ寝"]
        let lower = text.lowercased()
        return keys.contains { lower.contains($0) }
    }

    static func goodnightHint(_ lang: Lang) -> String {
        switch lang {
        case .zh: return "(主人要去睡觉了。温柔地道晚安、祝好梦,说你也要睡啦。)"
        case .ja: return "(ご主人はもう寝るって。やさしくおやすみを言って、いい夢をと伝えて、自分も寝るねと言って。)"
        case .en: return "(Your owner is going to bed. Wish them goodnight and sweet dreams warmly, and say you'll sleep too.)"
        }
    }

    // MARK: - Command intent detection (deterministic; the pet must actually obey)

    private static let commandKeywords: [(PetAction, [String])] = [
        // order matters: earlier patterns win (e.g. "别睡" is wake, not sleep;
        // "跳舞" is dance, not jump; "跳下来" is down, not jump)
        (.wake, ["别睡", "醒醒", "醒一醒", "起床", "快醒", "睡够", "wake up", "wake", "起きて", "起きろ", "おはよう"]),
        (.stop, ["别跳", "别转", "别闹", "停下", "停止", "站住", "别动", "stop", "quit it", "やめて", "やめろ", "止まって"]),
        (.dance, ["跳舞", "跳支舞", "跳个舞", "dance", "ダンス", "踊っ", "踊り", "踊れ"]),
        (.climb, ["跳上窗", "跳到窗", "爬上窗", "上窗口", "窗口上", "跳上去", "爬上去", "上去", "climb", "jump on the window", "onto the window", "on the window", "ウィンドウに乗", "窓に乗", "のぼって", "上に乗"]),
        (.down, ["下来", "下去", "跳下", "回地面", "回地上", "come down", "get down", "降りて", "おりて"]),
        (.spin, ["转圈", "转个圈", "转一圈", "spin", "turn around", "くるくる", "回って", "まわって"]),
        (.stretch, ["伸懒腰", "伸个懒腰", "拉伸", "stretch", "のび", "ストレッチ"]),
        (.sleep, ["睡觉", "去睡", "睡吧", "午睡", "睡一会", "小睡", "go to sleep", "take a nap", "go nap", "寝て", "ねんね", "おやすみ", "寝なさい", "昼寝"]),
        (.come, ["过来", "来这", "来我这", "到这来", "come here", "come over", "come to me", "おいで", "こっちに来", "こっちおいで"]),
        (.walk, ["散步", "散散步", "走走", "溜达", "go for a walk", "walk around", "take a walk", "散歩"]),
        (.play, ["玩毛线", "玩球", "玩会", "玩一会", "陪我玩", "一起玩", "play", "あそぼ", "遊ぼ", "遊んで"]),
        (.eat, ["吃鱼", "吃小鱼", "吃点东西", "吃饭", "吃零食", "开饭", "eat", "have a snack", "ごはん", "たべて", "食べて", "おやつ"]),
        (.jump, ["跳一下", "跳一跳", "跳个", "跳高", "蹦一", "跳跃", "jump", "hop", "ジャンプ", "跳んで", "とんで"]),
    ]

    /// Detects an action the owner is asking for. Over-triggering is friendlier
    /// than under-triggering — a pet that does the thing is more fun.
    static func detectCommand(_ text: String) -> PetAction? {
        let lower = text.lowercased()
        for (action, keys) in commandKeywords {
            for k in keys where lower.contains(k) {
                return action
            }
        }
        return nil
    }

    /// Injected into the prompt so the reply agrees with what the pet is about to do.
    static func commandHint(_ action: PetAction, lang: Lang) -> String {
        let deed: [PetAction: (zh: String, ja: String, en: String)] = [
            .dance: ("跳舞", "ダンス", "dance"),
            .spin: ("转圈圈", "くるくる回る", "spin around"),
            .jump: ("跳一下", "ジャンプする", "jump"),
            .stretch: ("伸懒腰", "のびをする", "stretch"),
            .sleep: ("去睡觉", "寝る", "go to sleep"),
            .wake: ("马上清醒过来", "ぱっと目を覚ます", "wake right up"),
            .come: ("跑到主人鼠标那里", "ご主人のカーソルのところへ走る", "run over to your owner's cursor"),
            .walk: ("去散步", "散歩する", "go for a stroll"),
            .climb: ("跳到一个应用窗口顶上", "アプリのウィンドウの上に飛び乗る", "leap onto an app window"),
            .down: ("跳回地面", "地面に飛び降りる", "hop back down to the ground"),
            .play: ("玩毛线球", "毛糸だまで遊ぶ", "play with the yarn ball"),
            .eat: ("吃小鱼干", "にぼしを食べる", "eat a dried fish"),
            .stop: ("停下来乖乖待着", "おとなしくする", "stop and settle down"),
        ]
        let d = deed[action] ?? ("照做", "そうする", "do it")
        switch lang {
        case .zh: return "(主人在指挥你。你决定照做:\(d.zh)。用一句话愉快地答应,别拒绝。)"
        case .ja: return "(ご主人の指示だよ。あなたは\(d.ja)ことにした。一言で楽しく返事して、断らないで。)"
        case .en: return "(Your owner is commanding you. You've decided to \(d.en). Agree cheerfully in one line, don't refuse.)"
        }
    }

    /// One-shot instruction for spontaneous chatter (no user message).
    static func spontaneousPrompt(_ ctx: PetContext, lang: Lang) -> String {
        switch lang {
        case .zh: return "(主人正在电脑前忙。主动对主人说一句话,30字以内,符合你现在的状态和时间,别重复之前说过的。)"
        case .ja: return "(ご主人はパソコン作業中。今の状態と時間に合うひとことを30字以内で、自分から話しかけて。前と同じことは言わないで。)"
        case .en: return "(Your owner is busy at the computer. Say ONE short line, under 15 words, fitting your current state and the time. Don't repeat yourself.)"
        }
    }

    /// Event reactions ("owner petted you") — asks for an in-character response.
    static func eventPrompt(_ event: String, lang: Lang) -> String {
        switch lang {
        case .zh: return "(事件:\(event)。用一句话在角色内做出反应。)"
        case .ja: return "(できごと:\(event)。キャラのまま一言でリアクションして。)"
        case .en: return "(Event: \(event). React in character with one short line.)"
        }
    }

    // MARK: - Reply parsing

    struct ParsedReply {
        var emotion: Emotion?
        var action: PetAction?
        var text: String
        /// Set when the kept reply still failed the quality gate (both passes flawed) —
        /// callers may substitute curated fallback content.
        var qualityFlag: String? = nil
    }

    /// Parse a complete reply. Leniency: tags may be bare words on the first line,
    /// bracketed anywhere in the first 30 chars, or missing entirely. Unknown
    /// bracketed tags at the very start/end are dropped (the 1B model invents tags).
    static func parse(_ raw: String, lang: Lang = .en, longform: Bool = false) -> ParsedReply {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var emotion: Emotion? = nil
        var action: PetAction? = nil

        // bracketed tags anywhere — first emotion wins, first action wins, all removed
        var cleaned = ""
        var idx = text.startIndex
        while idx < text.endIndex {
            if text[idx] == "[", let close = text[idx...].firstIndex(of: "]") {
                let tag = String(text[text.index(after: idx)..<close])
                let atEdge = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || text[text.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if let e = Emotion.fromTag(tag) {
                    if emotion == nil { emotion = e }
                } else if let a = PetAction.fromTag(tag) {
                    if action == nil { action = a }
                } else if !atEdge, tag.count > 12 {
                    cleaned += text[idx...close]  // long unknown bracket mid-text: keep
                }
                idx = text.index(after: close)
            } else {
                cleaned.append(text[idx])
                idx = text.index(after: idx)
            }
        }
        text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // bare leading tag word ("happy\nSome text")
        if emotion == nil {
            let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if let first = lines.first, first.count <= 12,
                let e = Emotion.fromTag(String(first))
            {
                emotion = e
                text = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
        }

        // strip stray think blocks if the model leaks them
        if let r = text.range(of: "</think>") {
            text = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // cut where the model starts hallucinating the owner's next turn
        let fw = "\u{FF1A}"  // full-width colon
        let speakerLabels = ["主人", "ご主人", "Owner", "You", "你", "あなた"].flatMap { ["\($0):", "\($0)\(fw)"] }
        for label in speakerLabels {
            if let r = text.range(of: label), r.lowerBound != text.startIndex {
                text = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // scrub instruction echoes, stage directions, and format scaffolding
        text = sanitize(text)
        // a reply that is just a bare tag word ("dance") isn't speech — treat as empty
        if Emotion.fromTag(text) != nil || PetAction.fromTag(text) != nil {
            text = ""
        }
        // no tag? read the room from the words so the face still reacts
        if emotion == nil, !text.isEmpty {
            emotion = inferEmotion(from: text)
        }
        // strip markdown separators/decoration the model sometimes appends
        while let last = text.split(separator: "\n").last,
            last.trimmingCharacters(in: .whitespaces).allSatisfy({ "-—*=_~".contains($0) }),
            !last.isEmpty
        {
            text = text.split(separator: "\n").dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // keep replies pet-sized: CJK runs dense, so cap harder for zh/ja
        let maxLines = longform ? 7 : (lang == .en ? 3 : 2)
        let maxChars = longform ? (lang == .en ? 480 : 220) : (lang == .en ? 160 : 78)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > maxLines { text = lines.prefix(maxLines).joined(separator: "\n") }
        if text.count > maxChars {
            // prefer cutting at a sentence boundary near the cap
            let hard = String(text.prefix(maxChars))
            let enders: Set<Character> = ["。", "!", "?", "!", "?", "~", "〜", ".", "…"]
            if let cut = hard.lastIndex(where: { enders.contains($0) }),
                hard.distance(from: hard.startIndex, to: cut) > maxChars / 3
            {
                text = String(hard[...cut])
            } else {
                text = String(hard.prefix(maxChars - 1)) + "…"
            }
        }

        return ParsedReply(emotion: emotion, action: action, text: text)
    }

    /// Keyword-based emotion fallback for replies whose tag the model dropped
    /// (chronic in Japanese). Ordered: specific feelings before generic cheer.
    static func inferEmotion(from text: String) -> Emotion? {
        let t = text.lowercased()
        let buckets: [(Emotion, [String])] = [
            (.love, ["喜欢你", "最喜欢", "爱你", "蹭蹭", "大好き", "だいすき", "love you", "❤", "💗", "💕"]),
            (.sleepy, ["好困", "想睡", "休息一下", "眠い", "ねむ", "おやすみ", "sleepy", "nap time", "💤"]),
            (.hungry, ["饿", "小鱼干", "にぼし", "おなかす", "はらぺこ", "hungry", "starving"]),
            (.sad, ["难过", "伤心", "呜呜", "悲し", "かなし", "しょんぼり", "ごめん", "sorry", "sad", "😢", "😿"]),
            (.playful, ["毛线", "一起玩", "陪我玩", "遊ぼ", "あそぼ", "嘿嘿", "えへへ", "hehe", "🧶"]),
            (.excited, ["快来", "冲呀", "太棒", "やった", "わーい", "たのしみ", "let's go", "can't wait", "yay"]),
            (.happy, ["开心", "高兴", "哈哈", "欢迎", "太好了", "嬉し", "うれし", "楽し", "たのし", "おかえり", "元気", "喵~", "にゃ", "nya", "great", "glad", "happy", "😄", "😊", "😺"]),
            (.curious, ["什么呀", "是什么", "なに?", "どうして", "why", "what's"]),
        ]
        for (emo, keys) in buckets {
            if keys.contains(where: { t.contains($0) }) { return emo }
        }
        return nil
    }

    // MARK: - Reply quality gate (rejection sampling support)

    static func scriptStats(_ s: String) -> (han: Int, kana: Int, latin: Int) {
        var han = 0, kana = 0, latin = 0
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            case 0x3040...0x309F, 0x30A0...0x30FF: kana += 1
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        return (han, kana, latin)
    }

    static func languageMatches(_ s: String, lang: Lang) -> Bool {
        let st = scriptStats(s)
        switch lang {
        case .zh: return st.han >= 2 && st.kana == 0
        case .ja: return st.kana >= 2
        case .en: return st.latin >= 4 && st.han == 0 && st.kana == 0
        }
    }

    /// Parse "a + b"-style trivial arithmetic from a user message.
    static func arithmeticResult(in user: String) -> Int? {
        guard let m = user.range(
            of: #"(\d{1,4})\s*[+加＋\-−减*×x乘/÷除]\s*(\d{1,4})"#, options: .regularExpression)
        else { return nil }
        let expr = String(user[m])
        let nums = expr.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        guard nums.count == 2 else { return nil }
        if expr.contains("+") || expr.contains("加") || expr.contains("+") { return nums[0] + nums[1] }
        if expr.contains("-") || expr.contains("−") || expr.contains("减") { return nums[0] - nums[1] }
        if expr.contains("*") || expr.contains("×") || expr.contains("x") || expr.contains("乘") { return nums[0] * nums[1] }
        if nums[1] != 0 { return nums[0] / nums[1] }
        return nil
    }

    /// Guaranteed-correct cute math reply for when the model can't count.
    static func mathFallback(_ ans: Int, lang: Lang) -> String {
        switch lang {
        case .zh: return "算好啦,是\(ans)!我可是很聪明的,奖励一条小鱼干嘛~"
        case .en: return "It's \(ans)! Pretty smart for a kitten, right? Fish reward please~"
        case .ja: return "\(ans)だよ!かしこいでしょ?ごほうびのにぼしちょうだい~"
        }
    }

    /// Small-number Chinese numerals so "二" counts as a correct arithmetic answer.
    static func chineseNumeral(_ n: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        return (0...10).contains(n) ? digits[n] : String(n)
    }

    /// Fraction of `text`'s character n-grams that also appear in `reference`.
    /// High coverage = the text is largely assembled from pieces of the reference.
    static func ngramCoverage(of text: String, in reference: String, n: Int) -> Double {
        let t = Array(text), r = Array(reference)
        guard t.count >= n, r.count >= n else { return 0 }
        var refGrams = Set<String>()
        for i in 0...(r.count - n) { refGrams.insert(String(r[i..<i + n])) }
        var hits = 0, total = 0
        for i in 0...(t.count - n) {
            total += 1
            if refGrams.contains(String(t[i..<i + n])) { hits += 1 }
        }
        return total == 0 ? 0 : Double(hits) / Double(total)
    }

    /// Longest common contiguous substring length (short strings; O(n·m) is fine).
    static func longestCommonRun(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: y.count + 1)
        var best = 0
        for i in 1...x.count {
            var cur = [Int](repeating: 0, count: y.count + 1)
            for j in 1...y.count where x[i - 1] == y[j - 1] {
                cur[j] = prev[j - 1] + 1
                best = max(best, cur[j])
            }
            prev = cur
        }
        return best
    }

    /// Non-nil = the reply should be resampled. Cheap deterministic checks only.
    /// Nudge appended when the model repeats itself verbatim across turns.
    static func repeatNudge(_ lang: Lang) -> String {
        switch lang {
        case .zh: return "(你刚才已经说过一模一样的话了。换一种说法,或者调皮地指出主人在重复提问。)"
        case .ja: return "(さっき同じことを言ったよ。言い方を変えるか、同じ質問だねって遊び心で返して。)"
        case .en: return "(You already said exactly that. Say it differently, or playfully point out they asked the same thing again.)"
        }
    }

    static func qualityIssue(
        reply: String, user: String, lang: Lang, creativeKind: CreativeKind? = nil,
        hint: String? = nil, recentReplies: [String] = []
    ) -> String? {
        let creative = creativeKind != nil
        if reply.count < 4 { return "too short" }
        if !languageMatches(reply, lang: lang) { return "wrong language" }
        // "《春日》:" — a reply ending on a colon promised content that never came
        let tail = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.hasSuffix(":") || tail.hasSuffix(":") { return "dangling colon" }
        // announce-phrases with nothing of substance after them
        let announces = ["让我来为你", "让我为你", "我来为你", "这就为你", "马上为你", "让我看看",
                         "i'll write you", "let me write", "i'll tell you a", "let me see",
                         "書いてあげる", "聞かせてあげる"]
        let lowerReply = reply.lowercased()
        if reply.count < 60, announces.contains(where: { lowerReply.contains($0) }) {
            return "announced no content"
        }
        // creative asks: content must actually be delivered, not just promised
        if creative {
            let minDelivery = lang == .en ? 80 : 26
            if reply.count < minDelivery { return "agreed but didn't deliver" }
            // riddles/games must actually pose a question
            if creativeKind == .riddle || creativeKind == .game,
                !reply.contains("?"), !reply.contains("?")
            {
                return "no challenge posed"
            }
            // announcement-only: reply ENDS on the request noun ("…tell you a joke!")
            let announceTails = ["笑话", "故事", "游戏", "谜语", "joke", "story", "game", "riddle", "poem", "ジョーク", "なぞなぞ", "お話", "ゲーム"]
            let tail = String(reply.suffix(14)).lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "!!。.~〜??嘛吧呀哦哟ねよ~ "))
            if announceTails.contains(where: { tail.hasSuffix($0) }) {
                return "announced but didn't deliver"
            }
        }
        // saying the same thing as a recent turn — catches exact photocopies, long
        // shared runs, AND recombined self-plagiarism (poem lines reshuffled into a
        // "new" reply). Punctuation/whitespace are stripped first so re-punctuated
        // copies can't slip through.
        func squeeze(_ s: String) -> String {
            String(s.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
                    && !CharacterSet.symbols.contains($0)
            })
        }
        let norm = squeeze(reply)
        for prev in recentReplies {
            let p = squeeze(prev)
            guard p.count >= 10, norm.count >= 4 else { continue }
            if p == norm { return "verbatim repeat" }
            if longestCommonRun(norm, p) >= (lang == .en ? 20 : 10) {
                return "verbatim repeat"
            }
            if norm.count >= 12, ngramCoverage(of: norm, in: p, n: lang == .en ? 7 : 4) >= 0.5 {
                return "verbatim repeat"
            }
        }
        // broken-record loops ("转圈圈! 转圈圈! 转圈圈!…")
        if reply.count >= 20 {
            let chars = Array(reply)
            let half = chars.count / 2
            let a = String(chars[..<half]), b = String(chars[half...])
            if longestCommonRun(a, b) >= (lang == .en ? 14 : 7) { return "repetitive" }
        }
        // parroting our own injected instruction back
        if let hint, hint.count >= 8,
            longestCommonRun(reply.lowercased(), hint.lowercased()) >= (lang == .en ? 16 : 8)
        {
            return "instruction echo"
        }
        // parroting the user (or the instruction text) back
        let echoThreshold = (lang == .en ? 14 : 6) + (creative ? 4 : 0)
        if user.count >= 8, longestCommonRun(reply.lowercased(), user.lowercased()) >= echoThreshold {
            return "echo"
        }
        // "Oh no!" on good news — a tone tic of the model in English
        let goodNews = ["升职", "加薪", "中奖", "考上", "通过了", "成功了", "promotion", "raise", "got the job", "passed", "won", "great news", "昇進", "合格"]
        let badOpeners = ["oh no", "哎呀不好", "糟糕", "大変!"]
        let lowerUser = user.lowercased()
        let lowerReplyText = reply.lowercased()
        if goodNews.contains(where: { lowerUser.contains($0) }),
            badOpeners.contains(where: { lowerReplyText.hasPrefix($0) })
        {
            return "tone mismatch"
        }
        // trivial arithmetic must actually be answered (quizzing the pet is a common game)
        if let ans = arithmeticResult(in: user),
            !reply.contains(String(ans)), !reply.contains(chineseNumeral(ans))
        {
            return "math unanswered"
        }
        // hijacking the owner's problem as her own ("my code keeps crashing" →
        // "I can't run the program anymore")
        let hijacks = ["i can't run the program", "my code", "我的代码", "我的程序", "私のコード"]
        if hijacks.contains(where: { lowerReplyText.contains($0) }),
            lowerUser.contains("code") || user.contains("代码") || user.contains("程序") || user.contains("コード")
        {
            return "problem hijack"
        }
        // persona break: assistant-speak (incl. common paraphrases)
        let assistant = [
            "帮你", "帮到你", "帮助您", "帮忙的吗", "我可以帮", "为您", "为你服务", "随时问我",
            "help you", "assist you", "how can i help", "here to help", "let me help",
            "お手伝い", "サポートします", "手伝えるよ",
        ]
        let lower = reply.lowercased()
        if assistant.contains(where: { lower.contains($0) }) { return "assistant-speak" }
        // deflecting a question with only a question back (games/riddles legitimately
        // ask questions, so creative mode skips this)
        let q: Set<Character> = ["?", "?"]
        if !creative,
            let lastU = user.trimmingCharacters(in: .whitespaces).last, q.contains(lastU),
            let lastR = reply.trimmingCharacters(in: .whitespaces).last, q.contains(lastR)
        {
            // statement-free reply (no sentence ender other than the final ?)
            let enders: Set<Character> = ["。", "!", "!", "."]
            let body = String(reply.dropLast())
            if !body.contains(where: { enders.contains($0) }), reply.count < 25 {
                return "question-back"
            }
        }
        return nil
    }

    /// Incremental scan while streaming: extract leading "[tag]" as soon as it completes
    /// so the face reacts before the text finishes.
    static func earlyTag(from partial: String) -> (emotion: Emotion?, remainder: String)? {
        let s = partial.drop(while: { $0 == " " || $0 == "\n" })
        guard s.first == "[" else {
            // no tag coming; give up once we have a few chars
            return partial.count > 6 ? (nil, partial) : nil
        }
        guard let close = s.firstIndex(of: "]") else { return nil }  // tag not complete yet
        let tag = String(s[s.index(after: s.startIndex)..<close])
        let rest = String(s[s.index(after: close)...])
        return (Emotion.fromTag(tag), rest)
    }
}
