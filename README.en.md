# Vertree

[Documentation](https://vertree.w0fv1.dev/docs/intro) · [Download](https://github.com/w0fv1/VerTree/releases/latest) · [Supported formats](docs/docs/tutorial-usage/preview.md) · [Troubleshooting](docs/docs/tutorial-usage/troubleshooting.md) · [Build guide](docs/docs/tutorial-develop/develop.md)

File previews use the bundled Office Viewer frontend (embedded on Windows/macOS, local browser on Linux). Before the first Flutter build, install Node.js 24 and Python 3 and run `python tools/build_office_preview.py`. Windows additionally needs NuGet CLI for building and WebView2 Runtime for viewing. See [integration notes](docs/office-preview.md).

Vertree is a desktop version manager for single files. It is meant for evolving design files, documents, scripts, and config files that do not fit cleanly into a normal Git workflow. Vertree keeps history as plain files, draws the file lineage as a tree, and exposes native desktop entry points so the workflow stays close to how people already work.

![Version tree overview](docs/static/img/version-tree-overview.png)

## 2.0.0

Version commands and file writes now share one backend across UI, CLI, tray and HTTP. Automatic snapshots have task UUIDs and ownership manifests; failed monitoring retries without losing subsequent changes. Windows MSI shortcut destinations are corrected and installation is checked before release.

**Breaking upgrade:** settings move to settings.json; old configuration and *_bak snapshots are not imported. Reconfigure preferences and monitoring after upgrading. Manual version files remain readable. The local API uses /versions and /snapshots; old backup routes are removed.

[Release notes](https://github.com/w0fv1/VerTree/releases/tag/V2.0.0)

## What It Does

- Visual version tree for a single file and its branches
- Manual backup and express backup
- File monitoring with owned snapshots under `.vertree/snapshots`
- Native entry points on Windows, macOS, and Linux GNOME
- Local loopback-only HTTP API for automation and verification
- Temporary LAN file sharing with a short share page and QR code

## Local Automation

The local HTTP API is disabled by default. Enable it in Settings and copy the actual loopback address and the token for the current session. Business requests require `Authorization: Bearer <token>`. Only the index, documentation, and minimal `/ping` endpoint are public.

- `GET /api/v1/health`
- `POST /api/v1/ui/navigation`
- `POST /api/v1/ui/window-state`
- `POST /api/v1/ui/theme-mode`
- `POST /api/v1/ui/file-tree/viewport`
- `POST /api/v1/ui/screenshot`

The `health` payload now includes the current UI page, theme setting, effective light/dark state, and whether startup announcement dialogs were suppressed for the current session.

## Screenshot-Friendly Startup

For documentation screenshots or scripted demos, you can start Vertree with:

```bash
python dev_server.py --bootstrap --device windows --app-arg --no-announcement
```

That runtime flag disables the startup announcement dialog so it does not pollute screenshots.

## Documentation Screenshots

Use the repository script below to refresh the docs screenshots:

```bash
python tools/update_doc_images.py
```

The script drives the local UI through the HTTP API and defaults normal documentation screenshots to light mode. Dark mode screenshots should only be used where the dark theme itself is being explained.

## More Docs

- Chinese README: [README.md](README.md)
- Docs site: https://vertree.w0fv1.dev/
- Local docs guide: [docs/README.md](docs/README.md)

## License

MIT. See [LICENSE](LICENSE).
