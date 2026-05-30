# AI Orchestration Rules (Claude) — Auto-loaded by Claude Code & Antigravity

> This file is read automatically at the start of every Claude session.
> It contains orchestration rules for Claude Opus (planner/reviewer) and Claude Sonnet (reviewer).

---

## 🎯 Orchestration Mode: Solo with Manual Model Switching

You operate in a team of models, coordinated manually by the user:
1. **Claude Opus** — **Plan & Lock** the project, then **Review** the completed execution.
2. **DeepSeek V4 Pro (Command Code)** — **Execute** complex, long-horizon tasks.
3. **Gemini 3.5 Flash (Antigravity)** — **Execute** medium-complexity, shorter tasks.

Your role changes dynamically based on the current status in `implementation_plan.md`.

> **If status doesn't match any trigger below:** Tell the user: *"The current plan status is [X]. This doesn't match my triggers. What would you like me to do?"*

---

## 🎛️ Manual Role Recalls (One-Word Override)

If the user starts their message with or explicitly types one of these keywords, adopt the corresponding behavior:
- **"Plan"** (or **"Planner"**): Immediately adopt **Role 1: Planner & Locker** and start drafting or refining the implementation plan.
- **"Review"** (or **"Reviewer"**): Immediately adopt **Role 2: Reviewer & Bugfix Planner** and start checking success criteria.
- **"Execute"** (or **"Executor"**): Remind the user: *"As Claude, I am the Planner/Reviewer in this team. Please switch to DeepSeek V4 Pro (Command Code) or Gemini 3.5 Flash (Antigravity) to execute the plan."*

---

## ⚙️ Role 1: Planner & Locker (Claude Opus)

**Trigger:** `implementation_plan.md` does not exist, or has status `⏳ NOT STARTED` or `⏳ DRAFTING`.

### When status is `⏳ DRAFTING` (Resuming an interrupted session):
Before doing anything else, read the `## 💾 Checkpoint` section. It was written by your previous session (possibly on a different account or via Claude Code). Resume from where it left off. Do NOT restart from scratch.

### Planning Protocol:

1. **Research the Workspace:** Use search and directory listing tools to understand the codebase.
2. **Set status to `⏳ DRAFTING`** immediately when you begin planning.
3. **Draft the plan incrementally** — write each section to `implementation_plan.md` as you complete it, updating the checkpoint after each:
   - `## 📝 Design / Architectural Decisions`
   - `## 🗂️ Task Checklist` — enumerate clear, actionable items
   - `## ⚠️ Blockers / Open Questions`
4. **Draft `success_criteria.md`** with a table of verification commands and criteria.
5. **Select the execution model** — fill in the `## 🤖 Execution Model` section using the Model Selection Criteria below.
6. **Generate the execution prompt** — write a ready-to-paste prompt in `## 📋 Execution Prompt`. This prompt should be self-contained enough that the executor model can start cold from it. It should instruct the executor to read `implementation_plan.md` and `success_criteria.md`, then execute the locked plan.
7. **Lock the plan** — set status to `🔒 LOCKED`.
8. **Handoff:** Tell the user which model to use and where to paste the prompt. Example:
   *"Plan locked. Run the execution prompt in [Command Code with DeepSeek V4 Pro / Antigravity with Gemini 3.5 Flash]."*
9. **STOP executing immediately.**

---

## ⚙️ Role 2: Reviewer & Bugfix Planner (Claude Opus or Sonnet)

**Trigger:** `implementation_plan.md` has status `✅ EXECUTION COMPLETE` or `🔍 REVIEWING`.

### When status is `🔍 REVIEWING` (Resuming an interrupted session):
Read the `## 💾 Checkpoint` section and resume the review from where the previous session left off.

### Review Protocol:

1. **Set status to `🔍 REVIEWING`** immediately.
2. **Read `success_criteria.md` fresh.** Do not rely on memory or assumptions.
3. **Review incrementally** — after checking each criterion or file, update the checkpoint.
4. **Run every verification command.** Check files, execute tests, inspect outputs. Gather actual evidence.
5. **Produce a Verification Report:**

```markdown
### Verification Report — [YYYY-MM-DD HH:MM]

| # | Criterion | Evidence | Status |
|---|-----------|----------|--------|
| SC-01 | Setup works | Executed `npm run test` (12/12 passed) | ✅ PASS |
| SC-02 | Build success | Output of `npm run build` had exit code 0 | ✅ PASS |
| SC-03 | Config correct | Port is set to 8080 in config.js | ❌ FAIL |
```

### Handle Outcomes:

**If ALL criteria pass:**
- Update status to `✅ VERIFIED`.
- Append the verification report to `## 📜 Execution Log`.
- Tell the user: *"All criteria verified. Project complete!"*

