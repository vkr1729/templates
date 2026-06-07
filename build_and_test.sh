#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  build_and_test.sh — Automated Test → Review → Fix Loop
#
#  Captures implementation changes and test failures, routes a
#  code review to the cheapest available Claude Opus instance
#  (Gemini AI Pro Account 1 → Account 2 → AWS Bedrock), then
#  hands the bugfix plan back to Command Code for autonomous
#  execution.
#
#  Usage:
#    ./build_and_test.sh              # Full loop
#    ./build_and_test.sh --dry-run    # Preview without API calls
#    ./build_and_test.sh --setup      # One-time account setup
#    ./build_and_test.sh --capture    # Only capture diff + tests
# ═══════════════════════════════════════════════════════════════

set -euo pipefail
# ══════════════════════════════════════
# CONFIGURATION — Edit these per project
# ══════════════════════════════════════
TEST_CMD="npm test"
MAX_FIX_ITERATIONS=2
IMPLEMENTATION_MODEL="cmd"                          # Command Code CLI binary
DEFAULT_CMD_MODEL="minimax-m3"                      # Default implementation model
CLAUDE_MODEL="us.anthropic.claude-opus-4-6-v1"             # Bedrock fallback model
BEDROCK_MODEL="${CLAUDE_MODEL}"
AGY_OPUS_MODEL="Claude Opus 4.6 (Thinking)"        # agy model string for Opus
REAL_HOME="$HOME"                                   # Preserve actual HOME
AGY_ACCOUNT_1="$REAL_HOME/.agy_account_1"
AGY_ACCOUNT_2="$REAL_HOME/.agy_account_2"
SAFETY_BUFFER_PCT=10                                # Quota safety margin %
QUOTA_THRESHOLD_PCT=5                               # Min remaining % to attempt

# ══════════════════════════════════════
# ENVIRONMENT SETUP
# ══════════════════════════════════════
if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi
if [ -d "$HOME/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi
if [ -d "$HOME/.opencode/bin" ]; then
    export PATH="$HOME/.opencode/bin:$PATH"
fi

# Define cmd function if it's not defined
if ! declare -F cmd &>/dev/null; then
    cmd() {
        local has_model=0
        for arg in "$@"; do
            if [[ "$arg" == "-m" || "$arg" == "--model" ]]; then
                has_model=1
                break
            fi
        done
        
        if [[ $has_model -eq 0 ]]; then
            # command-code --model "deepseek/deepseek-v4-pro" "$@"
            command-code --model "${DEFAULT_CMD_MODEL:-minimax-m3}" "$@"
        else
            command-code "$@"
        fi
    }
    export -f cmd
fi

# Helper: run agy with the correct env isolation for a given account.
# Account 1 uses keyring. Account 2 blocks keyring to force file-based token.
agy_for_account() {
    local acct_dir="$1"
    shift
    if [ "$acct_dir" = "$AGY_ACCOUNT_2" ]; then
        DBUS_SESSION_BUS_ADDRESS=/nonexistent HOME="$acct_dir" agy "$@"
    else
        DBUS_SESSION_BUS_ADDRESS=/nonexistent HOME="$acct_dir" agy "$@"
    fi
}

# ══════════════════════════════════════
# INTERNAL — Do not edit below
# ══════════════════════════════════════
PROJECT_DIR="$(pwd)"
DIFF_FILE="$PROJECT_DIR/IMPL_CHANGES.diff"
TEST_REPORT="$PROJECT_DIR/TEST_REPORT.md"
REVIEW_TEMPLATE="$PROJECT_DIR/REVIEW_PROMPT_TEMPLATE.md"
IMPL_PLAN="$PROJECT_DIR/implementation_plan.md"
DRY_RUN=false
SETUP_MODE=false
CAPTURE_ONLY=false
CHOSEN_ROUTE=""
CHOSEN_ROUTE_LABEL=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ══════════════════════════════════════
# UTILITY FUNCTIONS
# ══════════════════════════════════════

log_phase() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════${NC}" >&2
    echo -e "${CYAN}  $1${NC}" >&2
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}" >&2
}

log_step() {
    echo -e "  ${GREEN}▸${NC} $1" >&2
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC}  $1" >&2
}

log_error() {
    echo -e "  ${RED}✖${NC}  $1" >&2
}

