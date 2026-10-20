# Filee runtime packaging

The conversion page executes the Filee CLI beside the app. Build one self-contained runtime for each release target before packaging:

- Windows: `pwsh tools/build_filee_runtime.ps1 win-x64`
- macOS Intel: `pwsh tools/build_filee_runtime.ps1 osx-x64`
- macOS Apple Silicon: `pwsh tools/build_filee_runtime.ps1 osx-arm64`
- Linux x64: `./tools/build_filee_runtime.sh linux-x64`
- Linux ARM64: `./tools/build_filee_runtime.sh linux-arm64`

The resulting files live under `vendor/filee/<runtime>` and must be included beside the installed Vertree executable. The runtime is self-contained, so users do not install or configure .NET, FFmpeg, ImageMagick, or other conversion engines.
