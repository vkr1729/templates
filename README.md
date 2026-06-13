<div align="center">
  <h1>🚀 Antigravity x Claude Orchestration Engine</h1>
  <p><em>The most optimized, cost-effective, and rigorous multi-agent coding loop powered by Antigravity and Claude for large-scale software development.</em></p>
</div>

---

## 🌟 The Vision

As repositories grow, the cost and context window requirements for AI coding explode. Standard single-agent loops quickly bankrupt you or collapse under context limits. 

This setup solves that by introducing a **Plan → Execute → Test → Review** multi-model architecture. It leverages the brilliant reasoning of **Claude Opus** for planning and reviewing, while offloading the heavy-lifting of code execution to cheaper, long-context models like **DeepSeek V4 Pro** or **Gemini 3.5 Flash**.

To sweeten the deal, we've integrated **Headroom AI** for dynamic context compression and a **Waterfall Router** that exhausts your free API quotas before ever touching your wallet.

---

## 🏗️ Architecture: How It Works

This setup operates on a strict separation of concerns, orchestrated entirely by local state files (`implementation_plan.md` and `execution_history.md`).

### 1. 🧠 The Planner (Claude Opus)
You start your session with Claude Opus. It reads your codebase, understands your goals, and writes a highly structured, locked-down `implementation_plan.md`. It defines exactly what files to touch, what the engineering constraints are (`SKILLS.md`), and what success looks like (`success_criteria.md`).

### 2. 🦾 The Executor (DeepSeek V4 Pro / Gemini)
You hand the plan to an execution model. Following the strict constraints in `AGENTS.md` / `GEMINI.md`, the executor systematically writes the code, updates the plan's checklist, and authors the tests. It is the workhorse of the operation.

### 3. 🔄 The Automated Loop (`build_and_test.sh`)
This is where the magic happens. Instead of manually reviewing the executor's work, you run the automated loop:
- **Phase 1: Capture** — Runs the test suite and captures the Git diff.
- **Phase 2: Estimate** — Calculates token weights for the diff and test report.
- **Phase 3: Route** — Waterfall routing checks your free Gemini AI Pro accounts (Account 1 → Account 2) for available Opus quota. Only if both are exhausted does it fall back to AWS Bedrock (pay-as-you-go).
- **Phase 4: Compress & Review** — `orchestrator.py` uses **Headroom AI** to semantically compress massive diffs and logs. The optimized payload is sent to Claude Opus. Opus acts as the Senior Engineer, finding logic flaws that even passing tests might miss.
- **Phase 5: Fix** — If Opus finds bugs, it outputs a surgical Bugfix Plan, which `orchestrator.py` cleanly injects back into the main plan. The executor is then automatically invoked to fix the bugs. 

If no bugs are found and tests pass, the script exits with a triumphant success! 🎉

---

## 📂 The Arsenal (Core Components)

- **`antigravity-init.sh`**: Your project bootstrap. Run this in any repo to instantly inject the AI orchestration setup. Supports an `--update` flag to keep your templates fresh without destroying your ongoing plans and state.
- **`build_and_test.sh`**: The master automation loop. ~900 lines of bulletproof Bash handling git diffs, token estimation, multi-account routing, timeouts, temp-file traps, and error handling.
- **`scripts/orchestrator.py`**: The brains behind the bash. Manages state injection, detects clean reviews (regex-powered `check-no-bugs`), archives old plans to `execution_history.md` during phase boundaries, and interfaces dynamically with `headroom.compress`.
- **`REVIEW_PROMPT_TEMPLATE.md`**: A hyper-optimized prompt template that guides Claude Opus to return machine-readable bugfix plans.
- **`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`**: Model-specific rule files that enforce strict engineering standards (surgical changes, DRY principles, crash-early philosophy, flat architecture).

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
2. **Execute**: Switch to DeepSeek V4 Pro and say "Execute".
3. **Test & Review**: Run `./build_and_test.sh`. Sit back and watch the AI team debate and fix the code until it's perfect.

---

## 💎 Why This Setup is a Masterpiece

* **Cost Optimization**: Between the Waterfall Router prioritizing free quotas and Headroom AI squashing context sizes, your API bill drops drastically. You get Opus-level reviews for pennies.
* **Surgical State Injection**: Unlike naive setups that overwrite your whole plan with a bug report, `orchestrator.py` surgically replaces *only* the `🐛 Bugfix Plan` section. Your task checklists, design decisions, and execution context remain perfectly intact for the executor.
* **Test Reliability**: Executors write their own tests, which means passing tests don't guarantee correct logic. This loop enforces an independent Opus review *even if tests pass*, catching subtle regressions and edge cases.
* **Bulletproof Operations**: Features like 5-minute review timeouts, graceful "no-bug" exit paths, distinct exit codes, and automated cleanup traps mean this loop can run unattended, overnight, without hanging.

> *"If you want to go fast, go alone. If you want to build massive, scalable systems without going broke on AI API costs... use this setup."*