log_success() {
    echo -e "  ${GREEN}✔${NC}  $1" >&2
}

log_route() {
    echo -e "  ${MAGENTA}⟶${NC}  $1" >&2
}

log_dim() {
    echo -e "  ${DIM}$1${NC}" >&2
}

die() {
    log_error "$1"
    exit "${2:-1}"
}

print_usage() {
    return 0
}

# ══════════════════════════════════════
# PARSE ARGUMENTS
# ══════════════════════════════════════

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=true ;;
        --setup)    SETUP_MODE=true ;;
        --capture)  CAPTURE_ONLY=true ;;
        --help|-h)
            echo "Usage: ./build_and_test.sh [--dry-run] [--setup] [--capture]"
            echo ""
            echo "  --dry-run   Preview all phases without making API calls"
            echo "  --setup     One-time setup: install agy CLI and authenticate accounts"
            echo "  --capture   Only capture diff + test report, then exit"
            echo ""
            exit 0
            ;;
        *)
            die "Unknown argument: $arg. Use --help for usage." 1
            ;;
    esac
done

# ══════════════════════════════════════
# PREFLIGHT CHECKS
# ══════════════════════════════════════

preflight_check_agy() {
    # Returns 0 if agy is installed and both accounts are configured.
    # Returns 1 if anything is missing (caller decides whether to error or setup).
    if ! command -v agy &>/dev/null; then
        return 1
    fi
    # Quick probe: check that both isolated HOMEs can reach the API
    # (auth tokens live in system keyring, not files)
    if ! agy_for_account "$AGY_ACCOUNT_1" -p "reply with OK" --print-timeout 15s &>/dev/null; then
        return 1
    fi
    if ! agy_for_account "$AGY_ACCOUNT_2" -p "reply with OK" --print-timeout 15s &>/dev/null; then
        return 1
    fi
    return 0
}

