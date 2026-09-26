"""Explicit cache-only adapter for Flutter plugins' bounded NuGet install calls.

Not a general NuGet replacement. Enabled only with VERTREE_NUGET_CACHE_ONLY=1.
Verifies cached .nupkg SHA-512, rejects traversal/symlinks, writes only this
checkout's generated build directory, and never downloads or changes the cache.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def install(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['install'])
    parser.add_argument('package')
    parser.add_argument('-Version', required=True)
    parser.add_argument('-ExcludeVersion', action='store_true', required=True)
    parser.add_argument('-OutputDirectory', required=True)
    parser.add_argument('-NonInteractive', action='store_true')
    options = parser.parse_args(argv)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,150}', options.package):
        raise ValueError('Invalid package ID')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9A-Za-z-]+){1,5}', options.Version):
        raise ValueError('An exact package version is required')
    cache = Path(os.environ.get('NUGET_PACKAGES', str(Path.home() / '.nuget' / 'packages')))
    name, version = options.package.lower(), options.Version.lower()
    source = cache / name / version / f'{name}.{version}.nupkg'
    expected_file = source.with_name(source.name + '.sha512')
    if not source.is_file() or not expected_file.is_file():
        raise FileNotFoundError(f'Exact package missing from the local cache: {name} {version}. '
                                'Restore it using NuGet; this adapter never downloads packages.')
    expected = base64.b64decode(expected_file.read_text(encoding='utf-8-sig').strip(), validate=True)
    with source.open('rb') as archive:
        actual = hashlib.file_digest(archive, 'sha512').digest()
    if actual != expected:
        raise ValueError(f'Cached package failed SHA-512 verification: {name} {version}')
    destination = Path(options.OutputDirectory).resolve() / options.package
    build = (ROOT / 'build').resolve()
    if not destination.is_relative_to(build):
        raise ValueError('Offline package output must remain within this checkout/build')
    destination.mkdir(parents=True, exist_ok=True)
    total = 0
    with zipfile.ZipFile(source) as package:
        for info in package.infolist():
            relative = PurePosixPath(info.filename.replace('\\', '/'))
            if relative.is_absolute() or '..' in relative.parts or any(':' in part for part in relative.parts):
                raise ValueError('Unsafe path in cached package')
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Symlink in cached package is not supported')
            target = destination.joinpath(*relative.parts)
            if not target.resolve().is_relative_to(destination.resolve()) or target.is_symlink():
                raise ValueError('Package output would escape through a link')
            total += info.file_size
            if total > 1024 * 1024 * 1024:
                raise ValueError('Cached package exceeds the unpacking budget')
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            content = package.read(info)
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                if not target.is_file() or target.read_bytes() != content:
                    raise ValueError(f'Existing generated file differs from verified cache: {target}')
            else:
                with target.open('xb') as output:
                    output.write(content)
    print(f'Cache-only NuGet: verified {options.package} {options.Version}; {total} bytes -> {destination}')


if __name__ == '__main__':
    try:
        install(sys.argv[1:])
    except Exception as error:
        print(f'Cache-only NuGet failed: {error}', file=sys.stderr)
        raise SystemExit(1)
