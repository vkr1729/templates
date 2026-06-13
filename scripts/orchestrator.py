#!/usr/bin/env python3
import sys
import re
import os
from typing import Any

def usage():
    print("Usage: orchestrator.py <command> [args]")
    print("Commands:")
    print("  check-active")
    print("  check-no-bugs <review_file_path>")
    print("  extract-bugfix <review_file_path>")
    print("  inject-bugfix <bugfix_file_path>")
    print("  archive-plan")
    print("  mark-bugfix-complete")
    print("  has-headroom")
    print("  compress <file_path> <type> [model]")
    sys.exit(1)

class SQLiteCompressionBackend:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        import sqlite3
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS compression_cache (
                    hash TEXT PRIMARY KEY,
                    original_content TEXT,
                    compressed_content TEXT,
                    original_tokens INTEGER,
                    compressed_tokens INTEGER,
                    original_item_count INTEGER,
                    compressed_item_count INTEGER,
                    tool_name TEXT,
                    tool_call_id TEXT,
                    query_context TEXT,
                    created_at REAL,
                    ttl INTEGER,
                    tool_signature_hash TEXT,
                    compression_strategy TEXT,
                    retrieval_count INTEGER,
                    search_queries TEXT,
                    last_accessed REAL
                )
            """)
            conn.commit()

    def get(self, hash_key: str):
        import sqlite3
        import json
        from headroom.cache.compression_store import CompressionEntry
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM compression_cache WHERE hash = ?", (hash_key,))
            row = cursor.fetchone()
            if row is None:
                return None
            
            columns = [
                "hash", "original_content", "compressed_content", "original_tokens",
                "compressed_tokens", "original_item_count", "compressed_item_count",
                "tool_name", "tool_call_id", "query_context", "created_at", "ttl",
                "tool_signature_hash", "compression_strategy", "retrieval_count",
                "search_queries", "last_accessed"
            ]
            row_dict = dict(zip(columns, row))
            
            try:
                search_queries = json.loads(row_dict["search_queries"]) if row_dict["search_queries"] else []
            except Exception:
                search_queries = []
                
            return CompressionEntry(
                hash=row_dict["hash"],
                original_content=row_dict["original_content"],
                compressed_content=row_dict["compressed_content"],
                original_tokens=row_dict["original_tokens"],
                compressed_tokens=row_dict["compressed_tokens"],
                original_item_count=row_dict["original_item_count"],
                compressed_item_count=row_dict["compressed_item_count"],
                tool_name=row_dict["tool_name"],
                tool_call_id=row_dict["tool_call_id"],
                query_context=row_dict["query_context"],
                created_at=row_dict["created_at"],
                ttl=row_dict["ttl"],
                tool_signature_hash=row_dict["tool_signature_hash"],
                compression_strategy=row_dict["compression_strategy"],
                retrieval_count=row_dict["retrieval_count"],
                search_queries=search_queries,
                last_accessed=row_dict["last_accessed"]
            )

    def set(self, hash_key: str, entry) -> None:
        import sqlite3
        import json
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO compression_cache (
                    hash, original_content, compressed_content, original_tokens,
                    compressed_tokens, original_item_count, compressed_item_count,
                    tool_name, tool_call_id, query_context, created_at, ttl,
                    tool_signature_hash, compression_strategy, retrieval_count,
                    search_queries, last_accessed
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                entry.hash, entry.original_content, entry.compressed_content, entry.original_tokens,
                entry.compressed_tokens, entry.original_item_count, entry.compressed_item_count,
                entry.tool_name, entry.tool_call_id, entry.query_context, entry.created_at, entry.ttl,
                entry.tool_signature_hash, entry.compression_strategy, entry.retrieval_count,
                json.dumps(entry.search_queries), entry.last_accessed
            ))
            conn.commit()

    def delete(self, hash_key: str) -> bool:
        import sqlite3
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM compression_cache WHERE hash = ?", (hash_key,))
            deleted = cursor.rowcount > 0
            conn.commit()
            return deleted

    def exists(self, hash_key: str) -> bool:
        import sqlite3
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT 1 FROM compression_cache WHERE hash = ?", (hash_key,))
            return cursor.fetchone() is not None

    def clear(self) -> None:
        import sqlite3
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("DELETE FROM compression_cache")
            conn.commit()

    def count(self) -> int:
        import sqlite3
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM compression_cache")
            return cursor.fetchone()[0]

    def keys(self) -> list[str]:
        import sqlite3
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT hash FROM compression_cache")
            return [row[0] for row in cursor.fetchall()]

    def items(self) -> list[tuple[str, Any]]:
        keys = self.keys()
        res = []
        for k in keys:
            val = self.get(k)
            if val:
                res.append((k, val))
        return res

    def get_stats(self) -> dict[str, Any]:
        return {
            "entry_count": self.count(),
            "backend_type": "sqlite"
        }

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
            
    elif cmd == "check-no-bugs":
        if len(sys.argv) < 3:
            usage()
        review_path = sys.argv[2]
        try:
            with open(review_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except FileNotFoundError:
            print(f"Error: Review file not found: {review_path}", file=sys.stderr)
            sys.exit(1)
        # Look for "#### Bug N:" between "🐛 Bugfix Plan" and "End of Bugfix Plan" markers
        bugfix_section = re.search(r'(?i)🐛\s*Bugfix Plan(.*?)(?:End of Bugfix Plan|$)', content, re.DOTALL)
        if bugfix_section:
            bugs = re.findall(r'####\s*Bug\s+\d+:', bugfix_section.group(1))
            if bugs:
                print(f"Found {len(bugs)} bug(s) in review output")
                sys.exit(0)
        # No bugs found — clean review
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
            
        # Find the ## 🐛 Bugfix Plan section and replace its content.
        # Match: heading line + content + (next ## heading or --- or end)
        bugfix_pattern = r'(##\s*🐛\s*Bugfix Plan\s*\n).*?(?=\n##\s|\n---\s*\n|$)'
        if re.search(bugfix_pattern, old_plan, re.DOTALL):
            new_plan = re.sub(
                bugfix_pattern,
                r'\1\n' + bugfix_content + r'\n',
                old_plan,
                count=1,
                flags=re.DOTALL
            )
        else:
            # No bugfix section exists — append one before 📜 Execution Log or at end
            execution_log_match = re.search(r'\n##\s*📜\s*Execution Log', old_plan)
            if execution_log_match:
                idx = execution_log_match.start()
                new_plan = old_plan[:idx] + f"\n## 🐛 Bugfix Plan\n\n{bugfix_content}\n\n" + old_plan[idx:]
            else:
                new_plan = old_plan.rstrip() + f"\n\n## 🐛 Bugfix Plan\n\n{bugfix_content}\n"
        
        # Update status line: change any active status to 🐛 BUGFIX PLANNED
        status_pattern = r'`[^`]*?(?:LOCKED|EXECUTING|BUGFIX PLANNED|EXECUTION COMPLETE|NOT STARTED)[^`]*`'
        new_status = '`🐛 BUGFIX PLANNED`'
        if re.search(status_pattern, new_plan):
            new_plan = re.sub(status_pattern, new_status, new_plan, count=1)
        else:
            # Fallback: replace the Status line
            new_plan = re.sub(
                r'(#+\s*📍\s*Status\s*\n)',
                r'\1\n' + new_status + r'\n',
                new_plan,
                count=1
            )
            
        with open(plan_path, 'w', encoding='utf-8') as f:
            f.write(new_plan)
            
    elif cmd == "archive-plan":
        try:
            with open(plan_path, 'r', encoding='utf-8') as f:
                old_plan = f.read()
        except FileNotFoundError:
            print("Error: No plan found to archive.", file=sys.stderr)
            sys.exit(1)
        import datetime
        now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        history_path = os.path.join(os.path.dirname(plan_path) or ".", "execution_history.md")
        
        with open(history_path, 'a', encoding='utf-8') as f:
            f.write(f"\n\n# [{now_str}] Plan Archive\n\n")
            f.write(old_plan)
        print(f"Plan archived to {history_path}")
        sys.exit(0)
            
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
            
    elif cmd == "has-headroom":
        try:
            import headroom
            sys.exit(0)
        except ImportError:
            sys.exit(1)

    elif cmd == "compress":
        if len(sys.argv) < 4:
            print("Usage: orchestrator.py compress <file_path> <type> [model]")
            sys.exit(1)
        file_path = sys.argv[2]
        content_type = sys.argv[3]
        model = sys.argv[4] if len(sys.argv) >= 5 else "claude-opus"
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                file_content = f.read()
        except FileNotFoundError:
            sys.exit(1)

        if not file_content.strip():
            print("")
            sys.exit(0)

        try:
            import headroom
            from headroom.cache.compression_store import get_compression_store
        except ImportError:
            # Fallback if headroom is not installed
            print(file_content)
            sys.exit(0)

        # Setup persistent SQLite cache backend
        db_path = os.path.expanduser("~/.antigravity/headroom.db")
        backend = SQLiteCompressionBackend(db_path)
        get_compression_store(backend=backend)

        messages = [{"role": "user", "content": file_content}]
        # Compress user messages containing diffs or logs
        res = headroom.compress(messages, model=model, compress_user_messages=True)
        print(res.messages[0]["content"])
        sys.exit(0)

    else:
        print(f"Unknown command: {cmd}")
        usage()

if __name__ == "__main__":
    main()