preflight_check_tools() {
    # Verify required tools are available
    local missing=()

    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    if ! command -v "$IMPLEMENTATION_MODEL" &>/dev/null; then
        missing+=("$IMPLEMENTATION_MODEL (Command Code)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing required tools: ${missing[*]}" 4
    fi
}

preflight_check_project() {
    # Verify we're in a git repo with the required files
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        die "Not inside a git repository. Run from your project root." 4
    fi
    if [ ! -f "$REVIEW_TEMPLATE" ]; then
        die "REVIEW_PROMPT_TEMPLATE.md not found in project root. Run antigravity-init first." 4
    fi
    if [ ! -f "$IMPL_PLAN" ]; then
        die "implementation_plan.md not found in project root. Run antigravity-init first." 4
    fi
}

# ══════════════════════════════════════
# SETUP (One-time, only via --setup)
# ══════════════════════════════════════

run_setup() {
    log_phase "One-Time Account Setup"

    # Step 1: Install agy if missing
    if ! command -v agy &>/dev/null; then
        log_step "Installing Antigravity CLI (agy)..."
        echo -e "  ${DIM}Running: curl -fsSL https://antigravity.google/cli/install.sh | bash${NC}" >&2
        if $DRY_RUN; then
            log_dim "[DRY RUN] Would install agy CLI"
        else
            curl -fsSL https://antigravity.google/cli/install.sh | bash
            # Ensure PATH is updated for this session
            export PATH="$HOME/.local/bin:$PATH"
            if ! command -v agy &>/dev/null; then
                die "agy installed but not found in PATH. Add ~/.local/bin to your PATH and retry." 4
            fi
            log_success "agy CLI installed"
        fi
    else
        log_success "agy CLI already installed ($(agy --version 2>/dev/null || echo 'unknown version'))"
    fi

    # Step 2: Authenticate Account 1
    if ! agy_for_account "$AGY_ACCOUNT_1" -p "reply with OK" --print-timeout 15s &>/dev/null 2>&1; then
        log_step "Authenticating Account 1 (Gemini AI Pro)..."
        echo -e "\n  ${BOLD}Please log in with your FIRST Google AI Pro account:${NC}" >&2
        echo -e "  ${DIM}Running: HOME=$AGY_ACCOUNT_1 agy${NC}" >&2
        echo -e "  ${DIM}After login, type /quit to exit.${NC}" >&2
        mkdir -p "$AGY_ACCOUNT_1"
        if $DRY_RUN; then
            log_dim "[DRY RUN] Would launch: HOME=$AGY_ACCOUNT_1 agy"
        else
            DBUS_SESSION_BUS_ADDRESS=/nonexistent HOME="$AGY_ACCOUNT_1" agy
            log_success "Account 1 authenticated"
        fi
    else
        local acct1_email
        acct1_email=$(agy_for_account "$AGY_ACCOUNT_1" -p "reply with only your logged-in email address" --print-timeout 15s 2>/dev/null | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1) || acct1_email="verified"
        log_success "Account 1 already authenticated (${acct1_email:-verified})"
    fi

    # Step 3: Authenticate Account 2
    if ! agy_for_account "$AGY_ACCOUNT_2" -p "reply with OK" --print-timeout 15s &>/dev/null 2>&1; then
        log_step "Authenticating Account 2 (Gemini AI Pro)..."
        echo -e "\n  ${BOLD}Please log in with your SECOND Google AI Pro account:${NC}" >&2
        echo -e "  ${DIM}Running: DISPLAY= HOME=$AGY_ACCOUNT_2 agy${NC}" >&2
        echo -e "  ${DIM}(Uses headless auth — copy the URL to an incognito browser)${NC}" >&2
        echo -e "  ${DIM}After login, type /quit to exit.${NC}" >&2
        mkdir -p "$AGY_ACCOUNT_2"
        if $DRY_RUN; then
            log_dim "[DRY RUN] Would launch: DISPLAY= HOME=$AGY_ACCOUNT_2 agy"
        else
            DISPLAY= DBUS_SESSION_BUS_ADDRESS=/nonexistent HOME="$AGY_ACCOUNT_2" agy
            log_success "Account 2 authenticated"
        fi
    else
        local acct2_email
        acct2_email=$(agy_for_account "$AGY_ACCOUNT_2" -p "reply with only your logged-in email address" --print-timeout 15s 2>/dev/null | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | head -1) || acct2_email="verified"
        log_success "Account 2 already authenticated (${acct2_email:-verified})"
    fi

    # Step 4: Verify Bedrock fallback
    if command -v claude &>/dev/null; then
        log_success "Claude CLI available for Bedrock fallback"
    else
        log_warn "Claude CLI not found — Bedrock fallback will be unavailable"
    fi

    echo "" >&2
    log_success "Setup complete. Run ./build_and_test.sh to start the automation loop."
    exit 0
}

# ══════════════════════════════════════
# PHASE 1: CAPTURE CHANGES & TEST
# ══════════════════════════════════════

capture_changes() {
    log_phase "Phase 1: Capture Changes & Run Tests"

    # 1a. Capture staged diff
    log_step "Capturing staged changes (git diff --cached)..."
    git diff --cached > "$DIFF_FILE" 2>/dev/null || true

    if [ ! -s "$DIFF_FILE" ]; then
        # Fallback: check unstaged changes
        log_warn "No staged changes found. Checking unstaged working tree..."
        git diff > "$DIFF_FILE" 2>/dev/null || true
    fi

    if [ ! -s "$DIFF_FILE" ]; then
        die "No changes detected (staged or unstaged). Nothing to review." 1
    fi

    local diff_lines
    diff_lines=$(wc -l < "$DIFF_FILE")
    log_success "Captured ${diff_lines} lines of changes → IMPL_CHANGES.diff"

    # 1b. Run test suite
    log_step "Running test suite: ${BOLD}${TEST_CMD}${NC}..."
    local test_exit_code=0

    {
        echo "# Test Report"
        echo ""
        echo "**Command:** \`${TEST_CMD}\`"
        echo "**Timestamp:** $(date -Iseconds)"
        echo "**Project:** $(basename "$PROJECT_DIR")"
        echo ""
        echo '```'
    } > "$TEST_REPORT"

    # Run tests, capture all output, don't fail the script
    if eval "$TEST_CMD" >> "$TEST_REPORT" 2>&1; then
        test_exit_code=0
    else
        test_exit_code=$?
    fi

    {
        echo '```'
        echo ""
        echo "**Exit Code:** ${test_exit_code}"
    } >> "$TEST_REPORT"

    if [ "$test_exit_code" -eq 0 ]; then
        log_success "All tests passed (exit code 0). Proceeding with code review."
        return 0
    fi

    log_warn "Tests failed (exit code ${test_exit_code}) → TEST_REPORT.md"
    return 0
}

# ══════════════════════════════════════
# PHASE 2: ESTIMATE TOKEN WEIGHT
# ══════════════════════════════════════

estimate_tokens() {
    log_phase "Phase 2: Estimate Token Weight"

    local diff_chars test_chars template_chars total_chars
    local estimated_tokens overhead required_tokens

    diff_chars=$(wc -c < "$DIFF_FILE")
    test_chars=$(wc -c < "$TEST_REPORT")
    template_chars=$(wc -c < "$REVIEW_TEMPLATE")

    total_chars=$((diff_chars + test_chars + template_chars))

    # Approximation: 1 token ≈ 4 characters (standard for Claude/GPT tokenizers)
    estimated_tokens=$((total_chars / 4))

    # Add system prompt + response overhead
    overhead=5000
    estimated_tokens=$((estimated_tokens + overhead))

    # Apply safety buffer
    required_tokens=$(( estimated_tokens * (100 + SAFETY_BUFFER_PCT) / 100 ))

    log_step "Diff: ${diff_chars} chars | Tests: ${test_chars} chars | Template: ${template_chars} chars"
    log_step "Estimated input tokens: ~${estimated_tokens}"
    log_step "With ${SAFETY_BUFFER_PCT}% safety buffer: ~${required_tokens} tokens required"

    # Export for use by the router
    export ESTIMATED_TOKENS="$required_tokens"
    return 0
}

# ══════════════════════════════════════
# PHASE 3: DUAL-ACCOUNT WATERFALL ROUTER
# ══════════════════════════════════════

# Check if a specific agy account has enough quota.
# Uses a try-first approach: attempts a lightweight probe, checks for quota errors.
# Args: $1 = config_dir, $2 = label
check_agy_account() {
    local config_dir="$1"
    local label="$2"

    log_step "Checking ${label} (${config_dir})..."

    # Auth tokens are in system keyring (acct1) or file (acct2) — probe with a lightweight call
    if ! agy_for_account "$config_dir" -p "reply with OK" --print-timeout 10s &>/dev/null 2>&1; then
        log_dim "${label}: Not authenticated — skipping"
        return 1
    fi

    if $DRY_RUN; then
        log_dim "[DRY RUN] Would check quota via: HOME=${config_dir} agy -p \"/usage\""
        # In dry-run, simulate Account 1 as available
        if [ "$config_dir" = "$AGY_ACCOUNT_1" ]; then
            return 0
        fi
        return 1
    fi

    # Attempt to get quota info. The /usage slash command shows remaining quota.
    # We parse for the Opus model line and extract remaining percentage.
    local usage_output
    usage_output=$(agy_for_account "$config_dir" -p "/usage" 2>&1) || true

    # Check for explicit quota exhaustion signals
    if echo "$usage_output" | grep -qi "RESOURCE_EXHAUSTED\|rate.limit\|quota.*exceeded\|429"; then
        log_dim "${label}: Quota exhausted (rate limited)"
        return 1
    fi

    # Try to parse remaining percentage for Opus model
    # Expected format varies — try multiple patterns
    local remaining_pct
    remaining_pct=$(echo "$usage_output" | grep -i "opus" | grep -oP '\d+(?=\s*%\s*remaining|\s*%\s*left)' | head -1) || true

    if [ -z "$remaining_pct" ]; then
        # Fallback: try to find any percentage on the opus line
        remaining_pct=$(echo "$usage_output" | grep -i "opus" | grep -oP '\d+(?=%)' | tail -1) || true
    fi

    if [ -n "$remaining_pct" ]; then
        log_step "${label}: Opus quota remaining — ${remaining_pct}%"
        if [ "$remaining_pct" -lt "$QUOTA_THRESHOLD_PCT" ]; then
            log_dim "${label}: Below threshold (${QUOTA_THRESHOLD_PCT}%) — skipping"
            return 1
        fi
        log_success "${label}: Sufficient quota (${remaining_pct}% remaining)"
        return 0
    fi

    # If we can't parse quota, optimistically try it.
    # The actual API call in Phase 4 will catch failures.
    log_warn "${label}: Could not parse quota — will attempt and catch errors"
    return 0
}

route_review() {
    log_phase "Phase 3: Route Review (Waterfall)"

    # Tier 1: Gemini AI Pro Account 1 (free Opus quota)
    if command -v agy &>/dev/null; then
        if check_agy_account "$AGY_ACCOUNT_1" "Account 1"; then
            CHOSEN_ROUTE="agy_1"
            CHOSEN_ROUTE_LABEL="Gemini AI Pro — Account 1 (agy)"
            log_route "Routed to: ${BOLD}${CHOSEN_ROUTE_LABEL}${NC}"
            return 0
        fi

        # Tier 2: Gemini AI Pro Account 2 (free Opus quota)
        if check_agy_account "$AGY_ACCOUNT_2" "Account 2"; then
            CHOSEN_ROUTE="agy_2"
            CHOSEN_ROUTE_LABEL="Gemini AI Pro — Account 2 (agy)"
            log_route "Routed to: ${BOLD}${CHOSEN_ROUTE_LABEL}${NC}"
            return 0
        fi
    else
        log_warn "agy CLI not installed — skipping Gemini AI Pro accounts"
        log_dim "Run ./build_and_test.sh --setup to configure"
    fi

    # Tier 3: AWS Bedrock (pay-as-you-go)
    if command -v claude &>/dev/null; then
        log_step "Falling back to AWS Bedrock (${BEDROCK_MODEL})..."
        CHOSEN_ROUTE="bedrock"
        CHOSEN_ROUTE_LABEL="AWS Bedrock — ${BEDROCK_MODEL} (pay-as-you-go)"
        log_route "Routed to: ${BOLD}${CHOSEN_ROUTE_LABEL}${NC}"
        return 0
    fi

    die "No Opus route available. Install agy (--setup) or configure Claude CLI with Bedrock." 3
}

# ══════════════════════════════════════
# PHASE 4: EXECUTE REVIEW
# ══════════════════════════════════════

build_review_prompt() {
    local prompt_file="$PROJECT_DIR/.review_prompt_hydrated.md"

    # Read template and substitute placeholders
    local diff_content test_content
    diff_content=$(cat "$DIFF_FILE")
    test_content=$(cat "$TEST_REPORT")

    # Use awk for reliable multi-line substitution (sed chokes on large diffs)
    awk -v diff="$diff_content" -v tests="$test_content" '
    {
        if ($0 == "{{IMPL_CHANGES_DIFF}}") {
            print diff
        } else if ($0 == "{{TEST_REPORT}}") {
            print tests
        } else {
            print $0
        }
    }
    ' "$REVIEW_TEMPLATE" > "$prompt_file"

    echo "$prompt_file"
}

execute_review_via_agy() {
    local config_dir="$1"
    local prompt_file="$2"
    local output_file="$PROJECT_DIR/.review_output.md"
    local prompt_content
    prompt_content=$(cat "$prompt_file")

    log_step "Sending review to agy (model: ${AGY_OPUS_MODEL})..."

    local review_output
    local agy_exit=0

    # Use script(1) as TTY wrapper to work around agy -p non-TTY output issues
    # Run from /tmp to escape the workspace directory context and AGENTS.md rules
    local tmp_prompt="/tmp/agy_prompt_$$"
    echo "$prompt_content" | head -c 50000 > "$tmp_prompt"

    if command -v script &>/dev/null; then
        (cd /tmp && DBUS_SESSION_BUS_ADDRESS=/nonexistent HOME="$config_dir" script -qc "agy --model \"${AGY_OPUS_MODEL}\" -p \"\$(cat $tmp_prompt)\" --dangerously-skip-permissions 2>&1" /dev/null > "$output_file") || agy_exit=$?
    else
        (cd /tmp && agy_for_account "$config_dir" --model "${AGY_OPUS_MODEL}" -p "$(cat "$tmp_prompt")" --dangerously-skip-permissions > "$output_file" 2>&1) || agy_exit=$?
    fi
    rm -f "$tmp_prompt"

    # Check if the call actually failed due to quota
    if [ "$agy_exit" -ne 0 ] || grep -qi "RESOURCE_EXHAUSTED\|rate.limit\|quota.*exceeded\|429" "$output_file" 2>/dev/null; then
        log_warn "agy call failed or quota exhausted (exit code: ${agy_exit})"
        rm -f "$output_file"
        return 1
    fi

    # Verify we got meaningful output
    if [ ! -s "$output_file" ] || [ "$(wc -c < "$output_file")" -lt 50 ]; then
        log_warn "agy returned empty or too-short response — likely a TTY issue"
        rm -f "$output_file"
        return 1
    fi

    log_success "Review received ($(wc -c < "$output_file") chars)"
    return 0
}

execute_review_via_bedrock() {
    local prompt_file="$1"
    local output_file="$PROJECT_DIR/.review_output.md"
    local prompt_content
    prompt_content=$(cat "$prompt_file")

    log_step "Sending review to Bedrock (model: ${BEDROCK_MODEL})..."

    claude --model "$BEDROCK_MODEL" \
        -p "$prompt_content" \
        --max-turns 1 \
        --output-format text \
        > "$output_file" 2>&1 || {
        log_error "Bedrock review failed (exit code: $?)"
        return 1
    }

    if [ ! -s "$output_file" ] || [ "$(wc -c < "$output_file")" -lt 50 ]; then
        log_error "Bedrock returned empty response"
        rm -f "$output_file"
        return 1
    fi

    log_success "Review received ($(wc -c < "$output_file") chars)"
    return 0
}

run_review() {
    log_phase "Phase 4: Execute Code Review"

    local prompt_file
    prompt_file=$(build_review_prompt)
    log_step "Review prompt hydrated ($(wc -c < "$prompt_file") chars)"

    if $DRY_RUN; then
        log_dim "[DRY RUN] Would send review via: ${CHOSEN_ROUTE_LABEL}"
        log_dim "[DRY RUN] Prompt file: ${prompt_file}"
        log_dim "[DRY RUN] Prompt size: $(wc -c < "$prompt_file") chars (~$(($(wc -c < "$prompt_file") / 4)) tokens)"
        # Create a mock review output for dry-run
        cat > "$PROJECT_DIR/.review_output.md" << 'MOCKEOF'
### 🐛 Bugfix Plan

#### Bug 1: [DRY RUN — Mock Bug]
- **File:** example.py
- **Line(s):** 42-45
- **Root Cause:** This is a dry-run mock output
- **Fix:** No actual changes needed

### End of Bugfix Plan
MOCKEOF
        return 0
    fi

    local review_success=false

    case "$CHOSEN_ROUTE" in
        agy_1)
            if execute_review_via_agy "$AGY_ACCOUNT_1" "$prompt_file"; then
                review_success=true
            else
                # Waterfall: try Account 2
                log_warn "Account 1 failed — trying Account 2..."
                if execute_review_via_agy "$AGY_ACCOUNT_2" "$prompt_file"; then
                    review_success=true
                    CHOSEN_ROUTE_LABEL="Gemini AI Pro — Account 2 (agy) [fallback]"
                else
                    # Waterfall: try Bedrock
                    log_warn "Account 2 failed — falling back to Bedrock..."
                    if command -v claude &>/dev/null && execute_review_via_bedrock "$prompt_file"; then
                        review_success=true
                        CHOSEN_ROUTE_LABEL="AWS Bedrock [double fallback]"
                    fi
                fi
            fi
            ;;
        agy_2)
            if execute_review_via_agy "$AGY_ACCOUNT_2" "$prompt_file"; then
                review_success=true
            else
                # Waterfall: try Bedrock
                log_warn "Account 2 failed — falling back to Bedrock..."
                if command -v claude &>/dev/null && execute_review_via_bedrock "$prompt_file"; then
                    review_success=true
                    CHOSEN_ROUTE_LABEL="AWS Bedrock [fallback]"
                fi
            fi
            ;;
        bedrock)
            if execute_review_via_bedrock "$prompt_file"; then
                review_success=true
            fi
            ;;
    esac

    if ! $review_success; then
        die "All review routes failed. Check your accounts and try again." 3
    fi

    local model_used=""
    if [ "$CHOSEN_ROUTE" = "bedrock" ] || [[ "$CHOSEN_ROUTE_LABEL" == *"Bedrock"* ]]; then
        model_used="${BEDROCK_MODEL}"
    else
        model_used="${AGY_OPUS_MODEL}"
    fi
    log_success "Review completed via: ${CHOSEN_ROUTE_LABEL} (Model: ${model_used})"
    return 0
}

