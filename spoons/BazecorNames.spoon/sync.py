#!/usr/bin/env python3
"""Sync Bazecor layer/macro/superkey names between machines via a shared iCloud file.

The neuron stores keymaps and macro bodies but not names; Bazecor keeps names
only in its local config.json. Names are the only thing synced.
"""

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HOME = pathlib.Path.home()
CONFIG = pathlib.Path(os.environ.get(
    "BAZECOR_CONFIG", HOME / "Library/Application Support/Bazecor/config.json"))
SHARED = pathlib.Path(os.environ.get(
    "BAZECOR_SYNC_FILE",
    HOME / "Library/Mobile Documents/com~apple~CloudDocs/Bazecor/names.json"))
STATE = pathlib.Path(os.environ.get(
    "BAZECOR_SYNC_STATE", HOME / ".local/state/bazecor-sync/last-hash"))

KINDS = ("layers", "macros", "superkeys")


def extract(config):
    return {
        n["id"]: {k: {str(i["id"]): i["name"] for i in n.get(k, []) if "name" in i}
                  for k in KINDS}
        for n in config.get("neurons", [])
    }


def digest(names):
    return hashlib.sha256(json.dumps(names, sort_keys=True).encode()).hexdigest()


def apply(config, names):
    changed = False
    for n in config.get("neurons", []):
        for kind, by_id in names.get(n["id"], {}).items():
            for item in n.get(kind, []):
                new = by_id.get(str(item["id"]))
                if new is not None and item.get("name") != new:
                    item["name"] = new
                    changed = True
    return changed


def write_atomic(path, text):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        if path.exists():
            shutil.copymode(path, tmp)
        os.replace(tmp, path)
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise


def load_json(path):
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        raise ValueError(f"{path} is empty")
    return json.loads(text)


def valid_names(names):
    return isinstance(names, dict) and all(
        isinstance(kinds, dict) and all(
            k in KINDS and isinstance(by_id, dict)
            and all(isinstance(v, str) for v in by_id.values())
            for k, by_id in kinds.items())
        for kinds in names.values())


def bazecor_running():
    forced = os.environ.get("BAZECOR_RUNNING")
    if forced is not None:
        return forced == "1"
    # pgrep exits 1 for "no match"; anything else is an error, so assume running.
    return subprocess.run(["/usr/bin/pgrep", "-x", "Bazecor"],
                          capture_output=True).returncode != 1


def dump_config(config, trailing_newline):
    return json.dumps(config, indent="\t", ensure_ascii=False) + ("\n" if trailing_newline else "")


def main():
    if not CONFIG.exists():
        return print("no Bazecor config; nothing to do")
    if SHARED.with_name(f".{SHARED.name}.icloud").exists():
        return print("shared file not downloaded yet; skipping")
    if not SHARED.parent.exists() and not SHARED.parent.parent.exists():
        return print("iCloud Drive folder not found; skipping")

    raw_config = CONFIG.read_text(encoding="utf-8")
    config = json.loads(raw_config)
    local = extract(config)
    shared = None
    if SHARED.exists():
        if not SHARED.read_text(encoding="utf-8").strip():
            return print("shared file is empty (still syncing?); skipping")
        shared = load_json(SHARED)
        if not valid_names(shared):
            raise ValueError(f"{SHARED} is not a names file")
    last = STATE.read_text().strip() if STATE.exists() else None

    def push():
        SHARED.parent.mkdir(exist_ok=True)
        write_atomic(SHARED, json.dumps({**(shared or {}), **local}, indent=2,
                                        sort_keys=True, ensure_ascii=False) + "\n")
        save_state(local)
        print("pushed local names")

    def pull():
        if bazecor_running():
            return print("Bazecor is running; pull deferred")
        if not apply(config, shared):
            save_state(local)
            return print("in sync")
        text = dump_config(config, raw_config.endswith("\n"))
        if json.loads(text) != config:
            raise ValueError("refusing to write config that does not round-trip")
        write_atomic(CONFIG, text)
        save_state(extract(config))
        print("pulled shared names")

    if shared is None:
        return push()
    if digest(local) == digest({k: shared.get(k) for k in local}):
        save_state(local)
        return print("in sync")
    if last is None:
        return pull()
    if digest(local) != last:
        return push()
    return pull()


def save_state(names):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(STATE, digest(names))


def run():
    try:
        return main()
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
        print(f"sync aborted, nothing written: {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(run())
