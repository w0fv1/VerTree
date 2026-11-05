# Filee runtime packaging

The conversion runtime is built from the pinned `vendor/filee-source` submodule. Initialize it with `git submodule update --init vendor/filee-source` and install the .NET SDK required by its `global.json`.

Build with `pwsh tools/build_filee_runtime.ps1 <runtime>` or `bash tools/build_filee_runtime.sh <runtime>`. The scripts default to the pinned source and place self-contained output and its license under `vendor/filee/<runtime>`.

Release targets and real conversion checks are defined in [the release workflow](../.github/workflows/release.yml). [The runtime smoke test](../tools/test_filee_runtime.py) verifies format discovery, PNG-to-WebP output and source preservation before packaging.

The bundled CLI and managed/native package dependencies do not require a user-installed .NET runtime. Optional external engines are not bundled by these scripts; their formats depend on engine availability. Format support is resolved by the runtime, not a separate documented list.
