# Vertree Agent Notes

## Scope

- This repo contains a Flutter desktop app.
- The app exposes a local loopback HTTP API for monitoring, backup, version-tree inspection, and test-oriented verification.
- A separate local dev controller can own a `flutter run` subprocess and send reload / restart commands.

## Control Surface

- Dev controller script: [dev_control_server.py](/dev_control_server.py)
- Default controller URL: `http://127.0.0.1:32500`
- Controller endpoints:
  - `GET /status`
  - `GET /logs`
  - `POST /start`
  - `POST /reload`
  - `POST /hot-restart`
  - `POST /restart-process`
  - `POST /stop`
  - `POST /ensure-ready`

## App API

- Default app API base: `http://127.0.0.1:31414/api/v1`
- The app binds to loopback only.
- If `31414` is occupied, the port auto-increments.
- Prefer discovering the live base URL from controller `GET /status` or `POST /ensure-ready`.
- API metadata endpoints:
  - `GET /api/v1`
  - `GET /api/v1/openapi.json`
  - `GET /api/v1/docs`

## Testing Data

- Canonical sample data lives under `.sample/file_version_tree`.

## Conventions

- Prefer `reload` for ordinary Dart/UI changes.
- Prefer `hot-restart` when initialization or route registration changes.
- Prefer full process restart for platform-layer or startup-behavior changes.
- When calling loopback URLs from shell tools, avoid system proxy interference.

## Boundary

- The dev controller reliably controls only the `flutter run` process it started itself.
- It should not be assumed to safely take over an unrelated terminal session started by a user.
