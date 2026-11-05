param(
  [ValidateSet('win-x64','osx-x64','osx-arm64','linux-x64','linux-arm64')]
  [string]$Runtime = 'win-x64',
  [string]$FileeSource = (Join-Path $PSScriptRoot '..\vendor\filee-source')
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$destination = Join-Path $root "vendor\filee\$Runtime"
New-Item -ItemType Directory -Force $destination | Out-Null
$project = Join-Path $FileeSource 'src\Filee.Cli\Filee.Cli.csproj'
dotnet publish $project -c Release -r $Runtime --self-contained true -p:DebugSymbols=false -p:DebugType=None -o $destination

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item (Join-Path $FileeSource 'LICENSE') (Join-Path $destination 'LICENSE-Filee.txt') -Force
