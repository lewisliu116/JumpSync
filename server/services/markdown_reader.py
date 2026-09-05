import os
import glob
from datetime import datetime
from typing import List, Dict, Optional

from services.markdown_writer import DATA_DIR


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _parse_frontmatter(text: str) -> (Dict[str, str], str):
    """Split a markdown file into (frontmatter_dict, body). Matches the format
    produced by MarkdownWriter.write_reminder — a `---` fenced block of
    `key: value` lines followed by the markdown body."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text

    fm: Dict[str, str] = {}
    body_start = len(lines)
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            body_start = i + 1
            break
        raw = lines[i]
        if ":" not in raw:
            continue
        key, _, value = raw.partition(":")
        fm[key.strip()] = _strip_quotes(value)

    body = "\n".join(lines[body_start:])
    return fm, body


def _extract_notes(body: str) -> Optional[str]:
    """Reminder notes are written under a `## Notes` heading."""
    marker = "## Notes"
    idx = body.find(marker)
    if idx == -1:
        return None
    notes = body[idx + len(marker):].strip()
    return notes if notes else None


def _parse_reminder_file(file_path: str) -> Optional[Dict]:
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return None

    fm, body = _parse_frontmatter(text)
    if not fm.get("id"):
        return None

    try:
        priority = int(fm.get("priority", "0") or "0")
    except ValueError:
        priority = 0

    mtime = os.path.getmtime(file_path)
    # Timezone-aware, no microseconds — parses cleanly with ISO8601DateFormatter on
    # the client and stays correct even if the server and Mac are in different zones.
    server_modified = (
        datetime.fromtimestamp(mtime).astimezone().replace(microsecond=0).isoformat()
    )

    return {
        "id": fm.get("id", ""),
        "title": fm.get("title", ""),
        "notes": _extract_notes(body),
        "dueDate": fm.get("due_date"),
        "priority": priority,
        "list": fm.get("list", "Reminders"),
        "isCompleted": fm.get("completed", "false").strip().lower() == "true",
        "completionDate": None,
        "creationDate": fm.get("created_at"),
        "modificationDate": fm.get("modified_at"),
        "serverModified": server_modified,
        "relativePath": os.path.relpath(file_path, DATA_DIR),
    }


def read_reminders() -> List[Dict]:
    """Parse every reminder markdown file back into a reminder object so the
    macOS client can pull server-side edits and reconcile them into EventKit."""
    base = os.path.join(DATA_DIR, "reminders")
    if not os.path.isdir(base):
        return []

    results: List[Dict] = []
    for file_path in glob.glob(os.path.join(base, "**", "*.md"), recursive=True):
        parsed = _parse_reminder_file(file_path)
        if parsed is not None:
            results.append(parsed)
    return results
