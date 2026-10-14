"""Run a SQL file (or a single statement) against Snowflake with key-pair auth.

    .venv/bin/python scripts/run_sql.py --role ACCOUNTADMIN sql/01_setup.sql
    .venv/bin/python scripts/run_sql.py --dry-run sql/05_oauth.sql      # print rendered SQL only
    .venv/bin/python scripts/run_sql.py -e "SHOW GRANTS TO ROLE FLEET_MCP_ROLE" --role ACCOUNTADMIN

SQL files may contain {{VAR}} placeholders for environment-specific values. Only the variables
in TEMPLATE_VARS are substituted (from .env / the environment), each is validated against a
strict pattern, and any unresolved placeholder aborts the run.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import sf  # noqa: F401  (loads .env)

TEMPLATE_VARS = {
    "SNOWFLAKE_USER": re.compile(r"[A-Za-z_][A-Za-z0-9_$]*"),
    "FLEET_OAUTH_REDIRECT_URI": re.compile(r"https://[A-Za-z0-9.-]+(?::\d+)?/[A-Za-z0-9._~/-]*"),
}
PLACEHOLDER = re.compile(r"\{\{\s*([A-Z_]+)\s*\}\}")


def render(sql: str) -> str:
    def sub(m: re.Match) -> str:
        name = m.group(1)
        if name not in TEMPLATE_VARS:
            sys.exit(f"Unknown placeholder {{{{{name}}}}}; allowed: {', '.join(TEMPLATE_VARS)}")
        value = os.environ.get(name, "")
        if not TEMPLATE_VARS[name].fullmatch(value):
            sys.exit(f"{name} is missing or invalid in .env (expected pattern {TEMPLATE_VARS[name].pattern})")
        return value

    return PLACEHOLDER.sub(sub, sql)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("file", nargs="?", help="SQL file to execute")
    p.add_argument("-e", "--execute", help="SQL text to execute instead of a file")
    p.add_argument("--role", default=None, help="Session role (default: user's default role)")
    p.add_argument("--max-rows", type=int, default=20)
    p.add_argument("--dry-run", action="store_true", help="Print the rendered SQL; don't execute")
    args = p.parse_args()
    if not (args.file or args.execute):
        p.error("give a SQL file or -e")

    sql = render(args.execute or Path(args.file).read_text())
    if args.dry_run:
        print(sql)
        return
    with sf.connect(role=args.role) as conn:
        for cur in conn.execute_string(sql, remove_comments=True):
            first_line = (cur.query or "").strip().splitlines()[0][:100]
            print(f"\n>>> {first_line}")
            if cur.description:
                cols = [d[0] for d in cur.description]
                rows = cur.fetchmany(args.max_rows)
                print(" | ".join(cols))
                for r in rows:
                    print(" | ".join(str(v) for v in r))


if __name__ == "__main__":
    main()
