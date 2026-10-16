#!/usr/bin/env python3
"""Detect changes to the upstream wire contracts this native client implements."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASELINE = Path(__file__).resolve().parent / "contracts.json"
EXPORTS = {
    "packages/contracts/src/auth.ts": ["AuthTokenExchangeRequest", "AuthAccessTokenResult", "AuthWebSocketTicketResult"],
    "packages/contracts/src/orchestrationV2.ts": ["OrchestrationV2ThreadLaunchInput", "OrchestrationV2SubscribeThreadInput", "OrchestrationV2RuntimeRequest", "OrchestrationV2ShellStreamItem", "OrchestrationV2ThreadStreamItem"],
    "packages/contracts/src/modelSelection.ts": ["ModelSelectionWire"],
    "packages/contracts/src/model.ts": [],
    "packages/contracts/src/settings.ts": [],
    "packages/shared/src/themePalettes.ts": [],
    "apps/mobile/src/lib/typography.ts": [],
    "packages/contracts/src/environment.ts": ["ORCHESTRATION_PROTOCOL_VERSION", "ORCHESTRATION_PROTOCOL_QUERY_PARAM", "ORCHESTRATION_PROTOCOL_HEADER"],
}


def read(path, ref):
    if ref:
        return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


def canonical(value):
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    value = re.sub(r"^\s*//.*$", "", value, flags=re.M)
    return re.sub(r"\s+", "", value)


def snapshot(ref):
    result = {}
    for path, names in EXPORTS.items():
        source = read(path, ref)
        for name in names:
            match = re.search(rf"(?:export\s+)?const\s+{name}\s*=\s*(.*?);\n", source, re.S)
            if not match:
                raise ValueError(f"Missing upstream contract: {path}:{name}")
            result[name] = hashlib.sha256(canonical(match.group(1)).encode()).hexdigest()
        # Referenced schemas can change without the named export changing.
        result[path] = hashlib.sha256(canonical(source).encode()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ref", help="Git ref to inspect without changing the checkout")
    parser.add_argument("--record", action="store_true", help="Record after manually reviewing a contract update")
    args = parser.parse_args()
    current = snapshot(args.ref)
    if args.record:
        BASELINE.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
        print(f"Recorded {len(current)} upstream contracts. Review this baseline diff before committing.")
        return
    baseline = json.loads(BASELINE.read_text())
    changed = [name for name in current if current[name] != baseline.get(name)]
    if changed:
        raise SystemExit("Upstream contracts need native review: " + ", ".join(changed))
    print(f"PASS: {len(current)} native upstream contract and brand checks against {args.ref or 'the checkout'}")


if __name__ == "__main__":
    main()
