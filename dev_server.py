#!/usr/bin/env python3
"""Local development control server for Vertree.

This service owns a `flutter run` subprocess and exposes a small loopback-only
HTTP API that can:

- start the app
- hot reload
- hot restart
- fully restart the process
- stop the app
- wait until the app HTTP API is ready
- stream recent logs/status

It is intended to be used by local agents that need to iterate on the app
without manual terminal interaction.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


API_BASE_PATTERN = re.compile(r"(http://127\.0\.0\.1:(\d+)/api/v1)")
LOOPBACK_NO_PROXY_TOKENS = ("127.0.0.1", "localhost")


def _safe_print(value: str) -> None:
  try:
    print(value)
  except UnicodeEncodeError:
    encoded = value.encode(sys.stdout.encoding or "utf-8", errors="replace")
    sys.stdout.buffer.write(encoded + b"\n")
    sys.stdout.buffer.flush()


@dataclass
class ControllerConfig:
  project_root: Path
  flutter_bin: str = "flutter"
  device: str = "windows"
  controller_host: str = "127.0.0.1"
  controller_port: int = 32500
  log_tail_size: int = 400
  startup_timeout_seconds: int = 120
  api_port_start: int = 31414
  api_port_end: int = 31614
  local_docs_enabled: bool = False
  local_docs_host: str = "127.0.0.1"
  local_docs_port: int = 33030
  local_docs_path: str = "/f"
  npm_bin: str = "npm"
  extra_flutter_args: list[str] = field(default_factory=list)
  app_args: list[str] = field(default_factory=list)


class FlutterAppController:
  def __init__(self, config: ControllerConfig) -> None:
    self.config = config
    self._lock = threading.RLock()
    self._process: subprocess.Popen[str] | None = None
    self._reader_thread: threading.Thread | None = None
    self._logs: deque[str] = deque(maxlen=config.log_tail_size)
    self._api_base_url: str | None = None
    self._api_port: int | None = None
    self._last_command: str | None = None
    self._last_started_at: float | None = None
    self._last_exited_at: float | None = None
    self._last_exit_code: int | None = None
    self._run_count = 0
    self._docs_process: subprocess.Popen[str] | None = None
    self._docs_reader_thread: threading.Thread | None = None
    self._docs_url = (
      f"http://{self.config.local_docs_host}:{self.config.local_docs_port}{self.config.local_docs_path}"
      if self.config.local_docs_enabled
      else None
    )
    self._docs_last_started_at: float | None = None
    self._docs_last_exited_at: float | None = None
    self._docs_last_exit_code: int | None = None

  def status(self) -> dict[str, Any]:
    with self._lock:
      process = self._process
      running = process is not None and process.poll() is None
      docs_process = self._docs_process
      docs_running = docs_process is not None and docs_process.poll() is None
      return {
        "running": running,
        "pid": process.pid if running and process else None,
        "projectRoot": str(self.config.project_root),
        "flutterCommand": self._build_flutter_command(),
        "device": self.config.device,
        "controllerUrl": f"http://{self.config.controller_host}:{self.config.controller_port}",
        "appApiBaseUrl": self._api_base_url,
        "appApiPort": self._api_port,
        "lastCommand": self._last_command,
        "lastStartedAt": _iso_or_none(self._last_started_at),
        "lastExitedAt": _iso_or_none(self._last_exited_at),
        "lastExitCode": self._last_exit_code,
        "runCount": self._run_count,
        "localDocs": {
          "enabled": self.config.local_docs_enabled,
          "running": docs_running,
          "pid": docs_process.pid if docs_running and docs_process else None,
          "url": self._docs_url,
          "host": self.config.local_docs_host,
          "port": self.config.local_docs_port,
          "lastStartedAt": _iso_or_none(self._docs_last_started_at),
          "lastExitedAt": _iso_or_none(self._docs_last_exited_at),
          "lastExitCode": self._docs_last_exit_code,
        },
        "recentLogs": list(self._logs),
      }

  def start(self) -> dict[str, Any]:
    with self._lock:
      if self._is_running_locked():
        self._ensure_local_docs_locked()
        self._last_command = "start(no-op)"
        return self.status()

      self._ensure_local_docs_locked()
      command = self._build_flutter_command()
      env = _augment_loopback_no_proxy_env(os.environ.copy())
      process = subprocess.Popen(
        command,
        cwd=str(self.config.project_root),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        encoding="utf-8",
        errors="replace",
        env=env,
      )
      self._process = process
      self._api_base_url = None
      self._api_port = None
      self._last_started_at = time.time()
      self._last_exited_at = None
      self._last_exit_code = None
      self._last_command = "start"
      self._run_count += 1
      self._append_log(f"[controller] started process pid={process.pid}")
      self._reader_thread = threading.Thread(
        target=self._reader_loop,
        args=(process,),
        name="vertree-log-reader",
        daemon=True,
      )
      self._reader_thread.start()
      return self.status()

  def reload(self) -> dict[str, Any]:
    self._send_stdin_command("r", "reload")
    return self.status()

  def hot_restart(self) -> dict[str, Any]:
    self._send_stdin_command("R", "hot-restart")
    return self.status()

  def stop(self) -> dict[str, Any]:
    self._last_command = "stop"
    process = None
    with self._lock:
      if self._is_running_locked():
        assert self._process is not None
        process = self._process

    if process is not None:
      self._append_log("[controller] stopping app")
      self._write_to_process(process, "q\n")
      if not self._wait_for_exit(process, timeout_seconds=12):
        self._append_log("[controller] graceful stop timed out, terminating")
        process.terminate()
        if not self._wait_for_exit(process, timeout_seconds=6):
          self._append_log("[controller] terminate timed out, killing")
          process.kill()
          self._wait_for_exit(process, timeout_seconds=3)
    self._stop_local_docs()
    return self.status()

  def restart_process(self) -> dict[str, Any]:
    with self._lock:
      running = self._is_running_locked()
    if running:
      self.stop()
    self.start()
    return self.status()

  def ensure_ready(
    self,
    timeout_seconds: int | float | None = None,
    start_if_needed: bool = True,
  ) -> dict[str, Any]:
    if start_if_needed and not self._is_running():
      self.start()

    timeout_seconds = (
      float(timeout_seconds)
      if timeout_seconds is not None
      else float(self.config.startup_timeout_seconds)
    )
    deadline = time.time() + timeout_seconds
    last_error: str | None = None

    while time.time() < deadline:
      base_url = self._discover_api_base_url()
      if base_url is not None:
        health_url = f"{base_url}/health"
        try:
          payload = _http_json("GET", health_url)
          return {
            "ready": True,
            "appApiBaseUrl": base_url,
            "health": payload,
            "status": self.status(),
          }
        except Exception as exc:  # noqa: BLE001
          last_error = str(exc)
      time.sleep(1)

    return {
      "ready": False,
      "appApiBaseUrl": self._api_base_url,
      "lastError": last_error,
      "status": self.status(),
    }

  def logs(self, tail: int = 120) -> dict[str, Any]:
    with self._lock:
      lines = list(self._logs)[-tail:]
    return {
      "count": len(lines),
      "items": lines,
    }

  def _build_flutter_command(self) -> list[str]:
    extra_args = list(self.config.extra_flutter_args)
    if self.config.local_docs_enabled and self._docs_url:
      extra_args = [
        *extra_args,
        f"--dart-define=VERTREE_SHARE_PAGE_BASE_URL={self._docs_url}",
      ]
    command = [
      self.config.flutter_bin,
      "run",
      "-d",
      self.config.device,
      *extra_args,
    ]
    for app_arg in self.config.app_args:
      command.append(f"--dart-entrypoint-args={app_arg}")
    return command

  def _reader_loop(self, process: subprocess.Popen[str]) -> None:
    assert process.stdout is not None
    try:
      for raw_line in iter(process.stdout.readline, ""):
        line = raw_line.rstrip("\r\n")
        if not line:
          continue
        self._append_log(line)
        match = API_BASE_PATTERN.search(line)
        if match:
          with self._lock:
            self._api_base_url = match.group(1)
            self._api_port = int(match.group(2))
    finally:
      exit_code = process.poll()
      with self._lock:
        self._last_exited_at = time.time()
        self._last_exit_code = exit_code
        if self._process is process:
          self._process = None
      self._append_log(f"[controller] process exited code={exit_code}")

  def _docs_reader_loop(self, process: subprocess.Popen[str]) -> None:
    assert process.stdout is not None
    try:
      for raw_line in iter(process.stdout.readline, ""):
        line = raw_line.rstrip("\r\n")
        if not line:
          continue
        self._append_log(f"[docs] {line}")
    finally:
      exit_code = process.poll()
      with self._lock:
        self._docs_last_exited_at = time.time()
        self._docs_last_exit_code = exit_code
        if self._docs_process is process:
          self._docs_process = None
      self._append_log(f"[docs] process exited code={exit_code}")

  def _send_stdin_command(self, command: str, label: str) -> None:
    process = self._get_running_process()
    self._last_command = label
    self._append_log(f"[controller] sending command={label}")
    self._write_to_process(process, f"{command}\n")

  def _write_to_process(self, process: subprocess.Popen[str], value: str) -> None:
    if process.stdin is None:
      raise RuntimeError("app process stdin is not available")
    process.stdin.write(value)
    process.stdin.flush()

  def _get_running_process(self) -> subprocess.Popen[str]:
    with self._lock:
      if not self._is_running_locked():
        raise RuntimeError("app process is not running")
      assert self._process is not None
      return self._process

  def _wait_for_exit(self, process: subprocess.Popen[str], timeout_seconds: int) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
      if process.poll() is not None:
        return True
      time.sleep(0.25)
    return process.poll() is not None

  def _discover_api_base_url(self) -> str | None:
    with self._lock:
      candidate = self._api_base_url
    if candidate is not None:
      return candidate

    for port in range(self.config.api_port_start, self.config.api_port_end + 1):
      url = f"http://127.0.0.1:{port}/api/v1/health"
      try:
        payload = _http_json("GET", url, timeout_seconds=1)
        if payload.get("success") is True:
          base_url = f"http://127.0.0.1:{port}/api/v1"
          with self._lock:
            self._api_base_url = base_url
            self._api_port = port
          return base_url
      except Exception:  # noqa: BLE001
        continue
    return None

  def _is_running(self) -> bool:
    with self._lock:
      return self._is_running_locked()

  def _is_running_locked(self) -> bool:
    return self._process is not None and self._process.poll() is None

  def _append_log(self, line: str) -> None:
    with self._lock:
      self._logs.append(line)

  def _ensure_local_docs_locked(self) -> None:
    if not self.config.local_docs_enabled:
      return
    if self._docs_process is not None and self._docs_process.poll() is None:
      return

    docs_dir = self.config.project_root / "docs"
    if not docs_dir.exists():
      raise RuntimeError(f"docs directory not found: {docs_dir}")

    env = _augment_loopback_no_proxy_env(os.environ.copy())
    build_command = [self.config.npm_bin, "run", "build"]
    self._append_log("[docs] building local docs")
    build_result = subprocess.run(
      build_command,
      cwd=str(docs_dir),
      env=env,
      capture_output=True,
      text=True,
      encoding="utf-8",
      errors="replace",
      check=False,
    )
    for line in build_result.stdout.splitlines():
      if line.strip():
        self._append_log(f"[docs] {line}")
    for line in build_result.stderr.splitlines():
      if line.strip():
        self._append_log(f"[docs] {line}")
    if build_result.returncode != 0:
      raise RuntimeError(
        f"local docs build failed with code {build_result.returncode}"
      )

    docs_port, docs_url, reused_existing = _resolve_local_docs_endpoint(
      host=self.config.local_docs_host,
      preferred_port=self.config.local_docs_port,
      path=self.config.local_docs_path,
    )
    self.config.local_docs_port = docs_port
    self._docs_url = docs_url
    if reused_existing:
      self._append_log(f"[docs] reusing existing local docs at {docs_url}")
      return

    command = [
      self.config.npm_bin,
      "run",
      "serve",
      "--",
      "--host",
      self.config.local_docs_host,
      "--port",
      str(docs_port),
    ]
    process = subprocess.Popen(
      command,
      cwd=str(docs_dir),
      stdin=subprocess.DEVNULL,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
      text=True,
      bufsize=1,
      encoding="utf-8",
      errors="replace",
      env=env,
    )
    self._docs_process = process
    self._docs_last_started_at = time.time()
    self._docs_last_exited_at = None
    self._docs_last_exit_code = None
    self._append_log(f"[docs] started process pid={process.pid}")
    self._docs_reader_thread = threading.Thread(
      target=self._docs_reader_loop,
      args=(process,),
      name="vertree-docs-log-reader",
      daemon=True,
    )
    self._docs_reader_thread.start()

    docs_url = self._docs_url
    assert docs_url is not None
    deadline = time.time() + 60
    last_error: str | None = None
    while time.time() < deadline:
      if process.poll() is not None:
        raise RuntimeError(
          f"local docs process exited early with code {process.poll()}"
        )
      try:
        request = urllib.request.Request(url=docs_url, method="GET")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=2) as response:
          if 200 <= response.status < 500:
            self._append_log(f"[docs] ready at {docs_url}")
            return
      except Exception as exc:  # noqa: BLE001
        last_error = str(exc)
      time.sleep(1)

    raise RuntimeError(
      f"local docs did not become ready at {docs_url} in time: {last_error}"
    )

  def _stop_local_docs(self) -> None:
    with self._lock:
      process = self._docs_process
      if process is None or process.poll() is not None:
        return
      self._append_log("[docs] stopping local docs")

    process.terminate()
    if not self._wait_for_exit(process, timeout_seconds=8):
      self._append_log("[docs] terminate timed out, killing")
      process.kill()
      self._wait_for_exit(process, timeout_seconds=3)


class ControllerRequestHandler(BaseHTTPRequestHandler):
  controller: FlutterAppController | None = None
  request_queue: "queue.Queue[None]" = queue.Queue()

  def do_GET(self) -> None:  # noqa: N802
    try:
      if self.path == "/" or self.path == "":
        self._write_json(
          200,
          {
            "name": "Vertree Dev Control Server",
            "routes": [
              "GET /status",
              "GET /logs?tail=120",
              "POST /start",
              "POST /reload",
              "POST /hot-restart",
              "POST /restart-process",
              "POST /stop",
              "POST /ensure-ready",
            ],
          },
        )
        return

      if self.path.startswith("/status"):
        self._write_json(200, self._controller().status())
        return

      if self.path.startswith("/logs"):
        tail = 120
        if "?" in self.path:
          query = self.path.split("?", 1)[1]
          for part in query.split("&"):
            if part.startswith("tail="):
              try:
                tail = max(1, int(part.split("=", 1)[1]))
              except ValueError:
                tail = 120
        self._write_json(200, self._controller().logs(tail=tail))
        return

      self._write_json(404, {"error": "not found", "path": self.path})
    except Exception as exc:  # noqa: BLE001
      self._write_json(500, {"error": str(exc)})

  def do_POST(self) -> None:  # noqa: N802
    try:
      body = self._read_json_body()
      if self.path == "/start":
        self._write_json(200, self._controller().start())
        return
      if self.path == "/reload":
        self._write_json(200, self._controller().reload())
        return
      if self.path == "/hot-restart":
        self._write_json(200, self._controller().hot_restart())
        return
      if self.path == "/restart-process":
        self._write_json(200, self._controller().restart_process())
        return
      if self.path == "/stop":
        self._write_json(200, self._controller().stop())
        return
      if self.path == "/ensure-ready":
        timeout_seconds = body.get("timeoutSeconds")
        start_if_needed = body.get("startIfNeeded", True)
        self._write_json(
          200,
          self._controller().ensure_ready(
            timeout_seconds=timeout_seconds,
            start_if_needed=bool(start_if_needed),
          ),
        )
        return

      self._write_json(404, {"error": "not found", "path": self.path})
    except Exception as exc:  # noqa: BLE001
      self._write_json(500, {"error": str(exc)})

  def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
    return

  def _controller(self) -> FlutterAppController:
    if self.controller is None:
      raise RuntimeError("controller not configured")
    return self.controller

  def _read_json_body(self) -> dict[str, Any]:
    length = int(self.headers.get("Content-Length", "0") or "0")
    if length <= 0:
      return {}
    raw = self.rfile.read(length).decode("utf-8")
    if not raw.strip():
      return {}
    decoded = json.loads(raw)
    if isinstance(decoded, dict):
      return decoded
    raise ValueError("JSON body must be an object")

  def _write_json(self, status: int, payload: dict[str, Any]) -> None:
    encoded = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    self.send_response(status)
    self.send_header("Content-Type", "application/json; charset=utf-8")
    self.send_header("Cache-Control", "no-store")
    self.send_header("Content-Length", str(len(encoded)))
    self.end_headers()
    self.wfile.write(encoded)


def _http_json(method: str, url: str, timeout_seconds: int | float = 5) -> dict[str, Any]:
  request = urllib.request.Request(url=url, method=method)
  parsed = urllib.parse.urlparse(url)
  if parsed.hostname in LOOPBACK_NO_PROXY_TOKENS:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    response_cm = opener.open(request, timeout=float(timeout_seconds))
  else:
    response_cm = urllib.request.urlopen(request, timeout=float(timeout_seconds))

  with response_cm as response:
    raw = response.read().decode("utf-8")
  decoded = json.loads(raw)
  if isinstance(decoded, dict):
    return decoded
  raise ValueError(f"Expected JSON object from {url}")


def _http_json_or_none(
  method: str,
  url: str,
  timeout_seconds: int | float = 5,
) -> dict[str, Any] | None:
  try:
    return _http_json(method, url, timeout_seconds=timeout_seconds)
  except Exception:  # noqa: BLE001
    return None


def _can_open_url(url: str, timeout_seconds: int | float = 2) -> bool:
  try:
    parsed = urllib.parse.urlparse(url)
    request = urllib.request.Request(url=url, method="GET")
    opener = urllib.request.build_opener(
      urllib.request.ProxyHandler(
        {} if parsed.hostname in LOOPBACK_NO_PROXY_TOKENS else None
      )
    )
    with opener.open(request, timeout=float(timeout_seconds)) as response:
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


def _resolve_local_docs_endpoint(
  *,
  host: str,
  preferred_port: int,
  path: str,
) -> tuple[int, str, bool]:
  preferred_url = f"http://{host}:{preferred_port}{path}"
  if _can_open_url(preferred_url):
    return preferred_port, preferred_url, True

  if _is_tcp_port_in_use(host, preferred_port):
    next_port = _find_next_available_port(host, preferred_port + 1)
    return next_port, f"http://{host}:{next_port}{path}", False

  return preferred_port, preferred_url, False


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


def _resolve_flutter_bin(flutter_bin: str) -> str:
  candidate = shutil.which(flutter_bin)
  if candidate is not None:
    return candidate

  if os.name == "nt" and "." not in Path(flutter_bin).name:
    bat_candidate = shutil.which(f"{flutter_bin}.bat")
    if bat_candidate is not None:
      return bat_candidate

    cmd_candidate = shutil.which(f"{flutter_bin}.cmd")
    if cmd_candidate is not None:
      return cmd_candidate

  return flutter_bin


def _resolve_command_bin(command_bin: str) -> str:
  candidate = shutil.which(command_bin)
  if candidate is not None:
    return candidate

  if os.name == "nt" and "." not in Path(command_bin).name:
    cmd_candidate = shutil.which(f"{command_bin}.cmd")
    if cmd_candidate is not None:
      return cmd_candidate

    bat_candidate = shutil.which(f"{command_bin}.bat")
    if bat_candidate is not None:
      return bat_candidate

  return command_bin


def _controller_base_url(host: str, port: int) -> str:
  return f"http://{host}:{port}"


def _spawn_detached_controller(script_path: Path, args: argparse.Namespace) -> None:
  env = _augment_loopback_no_proxy_env(os.environ.copy())
  command = [
    sys.executable,
    str(script_path),
    "--host",
    args.host,
    "--port",
    str(args.port),
    "--flutter-bin",
    _resolve_flutter_bin(args.flutter_bin),
    "--device",
    args.device,
    "--project-root",
    str(Path(args.project_root).resolve()),
    "--startup-timeout",
    str(args.startup_timeout),
  ]
  if args.local_docs:
    command.append("--local-docs")
    command.extend(["--local-docs-host", args.local_docs_host])
    command.extend(["--local-docs-port", str(args.local_docs_port)])
    command.extend(["--npm-bin", _resolve_command_bin(args.npm_bin)])
  for extra_arg in args.extra_flutter_arg:
    command.extend(["--extra-flutter-arg", extra_arg])
  for app_arg in args.app_arg:
    command.extend(["--app-arg", app_arg])

  popen_kwargs: dict[str, Any] = {
    "cwd": str(Path(args.project_root).resolve()),
    "stdin": subprocess.DEVNULL,
    "stdout": subprocess.DEVNULL,
    "stderr": subprocess.DEVNULL,
    "env": env,
  }

  if os.name == "nt":
    popen_kwargs["creationflags"] = (
      subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
    )
  else:
    popen_kwargs["start_new_session"] = True

  subprocess.Popen(command, **popen_kwargs)


def _bootstrap_controller(script_path: Path, args: argparse.Namespace) -> int:
  controller_url = _controller_base_url(args.host, args.port)
  status_url = f"{controller_url}/status"
  start_url = f"{controller_url}/start"

  status = _http_json_or_none("GET", status_url, timeout_seconds=2)
  if status is None:
    _spawn_detached_controller(script_path, args)
    deadline = time.time() + 15
    while time.time() < deadline:
      status = _http_json_or_none("GET", status_url, timeout_seconds=2)
      if status is not None:
        break
      time.sleep(0.5)

  if status is None:
    _safe_print(
      json.dumps(
        {
          "ok": False,
          "message": "Controller did not start in time",
          "controllerUrl": controller_url,
        },
        ensure_ascii=False,
      )
    )
    return 1

  if status.get("running") is not True:
    request = urllib.request.Request(
      url=start_url,
      method="POST",
      data=b"{}",
      headers={"Content-Type": "application/json"},
    )
    parsed = urllib.parse.urlparse(start_url)
    opener = urllib.request.build_opener(
      urllib.request.ProxyHandler({} if parsed.hostname in LOOPBACK_NO_PROXY_TOKENS else None)
    )
    with opener.open(request, timeout=10) as response:
      status = json.loads(response.read().decode("utf-8"))

  deadline = time.time() + float(args.startup_timeout)
  last_error: str | None = None
  payload: dict[str, Any] | None = None
  while time.time() < deadline:
    status = _http_json_or_none("GET", status_url, timeout_seconds=2)
    if status is None:
      last_error = "Controller became unreachable"
      time.sleep(1)
      continue

    base_url = status.get("appApiBaseUrl")
    if isinstance(base_url, str) and base_url:
      health = _http_json_or_none("GET", f"{base_url}/health", timeout_seconds=2)
      if health is not None and health.get("success") is True:
        payload = {
          "ready": True,
          "appApiBaseUrl": base_url,
          "health": health,
          "status": status,
        }
        break
      last_error = f"App API discovered but health check failed at {base_url}/health"
    else:
      last_error = "Waiting for app API base URL to appear in controller status"
    time.sleep(1)

  if payload is None:
    payload = {
      "ready": False,
      "controllerUrl": controller_url,
      "lastError": last_error,
      "status": status,
    }

  _safe_print(json.dumps(payload, ensure_ascii=False, indent=2))
  return 0 if payload.get("ready") is True else 1


def _iso_or_none(timestamp: float | None) -> str | None:
  if timestamp is None:
    return None
  return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(timestamp))


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description="Vertree development control server")
  parser.add_argument(
    "--bootstrap",
    action="store_true",
    help="Start the controller in the background if needed and wait until the app API is ready.",
  )
  parser.add_argument("--host", default="127.0.0.1")
  parser.add_argument("--port", type=int, default=32500)
  parser.add_argument("--flutter-bin", default="flutter")
  parser.add_argument("--device", default="windows")
  parser.add_argument("--project-root", default=str(Path(__file__).resolve().parent))
  parser.add_argument("--startup-timeout", type=int, default=120)
  parser.add_argument(
    "--local-docs",
    action="store_true",
    help="Start local Docusaurus docs and point LAN share page URLs to it.",
  )
  parser.add_argument("--local-docs-host", default="127.0.0.1")
  parser.add_argument("--local-docs-port", type=int, default=33030)
  parser.add_argument("--npm-bin", default="npm")
  parser.add_argument("--extra-flutter-arg", action="append", default=[])
  parser.add_argument(
    "--app-arg",
    action="append",
    default=[],
    help="Argument forwarded to the Flutter desktop app after `--`.",
  )
  return parser.parse_args()


def main() -> int:
  _augment_loopback_no_proxy_env(os.environ)
  script_path = Path(__file__).resolve()
  args = parse_args()
  if args.bootstrap:
    return _bootstrap_controller(script_path, args)

  config = ControllerConfig(
    project_root=Path(args.project_root).resolve(),
    flutter_bin=_resolve_flutter_bin(args.flutter_bin),
    device=args.device,
    controller_host=args.host,
    controller_port=args.port,
    startup_timeout_seconds=args.startup_timeout,
    local_docs_enabled=bool(args.local_docs),
    local_docs_host=args.local_docs_host,
    local_docs_port=args.local_docs_port,
    npm_bin=_resolve_command_bin(args.npm_bin),
    extra_flutter_args=list(args.extra_flutter_arg),
    app_args=list(args.app_arg),
  )
  controller = FlutterAppController(config)
  ControllerRequestHandler.controller = controller

  server = ThreadingHTTPServer((config.controller_host, config.controller_port), ControllerRequestHandler)
  _safe_print(
    json.dumps(
      {
        "message": "Vertree dev control server started",
        "controllerUrl": f"http://{config.controller_host}:{config.controller_port}",
        "projectRoot": str(config.project_root),
        "flutterCommand": controller.status()["flutterCommand"],
      },
      ensure_ascii=False,
    )
  )

  try:
    server.serve_forever()
  except KeyboardInterrupt:
    pass
  finally:
    try:
      controller.stop()
    except Exception:  # noqa: BLE001
      pass
    server.server_close()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
