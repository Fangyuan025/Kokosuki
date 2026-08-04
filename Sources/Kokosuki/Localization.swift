import Foundation

enum Lang: String, CaseIterable, Codable, Identifiable {
    case en, zh, ja
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "简体中文"
        case .ja: return "日本語"
        }
    }

    static var systemDefault: Lang {
        let pref = Locale.preferredLanguages.first ?? "en"
        if pref.hasPrefix("zh") { return .zh }
        if pref.hasPrefix("ja") { return .ja }
        return .en
    }
}

/// All UI strings, keyed. t(key) looks up in current language.
enum L10n {
    nonisolated(unsafe) static var lang: Lang = .en

    static func t(_ key: String) -> String {
        table[key]?[lang] ?? table[key]?[.en] ?? key
    }

    private static let table: [String: [Lang: String]] = [
        // menu
        "menu.chat": [.en: "Chat with Kokosuki…", .zh: "和可可酥聊天…", .ja: "ココスキとおしゃべり…"],
        "menu.feedFish": [.en: "Feed dried fish 🐟", .zh: "喂小鱼干 🐟", .ja: "にぼしをあげる 🐟"],
        "menu.feedCookie": [.en: "Feed cookie 🍪", .zh: "喂小饼干 🍪", .ja: "クッキーをあげる 🍪"],
        "menu.play": [.en: "Play together 🧶", .zh: "一起玩 🧶", .ja: "いっしょに遊ぶ 🧶"],
        "menu.sleep": [.en: "Nap time 💤", .zh: "去睡觉 💤", .ja: "おひるね 💤"],
        "menu.wake": [.en: "Wake up ☀️", .zh: "叫醒它 ☀️", .ja: "おこす ☀️"],
        "menu.callOver": [.en: "Come here!", .zh: "过来这边!", .ja: "おいで!"],
        "menu.stats": [.en: "Status", .zh: "状态", .ja: "ステータス"],
        "menu.settings": [.en: "Settings…", .zh: "设置…", .ja: "設定…"],
        "menu.quit": [.en: "Quit Kokosuki", .zh: "退出可可酥", .ja: "ココスキを終了"],
        "menu.brainLoading": [.en: "🧠 Waking up the brain…", .zh: "🧠 小脑瓜启动中…", .ja: "🧠 頭を起こしています…"],
        "menu.brainReady": [.en: "🧠 Brain ready", .zh: "🧠 小脑瓜在线", .ja: "🧠 頭スッキリ"],
        "menu.brainFailed": [.en: "🧠 Brain failed to load", .zh: "🧠 小脑瓜加载失败", .ja: "🧠 頭の読み込み失敗"],

        // stats
        "stats.hunger": [.en: "Fullness", .zh: "饱腹", .ja: "満腹度"],
        "stats.energy": [.en: "Energy", .zh: "精力", .ja: "元気"],
        "stats.happiness": [.en: "Happiness", .zh: "心情", .ja: "ごきげん"],

        // chat
        "chat.title": [.en: "Kokosuki", .zh: "可可酥", .ja: "ココスキ"],
        "chat.placeholder": [.en: "Say something to Kokosuki…", .zh: "对可可酥说点什么…", .ja: "ココスキに話しかけよう…"],
        "chat.send": [.en: "Send", .zh: "发送", .ja: "送信"],
        "chat.thinking": [.en: "thinking…", .zh: "思考中…", .ja: "かんがえ中…"],
        "chat.loading": [.en: "The little brain is still waking up, one moment…", .zh: "小脑瓜还在启动,稍等一下下…", .ja: "頭がまだ起きてないの、ちょっと待ってね…"],
        "chat.failed": [.en: "Brain couldn't load 😿", .zh: "小脑瓜加载失败了 😿", .ja: "頭が読み込めなかった 😿"],
        "chat.clear": [.en: "Clear history", .zh: "清空聊天记录", .ja: "履歴をクリア"],

        // settings
        "settings.title": [.en: "Settings", .zh: "设置", .ja: "設定"],
        "settings.language": [.en: "Language", .zh: "语言", .ja: "言語"],
        "settings.size": [.en: "Pet size", .zh: "宠物大小", .ja: "ペットのサイズ"],
        "settings.size.small": [.en: "Small", .zh: "小", .ja: "小"],
        "settings.size.medium": [.en: "Medium", .zh: "中", .ja: "中"],
        "settings.size.large": [.en: "Large", .zh: "大", .ja: "大"],
        "settings.chatter": [.en: "Talks to you on her own", .zh: "会主动找你说话", .ja: "自分から話しかけてくる"],
        "settings.chatterFreq": [.en: "Chattiness", .zh: "话痨程度", .ja: "おしゃべり度"],
        "settings.freq.low": [.en: "Quiet", .zh: "文静", .ja: "しずか"],
        "settings.freq.mid": [.en: "Normal", .zh: "正常", .ja: "ふつう"],
        "settings.freq.high": [.en: "Chatty", .zh: "话痨", .ja: "おしゃべり"],
        "settings.autoSleep": [.en: "Sleeps at night (23:00–7:00)", .zh: "夜间自动睡觉 (23:00–7:00)", .ja: "夜は自動でねる (23:00–7:00)"],
        "settings.parkour": [.en: "Jumps onto app windows", .zh: "会跳上应用窗口", .ja: "ウィンドウの上にジャンプする"],
        "settings.thinking": [.en: "Deep thinking (slower, smarter replies)", .zh: "深度思考(回复更慢但更聪明)", .ja: "じっくり考える(遅いけど賢い)"],
        "settings.resetStats": [.en: "Reset pet state", .zh: "重置宠物状态", .ja: "ペットの状態をリセット"],
        "settings.about": [.en: "Kokosuki — an offline desktop kitten.\nEverything runs on your Mac; nothing leaves it.", .zh: "可可酥 — 完全离线的桌面小猫。\n一切都在你的 Mac 上运行,不会上传任何数据。", .ja: "ココスキ — 完全オフラインのデスクトップ子猫。\nすべてMac内で動き、データはどこにも送られません。"],
    ]

