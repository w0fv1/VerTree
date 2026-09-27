"""Read-only verification of public release bytes and the deployed website.

Uses only Python's standard library. Downloads are hashed in memory as streams;
no installer is executed, and no release, tag, or deployment is modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from html.parser import HTMLParser

REPOSITORY = "w0fv1/VerTree"
SITE = "https://vertree.w0fv1.dev"
USER_AGENT = "Vertree-published-release-verification/1.0"


def version_for(tag: str) -> str:
    match = re.fullmatch(r"[Vv]?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)", tag)
    if not match:
        raise ValueError("Expected a semantic-version release tag")
    return match[1]


def parse_checksums(content: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in content.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](?:\./)?([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if not match or match[2] in result:
            raise ValueError("Invalid or duplicate checksum entry")
        result[match[2]] = match[1].lower()
    if not result:
        raise ValueError("Checksum manifest is empty")
    return result


def read_url(url: str, *, stream_hash: bool = False):
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("Verification requires HTTPS")
    # Retries apply only to reads; there are no side-effecting HTTP methods.
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={
                "User-Agent": USER_AGENT, "Cache-Control": "no-cache",
            })
            with urllib.request.urlopen(request, timeout=25) as response:
                if response.status != 200:
                    raise RuntimeError(f"HTTP {response.status}")
                digest, length, chunks = hashlib.sha256(), 0, []
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
                    length += len(chunk)
                    if not stream_hash:
                        if length > 4 * 1024 * 1024:
                            raise ValueError("Metadata or page is unexpectedly large")
                        chunks.append(chunk)
                return (digest.hexdigest(), length) if stream_hash else b"".join(chunks)
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))
    raise AssertionError("Unreachable")


def verify_release(tag: str) -> dict:
    version = version_for(tag)
    api = f"https://api.github.com/repos/{REPOSITORY}/releases/tags/{tag}"
    release = json.loads(read_url(api))
    if release["tag_name"] != tag or release["draft"] or release["prerelease"]:
        raise ValueError("Expected the specified public stable release")
    assets = {asset["name"]: asset for asset in release["assets"]}
    if len(assets) != len(release["assets"]):
        raise ValueError("Duplicate release asset names")
    required = {"SHA256SUMS.txt"}
    required.update(f"vertree-windows-x64-{version}{suffix}" for suffix in ("-setup.exe", ".zip", ".msi", ".msix"))
    required.update(f"vertree-linux-x64-{version}{suffix}" for suffix in (".deb", ".rpm", ".tar.gz"))
    required.update(f"vertree-macos-arm64-{version}{suffix}" for suffix in (".dmg", ".zip"))
    if missing := required - assets.keys():
        raise ValueError(f"Missing required release assets: {sorted(missing)}")
    for name, asset in assets.items():
        expected_url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{name}"
        if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name)
                or asset["browser_download_url"] != expected_url
                or asset["state"] != "uploaded" or asset["size"] <= 0):
            raise ValueError(f"Invalid published asset: {name}")
    raw = read_url(assets["SHA256SUMS.txt"]["browser_download_url"])
    sums = parse_checksums(raw.decode("utf-8-sig"))
    if set(sums) != assets.keys() - {"SHA256SUMS.txt"}:
        raise ValueError("Checksums and release asset names differ")
    manifest_hash = hashlib.sha256(raw).hexdigest()
    if assets["SHA256SUMS.txt"].get("digest") != f"sha256:{manifest_hash}":
        raise ValueError("Checksum manifest digest does not match GitHub metadata")

    def verify_asset(item):
        name, expected = item
        asset = assets[name]
        digest, length = read_url(asset["browser_download_url"], stream_hash=True)
        if digest != expected or length != asset["size"] or asset.get("digest") != f"sha256:{digest}":
            raise ValueError(f"Downloaded asset verification failed: {name}")
        print(f"PASS asset {name} ({length} bytes)", flush=True)
        return {"name": name, "bytes": length, "sha256": digest}

    with ThreadPoolExecutor(max_workers=4) as pool:
        verified = list(pool.map(verify_asset, sorted(sums.items())))
    return {"tag": tag, "releaseId": release["id"], "url": release["html_url"],
            "publishedAt": release["published_at"], "targetCommit": release["target_commitish"],
            "manifestSha256": manifest_hash, "assets": verified}


class _TitleParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.inside_title = False
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "title":
            self.inside_title = True

    def handle_endtag(self, tag):
        if tag == "title":
            self.inside_title = False

    def handle_data(self, data):
        if self.inside_title:
            self.parts.append(data)


def page_title(html: str) -> str | None:
    # React/Docusaurus adds attributes such as data-rh="true" to <title>.
    # Use an HTML parser so attributes, case and entities remain valid HTML.
    parser = _TitleParser()
    parser.feed(html)
    return " ".join("".join(parser.parts).split()) or None


def verify_website(tag: str) -> dict:
    version = version_for(tag)
    # Check deployed HTML, not local build output. These are informational pages;
    # never probe the LAN share endpoint or follow private-network URLs.
    routes = {
        "/": "让每一次迭代都有迹可循",
        "/features/": "功能与使用场景",
        "/download/": f"vertree-windows-x64-{version}-setup.exe",
        "/docs/intro/": "从一个文件开始",
        "/docs/tutorial-usage/fast-delete/": "永久",
        "/docs/tutorial-usage/file-locks/": "占用",
        "/docs/tutorial-usage/settings/": "settings.json",
        "/blog/3-0-0-file-tools/": "3.0.0",
    }

    def verify_page(item):
        route, marker = item
        url = SITE + route + "?release-verification=" + urllib.parse.quote(tag)
        html = read_url(url).decode("utf-8")
        title = page_title(html)
        if not title or marker not in html:
            raise ValueError(f"Deployed page is missing its expected content: {route}; title={title!r}; bytes={len(html)}")
        print(f"PASS website {route}", flush=True)
        return {"route": route, "title": title, "markerFound": True}

    with ThreadPoolExecutor(max_workers=4) as pool:
        pages = list(pool.map(verify_page, routes.items()))
    return {"origin": SITE, "pages": pages}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--report", type=Path, default=Path("build/published-release-verification.json"))
    args = parser.parse_args()
    version_for(args.tag)
    report = {"checkedAt": datetime.now(timezone.utc).isoformat(), "tag": args.tag,
              "readOnly": True, "passed": True}
    # Keep independent results: a local/CDN network error must not erase evidence
    # that all published installer bytes were successfully checked (or vice versa).
    for key, action in (("release", verify_release), ("website", verify_website)):
        try:
            report[key] = {"passed": True, **action(args.tag)}
        except Exception as error:
            report[key] = {"passed": False, "error": str(error)}
            report["passed"] = False
            print(f"FAIL {key}: {error}", flush=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Report: {args.report}", flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