# ══════════════════════════════════════
# PHASE 4b: INJECT BUGFIX PLAN
# ══════════════════════════════════════

inject_bugfix_plan() {
    log_step "Injecting bugfix plan into implementation_plan.md..."

    local review_output="$PROJECT_DIR/.review_output.md"
    local extracted_bugfix="$PROJECT_DIR/.extracted_bugfix.md"

    if [ ! -s "$review_output" ]; then
        die "Review output file is empty — cannot inject bugfix plan." 1
    fi

    # Extract the bugfix plan section
    if ! python3 scripts/orchestrator.py extract-bugfix "$review_output" > "$extracted_bugfix"; then
        log_warn "Could not extract structured bugfix plan — using full review output"
        cp "$review_output" "$extracted_bugfix"
    fi

    # Inject into implementation_plan.md
    if ! python3 scripts/orchestrator.py inject-bugfix "$extracted_bugfix"; then
        die "Failed to inject structured bugfix plan. Check plan formatting." 1
    fi

    log_success "Bugfix plan injected → implementation_plan.md (status: 🐛 BUGFIX PLANNED)"

    # Clean up temp files
    rm -f "$review_output" "$PROJECT_DIR/.review_prompt_hydrated.md" "$extracted_bugfix"
}

# ══════════════════════════════════════
# PHASE 5: EXECUTE FIX (Command Code)
# ══════════════════════════════════════

