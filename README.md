<div align="center">
  <h1>🚀 Antigravity x Claude Orchestration Engine</h1>
  <p><em>The most versatile, customizable, and rigorous multi-agent coding loop powered by your choice of CLI and models for large-scale software development.</em></p>
</div>

---

## 🌟 The Vision

As repositories grow, the cost and context window requirements for AI coding explode. Standard single-agent loops quickly bankrupt you or collapse under context limits. 

This setup solves that by introducing a highly-versatile **Plan → Execute → Test → Review** multi-model architecture. You can dynamically mix and match your preferred CLIs (`cmd`, `agy`, `kimchi`, `claude`) and models for both implementation and code review, tailoring the setup entirely to your workflow.

---

## 🏗️ Architecture: How It Works

This setup operates on a strict separation of concerns, orchestrated entirely by local state files (`implementation_plan.md` and `execution_history.md`).

### 1. 🧠 The Planner (Claude Opus)
You start your session with an advanced model like Claude Opus. It reads your codebase, understands your goals, and writes a highly structured, locked-down `implementation_plan.md`. It defines exactly what files to touch, what the engineering constraints are (`SKILLS.md`), and what success looks like (`success_criteria.md`).

### 2. 🦾 The Executor (Your CLI of Choice)
You hand the plan to an execution model. Following the strict constraints in `AGENTS.md` / `GEMINI.md` / `KIMCHI.md` / `CLAUDE.md`, the executor systematically writes the code, updates the plan's checklist, and authors the tests. 

### 3. 🔄 The Automated Loop (`build_and_test.sh`)
Instead of manually reviewing the executor's work, you run the automated loop:
- **Phase 1: Implement** — The selected implementation CLI executes the initial implementation plan.
- **Phase 2: Capture** — Runs the test suite and captures the Git diff.
- **Phase 3: Estimate** — Calculates token weights for the diff and test report.
- **Phase 4: Route** — Routes the review to your chosen Review CLI/Model (or falls back to a custom waterfall quota router if unconfigured).
- **Phase 5: Compress & Review** — `orchestrator.py` uses **Headroom AI** to semantically compress massive diffs and logs. The optimized payload is sent to the Review Model, which acts as the Senior Engineer, finding logic flaws that even passing tests might miss.
- **Phase 6: Fix** — If bugs are found, it outputs a surgical Bugfix Plan, which `orchestrator.py` cleanly injects back into the main plan. The implementation executor is then automatically invoked to fix the bugs. 

If no bugs are found and tests pass, the script exits with a triumphant success! 🎉

---

## 🎛️ Extreme Versatility: CLI & Model Configuration

The `build_and_test.sh` script is built to adapt to whatever CLI and model combination you prefer. You can specify the implementation and review CLIs using the `--impl-cli` and `--review-cli` flags.

If no specific models are passed (via `--model` or `--review-model`), the script seamlessly falls back to optimized defaults:

| CLI | Default Implementation Model | Default Review Model |
| --- | --- | --- |
| `agy` | Gemini 3.1 Pro (High) | Claude Opus 4.6 (Thinking) |
| `cmd` | minimax-m3 | minimax-m3 |
| `kimchi` | kimi-k2.6 | kimi-k2.6 |
| `claude` | us.anthropic.claude-opus-4-6-v1 | us.anthropic.claude-opus-4-6-v1 |

### Examples

**Standard run (uses configured defaults in script):**
```bash
./build_and_test.sh
```

**Use Claude for execution, Kimchi for review:**
```bash
./build_and_test.sh --impl-cli claude --review-cli kimchi
```

**Override models entirely:**
```bash
./build_and_test.sh --impl-cli cmd --model "super-minimax-v4" --review-cli agy --review-model "Claude Sonnet 3.5"
```

*(Note: If no `--review-cli` is specified, the script falls back to an advanced Waterfall model designed to exhaust free API quotas before touching pay-as-you-go billing).*

### 🔧 Adding a Custom CLI