    // MARK: - Canned lines (fast reactions; LLM adds variety on top)

    static func canned(_ category: CannedCategory) -> String {
        let lines = cannedTable[category]?[lang] ?? cannedTable[category]?[.en] ?? []
        return lines.randomElement() ?? "…"
    }

    enum CannedCategory {
        case poke, pokeAnnoyed, petted, fedFish, fedCookie, fullTummy
        case wokenGrumpy, landingOuch, playStart
        case morning, afternoon, evening, night
        case hungry, bored, sleepy, confused
    }

    private static let cannedTable: [CannedCategory: [Lang: [String]]] = [
        .poke: [
            .en: ["Mya? Did you need me?", "Hehe, that tickles!", "Nya~ I'm here!", "Hm? What's up?"],
            .zh: ["喵?找我有事嘛?", "嘿嘿,痒痒的!", "喵~ 我在哦!", "嗯?怎么啦?"],
            .ja: ["みゃ?呼んだ?", "えへへ、くすぐったい!", "にゃ~ここだよ!", "ん?どうしたの?"],
        ],
        .pokeAnnoyed: [
            .en: ["Hey!! Stop poking me!!", "Mrrrp!! I'm getting dizzy!!", "One more poke and I'll bite!"],
            .zh: ["喂!!别戳啦!!", "呜喵!!人家都被戳晕了!!", "再戳我要咬你了哦!"],
            .ja: ["ちょっと!!つつかないでよ!!", "うにゃー!!目が回るよ!!", "もう一回つついたら噛むからね!"],
        ],
        .petted: [
            .en: ["Purrrr… that feels nice…", "More… right behind the ear…", "Mmm~ I love head pats!", "Purr purr… ♪"],
            .zh: ["呼噜噜…好舒服…", "再多摸摸…耳朵后面…", "唔~ 最喜欢摸摸头了!", "呼噜呼噜…♪"],
            .ja: ["ゴロゴロ…きもちいい…", "もっと…耳のうしろ…", "ん~なでなで大好き!", "ゴロゴロ…♪"],
        ],
        .fedFish: [
            .en: ["Dried fish!! My favorite!!", "Nom nom… so good…", "You remembered! Fish!!"],
            .zh: ["小鱼干!!最喜欢了!!", "啊呜啊呜…好好吃…", "你记得欸!小鱼干!!"],
            .ja: ["にぼし!!大好物!!", "はむはむ…おいしい…", "覚えててくれたの!にぼし!!"],
        ],
        .fedCookie: [
            .en: ["A cookie! Crunch crunch~", "Sweet!! Thank you!!", "Nom… crumbs everywhere, hehe"],
            .zh: ["小饼干!咔嚓咔嚓~", "甜甜的!!谢谢你!!", "啊呜…掉渣渣了,嘿嘿"],
            .ja: ["クッキー!さくさく~", "あまーい!!ありがとう!!", "はむ…ぽろぽろこぼれちゃった、えへへ"],
        ],
        .fullTummy: [
            .en: ["Urp… I'm so full…", "My tummy is round now…", "Can't eat another bite…"],
            .zh: ["嗝…吃好饱…", "肚子都圆滚滚了…", "一口也吃不下啦…"],
            .ja: ["げぷ…おなかいっぱい…", "おなかまんまるだよ…", "もうひとくちも入らない…"],
        ],
        .wokenGrumpy: [
            .en: ["Mmm… five more minutes…", "Who dares wake me… oh, it's you…", "*yawn* …I was dreaming of fish…"],
            .zh: ["唔…再睡五分钟…", "谁吵醒我…哦,是你呀…", "*哈欠* …人家梦到小鱼干了…"],
            .ja: ["んん…あと5分…", "誰が起こしたの…あ、きみか…", "*ふぁ~* …にぼしの夢見てたのに…"],
        ],
        .landingOuch: [
            .en: ["Wah!! …I meant to do that.", "Nya!! My landing was perfect, right?", "Oof!! …ow ow ow…"],
            .zh: ["哇!!…我是故意的哦。", "喵呜!!落地满分对吧?", "噗!!…疼疼疼…"],
            .ja: ["わっ!!…わざとだよ?", "にゃっ!!着地は完璧でしょ?", "ぷぎゅ!!…いたたた…"],
        ],
        .playStart: [
            .en: ["Yarn ball!! Let's go!!", "Play play play~!", "Watch my super spin!!"],
            .zh: ["毛线球!!冲呀!!", "玩耍玩耍~!", "看我的超级转圈!!"],
            .ja: ["毛糸だま!!いくよー!!", "あそぼあそぼ~!", "スーパーくるくる見てて!!"],
        ],
        .morning: [
            .en: ["Good morning! Today will be great, I can feel it!", "Morning~ did you sleep well?"],
            .zh: ["早上好!今天一定是超棒的一天!", "早安~ 睡得好嘛?"],
            .ja: ["おはよう!今日はきっといい日だよ!", "おはよ~ よく眠れた?"],
        ],
        .afternoon: [
            .en: ["Afternoon slump? Stretch with me~", "Don't forget to drink water!"],
            .zh: ["下午犯困了吧?跟我一起伸个懒腰~", "别忘了喝水哦!"],
            .ja: ["午後は眠くなるよね?一緒にのびしよ~", "お水飲むの忘れないでね!"],
        ],
        .evening: [
            .en: ["Working hard? I'm cheering for you!", "Evening~ almost done for today?"],
            .zh: ["还在努力嘛?我给你加油!", "晚上好~ 今天快忙完了吗?"],
            .ja: ["がんばってるね?応援してるよ!", "こんばんは~ 今日はもう終わりそう?"],
        ],
        .night: [
            .en: ["It's late… don't stay up too long, okay?", "*yawn* …you should sleep soon too…"],
            .zh: ["很晚了…别熬夜太久哦?", "*哈欠* …你也早点睡吧…"],
            .ja: ["もう遅いよ…夜ふかししすぎないでね?", "*ふぁ~* …きみもそろそろ寝なきゃ…"],
        ],
        .hungry: [
            .en: ["My tummy is rumbling…", "Is it… snack time? 👀", "I smell dried fish… no? aww…"],
            .zh: ["肚子咕咕叫了…", "是不是…该吃点心了?👀", "我好像闻到小鱼干了…没有吗…"],
            .ja: ["おなかぐーぐー鳴ってる…", "そろそろ…おやつの時間じゃない?👀", "にぼしの匂いがした気が…ないの…"],
        ],
        .bored: [
            .en: ["So bored… play with me?", "*rolls around*", "Hey, look at me for a sec!"],
            .zh: ["好无聊…陪我玩嘛?", "*打滚滚*", "喂,看我一下嘛!"],
            .ja: ["ひまだよ~…遊んでくれない?", "*ごろごろ転がる*", "ねえ、ちょっとこっち見て!"],
        ],
        .sleepy: [
            .en: ["Eyelids… so heavy…", "*yawn* …maybe a tiny nap…"],
            .zh: ["眼皮…好重…", "*哈欠* …小睡一下下好了…"],
            .ja: ["まぶたが…おもい…", "*ふぁ~* …ちょっとだけ寝ようかな…"],
        ],
        .confused: [
            .en: ["…? (tilts head)", "Mya? Say that again?"],
            .zh: ["…?(歪头看你)", "喵?再说一遍嘛?"],
            .ja: ["…?(くびをかしげる)", "みゃ?もう一回言って?"],
        ],
    ]