execute_fix() {
    log_phase "Phase 5: Execute Bugfix (Command Code)"

    if $DRY_RUN; then
        log_dim "[DRY RUN] Would execute: ${IMPLEMENTATION_MODEL} -p \"Execute\" --yolo --max-turns 80"
        return 0
    fi

    log_step "Handing off to Command Code for autonomous bugfix..."
    log_dim "Running: ${IMPLEMENTATION_MODEL} -p \"Execute\" --yolo --max-turns 80"

    local cmd_exit=0
    $IMPLEMENTATION_MODEL -p "Execute" --yolo --max-turns 80 || cmd_exit=$?

    if [ "$cmd_exit" -eq 8 ]; then
        log_warn "Command Code hit max turns limit (80). Bugfix may be incomplete."
    elif [ "$cmd_exit" -ne 0 ]; then
        log_error "Command Code exited with code ${cmd_exit}"
        return 1
    fi

    log_success "Command Code finished bugfix execution (Model: ${DEFAULT_CMD_MODEL})"
    return 0
}

# ══════════════════════════════════════
# PHASE 0: INITIAL IMPLEMENTATION
# ══════════════════════════════════════

execute_initial_plan() {
    log_phase "Phase 0: Initial Implementation (Command Code)"

    if ! python3 scripts/orchestrator.py check-active; then
        log_step "Plan is neither 🔒 LOCKED nor 💻 EXECUTING. Skipping initial implementation."
        return 0
    fi

    log_step "Found active implementation plan. Running execution..."
    
    if $DRY_RUN; then
        log_dim "[DRY RUN] Would execute: ${IMPLEMENTATION_MODEL} -p \"Execute\" --yolo --max-turns 150"
        return 0
    fi

    log_dim "Running: ${IMPLEMENTATION_MODEL} -p \"Execute\" --yolo --max-turns 150"
    local cmd_exit=0
    $IMPLEMENTATION_MODEL -p "Execute" --yolo --max-turns 150 || cmd_exit=$?

    if [ "$cmd_exit" -eq 8 ]; then
        log_warn "Command Code hit max turns limit (150). Implementation is incomplete."
        log_warn "Exiting to allow resuming. Run ./build_and_test.sh again to continue implementation."
        print_usage
        exit 8
    elif [ "$cmd_exit" -ne 0 ]; then
        log_error "Command Code exited with code ${cmd_exit}"
        return 1
    fi

    log_success "Command Code finished initial implementation (Model: ${DEFAULT_CMD_MODEL})"
    return 0
}

