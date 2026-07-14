#!/usr/bin/env python3
"""Update documentation screenshots through the local Vertree HTTP API."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONTROLLER_URL = "http://127.0.0.1:32500"
DEFAULT_IMAGE_ROOT = REPO_ROOT / "docs" / "static" / "img"
DEFAULT_API_TOKEN_PATH = REPO_ROOT / ".dart_tool" / "vertree_local_api_token"
DEFAULT_MONITOR_SAMPLE_PATH = (
    REPO_ROOT
    / ".sample"
    / "file_version_tree"
    / "storyboard"
    / "storyboard.0.0.txt"
)
DEFAULT_VERSION_TREE_SAMPLE_PATH = (
    REPO_ROOT
    / ".sample"
    / "file_version_tree"
    / "storyboard"
    / "storyboard#release.0.2.txt"
)


def _build_capture_manifest(image_root: Path) -> dict[str, dict[str, Any]]:
    return {
        "brand-home-page": {
            "output_path": image_root / "brand-home-page.png",
            "theme_mode": "light",
            "navigation": {
                "page": "brand",
                "waitMilliseconds": 650,
            },
            "window_state": {
                "mode": "restore",
                "width": 1280,
                "height": 860,
            },
            "screenshot": {
                "waitMilliseconds": 500,
            },
        },
        "initial-setup-dialog": {
            "output_path": image_root / "tutorial" / "initial-setup-dialog.png",
            "theme_mode": "light",
            "navigation": {
                "page": "brand",
                "showInitialSetupDialog": True,
                "waitMilliseconds": 950,
            },
            "window_state": {
                "mode": "restore",
                "width": 1120,
                "height": 760,
            },
            "screenshot": {
                "waitMilliseconds": 550,
            },
        },
        "monitor-tasks-page": {
            "output_path": image_root / "usage" / "monitor-tasks-page.png",
            "theme_mode": "light",
            "navigation": {
                "page": "monitor",
                "waitMilliseconds": 700,
            },
            "window_state": {
                "mode": "restore",
                "width": 1420,
                "height": 920,
            },
            "screenshot": {
                "waitMilliseconds": 650,
            },
            "prepare": "ensure_monitor_task",
        },
        "settings-page": {
            "output_path": image_root / "usage" / "settings-page.png",
            "theme_mode": "light",
            "navigation": {
                "page": "settings",
                "waitMilliseconds": 550,
            },
            "window_state": {
                "mode": "restore",
                "width": 1420,
                "height": 920,
            },
            "screenshot": {
                "waitMilliseconds": 500,
            },
        },
        "version-tree-page": {
            "output_path": image_root / "usage" / "version-tree-page.png",
            "theme_mode": "light",
            "navigation": {
                "page": "version-tree",
                "path": str(DEFAULT_VERSION_TREE_SAMPLE_PATH),
                "waitMilliseconds": 1500,
            },
            "window_state": {
                "mode": "restore",
                "width": 1600,
                "height": 980,
            },
            "file_tree_viewport": {
                "fitToViewport": True,
            },
            "screenshot": {
                "waitMilliseconds": 1000,
            },
        },
        "version-tree-overview": {
            "output_path": image_root / "version-tree-overview.png",
            "theme_mode": "light",
            "navigation": {
                "page": "version-tree",
                "path": str(DEFAULT_VERSION_TREE_SAMPLE_PATH),
                "waitMilliseconds": 1650,
            },
            "window_state": {
                "mode": "fullscreen",
            },
            "file_tree_viewport": {
                "fitToViewport": True,
            },
            "screenshot": {
                "waitMilliseconds": 1100,
            },
        },
    }


def _request_json(
    method: str,
    url: str,
    *,
    payload: dict[str, Any] | None = None,
    access_token: str | None = None,
    timeout_seconds: int | float = 30,
) -> dict[str, Any]:
    data = None
    headers = {}
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"

    request = urllib.request.Request(
        url=url,
        method=method,
        data=data,
        headers=headers,
    )
    parsed = urllib.parse.urlparse(url)
    opener = (
        urllib.request.build_opener(urllib.request.ProxyHandler({}))
        if parsed.hostname in {"127.0.0.1", "localhost"}
        else urllib.request.build_opener()
    )

    try:
        with opener.open(request, timeout=float(timeout_seconds)) as response:
            raw = response.read().decode("utf-8")
    except TimeoutError as exc:
        raise RuntimeError(
            f"{method} {url} timed out after {timeout_seconds} seconds"
        ) from exc
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload_obj = json.loads(raw)
        except json.JSONDecodeError as json_exc:
            raise RuntimeError(f"{method} {url} failed: HTTP {exc.code} {raw}") from json_exc
        raise RuntimeError(
            f"{method} {url} failed: HTTP {exc.code} {json.dumps(payload_obj, ensure_ascii=False)}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"{method} {url} failed: {exc.reason}") from exc
    except OSError as exc:
        raise RuntimeError(f"{method} {url} failed: {exc}") from exc

    decoded = json.loads(raw)
    if not isinstance(decoded, dict):
        raise RuntimeError(f"{method} {url} did not return a JSON object")
    return decoded


def _ensure_ready(controller_url: str, timeout_seconds: int) -> str:
    request_url = f"{controller_url.rstrip('/')}/ensure-ready"
    try:
        payload = _request_json(
            "POST",
            request_url,
            payload={"timeoutSeconds": timeout_seconds, "startIfNeeded": True},
            timeout_seconds=timeout_seconds + 10,
        )
    except RuntimeError as exc:
        raise RuntimeError(
            "Failed to obtain a ready app instance from the dev controller.\n"
            f"Controller URL: {controller_url}\n"
            f"Reason: {exc}\n"
            "Guidance:\n"
            "1. This script is intended for an active local development session, not ordinary end-user usage.\n"
            "2. Start the controller first: python dev_server.py --bootstrap --device windows\n"
            "   For screenshots, add: --app-arg --no-announcement\n"
            "3. If the controller output crashes in a non-UTF-8 terminal, set PYTHONUTF8=1 and retry.\n"
            "4. If the app is already running, bypass the controller with:\n"
            "   python tools/update_doc_images.py --api-base http://127.0.0.1:31414/api/v1 --capture settings-page\n"
            "5. Inspect controller health/logs:\n"
            "   GET http://127.0.0.1:32500/status\n"
            "   GET http://127.0.0.1:32500/logs\n"
            "6. Ensure Flutter Windows development works before using this script."
        ) from exc
    if payload.get("ready") is not True:
        raise RuntimeError(
            f"Controller did not reach ready state: {json.dumps(payload, ensure_ascii=False)}"
        )
    app_api_base = payload.get("appApiBaseUrl")
    if not isinstance(app_api_base, str) or not app_api_base:
        raise RuntimeError(f"Controller response did not include appApiBaseUrl: {payload}")
    return app_api_base.rstrip("/")


def _post_api(
    base_url: str,
    path: str,
    payload: dict[str, Any],
    access_token: str,
) -> dict[str, Any]:
    return _request_json(
        "POST",
        f"{base_url}{path}",
        payload=payload,
        access_token=access_token,
    )


def _ensure_monitor_task(base_url: str, sample_path: Path, access_token: str) -> None:
    try:
        _post_api(
            base_url,
            "/monitor-tasks",
            {"path": str(sample_path)},
            access_token,
        )
    except RuntimeError as exc:
        if "Task already exists for:" not in str(exc):
            raise


def _run_capture(
    name: str,
    definition: dict[str, Any],
    *,
    base_url: str,
    pixel_ratio: float,
    monitor_sample_path: Path,
    access_token: str,
) -> Path:
    prepare_step = definition.get("prepare")
    if prepare_step == "ensure_monitor_task":
        _ensure_monitor_task(base_url, monitor_sample_path, access_token)

    navigation = dict(definition["navigation"])
    screenshot = dict(definition["screenshot"])
    window_state = dict(definition.get("window_state", {}))
    file_tree_viewport = dict(definition.get("file_tree_viewport", {}))
    theme_mode = definition.get("theme_mode")
    output_path = Path(definition["output_path"]).resolve()

    if isinstance(theme_mode, str) and theme_mode:
        _post_api(base_url, "/ui/theme-mode", {"mode": theme_mode}, access_token)
    _post_api(base_url, "/ui/navigation", navigation, access_token)
    if window_state:
        _post_api(base_url, "/ui/window-state", window_state, access_token)
    if file_tree_viewport:
        _post_api(
            base_url,
            "/ui/file-tree/viewport",
            file_tree_viewport,
            access_token,
        )
    screenshot_payload = {
        "outputPath": str(output_path),
        "pixelRatio": pixel_ratio,
        **screenshot,
    }
    response = _post_api(
        base_url,
        "/ui/screenshot",
        screenshot_payload,
        access_token,
    )
    success = response.get("success")
    if success is not True:
        raise RuntimeError(f"Screenshot capture failed for {name}: {response}")
    return output_path


def _validate_runtime_inputs(selected_captures: list[str], monitor_sample_path: Path) -> None:
    missing_paths: list[str] = []
    if "monitor-tasks-page" in selected_captures and not monitor_sample_path.exists():
        missing_paths.append(
            f"monitor sample path does not exist: {monitor_sample_path}"
        )
    if any(
        capture_name in {"version-tree-page", "version-tree-overview"}
        for capture_name in selected_captures
    ) and not DEFAULT_VERSION_TREE_SAMPLE_PATH.exists():
        missing_paths.append(
            f"version-tree sample path does not exist: {DEFAULT_VERSION_TREE_SAMPLE_PATH}"
        )

    if missing_paths:
        joined = "\n".join(f"- {item}" for item in missing_paths)
        raise RuntimeError(
            "Required sample data is missing for the requested documentation captures.\n"
            f"{joined}\n"
            "Guidance:\n"
            "1. Restore the repository sample data under .sample/file_version_tree.\n"
            "2. Or point the script at valid files with --monitor-sample-path.\n"
            "3. For version-tree captures, keep the storyboard sample files available unless you also update the capture manifest."
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Drive the local Vertree app and refresh documentation screenshots.",
    )
    parser.add_argument(
        "--controller-url",
        default=DEFAULT_CONTROLLER_URL,
        help=f"Dev controller base URL. Default: {DEFAULT_CONTROLLER_URL}",
    )
    parser.add_argument(
        "--api-base",
        help="Use an already running app API base URL instead of asking the controller.",
    )
    parser.add_argument(
        "--api-token",
        help="Bearer token for the local app API.",
    )
    parser.add_argument(
        "--capture",
        action="append",
        dest="captures",
        help="Capture name to run. Can be provided multiple times. Defaults to all.",
    )
    parser.add_argument(
        "--pixel-ratio",
        type=float,
        default=1.75,
        help="Pixel ratio used by /ui/screenshot. Default: 1.75",
    )
    parser.add_argument(
        "--image-root",
        default=str(DEFAULT_IMAGE_ROOT),
        help=f"Root directory used for generated images. Default: {DEFAULT_IMAGE_ROOT}",
    )
    parser.add_argument(
        "--monitor-sample-path",
        default=str(DEFAULT_MONITOR_SAMPLE_PATH),
        help="Sample file path used to populate the monitor page.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=120,
        help="Controller startup timeout when --api-base is not provided.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available capture names and exit.",
    )
    args = parser.parse_args()

    image_root = Path(args.image_root).resolve()
    image_root.mkdir(parents=True, exist_ok=True)
    manifest = _build_capture_manifest(image_root)

    if args.list:
        for capture_name in manifest:
            print(capture_name)
        return 0

    selected_captures = args.captures or list(manifest.keys())
    unknown_captures = [name for name in selected_captures if name not in manifest]
    if unknown_captures:
        print(f"Unknown capture names: {', '.join(unknown_captures)}", file=sys.stderr)
        return 2

    try:
        base_url = (
            args.api_base.rstrip("/")
            if args.api_base
            else _ensure_ready(args.controller_url, args.timeout_seconds)
        )
        access_token = args.api_token or os.environ.get("VERTREE_LOCAL_API_TOKEN")
        if not access_token and DEFAULT_API_TOKEN_PATH.exists():
            access_token = DEFAULT_API_TOKEN_PATH.read_text(encoding="utf-8").strip()
        if not access_token:
            raise RuntimeError(
                "Local API token is required. Pass --api-token or start the app through dev_server.py."
            )
        monitor_sample_path = Path(args.monitor_sample_path).resolve()
        _validate_runtime_inputs(selected_captures, monitor_sample_path)

        generated: list[Path] = []
        for capture_name in selected_captures:
            output_path = _run_capture(
                capture_name,
                manifest[capture_name],
                base_url=base_url,
                pixel_ratio=args.pixel_ratio,
                monitor_sample_path=monitor_sample_path,
                access_token=access_token,
            )
            generated.append(output_path)
            print(f"[updated] {capture_name}: {output_path}")
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        if not args.api_base:
            print(
                "Hint: if the app is already running, retry with --api-base to skip controller bootstrap.",
                file=sys.stderr,
            )
        return 1

    print(f"[done] generated {len(generated)} screenshot(s) via {base_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
