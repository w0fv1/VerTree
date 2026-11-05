#!/usr/bin/env bash
set -euo pipefail
runtime="${1:-linux-x64}"
root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${2:-$root/vendor/filee-source}"
destination="$root/vendor/filee/$runtime"
mkdir -p "$destination"
dotnet publish "$source_dir/src/Filee.Cli/Filee.Cli.csproj" -c Release -r "$runtime" --self-contained true -p:DebugSymbols=false -p:DebugType=None -o "$destination"

cp "$source_dir/LICENSE" "$destination/LICENSE-Filee.txt"
