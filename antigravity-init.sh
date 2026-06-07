#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  antigravity-init — Initialize lean solo-mode AI orchestration
#
#  Works with: Antigravity, Claude Code, Command Code, and any
#              tool that reads workspace files.
#
#  Usage:
#    cd /path/to/your/project
#    antigravity-init
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

TEMPLATE_DIR="$HOME/.antigravity/templates"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  antigravity-init — Lean AI Orchestration Setup       ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Project:  ${GREEN}${PROJECT_NAME}${NC}"
echo -e "  Path:     ${PROJECT_DIR}"
echo ""

# ── Validate templates exist ──
missing=()
for f in GEMINI.md CLAUDE.md AGENTS.md build_and_test.sh REVIEW_PROMPT_TEMPLATE.md; do
    [ ! -f "$TEMPLATE_DIR/$f" ] && missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo -e "ERROR: Templates not found at ${TEMPLATE_DIR}: ${missing[*]}"
    exit 1
fi

# ── Step 0: Git Initialization ──
if [ ! -d "$PROJECT_DIR/.git" ]; then
    echo -e "${GREEN}[0/5]${NC} Initializing git repository..."
    git init "$PROJECT_DIR"
    echo "  ✅ git init"
else
    echo -e "${GREEN}[0/5]${NC} Git repository already exists."
fi

# ── Step 1: Copy rule files ──
echo -e "${GREEN}[1/5]${NC} Copying tool rules files..."
cp "$TEMPLATE_DIR/GEMINI.md" "$PROJECT_DIR/GEMINI.md"
cp "$TEMPLATE_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"
cp "$TEMPLATE_DIR/AGENTS.md" "$PROJECT_DIR/AGENTS.md"
echo "  ✅ GEMINI.md   (Executor rules for Gemini 3.5 Flash)"
echo "  ✅ CLAUDE.md   (Planner/Reviewer rules for Claude Opus/Sonnet)"
echo "  ✅ AGENTS.md   (Executor rules for DeepSeek V4 Pro — Command Code)"

# ── Step 1b: Copy automation scripts ──
echo ""
echo -e "${GREEN}[2/5]${NC} Copying automation scripts..."
cp "$TEMPLATE_DIR/build_and_test.sh" "$PROJECT_DIR/build_and_test.sh"
chmod +x "$PROJECT_DIR/build_and_test.sh"
cp "$TEMPLATE_DIR/REVIEW_PROMPT_TEMPLATE.md" "$PROJECT_DIR/REVIEW_PROMPT_TEMPLATE.md"
mkdir -p "$PROJECT_DIR/scripts"
cp "$TEMPLATE_DIR/scripts/orchestrator.py" "$PROJECT_DIR/scripts/orchestrator.py"
echo "  ✅ build_and_test.sh           (Automated test → review → fix loop)"
echo "  ✅ REVIEW_PROMPT_TEMPLATE.md   (Token-efficient Opus review prompt)"
echo "  ✅ scripts/orchestrator.py     (Plan injection and archiving logic)"

# ── Step 2: Create state files ──
echo ""
echo -e "${GREEN}[3/5]${NC} Creating shared state files..."

if [ -f "$PROJECT_DIR/implementation_plan.md" ]; then
    echo -e "  ${YELLOW}⚠  implementation_plan.md exists — keeping current plan${NC}"
else
    cat > "$PROJECT_DIR/implementation_plan.md" << 'PLANEOF'
# Implementation Plan

> **Verification gate:** `success_criteria.md`

---

## 📍 Status

`⏳ NOT STARTED`

---

## 💾 Checkpoint

**Last updated:** —
**Phase:** —
**Completed sections:** None
**Currently working on:** —
**Resume instructions:** Start fresh.

---

## 📝 Design / Architectural Decisions

*(Design decisions go here.)*

---

## 🗂️ Task Checklist

- [ ] Task 1 <!-- id: 0 -->

---

## 🤖 Execution Model

**Recommended:** *(Pending planning — Claude Opus will fill this in)*
**Reasoning:** *(Pending planning)*

---

## 📋 Execution Prompt

*(Claude Opus will generate a ready-to-paste prompt here after locking the plan.)*