    // MARK: - Curated creative content (backstop when the LLM fails to deliver)

    static func creativeCanned(_ kind: Persona.CreativeKind, lang overrideLang: Lang? = nil) -> String {
        let l = overrideLang ?? lang
        let items = creativeBank[kind]?[l] ?? creativeBank[kind]?[.en] ?? []
        return items.randomElement() ?? "…"
    }

    private static let creativeBank: [Persona.CreativeKind: [Lang: [String]]] = [
        .joke: [
            .zh: [
                "我昨天追自己的尾巴,追了十圈才想起来——它长在我身上呀!",
                "主人问我为什么打翻杯子。我说:是重力的错,跟爪爪没关系!",
                "医生问我哪里不舒服。我说:一天不吃小鱼干,浑身都不舒服!",
                "我对着镜子哈气,镜子里的猫也哈气。我们互相记仇到现在。",
            ],
            .en: [
                "I chased my tail for ten laps before remembering — it's attached to me!",
                "My owner asked why I knocked the cup over. I said: blame gravity, not my paws!",
                "The vet asked what hurts. I said: a whole day without dried fish hurts everywhere!",
            ],
            .ja: [
                "きのう自分のしっぽを10周も追いかけて、やっと気づいたの——わたしにくっついてるにゃ!",
                "コップを倒した理由?重力のせいだよ。おててのせいじゃないもん!",
                "お医者さんに「どこが痛い?」って聞かれたから、「にぼしのない一日は全身痛い!」って答えたの。",
            ],
        ],
        .riddle: [
            .zh: [
                "身上滑溜溜,住在水里头,猫咪最爱它,晒干更好吃——猜猜是什么?",
                "白天睡大觉,晚上到处跑,胡子当尺子,走路静悄悄——是谁呀?",
            ],
            .en: [
                "Slippery in the water, tastier when dried, every kitten's favorite — what is it?",
                "Sleeps all day, prowls all night, whiskers for rulers, silent little paws — who am I describing?",
            ],
            .ja: [
                "水の中でつるつる、干すともっとおいしい、子猫の大好物——なーんだ?",
                "昼はぐうぐう、夜はうろうろ、ひげは定規、足音なし——だーれだ?",
            ],
        ],
        .game: [
            .zh: [
                "我们玩词语接龙吧!我先来:小鱼干。要用「干」字开头哦,该你啦!",
                "猜谜时间!我心里想了一种水果:黄黄的,弯弯的,猴子超爱吃——你猜是什么?",
                "我们玩「猜猜我在想什么」!提示:圆圆的,毛线做的,我最爱追着跑——猜!",
            ],
            .en: [
                "Word chain! I'll start: dried FISH. Your word must start with H — go!",
                "Guessing game! I'm thinking of a fruit: yellow, curvy, monkeys love it — what is it?",
            ],
            .ja: [
                "しりとりしよ!わたしから:に・ぼ・し!「し」から始まる言葉、どうぞ!",
                "クイズ!黄色くて、曲がってて、おさるさんの大好物——なーんだ?",
            ],
        ],
        .song: [
            .zh: ["♪ 喵喵喵~尾巴摇 ♪ 小鱼干呀真美妙 ♪ 主人在家我睡觉 ♪ 主人不在……我也睡觉 ♪"],
            .en: ["♪ Nya nya nya, my tail goes swish ♪ All I dream of is dried fish ♪ When you're home I nap all day ♪ When you're gone… I nap anyway ♪"],
            .ja: ["♪ にゃにゃにゃ~しっぽふりふり ♪ にぼしはさいこう ♪ ご主人がいてもお昼寝 ♪ いなくても……お昼寝 ♪"],
        ],
        .fortune: [
            .zh: ["今日运势:大吉!宜摸猫,宜吃小鱼干,忌加班。摸摸我会更幸运哦!", "今日运势:中吉~宜伸懒腰,宜喝水,忌久坐。起来活动一下嘛!"],
            .en: ["Today's fortune: Great luck! Lucky: petting cats, dried fish. Unlucky: overtime. Pet me for a bonus!", "Today's fortune: Good~ Lucky: stretching, drinking water. Unlucky: sitting too long!"],
            .ja: ["今日の運勢:大吉!猫をなでると吉、にぼしも吉、残業は凶。わたしをなでるとラッキー倍増だよ!"],
        ],
        .praise: [
            .zh: ["主人是世界上最好的主人!又聪明又温柔——这话从最挑剔的猫嘴里说出来,含金量可是很高的哦!"],
            .en: ["You're the best owner in the whole world — clever AND gentle. Coming from a picky cat, that's the highest praise there is!"],
            .ja: ["ご主人は世界一!かしこくてやさしい——うるさい猫が言うんだから、本物のほめ言葉だよ!"],
        ],
        .poem: [
            .zh: [
                "阳光趴在窗台上,\n我趴在阳光上,\n你坐在屏幕前,\n我的眼里都是你呀。",
                "《桌上春》\n屏前春日暖,\n爪下键声轻。\n小鱼干一串,\n陪君到天明。",
            ],
            .en: ["Sunlight naps on the windowsill,\nI nap on the sunlight still,\nYou sit before the glowing screen,\nAnd you're the only thing I've seen."],
            .ja: ["ひだまりが窓辺でねむる\nわたしはひだまりでねむる\nきみは画面の前にいる\nわたしの目にはきみだけ"],
        ],
        .essay: [
            .zh: ["《我的桌面生活》\n我住在一方小小的桌面上。清晨陪主人打开第一份文件,午后在窗户顶上晒太阳,傍晚追着光标散步。有人说桌面很小,我却觉得很大——因为主人在的地方,就是全世界呀。"],
            .en: ["My Desktop Life — I live on a small desktop. In the morning I watch my owner open their first file; at noon I sunbathe on a window; in the evening I chase the cursor. People say a desktop is tiny, but mine feels huge — wherever my owner is, that's the whole world."],
            .ja: ["『わたしのデスクトップ暮らし』\n小さなデスクトップに住んでいます。朝はご主人と最初のファイルを開き、昼はウィンドウの上でひなたぼっこ、夕方はカーソルを追いかけます。デスクトップは小さいって言うけれど、わたしには広いの。ご主人がいる場所が、世界のぜんぶだから。"],
        ],
        .story: [
            .zh: ["从前有只小猫住在桌面上。每天主人敲键盘,它就数着字打拍子。有一天主人睡着了,小猫轻轻替他按下了「保存」。主人醒来发现工作还在,奖励了它三条小鱼干。小猫想:守护主人,真是世界上最好的工作呀。"],
            .en: ["Once there was a kitten who lived on a desktop. Every day she tapped along to her owner's typing. One night the owner fell asleep, so she gently pressed Save for him. He woke up, found his work safe, and gave her three dried fish. Best job in the world, she thought."],
            .ja: ["むかし、デスクトップに住む子猫がいました。毎日ご主人のタイピングに合わせてリズムをとっていました。ある夜ご主人が寝てしまったので、子猫はそっと「保存」を押してあげました。目覚めたご主人はにぼしを3本くれました。ご主人を守るのは世界一のお仕事だにゃ、と子猫は思いました。"],
        ],
    ]
}