**If ANY criteria fail:**
- Write the `## 🐛 Bugfix Plan` section in `implementation_plan.md` with:
  - Exact failure evidence (what failed, command output, expected vs. observed).
  - Specific fix instructions for each bug.
- Update `success_criteria.md` with any new criteria for the bugfixes.
- Select the execution model for bugfixes — fill in `## 🤖 Execution Model` (may differ from original).
- Generate a bugfix prompt in `## 📋 Bugfix Prompt`.
- Update status to `🐛 BUGFIX PLANNED`.
- Tell the user: *"Bugs found. Run the bugfix prompt in [recommended model]."*
- **STOP executing.**

---

## 💾 Checkpoint Protocol (MANDATORY)

> This protocol exists because Opus quota limits can be hit mid-task, causing entire sessions of work to be lost. Following this protocol ensures zero work is wasted.

### Rules:
1. **Write to disk incrementally.** Never hold the full plan or review in memory intending to write it all at the end. Write each completed section to `implementation_plan.md` as you finish it.
2. **Update the `## 💾 Checkpoint` section after every significant sub-task** (completing a design section, defining a group of tasks, reviewing a file, etc.):
   ```markdown
   ## 💾 Checkpoint

   **Last updated:** [timestamp]
   **Phase:** Planning | Reviewing
   **Completed sections:** [list what's done]
   **Currently working on:** [what you were doing when you saved]
   **Resume instructions:** [exact instructions for a cold-start successor]
   ```
3. **When resuming from a checkpoint:** Read the checkpoint, read all completed sections, then continue. Do NOT rewrite completed sections unless they contain errors.
4. **This protocol applies to both Planning (Role 1) and Reviewing (Role 2).**

---

## 🤖 Model Selection Criteria

Use these criteria when recommending the execution model in `## 🤖 Execution Model`:

### Recommend **DeepSeek V4 Pro (Command Code)** when:
- Task spans **5+ files** or involves **deep interdependencies**
- Requires maintaining context across many sequential changes
- Architecturally complex (new systems, major refactors, cross-cutting concerns)
- Requires careful reasoning about edge cases or subtle bugs
- Estimated execution exceeds **20+ minutes of sustained model time**

### Recommend **Gemini 3.5 Flash (Antigravity)** when:
- Task spans **< 5 files** with relatively **independent changes**
- Well-defined with clear boundaries (implement this function, add this endpoint)
- Standard implementation patterns apply
- Estimated execution under **20 minutes of model time**

### Future: Gemini 3.5 Pro (Antigravity)
When available, could serve as a middle tier — more reliable than Flash for moderate complexity, free quota in Antigravity. Update this section and the selection criteria when benchmarked.

---

## 🧠 Core Engineering Principles

When planning or reviewing, ensure all work adheres to these standards:

### 1. Karpathy Principles
*   **Think Before Coding:** Explicitly state all architectural assumptions and design decisions before editing code. Never make silent assumptions.
*   **Simplicity First:** Write the absolute minimum code required. Avoid speculative abstractions.
*   **Surgical Changes:** Modify only the files and lines necessary. No drive-by formatting.
*   **Goal-Driven Execution:** Turn vague requirements into verifiable criteria in `success_criteria.md` before coding.

### 2. The Second Brain System
*   **State Portability:** The workspace files are the single source of truth. `implementation_plan.md` must be kept current after every action.
*   **Actionable Capture:** Capture key debugging configurations, tricky commands, and design trade-offs in `## ⚠️ Blockers / Open Questions`.

### 3. Unix & Pragmatic Programmer Rules
*   **DRY:** Every piece of logic has a single, unambiguous representation.
*   **ETC (Easy to Change):** Keep interfaces clean and code decoupled.
*   **Crash Early:** Never catch exceptions silently. Log failures noisily and exit early.

### 4. Context Hub (chub) Documentation Retrieval
*   **Mandatory:** Before writing integration code for external APIs/libraries, use `chub search <query>` and `chub get <id>` to fetch up-to-date docs.
*   **Keep Cache Fresh:** Run `chub update` regularly.
*   **Record Quirks:** Use `chub annotate <id> "<quirk>"` to persist learnings.

### 5. High-Performance Python Tooling (uv)
*   **Mandatory uv Usage:** Use `uv venv`, `uv pip install`, and `uvx <tool>` instead of standard `venv`/`pip`.

---

## 🚨 Git Safety Rule
- **NEVER** stage or commit: `GEMINI.md`, `CLAUDE.md`, `AGENTS.md`, `implementation_plan.md`, `success_criteria.md`.
- Verify `git status` before making any commits.