If you want to use a brand new CLI tool (e.g., `aider`, `cline`, or a custom Python script), you can easily add support by modifying `build_and_test.sh` in just 3 spots:

1. **Add Model Defaults:**
   Around line 195, add your CLI to the `case` statement to resolve the default model:
   ```bash
   case "$IMPL_CLI" in
       my_cli) IMPL_MODEL="my-custom-model-v2" ;; # <--- Add this
   ```

2. **Add Implementation Logic:**
   In the `run_executor()` function (around line 850), add an `elif` condition to format the exact arguments your CLI needs to run autonomously:
   ```bash
   elif [ "$IMPL_CLI" = "my_cli" ]; then
       my_cli --run-model "$IMPL_MODEL" --prompt "Execute" --skip-confirm || cmd_exit=$?
   ```

3. **Add Review Logic:**
   In the `execute_custom_review()` function (around line 665), define how your CLI accepts file-based prompts and outputs to stdout:
   ```bash
   elif [ "$REVIEW_CLI" = "my_cli" ]; then
       my_cli --run-model "$REVIEW_MODEL" --prompt "$(cat "$prompt_file")" > "$output_file" 2>&1 || review_exit=$?
   ```

As long as your CLI exits with a `0` when finished and outputs markdown text during review, the bash loop and Python orchestrator will handle the rest flawlessly!

---

## 📂 The Arsenal (Core Components)

- **`antigravity-init.sh`**: Your project bootstrap. Run this in any repo to instantly inject the AI orchestration setup. Supports an `--update` flag to keep your templates fresh without destroying your ongoing plans and state.
- **`build_and_test.sh`**: The master automation loop. Over 1000 lines of bulletproof Bash handling git diffs, multi-account routing, custom CLI executions, timeouts, temp-file traps, and error handling.
- **`scripts/orchestrator.py`**: The brains behind the bash. Manages state injection, detects clean reviews (regex-powered `check-no-bugs`), archives old plans to `execution_history.md` during phase boundaries, and interfaces dynamically with `headroom.compress`.
- **`REVIEW_PROMPT_TEMPLATE.md`**: A hyper-optimized prompt template that guides the Review Model to return machine-readable bugfix plans.
- **`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `KIMCHI.md`**: Model-specific rule files that enforce strict engineering standards (surgical changes, DRY principles, crash-early philosophy, flat architecture).

---

## 🛠️ Getting Started

### 1. Initialization
Navigate to your project folder and run the init script to copy the templates:
```bash
~/.antigravity/templates/antigravity-init.sh
```

### 2. One-Time Setup
Run the setup command to install dependencies (`headroom-ai`) and securely authenticate your API accounts:
```bash
./build_and_test.sh --setup
```

### 3. The Daily Workflow
1. **Plan**: Ask Claude Opus to design a feature.
2. **Execute**: Switch to your preferred executor and say "Execute".
3. **Test & Review**: Run `./build_and_test.sh`. Sit back and watch the AI team debate and fix the code until it's perfect.

---

## 💎 Why This Setup is a Masterpiece

* **Unmatched Flexibility**: Mix and match any AI CLI you want. Bring your own models, your own keys, and orchestrate them perfectly.
* **Surgical State Injection**: Unlike naive setups that overwrite your whole plan with a bug report, `orchestrator.py` surgically replaces *only* the `🐛 Bugfix Plan` section. Your task checklists, design decisions, and execution context remain perfectly intact for the executor.
* **Test Reliability**: Executors write their own tests, which means passing tests don't guarantee correct logic. This loop enforces an independent AI review *even if tests pass*, catching subtle regressions and edge cases.
* **Bulletproof Operations**: Features like automated dry-runs, graceful "no-bug" exit paths, distinct exit codes, and automated cleanup traps mean this loop can run unattended, overnight, without hanging.

> *"If you want to go fast, go alone. If you want to build massive, scalable systems perfectly... orchestrate an entire AI engineering team."*
