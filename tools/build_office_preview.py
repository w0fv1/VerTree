"""Build the pinned Office Viewer frontend into Flutter's bundled assets."""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-install', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if not (root / 'vendor/office-viewer/office-viewer-app/src/viewers/registry.ts').is_file():
        subprocess.run(['git', 'submodule', 'update', '--init', 'vendor/office-viewer'], cwd=root, check=True)
    npm = shutil.which('npm.cmd') or shutil.which('npm')
    if not npm:
        raise SystemExit('Install Node.js 22.12+ (or Node.js 24) before building previews.')
    frontend = root / 'web/office_preview'
    if not args.skip_install:
        subprocess.run([npm, 'ci', '--no-audit', '--no-fund'], cwd=frontend, check=True)
    subprocess.run([npm, 'run', 'build'], cwd=frontend, check=True)
    for directory in [root / 'assets/office_viewer', root / 'assets/office_viewer/assets']:
        (directory / '.gitkeep').touch()


if __name__ == '__main__':
    main()
