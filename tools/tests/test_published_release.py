"""Offline regression tests: never reach GitHub or the production site."""
import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_published_release as verifier


class PublishedReleaseTests(unittest.TestCase):
    def fixtures(self):
        names = [f"vertree-windows-x64-3.0.0{s}" for s in ("-setup.exe", ".zip", ".msi", ".msix")]
        names += [f"vertree-linux-x64-3.0.0{s}" for s in (".deb", ".rpm", ".tar.gz")]
        names += [f"vertree-macos-arm64-3.0.0{s}" for s in (".dmg", ".zip")]
        bodies = {name: ("fixture:" + name).encode() for name in names}
        sums = {name: hashlib.sha256(body).hexdigest() for name, body in bodies.items()}
        bodies["SHA256SUMS.txt"] = "".join(f"{digest}  ./{name}\n" for name, digest in sums.items()).encode()
        release = {"id": 1, "tag_name": "V3.0.0", "draft": False, "prerelease": False,
                   "published_at": "2026-09-27T00:00:00Z", "target_commitish": "abc",
                   "html_url": "https://github.com/w0fv1/VerTree/releases/tag/V3.0.0", "assets": []}
        for name, body in bodies.items():
            release["assets"].append({"name": name, "state": "uploaded", "size": len(body),
                "digest": "sha256:" + hashlib.sha256(body).hexdigest(),
                "browser_download_url": f"https://github.com/w0fv1/VerTree/releases/download/V3.0.0/{name}"})
        def read(url, *, stream_hash=False):
            if "api.github.com" in url:
                return json.dumps(release).encode()
            body = bodies[url.rsplit("/", 1)[-1]]
            return (hashlib.sha256(body).hexdigest(), len(body)) if stream_hash else body
        return release, bodies, read

    def test_version_input(self):
        self.assertEqual(verifier.version_for("V3.0.0"), "3.0.0")
        for value in ("latest", "V3.0.0/../../main", "3.0.0;echo bad", ""):
            with self.assertRaises(ValueError):
                verifier.version_for(value)

    def test_checksum_format(self):
        digest = "a" * 64
        self.assertEqual(verifier.parse_checksums(f"{digest}  ./test.exe\n"), {"test.exe": digest})
        for content in ("", f"{digest}  ../test.exe", f"{digest}  /test.exe", f"{digest}  a.exe\n{digest}  a.exe", "bad  a.exe"):
            with self.assertRaises(ValueError):
                verifier.parse_checksums(content)

    def test_all_public_asset_bytes_are_checked(self):
        _, bodies, read = self.fixtures()
        with patch.object(verifier, "read_url", side_effect=read):
            result = verifier.verify_release("V3.0.0")
        self.assertEqual(len(result["assets"]), len(bodies) - 1)

    def test_rejects_drafts_and_incomplete_releases(self):
        release, _, read = self.fixtures()
        release["draft"] = True
        with patch.object(verifier, "read_url", side_effect=read), self.assertRaises(ValueError):
            verifier.verify_release("V3.0.0")
        release["draft"] = False
        release["assets"].pop(0)
        with patch.object(verifier, "read_url", side_effect=read), self.assertRaises(ValueError):
            verifier.verify_release("V3.0.0")

    def test_rejects_mismatched_download_and_unrelated_urls(self):
        release, bodies, read = self.fixtures()
        name = "vertree-windows-x64-3.0.0-setup.exe"
        before = bodies[name]
        bodies[name] = b"altered"
        with patch.object(verifier, "read_url", side_effect=read), self.assertRaises(ValueError):
            verifier.verify_release("V3.0.0")
        bodies[name] = before
        release["assets"][0]["browser_download_url"] = "https://unrelated.invalid/installer.exe"
        with patch.object(verifier, "read_url", side_effect=read), self.assertRaises(ValueError):
            verifier.verify_release("V3.0.0")

    def test_rejects_duplicate_assets(self):
        release, _, read = self.fixtures()
        release["assets"].append(copy.deepcopy(release["assets"][0]))
        with patch.object(verifier, "read_url", side_effect=read), self.assertRaises(ValueError):
            verifier.verify_release("V3.0.0")

    def test_title_attributes_case_entities_and_newlines(self):
        self.assertEqual(verifier.page_title('<title data-rh="true">让每一次迭代都有迹可循 | Vertree 维树</title>'), '让每一次迭代都有迹可循 | Vertree 维树')
        self.assertEqual(verifier.page_title('<TITLE data-value=">"> A &amp; B\n </TITLE>'), 'A & B')
        self.assertIsNone(verifier.page_title('<html><h1>No title</h1></html>'))

    def test_website_accepts_real_docusaurus_title_markup(self):
        html = ('<html><head><title data-rh="true">Vertree 维树</title></head><body>'
                '让每一次迭代都有迹可循 功能与使用场景 从一个文件开始 永久 占用 settings.json '
                'vertree-windows-x64-3.0.0-setup.exe 3.0.0</body></html>').encode()
        with patch.object(verifier, "read_url", return_value=html):
            result = verifier.verify_website("V3.0.0")
        self.assertEqual(len(result["pages"]), 8)
        self.assertTrue(all(page["markerFound"] for page in result["pages"]))

    def test_website_rejects_old_deployment(self):
        with patch.object(verifier, "read_url", return_value=b"<title>Old website</title>"), self.assertRaises(ValueError):
            verifier.verify_website("V3.0.0")


if __name__ == "__main__":
    unittest.main()
