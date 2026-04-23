#!/usr/bin/env python3
"""Foreground development runner for Vertree.

Optionally builds and serves the local docs share page, then launches
`flutter run` with a local LAN share page URL injected via `dart-define`.
"""

from __future__ import annotations

import argparse
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


LOOPBACK_NO_PROXY_TOKENS = ("127.0.0.1", "localhost")


def _augment_no_proxy_value(existing: str | None) -> str:
  tokens: list[str] = []
  seen: set[str] = set()

  def add_token(value: str) -> None:
    normalized = value.strip()
    if not normalized:
      return
    key = normalized.lower()
    if key in seen:
      return
    seen.add(key)
    tokens.append(normalized)

  for token in (existing or "").split(","):
    add_token(token)
  for token in LOOPBACK_NO_PROXY_TOKENS:
    add_token(token)

  return ",".join(tokens)


def _augment_loopback_no_proxy_env(env: dict[str, str]) -> dict[str, str]:
  current = env.get("NO_PROXY") or env.get("no_proxy")
  updated = _augment_no_proxy_value(current)
  env["NO_PROXY"] = updated
  env["no_proxy"] = updated
  return env


def _resolve_command_bin(command_bin: str) -> str:
  candidate = shutil.which(command_bin)
  if candidate is not None:
    return candidate

  if os.name == "nt" and "." not in Path(command_bin).name:
    for suffix in (".cmd", ".bat"):
      next_candidate = shutil.which(f"{command_bin}{suffix}")
      if next_candidate is not None:
        return next_candidate

  return command_bin


def _wait_for_url(url: str, timeout_seconds: int = 60) -> None:
  opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
  deadline = time.time() + timeout_seconds
  last_error: str | None = None
  while time.time() < deadline:
    try:
      with opener.open(url, timeout=3) as response:
        if 200 <= response.status < 500:
          return
    except Exception as exc:  # noqa: BLE001
      last_error = str(exc)
    time.sleep(1)

  raise RuntimeError(f"URL did not become reachable in time: {url}. {last_error}")


def _can_open_url(url: str, timeout_seconds: int = 2) -> bool:
  try:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=timeout_seconds) as response:
      return 200 <= response.status < 500
  except Exception:  # noqa: BLE001
    return False


def _is_tcp_port_in_use(host: str, port: int) -> bool:
  with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.settimeout(0.5)
    return sock.connect_ex((host, port)) == 0


def _find_next_available_port(host: str, preferred_port: int, span: int = 100) -> int:
  for port in range(preferred_port, preferred_port + span):
    if not _is_tcp_port_in_use(host, port):
      return port
  raise RuntimeError(
    f"Could not find an available local docs port in range {preferred_port}-{preferred_port + span - 1}"
  )


def _resolve_local_docs_endpoint(host: str, preferred_port: int, path: str) -> tuple[int, str, bool]:
  preferred_url = f"http://{host}:{preferred_port}{path}"
  if _can_open_url(preferred_url):
    return preferred_port, preferred_url, True

  if _is_tcp_port_in_use(host, preferred_port):
    next_port = _find_next_available_port(host, preferred_port + 1)
    return next_port, f"http://{host}:{next_port}{path}", False

  return preferred_port, preferred_url, False


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description="Run Vertree in foreground dev mode.")
  parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[1]))
  parser.add_argument("--flutter-bin", default="flutter")
  parser.add_argument("--device", default="windows")
  parser.add_argument("--local-docs", action="store_true")
  parser.add_argument("--local-docs-host", default="127.0.0.1")
  parser.add_argument("--local-docs-port", type=int, default=33030)
  parser.add_argument("--npm-bin", default="npm")
  parser.add_argument(
    "--app-arg",
    action="append",
    default=[],
    help="Argument forwarded to the Flutter desktop app after `--`.",
  )
  parser.add_argument("extra_flutter_args", nargs=argparse.REMAINDER)
  return parser.parse_args()


def main() -> int:
  args = parse_args()
  project_root = Path(args.project_root).resolve()
  docs_dir = project_root / "docs"
  env = _augment_loopback_no_proxy_env(os.environ.copy())
  flutter_bin = _resolve_command_bin(args.flutter_bin)
  npm_bin = _resolve_command_bin(args.npm_bin)

  docs_process: subprocess.Popen[str] | None = None
  docs_port = args.local_docs_port
  docs_url = f"http://{args.local_docs_host}:{docs_port}/f"

  try:
    if args.local_docs:
      if not docs_dir.exists():
        raise RuntimeError(f"docs directory not found: {docs_dir}")

      print("[dev_run] building docs...")
      build_result = subprocess.run(
        [npm_bin, "run", "build"],
        cwd=str(docs_dir),
        env=env,
        check=False,
      )
      if build_result.returncode != 0:
        return build_result.returncode

      docs_port, docs_url, reused_existing = _resolve_local_docs_endpoint(
        args.local_docs_host,
        docs_port,
        "/f",
      )
      if reused_existing:
        print(f"[dev_run] reusing docs at {docs_url}")
      else:
        print(f"[dev_run] serving docs at {docs_url}")
        docs_process = subprocess.Popen(
          [
            npm_bin,
            "run",
            "serve",
            "--",
            "--host",
            args.local_docs_host,
            "--port",
            str(docs_port),
          ],
          cwd=str(docs_dir),
          stdin=subprocess.DEVNULL,
          env=env,
        )
        _wait_for_url(docs_url)

    flutter_command = [flutter_bin, "run", "-d", args.device]
    if args.local_docs:
      flutter_command.append(
        f"--dart-define=VERTREE_SHARE_PAGE_BASE_URL={docs_url}"
      )
    flutter_command.extend(args.extra_flutter_args)
    for app_arg in args.app_arg:
      flutter_command.append(f"--dart-entrypoint-args={app_arg}")

    print("[dev_run] running:", " ".join(flutter_command))
    return subprocess.call(
      flutter_command,
      cwd=str(project_root),
      env=env,
    )
  finally:
    if docs_process is not None and docs_process.poll() is None:
      docs_process.terminate()
      try:
        docs_process.wait(timeout=8)
      except subprocess.TimeoutExpired:
        docs_process.kill()
        docs_process.wait(timeout=3)


if __name__ == "__main__":
  raise SystemExit(main())
