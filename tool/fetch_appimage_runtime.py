"""Download the pinned runtime and source archives used by AppImage packaging."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("Usage: python3 tool/fetch_appimage_runtime.py OUTPUT_DIRECTORY")
root = Path(__file__).resolve().parent.parent
specification = json.loads((root / "packaging/appimage/build-inputs.json").read_text())
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
for item in [specification["runtime"], *specification["runtime_sources"]]:
    target = output / item["file"]
    if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != item["sha256"]:
        temporary = target.with_suffix(target.suffix + ".part")
        subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                        "--retry", "3", "--max-time", "180", item["url"],
                        "--output", str(temporary)], check=True)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != item["sha256"]:
            temporary.unlink()
            sys.exit("Checksum does not match: " + item["file"])
        temporary.replace(target)
(output / "build-inputs.json").write_text(json.dumps(specification, indent=2) + "\n")
print("Verified AppImage runtime inputs: " + str(output))