# ══════════════════════════════════════
# MAIN LOOP
# ══════════════════════════════════════

main() {
    echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${BOLD}${CYAN}║     build_and_test.sh — Automated Review Loop        ║${NC}" >&2
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}" >&2

    if $DRY_RUN; then
        echo -e "\n  ${YELLOW}🏜  DRY RUN MODE — No API calls will be made${NC}\n" >&2
    fi

    # Handle --setup mode
    if $SETUP_MODE; then
        run_setup
    fi

    # Preflight
    preflight_check_tools
    preflight_check_project

    # Silent agy check — only warn, don't block
    if ! preflight_check_agy; then
        if ! command -v claude &>/dev/null; then
            die "Neither agy nor claude CLI available. Run --setup or install claude CLI." 4
        fi
        log_warn "agy not fully configured — will use Bedrock fallback only"
        log_dim "Run ./build_and_test.sh --setup to enable free Opus quota routing"
    fi

    # Phase 0: Initial Implementation
    execute_initial_plan

    local iteration=0

    while [ "$iteration" -lt "$MAX_FIX_ITERATIONS" ]; do
        iteration=$((iteration + 1))

        if [ "$iteration" -gt 1 ]; then
            echo "" >&2
            echo -e "  ${BOLD}${YELLOW}─── Fix Iteration ${iteration}/${MAX_FIX_ITERATIONS} ───${NC}" >&2
        fi

        # Phase 1: Capture
        capture_changes
        # Note: capture_changes exits 0 if tests pass

        if $CAPTURE_ONLY; then
            log_success "Capture complete. Files written:"
            log_dim "  IMPL_CHANGES.diff ($(wc -c < "$DIFF_FILE") chars)"
            log_dim "  TEST_REPORT.md ($(wc -c < "$TEST_REPORT") chars)"
            exit 0
        fi

        # Phase 2: Estimate
        estimate_tokens

        # Phase 3: Route
        route_review

        # Phase 4: Review
        run_review

        # Phase 4b: Inject
        inject_bugfix_plan

        # Phase 5: Execute Fix
        execute_fix

        # Re-run tests to check if fix worked
        log_phase "Verification: Re-running Tests"
        log_step "Running: ${TEST_CMD}..."

        local verify_exit=0
        eval "$TEST_CMD" > /dev/null 2>&1 || verify_exit=$?

        if [ "$verify_exit" -eq 0 ]; then
            log_success "All tests pass after fix iteration ${iteration}!"

            # Update the ACTIVE status to EXECUTION COMPLETE safely
            if ! python3 scripts/orchestrator.py mark-bugfix-complete; then
                log_warn "Failed to mark bugfix complete. Check plan formatting."
            fi

            # Clean up artifacts
            rm -f "$DIFF_FILE" "$TEST_REPORT"

            echo "" >&2
            echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════╗${NC}" >&2
            echo -e "${BOLD}${GREEN}║     ✅  ALL TESTS PASS — Loop Complete               ║${NC}" >&2
            echo -e "${BOLD}${GREEN}╠═══════════════════════════════════════════════════════╣${NC}" >&2
            echo -e "${BOLD}${GREEN}║  Route used:  ${CHOSEN_ROUTE_LABEL}${NC}" >&2
            echo -e "${BOLD}${GREEN}║  Iterations:  ${iteration}/${MAX_FIX_ITERATIONS}${NC}" >&2
            echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════╝${NC}" >&2
            print_usage
            exit 0
        fi

        log_warn "Tests still failing after iteration ${iteration}. $(( MAX_FIX_ITERATIONS - iteration )) attempts remaining."
    done

    # Exhausted all iterations
    echo "" >&2
    echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${BOLD}${RED}║     ❌  MAX ITERATIONS REACHED — Manual Fix Needed   ║${NC}" >&2
    echo -e "${BOLD}${RED}╠═══════════════════════════════════════════════════════╣${NC}" >&2
    echo -e "${BOLD}${RED}║  Iterations:  ${MAX_FIX_ITERATIONS}/${MAX_FIX_ITERATIONS}${NC}" >&2
    echo -e "${BOLD}${RED}║  See: TEST_REPORT.md, IMPL_CHANGES.diff             ║${NC}" >&2
    echo -e "${BOLD}${RED}║  See: implementation_plan.md § Bugfix Plan           ║${NC}" >&2
    echo -e "${BOLD}${RED}╚═══════════════════════════════════════════════════════╝${NC}" >&2
    print_usage
    exit 2
}

main "$@"
