#!/usr/bin/env python3
import sys
import re
import os

def usage():
    print("Usage: orchestrator.py <command> [args]")
    print("Commands:")
    print("  check-active")
    print("  extract-bugfix <review_file_path>")
    print("  inject-bugfix <bugfix_file_path>")
    print("  mark-bugfix-complete")
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        usage()
        
    cmd = sys.argv[1]
    plan_path = os.environ.get("IMPL_PLAN", "implementation_plan.md")
    
    if cmd == "check-active":
        with open(plan_path, 'r', encoding='utf-8') as f:
            content = f.read()
        if re.search(r'(🔒\s*LOCKED|💻\s*EXECUTING|🐛\s*BUGFIX PLANNED)', content):
            sys.exit(0)
        else:
            sys.exit(1)
            
    elif cmd == "extract-bugfix":
        if len(sys.argv) < 3:
            usage()
        review_path = sys.argv[2]
        try:
            with open(review_path, 'r', encoding='utf-8') as f:
                review_content = f.read()
        except FileNotFoundError:
            sys.exit(1)
            
        # Match from "## Bugfix Plan" to the next "## " heading or "---"
        match = re.search(r'(?i)(###?\s*(?:🐛\s*)?Bugfix Plan.*?)(?=###?\s*End of Bugfix Plan|(?:\n---)|\n##\s|$)', review_content, re.DOTALL)
        if match:
            print(match.group(1).strip())
            sys.exit(0)
        else:
            sys.exit(1)

    elif cmd == "inject-bugfix":
        if len(sys.argv) < 3:
            usage()
        bugfix_file = sys.argv[2]
        with open(bugfix_file, 'r', encoding='utf-8') as f:
            bugfix_content = f.read().strip()
            
        # Strip heading if present so we can standardise it
        bugfix_content = re.sub(r'(?i)^###?\s*(?:🐛\s*)?Bugfix Plan\s*\n', '', bugfix_content).strip()
            
        # Read existing plan
        try:
            with open(plan_path, 'r', encoding='utf-8') as f:
                old_plan = f.read()
        except FileNotFoundError:
            old_plan = ""
            
        # Archive the existing plan to execution_history.md
        import datetime
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        history_path = os.path.join(os.path.dirname(plan_path) or ".", "execution_history.md")
        
        with open(history_path, 'a', encoding='utf-8') as f:
            f.write(f"\n\n# [{now_str}] Iteration Archive\n\n")
            f.write(old_plan)
            
        # Write new focused plan
        new_plan = f"""# Implementation Plan

**Status:** 🐛 BUGFIX PLANNED

## 🐛 Bugfix Plan

{bugfix_content}

## 📋 Execution Prompt

Read `AGENTS.md` and `execution_history.md` for context.
Execute the bugfix plan described above.
"""
        with open(plan_path, 'w', encoding='utf-8') as f:
            f.write(new_plan)
            
    elif cmd == "mark-bugfix-complete":
        with open(plan_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        if re.search(r'✅\s*EXECUTION COMPLETE', content):
            sys.exit(0)
        
        new_content, count = re.subn(r'(🐛\s*BUGFIX PLANNED|💻\s*EXECUTING)', r'✅ EXECUTION COMPLETE', content, count=1)
        if count == 0:
            print("Error: Could not find active status to mark complete.", file=sys.stderr)
            sys.exit(1)
            
        with open(plan_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
            
    else:
        print(f"Unknown command: {cmd}")
        usage()

if __name__ == "__main__":
    main()
