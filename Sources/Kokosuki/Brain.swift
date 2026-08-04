import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// The pet's offline mind: loads the bundled MiniCPM5 MLX model and produces
/// structured, state-aware replies. All callbacks are delivered on the main actor.
final class Brain: @unchecked Sendable {

    struct Message: Codable {
        var role: String   // "user" | "assistant"
        var text: String
        var date: Date
    }

    private var container: ModelContainer?
    private(set) var history: [Message] = []
    private let historyURL: URL
    private var generation: Task<Void, Never>?
    private var epoch = 0   // stale-generation guard: callbacks from cancelled runs are dropped

    @MainActor var onStateChange: ((BrainState) -> Void)?

    /// `loadPersistedHistory: false` gives an isolated brain (selftest) that neither
    /// reads nor pollutes the user's real conversation history.
    private let persistHistory: Bool

    init(loadPersistedHistory: Bool = true) {
        persistHistory = loadPersistedHistory
        let dir = Persistence.supportDir
        historyURL = dir.appendingPathComponent("chat-history.json")
        if loadPersistedHistory,
            let data = try? Data(contentsOf: historyURL),
            let saved = try? JSONDecoder().decode([Message].self, from: data)
        {
            history = saved
        }
    }

    // MARK: - Loading

    static func locateModelDir() -> URL? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("model"))
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("model"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("model"))
        return candidates.first {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("model.safetensors").path)
        }
    }

    func load() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                guard let dir = Brain.locateModelDir() else {
                    throw NSError(domain: "Kokosuki", code: 1, userInfo: [NSLocalizedDescriptionKey: "model directory not found"])
                }
                // keep MLX's buffer cache small; a desktop pet should stay lightweight
                MLX.GPU.set(cacheLimit: 128 * 1024 * 1024)
                replacementTokenizers["TokenizersBackend"] = "PreTrainedTokenizer"
                let config = ModelConfiguration(
                    directory: dir, overrideTokenizer: "PreTrainedTokenizer",
                    extraEOSTokens: ["<|im_end|>"])
                let container = try await LLMModelFactory.shared.loadContainer(configuration: config)
                self.container = container

                // Warm up: tiny generation compiles the JIT metal kernels now,
                // so the first real reply isn't slow.
                try await container.perform { context in
                    let tokens = context.tokenizer.encode(text: "<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n")
                    let input = LMInput(tokens: MLXArray(tokens))
                    let params = GenerateParameters(maxTokens: 2, temperature: 0.7)
                    let stream = try MLXLMCommon.generate(input: input, parameters: params, context: context)
                    for await _ in stream {}
                }
                await MainActor.run { self.onStateChange?(.ready) }
            } catch {
                let msg = "\(error)"
                await MainActor.run { self.onStateChange?(.failed(msg)) }
            }
        }
    }

    var isReady: Bool { container != nil }
    var isGenerating: Bool { generation != nil }

    // MARK: - Prompt assembly (manual ChatML; empty think block = fast non-thinking mode)

    /// Manual ChatML. The empty think block selects fast non-thinking mode, and we
    /// prefill "[" so the reply is forced to start with an emotion tag.
    private func buildPrompt(system: String, turns: [Message], user: String) -> String {
        var p = "<|im_start|>system\n\(system)<|im_end|>\n"
        for m in turns {
            p += "<|im_start|>\(m.role)\n\(m.text)<|im_end|>\n"
        }
        p += "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n["
        return p
    }

    // MARK: - Generation

    /// Stream a reply. `recordHistory` false for spontaneous chatter/events so canned
    /// context lines don't pollute the visible chat log (they still get persona context).
    /// Callbacks: `onEmotion` fires as soon as the leading tag parses; `onText` receives
    /// the running de-tagged text; `onDone` the final parse (nil text on cancel/error).
    @MainActor
    func generate(
        userContent: String,
        context ctx: PetContext,
        recordHistory: Bool,
        historyUserText: String? = nil,
        commandHint: String? = nil,
        creative: (kind: Persona.CreativeKind, fallback: String)? = nil,
        onEmotion: @escaping @MainActor (Emotion) -> Void,
        onText: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor (Persona.ParsedReply?) -> Void
    ) {
        guard let container else {
            onDone(nil)
            return
        }
        generation?.cancel()
        epoch += 1
        let myEpoch = epoch
        let longform = creative != nil

        let lang = ctx.lang
        var system = Persona.system(ctx)
        if longform { system += "\n\n" + Persona.creativeExample(lang) }
        // window balances multi-turn coherence against bad-habit contamination, and
        // only turns in the CURRENT language — zh history dragged en/ja into Chinese
        let turns = Array(
            history.suffix(18)
                .filter { Persona.languageMatches($0.text, lang: lang) }
                .suffix(10))
        var wrapped = userContent
        if let commandHint { wrapped += "\n" + commandHint }
        wrapped += "\n" + Persona.reminder(lang)
        let prompt = buildPrompt(system: system, turns: turns, user: wrapped)
        // for verbatim-repeat retries: same prompt plus an explicit variation nudge
        let nudgedPrompt = buildPrompt(
            system: system, turns: turns,
            user: wrapped + "\n" + Persona.repeatNudge(lang))
        let recentReplies = history.suffix(8).filter { $0.role == "assistant" }.map(\.text)

        generation = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // One streamed sampling pass; returns the raw accumulated text.
            func onePass(temperature: Float, prompt: String) async throws -> String {
                var raw = "["   // mirror the prefilled tag opener
                var announcedEmotion = false
                var emittedLen = 0
                try await container.perform { context in
                    let tokens = context.tokenizer.encode(text: prompt)
                    let input = LMInput(tokens: MLXArray(tokens))
                    let params = GenerateParameters(
                        maxTokens: longform ? 280 : 90, temperature: temperature, topP: 0.85,
                        repetitionPenalty: 1.12, repetitionContextSize: 60)
                    let stream = try MLXLMCommon.generate(input: input, parameters: params, context: context)
                    let rawCap = longform ? 560 : 200
                    for await item in stream {
                        if Task.isCancelled { break }
                        if case .chunk(let piece) = item {
                            raw += piece
                            if raw.count > rawCap { break }  // pet-sized replies only
                            if !announcedEmotion, let (emo, _) = Persona.earlyTag(from: raw) {
                                announcedEmotion = true
                                if let emo {
                                    await MainActor.run {
                                        if self.epoch == myEpoch { onEmotion(emo) }
                                    }
                                }
                            }
                            // stream the de-tagged running text (flattened + capped so
                            // the bubble can never balloon mid-stream)
                            if announcedEmotion || raw.count > 6 {
                                var visible = raw
                                if let (_, rest) = Persona.earlyTag(from: raw) { visible = rest }
                                visible = visible
                                    .replacingOccurrences(of: "[", with: " ")
                                    .replacingOccurrences(of: "]", with: " ")
                                    .replacingOccurrences(of: "\n", with: " ")
                                while visible.contains("  ") {
                                    visible = visible.replacingOccurrences(of: "  ", with: " ")
                                }
                                let streamCap = longform ? 420 : 150
                                if visible.count > streamCap { visible = String(visible.prefix(streamCap)) + "…" }
                                if visible.count > emittedLen {
                                    emittedLen = visible.count
                                    let v = visible.trimmingCharacters(in: .whitespaces)
                                    await MainActor.run {
                                        if self.epoch == myEpoch { onText(v) }
                                    }
                                }
                            }
                        }
                    }
                }
                return raw
            }

            // Rejection sampling: a coherent first pass at low temperature; if it's
            // empty, off-language, a parrot-echo, or assistant-speak, resample once
            // hotter and keep the better of the two.
            func issue(_ p: Persona.ParsedReply) -> String? {
                if p.text.isEmpty { return "empty" }
                // echo reference covers everything we injected: command hint,
                // reminder, and the status block (reciting one's stat sheet is weird)
                let injected = [commandHint, Persona.reminder(lang), Persona.statusLine(ctx)]
                    .compactMap { $0 }.joined(separator: "\n")
                return Persona.qualityIssue(
                    reply: p.text, user: userContent, lang: lang,
                    creativeKind: creative?.kind, hint: injected,
                    recentReplies: recentReplies)
            }
            var parsed: Persona.ParsedReply?
            do {
                let first = Persona.parse(
                    try await onePass(temperature: longform ? 0.7 : 0.5, prompt: prompt),
                    lang: lang, longform: longform)
                let firstIssue = issue(first)
                if firstIssue == nil || Task.isCancelled {
                    parsed = first
                } else {
                    // repeats get an explicit "say it differently" nudge on the retry
                    let retryPrompt = firstIssue == "verbatim repeat" ? nudgedPrompt : prompt
                    let second = Persona.parse(
                        try await onePass(temperature: 0.9, prompt: retryPrompt),
                        lang: lang, longform: longform)
                    if issue(second) == nil {
                        parsed = second
                    } else if first.text.isEmpty {
                        parsed = second   // anything beats silence
                    } else if second.text.isEmpty {
                        parsed = first
                    } else {
                        // both flawed: prefer the one in the right language
                        parsed = Persona.languageMatches(second.text, lang: lang) && !Persona.languageMatches(first.text, lang: lang)
                            ? second : first
                    }
                    if var p = parsed {
                        p.qualityFlag = issue(p)
                        parsed = p
                    }
                }
            } catch {
                parsed = nil
            }

            let cancelled = Task.isCancelled
            var result = parsed
            // creative ask that the model fumbled twice: deliver curated content
            // instead, and record IT in history so follow-up turns stay coherent
            if !cancelled, let creative,
                result == nil || result!.text.isEmpty || result!.qualityFlag != nil
            {
                result = Persona.ParsedReply(
                    emotion: result?.emotion ?? .playful, action: nil, text: creative.fallback)
            }
            // simple arithmetic the model kept fumbling: answer deterministically
            if !cancelled, result?.qualityFlag == "math unanswered",
                let ans = Persona.arithmeticResult(in: userContent)
            {
                result = Persona.ParsedReply(
                    emotion: .proud, action: nil, text: Persona.mathFallback(ans, lang: lang))
            }
            let final = result
            await MainActor.run {
                // a newer generation superseded us — vanish silently
                guard self.epoch == myEpoch else { return }
                self.generation = nil
                guard let result = final, !cancelled, !result.text.isEmpty else {
                    onDone(cancelled ? nil : final)
                    return
                }
                if recordHistory {
                    self.history.append(Message(role: "user", text: historyUserText ?? userContent, date: .now))
                    self.history.append(Message(role: "assistant", text: result.text, date: .now))
                    self.trimAndSaveHistory()
                }
                onDone(result)
            }
        }
    }

    @MainActor
    func cancelGeneration() {
        generation?.cancel()
        generation = nil
    }

    // MARK: - History

    private func trimAndSaveHistory() {
        if history.count > 60 { history.removeFirst(history.count - 60) }
        guard persistHistory else { return }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    @MainActor
    func clearHistory() {
        history.removeAll()
        if persistHistory {
            try? FileManager.default.removeItem(at: historyURL)
        }
    }

    /// Record a line the pet said on its own (spontaneous chatter, canned or LLM),
    /// so later chat turns remember it was said.
    @MainActor
    func noteAssistantLine(_ text: String) {
        guard !text.isEmpty else { return }
        history.append(Message(role: "assistant", text: text, date: .now))
        trimAndSaveHistory()
    }
}
