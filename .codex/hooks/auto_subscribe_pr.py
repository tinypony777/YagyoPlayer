#!/usr/bin/env python3
"""Record the current branch's open PR against the Codex SessionStart session id."""

from __future__ import annotations

from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


MAX_INPUT_BYTES = 1_048_576


def command(arguments: list[str], *, cwd: Path, timeout: int = 5) -> str | None:
    try:
        result = subprocess.run(
            arguments,
            cwd=cwd,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def default_branches(root: Path) -> set[str]:
    names = {"main", "master"}
    remote = command(
        ["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], cwd=root
    )
    if remote and "/" in remote:
        names.add(remote.split("/", 1)[1])
    return names


def registry_path() -> Path:
    configured = os.environ.get("CODEX_PR_SUBSCRIPTIONS_FILE")
    return (
        Path(configured).expanduser()
        if configured
        else Path.home() / ".codex" / "pr-subscriptions.json"
    )


def read_registry(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"version": 1, "subscriptions": {}}
    value = json.loads(path.read_text(encoding="utf-8"))
    if type(value) is not dict or value.get("version") != 1:
        raise ValueError("unsupported subscription registry")
    subscriptions = value.get("subscriptions")
    if type(subscriptions) is not dict:
        raise ValueError("invalid subscription registry")
    return value


def write_session_subscription(
    path: Path,
    session_id: str,
    key: str | None = None,
    subscription: dict[str, object] | None = None,
) -> None:
    if (key is None) != (subscription is None):
        raise ValueError("subscription key and value must be provided together")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = path.with_name(path.name + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        registry = read_registry(path)
        subscriptions = registry["subscriptions"]
        assert isinstance(subscriptions, dict)
        for existing_key, existing_subscription in list(subscriptions.items()):
            if (
                type(existing_subscription) is dict
                and existing_subscription.get("sessionId") == session_id
            ):
                del subscriptions[existing_key]
        if key is not None and subscription is not None:
            subscriptions[key] = subscription
        data = (json.dumps(registry, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.chmod(0o600)
        temporary.replace(path)


def emit_context(message: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": message,
                }
            }
        )
    )


def clear_session_subscription(session_id: str) -> bool:
    try:
        write_session_subscription(registry_path(), session_id)
    except (OSError, ValueError, json.JSONDecodeError):
        emit_context("[auto-subscribe-pr] Registration skipped: local registry update failed.")
        return False
    return True


def pull_request_matches_local_head(
    pull_request: object,
    branch: str,
    head_oid: str,
    repository_owner: str,
) -> bool:
    if type(pull_request) is not dict:
        return False
    owner = pull_request.get("headRepositoryOwner")
    return (
        pull_request.get("headRefName") == branch
        and pull_request.get("headRefOid") == head_oid
        and type(owner) is dict
        and owner.get("login") == repository_owner
    )


def main() -> None:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        return
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return
    if type(payload) is not dict:
        return
    session_id = payload.get("session_id")
    cwd = payload.get("cwd")
    source = payload.get("source")
    if not all(type(value) is str and value for value in (session_id, cwd, source)):
        return

    root_text = command(["git", "-C", cwd, "rev-parse", "--show-toplevel"], cwd=Path(cwd))
    if not root_text:
        clear_session_subscription(session_id)
        return
    root = Path(root_text)
    branch = command(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root)
    if not branch or branch == "HEAD" or branch in default_branches(root):
        clear_session_subscription(session_id)
        return
    head_oid = command(["git", "rev-parse", "HEAD"], cwd=root)
    if not head_oid:
        clear_session_subscription(session_id)
        return
    if shutil.which("gh") is None:
        clear_session_subscription(session_id)
        emit_context("[auto-subscribe-pr] Registration skipped: authenticated gh is unavailable.")
        return

    repository = command(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        cwd=root,
        timeout=10,
    )
    prs_text = command(
        [
            "gh",
            "pr",
            "list",
            "--state",
            "open",
            "--head",
            branch,
            "--json",
            "number,url,headRefName,headRefOid,headRepositoryOwner",
            "--limit",
            "2",
        ],
        cwd=root,
        timeout=10,
    )
    if not repository or "/" not in repository or prs_text is None:
        clear_session_subscription(session_id)
        emit_context(
            "[auto-subscribe-pr] Registration skipped: GitHub repository or PR lookup failed."
        )
        return
    try:
        prs = json.loads(prs_text)
    except json.JSONDecodeError:
        clear_session_subscription(session_id)
        emit_context("[auto-subscribe-pr] Registration skipped: GitHub PR output was invalid.")
        return
    if type(prs) is not list:
        clear_session_subscription(session_id)
        return
    repository_owner = repository.split("/", 1)[0]
    matching_prs = [
        pr
        for pr in prs
        if pull_request_matches_local_head(pr, branch, head_oid, repository_owner)
    ]
    if len(matching_prs) != 1:
        clear_session_subscription(session_id)
        return
    pr = matching_prs[0]
    number = pr.get("number")
    url = pr.get("url")
    head = pr.get("headRefName")
    if type(number) is not int or number <= 0 or type(url) is not str or head != branch:
        clear_session_subscription(session_id)
        return

    updated_at = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    subscription = {
        "repository": repository,
        "pullRequest": number,
        "pullRequestUrl": url,
        "headBranch": branch,
        "sessionId": session_id,
        "sessionSource": source,
        "updatedAt": updated_at,
    }
    try:
        write_session_subscription(
            registry_path(), session_id, f"{repository}#{number}", subscription
        )
    except (OSError, ValueError, json.JSONDecodeError):
        emit_context("[auto-subscribe-pr] Registration skipped: local registry update failed.")
        return
    emit_context(
        f"[auto-subscribe-pr] Registered PR #{number} for this Codex session. "
        "Event delivery still requires the Codex PR event bridge."
    )


if __name__ == "__main__":
    main()
