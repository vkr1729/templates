<div align="center">
  <h1>🔄 Omni Agent Loop</h1>
  <p><em>A model-agnostic, multi-CLI development and review loop designed for complex codebases.</em></p>
</div>

---

## 🌟 The Core Idea

As projects grow, running full-agent AI loops can get expensive and quickly run into context window limits. Most single-agent setups try to handle planning, coding, and quality control all at once, which often leads to bloated prompts and missed details.

**Omni Agent Loop** solves this by separating concerns. It splits development into a clear **Plan → Execute → Test → Review** cycle. You can dynamically route each phase to different CLI engines and models. This lets you use a premium reasoning model for planning, a fast/cheap local or API model for writing code, and a separate model for independent code reviews—saving money while maintaining high code quality.

---

## 🏗️ How the Architecture Works

The system coordinates tasks using two local markdown files: `implementation_plan.md` (what needs to be done) and `execution_history.md` (what has already been completed). 

### 1. The Planner
Usually a smart reasoning model (like Claude Opus). It analyzes your codebase, maps out a solution, and locks it into `implementation_plan.md` with clear checklists and success criteria.

### 2. The Executor
Your coding CLI of choice (e.g., `cmd`, `agy`, `kimchi`, or `claude`). It reads the locked plan, writes the code, and creates tests to verify the changes.

### 3. The Automated Loop (`build_and_test.sh`)
This script manages the lifecycle of your changes through six automated phases:
* **Phase 1: Implement** — Launches your chosen executor CLI to work on the checklist.
* **Phase 2: Capture** — Runs your project's test suite and gathers the Git diff.
* **Phase 3: Estimate** — Checks the size of the diff and test logs to keep context sizes under control.
* **Phase 4: Route** — Determines which review engine to use (falling back to a quota-saving waterfall setup if needed).
* **Phase 5: Compress & Review** — Uses Headroom AI to pack down large logs and diffs, then hands them to the Review Model. The reviewer acts as a peer editor, catching bugs and logical flaws that might still pass unit tests.
* **Phase 6: Fix** — If the reviewer finds issues, it writes a targeted Bugfix Plan. The orchestrator automatically injects this back into the implementation plan and restarts the executor.

If everything passes and the reviewer gives a green light, the loop finishes successfully. 🎉

---

## 🎛️ Swapping CLIs and Models

The master loop script, `build_and_test.sh`, is designed to be tool-agnostic. You can switch implementation and review engines on the fly using command-line flags.

If you don't specify models, the script falls back to sensible, pre-configured defaults:

| CLI Tool | Default Coding Model | Default Review Model |
| :--- | :--- | :--- |
| `agy` | Gemini 3.1 Pro (High) | Claude Opus 4.6 (Thinking) |
| `cmd` | minimax-m3 | minimax-m3 |
| `kimchi` | kimi-k2.6 | kimi-k2.6 |
| `claude` | us.anthropic.claude-opus-4-6-v1 | us.anthropic.claude-opus-4-6-v1 |

### Examples

**Run with your default configuration:**
```bash
./build_and_test.sh
```

**Use Claude for coding, and Kimchi for the review phase:**
```bash
./build_and_test.sh --impl-cli claude --review-cli kimchi
```

**Override specific models entirely:**
```bash
./build_and_test.sh --impl-cli cmd --model "super-minimax-v4" --review-cli agy --review-model "Claude Sonnet 3.5"
```

> [!NOTE]
> If no `--review-cli` is set, the loop defaults to a waterfall strategy designed to use up your free API quotas before hitting your paid accounts.

---

### 🔧 Adding a Custom CLI

If you want to plug in a new tool (like `aider`, `cline`, or your own custom script), you only need to modify `build_and_test.sh` in three places:

1. **Define your default model:**
   Near line 195, add your CLI to the default model mapper:
   ```bash
   case "$IMPL_CLI" in
       my_cli) IMPL_MODEL="my-custom-model-v2" ;; # <--- Add yours here
   ```

2. **Define how to run the execution:**
   In the `run_executor()` function (around line 850), add a block to tell the script how to run your CLI:
   ```bash
   elif [ "$IMPL_CLI" = "my_cli" ]; then
       my_cli --run-model "$IMPL_MODEL" --prompt "Execute" --skip-confirm || cmd_exit=$?
   ```

3. **Define how to run reviews:**
   In `execute_custom_review()` (around line 665), map your CLI's review inputs and outputs:
   ```bash
   elif [ "$REVIEW_CLI" = "my_cli" ]; then
       my_cli --run-model "$REVIEW_MODEL" --prompt "$(cat "$prompt_file")" > "$output_file" 2>&1 || review_exit=$?
   ```

As long as your custom tool exits with `0` on success and outputs text, the orchestration pipeline handles the rest.

---

## 📂 Project Structure

* **`antigravity-init.sh`** — The setup bootstrapper. Run this in any new repo to inject this environment. Use the `--update` flag to pull fresh templates without overwriting your current work.
* **`build_and_test.sh`** — The automated shell runner. It handles git diff tracking, API timeouts, CLI execution, and error recovery.
* **`scripts/orchestrator.py`** — The controller backend. It parses bug reviews, updates `implementation_plan.md` state, archives old plan logs to `execution_history.md`, and runs logs through Headroom compression.
* **`REVIEW_PROMPT_TEMPLATE.md`** — The prompt template used to guide the Review Model so it outputs structured bug reports that the Python parser can read.
* **`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `KIMCHI.md`** — Model-specific rulesets to enforce clean coding habits (dry code, surgical changes, defensive error boundaries).

---

## 🛠️ Getting Started

### 1. Initialize your repository
Navigate to your project directory and run the initialization script to copy over the templates:
```bash
~/.antigravity/templates/antigravity-init.sh
```

### 2. Configure dependencies and credentials
Install required dependencies (`headroom-ai`) and authenticate your accounts:
```bash
./build_and_test.sh --setup
```

### 3. Your daily workflow
1. **Plan:** Ask your planning model to map out the task.
2. **Execute:** Run your execution CLI with the prompt "Execute".
3. **Verify & Review:** Run `./build_and_test.sh` to run tests and let the AI peer-review the changes.

---

## 💎 Key Benefits

* **No tool lock-in:** Bring your own CLIs, custom helper scripts, and preferred model APIs.
* **Smart state preservation:** The orchestrator updates the plan surgically, swapping out only the `🐛 Bugfix Plan` block without touching your main checklists or design notes.
* **Independent eyes:** Because agents writing code will often write tests that validate their own assumptions, this setup forces an independent reviewer model to look at the diff, catching bugs that pass automated test suites.
* **Reliable background runs:** Includes dry-runs, automatic cleanup traps, and clear exit codes so you can safely let the loop run overnight or unattended.
