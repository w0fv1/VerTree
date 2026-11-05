import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("--runtime", required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
runtime = root / "vendor" / "filee" / args.runtime
executable = runtime / ("filee-cli.exe" if args.runtime.startswith("win-") else "filee-cli")
assert (runtime / "LICENSE-Filee.txt").is_file()
formats = subprocess.run([str(executable), "formats", "png"], check=True, capture_output=True, text=True, encoding="utf-8-sig")
assert "webp" in formats.stdout.lower(), formats.stdout
with tempfile.TemporaryDirectory(prefix="vertree-conversion-") as directory:
    source = Path(directory) / "source.png"
    shutil.copyfile(root / "assets/img/logo/logo.png", source)
    original = source.read_bytes()
    result = subprocess.run([str(executable), "convert", str(source), "--to", "webp", "--json"], check=True, capture_output=True, text=True, encoding="utf-8-sig")
    payload = json.loads(result.stdout.lstrip("\ufeff"))
    assert payload["failed"] == 0, payload
    outputs = [Path(output) for item in payload["files"] for output in item["outputs"]]
    assert outputs and all(path.is_file() and path.stat().st_size > 0 for path in outputs), payload
    assert all(path.read_bytes()[:4] == b"RIFF" and path.read_bytes()[8:12] == b"WEBP" for path in outputs)
    assert source.read_bytes() == original
print("Bundled Filee: PNG to WebP passed; source preserved")
