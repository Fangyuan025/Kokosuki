# Building Kokosuki

## Requirements

- Apple Silicon Mac (the LLM runs on the GPU via [MLX](https://github.com/ml-explore/mlx-swift))
- macOS 14+
- Xcode 16+ command line tools (`xcode-select --install` at minimum, full Xcode
  recommended — the Metal shader compiler is required)

## Quick start

```bash
git clone https://github.com/Fangyuan025/Kokosuki.git
cd Kokosuki

# 1. Download the model weights (~907 MB) — see model/README.md
cd model
for f in config.json generation_config.json model.safetensors \
         model.safetensors.index.json tokenizer.json tokenizer_config.json \
         chat_template.jinja; do
  curl -L -O "https://huggingface.co/mlx-community/MiniCPM5-1B-OptiQ-4bit/resolve/main/$f"
done
cd ..

# 2. Build, compile the MLX metallib, bundle everything, sign (ad-hoc)
./scripts/package_app.sh

# 3. Done — a single self-contained app
open build/Kokosuki.app
```

The resulting `Kokosuki.app` (~1 GB) contains the binary, the Metal kernel
library, and the model. It runs fully offline and can be copied to any Apple
Silicon Mac (on other machines, right-click → Open the first time, since it is
ad-hoc signed).

## What the packaging script does

`scripts/package_app.sh`:

1. `swift build -c release`
2. `scripts/build_metallib.sh` — SwiftPM builds of mlx-swift don't produce the
   Metal kernel library, so the script compiles the non-JIT kernel set
   (`rms_norm`, `rope`, `scaled_dot_product_attention`, `gemv`, …) with
   `xcrun metal` into `mlx.metallib`, which must sit next to the executable
3. Assembles the `.app` bundle: binary, metallib, SwiftPM resource bundles,
   `model/`, generated `.icns` (the icon is rendered from the same vector code
   that draws the pet), `Info.plist` (`LSUIElement` = menu-bar app)
4. Ad-hoc codesigns the bundle

## Using a different model

Kokosuki talks to the model through a small, well-isolated surface, so swapping
models is easy:

**Works out of the box** — any MLX-format model that
[mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) can load
(llama/qwen/gemma/phi families, quantized or not) **and** that uses a
ChatML-style template (`<|im_start|>role … <|im_end|>`). Examples:
Qwen-family instruct models, MiniCPM. Just put its files in `model/` and run
the packaging script. Note the app looks for a single `model.safetensors`; for
sharded models edit the file list in `scripts/package_app.sh` accordingly.

**Needs a 2-line tweak** — models with a different chat template (e.g. Gemma's
`<start_of_turn>`): edit `buildPrompt` in `Sources/Kokosuki/Brain.swift` (the
prompt is assembled manually — no Jinja at runtime) and the `extraEOSTokens`
in `Brain.load()`.

Things to keep in mind when swapping:

- **Size / speed**: the UX is tuned for ~40+ tok/s. A 3B-4B quantized model is
  still fine on an M-series Pro; expect ~2× the memory of the weights file.
- **The persona prompts** (`Sources/Kokosuki/Persona.swift`) are written for a
  small model: heavy few-shot examples, a forced `[emotion]` tag prefill, and a
  rejection-sampling quality gate. Larger models simply comply better — no
  changes needed, replies just get smarter.
- **Language support** follows the model. The default MiniCPM is strong in
  Chinese/English and weak in Japanese; the app's quality gates keep the format
  correct regardless, and curated fallback content guarantees delivery for
  jokes/stories/games even when the model fumbles.
- The tokenizer-class workaround `replacementTokenizers["TokenizersBackend"]`
  in `Brain.load()` is needed for models exported with transformers v5; it is
  harmless for older exports.

## Development utilities

```bash
.build/release/Kokosuki --snapshot <dir>   # render all pet states to PNGs (visual QA)
.build/release/Kokosuki --icon <dir>       # render the app icon art
.build/release/Kokosuki --selftest 2       # unit gates + trilingual LLM batch:
                                           #   chat quality, creative delivery,
                                           #   context recall, repeat-variation
.build/release/Kokosuki --scenarios 1      # 32-prompt common-scenario suite
.build/release/Kokosuki --platforms        # list window tops the cat can jump onto
.build/release/kokosuki-cli model "hello"  # raw generation harness
KOKOSUKI_DEBUG=1                           # env var: interaction event log to /tmp
```

The selftest suites are how the LLM behavior was tuned: every reply must pass
deterministic gates (language match, no instruction echo, no verbatim repeats,
no announced-but-undelivered content, correct arithmetic, …) with automatic
resampling and curated fallbacks. If you change the prompts, run
`--selftest 2` and `--scenarios 1` to catch regressions.
