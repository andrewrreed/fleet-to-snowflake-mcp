"""Smoke-test the Snowflake MCP server outside Fleet: initialize, tools/list, then call each tool.

    .venv/bin/python scripts/mcp_smoke_test.py                 # list tools + run both patterns
    .venv/bin/python scripts/mcp_smoke_test.py --list-only
    .venv/bin/python scripts/mcp_smoke_test.py -q "Top 5 customers by order value in 1997?"

Auth is a short-lived key-pair JWT; the session runs as the user's DEFAULT_ROLE.
"""

from __future__ import annotations

import argparse
import json
import os
import time

import requests

from sf import ACCOUNT_URL, keypair_jwt

URL = (
    f"{ACCOUNT_URL}/api/v2/databases/{os.environ['MCP_DATABASE']}"
    f"/schemas/{os.environ['MCP_SCHEMA']}/mcp-servers/{os.environ['MCP_SERVER']}"
)
_ids = iter(range(1, 1_000_000))


def rpc(method: str, params: dict | None = None) -> dict:
    headers = {
        "Authorization": f"Bearer {keypair_jwt()}",
        "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    body = {"jsonrpc": "2.0", "id": next(_ids), "method": method, "params": params or {}}
    t0 = time.time()
    resp = requests.post(URL, headers=headers, json=body, timeout=180)
    elapsed = time.time() - t0
    if resp.status_code >= 400:
        raise SystemExit(f"{method}: HTTP {resp.status_code}: {resp.text[:800]}")
    print(f"  [{method}] {resp.status_code} {resp.headers.get('content-type')} {len(resp.content)}B {elapsed:.1f}s")
    if "text/event-stream" in resp.headers.get("content-type", ""):
        msgs = [
            json.loads(line[5:].strip())
            for line in resp.text.splitlines()
            if line.startswith("data:") and line[5:].strip() not in ("", "[DONE]")
        ]
        return msgs[-1] if msgs else {}
    return resp.json()


def show(result: dict, limit: int = 2500) -> None:
    text = json.dumps(result.get("result", result), indent=2)
    print(text[:limit] + ("\n  …(truncated)" if len(text) > limit else ""))


def first_text(result: dict) -> str:
    for item in result.get("result", {}).get("content", []):
        if item.get("type") == "text":
            return item["text"]
    return ""


def arg_name(tool: dict, preferred: tuple[str, ...]) -> str:
    props = (tool.get("inputSchema") or {}).get("properties", {})
    return next((p for p in preferred if p in props), next(iter(props), preferred[0]))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("-q", "--question", default="What was total revenue by region in 1995?")
    p.add_argument("--list-only", action="store_true")
    args = p.parse_args()

    print(f"MCP server: {URL}")
    show(rpc("initialize", {
        "protocolVersion": "2025-11-25",
        "capabilities": {},
        "clientInfo": {"name": "fleet-mcp-smoke-test", "version": "0.1"},
    }))

    tools = {t["name"]: t for t in rpc("tools/list").get("result", {}).get("tools", [])}
    print("\nTools:")
    for t in tools.values():
        print(f"  - {t['name']}: args={list((t.get('inputSchema') or {}).get('properties', {}))}")
    if args.list_only:
        return

    print(f"\n=== Pattern A: sales_agent  — {args.question!r}")
    agent = tools["sales_agent"]
    show(rpc("tools/call", {"name": "sales_agent",
                            "arguments": {arg_name(agent, ("message", "query", "question")): args.question}}))

    print(f"\n=== Pattern B step 1: sales_analyst — {args.question!r}")
    analyst = tools["sales_analyst"]
    res = rpc("tools/call", {"name": "sales_analyst",
                             "arguments": {arg_name(analyst, ("message", "query")): args.question}})
    show(res)

    sql = _extract_sql(res)
    if not sql:
        print("\nNo SQL found in analyst response; skipping run_sql.")
        return
    print(f"\n=== Pattern B step 2: run_sql\n{sql}\n")
    runner = tools["run_sql"]
    show(rpc("tools/call", {"name": "run_sql",
                            "arguments": {arg_name(runner, ("sql", "statement", "query")): sql}}))


def _extract_sql(result: dict) -> str:
    """Analyst output shape isn't documented; look for a 'sql' field in JSON text content."""
    text = first_text(result)
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return ""
    stack = [data]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            if isinstance(node.get("sql"), str) or isinstance(node.get("statement"), str):
                return node.get("sql") or node["statement"]
            stack.extend(node.values())
        elif isinstance(node, list):
            stack.extend(node)
    return ""


if __name__ == "__main__":
    main()