---

## 🐛 Bugfix Plan

*(Populated after review, if bugs are found.)*

---

## 📋 Bugfix Prompt

*(Claude Opus will generate a ready-to-paste bugfix prompt here after review.)*

---

## 📜 Execution Log

*(None yet.)*

---

## 🔜 Next Step

**What to do:** *(Pending first task assignment.)*
**Why this is next:** *(N/A)*
**File(s) to touch:** *(TBD)*
**What "done" looks like:** *(TBD)*
**Quality checks:** *(TBD)*

---

## ⚠️ Blockers / Open Questions

*(None yet.)*
PLANEOF
    echo "  ✅ implementation_plan.md"
fi

if [ -f "$PROJECT_DIR/success_criteria.md" ]; then
    echo -e "  ${YELLOW}⚠  success_criteria.md exists — keeping current criteria${NC}"
else
    cat > "$PROJECT_DIR/success_criteria.md" << 'CRITERIAEOF'
# Success Criteria

---

## 🏗️ Professional Quality & Production Standards

| # | Criterion | Verification Command | Pass Condition |
|---|-----------|----------------------|----------------|
| SC-01 | **DRY:** No duplicated logic | `git diff --name-only HEAD` — cross-check against plan's file list | Only planned files appear. Zero unplanned edits. |
| SC-02 | **Surgical:** No drive-by changes | `git diff --stat HEAD` | Changed line count is proportional to the task. No unrelated file edits. |
| SC-03 | **Crash-Early:** No silent failures | `grep -rn "except:\|except Exception:\s*$\|catch\s*{}" . --include="*.py" --include="*.js" --include="*.ts" 2>/dev/null` | Zero matches (any match = silent catch = FAIL) |

---

## 🔧 Project-Specific Criteria

| # | Criterion | Verification Method | Status |
|---|-----------|---------------------|--------|
| SC-04 | *(Add your first task-specific criterion)* | *(How to verify)* | ⏳ PENDING |
CRITERIAEOF
    echo "  ✅ success_criteria.md"
fi

# ── Step 3: Update .gitignore ──
echo ""
echo -e "${GREEN}[4/5]${NC} Checking .gitignore..."

IGNORE_ENTRIES=("GEMINI.md" "CLAUDE.md" "AGENTS.md" "implementation_plan.md" "success_criteria.md" "execution_history.md" "antigravity-init.sh" "build_and_test.sh" "REVIEW_PROMPT_TEMPLATE.md" "scripts/orchestrator.py" "IMPL_CHANGES.diff" "TEST_REPORT.md" ".review_output.md" ".review_prompt_hydrated.md")

if [ -f "$PROJECT_DIR/.gitignore" ]; then
    for entry in "${IGNORE_ENTRIES[@]}"; do
        if ! grep -q "^${entry}$" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
            echo "$entry" >> "$PROJECT_DIR/.gitignore"
            echo "  ✅ Added $entry to .gitignore"
        fi
    done
else
    echo -e "  ${YELLOW}⚠  No .gitignore found — creating one${NC}"
    {
        echo "# AI Orchestration state files"
        for entry in "${IGNORE_ENTRIES[@]}"; do
            echo "$entry"
        done
    } > "$PROJECT_DIR/.gitignore"
    echo "  ✅ Created .gitignore"
fi

# ── Done ──
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Lean AI orchestration initialized!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Workflow:"
echo "    1. Start with Claude Opus — it plans, locks, and recommends an executor."
echo "    2. Run the execution prompt in the recommended model:"
echo "       • DeepSeek V4 Pro (Command Code) for complex tasks"
echo "       • Gemini 3.5 Flash (Antigravity) for medium tasks"
echo "    3. Switch to Claude Opus/Sonnet to review the execution."
echo "    4. If bugs found, run the bugfix prompt in the recommended model."
echo "    5. Manual testing — you control the models from here."
echo ""
echo "  Automated Loop (optional):"
echo "    • Run ./build_and_test.sh to auto-test, auto-review, and auto-fix"
echo "    • First time? Run ./build_and_test.sh --setup to configure accounts"
echo "    • Edit TEST_CMD in build_and_test.sh to set your test runner"
echo ""
