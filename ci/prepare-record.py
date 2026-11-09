"""Record the checksummed seed files without exporting workstation secrets."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
record = {
    "date": "2026-11-10",
    "repository": "Dingtaiqi/socrates-Arch",
    "sources": {},
    "baseline": json.loads((root / "ci/baselines.json").read_text()),
    "hardware_scope": "socrates, stock Android kernel, Android slot a",
    "contents": "system images only; persistent userdata not archived",
}
for name in ("minit_kde.c", "kde-start.sh"):
    p = root / "arch" / name
    record["sources"][name] = {
        "bytes": p.stat().st_size,
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
    }
(root / "arch/source-record.json").write_text(
    json.dumps(record, indent=2) + "\n", encoding="utf-8")
