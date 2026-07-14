param(
    [ValidateSet("Debug","Profile","Release")]
    [string]$BuildMode = "Release",
    [switch]$Sparse,
    [switch]$SparseRefresh,
    [string]$Flutter = "",
    [string]$ISCC = "",
    [string]$WixBin = "",
    [string]$MakeAppx = "",
    [string]$SignTool = "",
    [string]$MsixCertificatePath = "",
    [string]$MsixCertificatePassword = "",
    [string]$Target = "lib/main.dart"
)


$innoSetupCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$flutterDefault = "C:\flutter\bin\flutter.bat"

function Resolve-ToolPath([string]$preferred, [string]$fallbackPath, [string]$commandName) {
    if (-not [string]::IsNullOrWhiteSpace($preferred)) {
        return $preferred
    }
    $cmd = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($cmd) {
        return $commandName
    }
    if (-not [string]::IsNullOrWhiteSpace($fallbackPath) -and (Test-Path $fallbackPath)) {
        return $fallbackPath
    }
    return ""
}

function Get-PubspecVersion([string]$projectRoot) {
    $pubspec = Join-Path $projectRoot "pubspec.yaml"
    if (-not (Test-Path $pubspec)) {
        throw "pubspec.yaml not found at $pubspec"
    }
    $line = Select-String -Path $pubspec -Pattern '^\s*version:\s*(.+?)\s*$' | Select-Object -First 1
    if (-not $line) {
        throw "pubspec.yaml missing 'version:'"
    }
    $raw = $line.Matches[0].Groups[1].Value
    return $raw.Trim().Trim("'").Trim('"')
}

function Get-VersionInfoVersion([string]$pubspecVersion) {
    $base = $pubspecVersion.Split('-')[0]
    $parts = $base.Split('.')
    if ($parts.Length -eq 3) {
        return ($base + ".0")
    }
    if ($parts.Length -eq 4) {
        return $base
    }

    return "0.0.0.0"
}

function Get-MsiProductVersion([string]$pubspecVersion) {
    $baseVersion = $pubspecVersion
    $preRelease = ""
    if ($pubspecVersion.Contains('-')) {
        $parts = $pubspecVersion.Split('-', 2)
        $baseVersion = $parts[0]
        $preRelease = $parts[1]
    }

    $baseParts = $baseVersion.Split('.')
    if ($baseParts.Length -lt 3) {
        return "0.0.0"
    }

    $major = [int]$baseParts[0]
    $minor = [int]$baseParts[1]
    $patch = [int]$baseParts[2]

    $patchBucket = $patch * 100
    $preOffset = 99
    if (-not [string]::IsNullOrWhiteSpace($preRelease)) {
        $preLower = $preRelease.ToLowerInvariant()
        $baseWeight = 0
        if ($preLower.StartsWith("alpha")) {
            $baseWeight = 0
        } elseif ($preLower.StartsWith("beta")) {
            $baseWeight = 30
        } elseif ($preLower.StartsWith("rc")) {
            $baseWeight = 60
        } else {
            $baseWeight = 80
        }

        $match = [regex]::Match($preLower, '(\d+)$')
        $ordinal = if ($match.Success) { [int]$match.Groups[1].Value } else { 0 }
        $preOffset = [Math]::Min($baseWeight + $ordinal, 98)
    }

    return "$major.$minor.$($patchBucket + $preOffset)"
}

function Get-MsixPackageVersion([string]$pubspecVersion) {
    $msiVersion = Get-MsiProductVersion -pubspecVersion $pubspecVersion
    $parts = $msiVersion.Split('.')
    if ($parts.Length -eq 3) {
        return "$msiVersion.0"
    }
    if ($parts.Length -eq 4) {
        return $msiVersion
    }
    return "0.0.0.0"
}

function Resolve-WixBin([string]$preferred) {
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and (Test-Path $preferred)) {
        return $preferred
    }

    $candleCmd = Get-Command candle.exe -ErrorAction SilentlyContinue
    $lightCmd = Get-Command light.exe -ErrorAction SilentlyContinue
    $heatCmd = Get-Command heat.exe -ErrorAction SilentlyContinue
    if ($candleCmd -and $lightCmd -and $heatCmd) {
        return Split-Path -Parent $candleCmd.Source
    }

    foreach ($candidate in @(
        "C:\Program Files (x86)\WiX Toolset v3.14\bin",
        "C:\Program Files (x86)\WiX Toolset v3.11\bin"
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return ""
}

function Resolve-MakeAppx([string]$preferred) {
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and (Test-Path $preferred)) {
        return $preferred
    }

    $cmd = Get-Command makeappx.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $kitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path $kitsRoot)) {
        return ""
    }

    $candidates = Get-ChildItem -Path $kitsRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
        Sort-Object FullName -Descending
    if ($candidates) {
        return $candidates[0].FullName
    }

    return ""
}

function Resolve-SignTool([string]$preferred) {
    if (-not [string]::IsNullOrWhiteSpace($preferred) -and (Test-Path $preferred)) {
        return $preferred
    }

    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $kitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path $kitsRoot)) {
        return ""
    }

    $candidates = Get-ChildItem -Path $kitsRoot -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending
    if ($candidates) {
        return $candidates[0].FullName
    }

    return ""
}

function Escape-XmlAttribute([string]$value) {
    if ($null -eq $value) {
        return ""
    }
    return [System.Security.SecurityElement]::Escape($value)
}

function New-SparseIdentityPackage(
    [string]$sourceSparseDir,
    [string]$outputDir,
    [string]$packageVersion,
    [string]$makeAppxPreferred,
    [string]$signToolPreferred,
    [string]$certificatePath,
    [string]$certificatePassword
) {
    if ([string]::IsNullOrWhiteSpace($certificatePath)) {
        $certificatePath = $env:VERTREE_MSIX_CERTIFICATE_PATH
    }
    if ([string]::IsNullOrWhiteSpace($certificatePassword)) {
        $certificatePassword = $env:VERTREE_MSIX_CERTIFICATE_PASSWORD
    }
    $allowUnsignedSparse = ($env:VERTREE_ENABLE_UNSIGNED_MSIX -eq '1')
    if ([string]::IsNullOrWhiteSpace($certificatePath) -and -not $allowUnsignedSparse) {
        Write-Host "跳过 Win11 sparse MSIX；如需终端设备可注册的新菜单包，请提供 MSIX 签名证书。"
        return ""
    }

    if (-not (Test-Path $sourceSparseDir)) {
        Write-Warning "未找到 sparse manifest 目录，跳过 Win11 sparse MSIX: $sourceSparseDir"
        return ""
    }

    $makeAppxExe = Resolve-MakeAppx -preferred $makeAppxPreferred
    if ([string]::IsNullOrWhiteSpace($makeAppxExe)) {
        Write-Warning "未找到 MakeAppx.exe，跳过 Win11 sparse MSIX。"
        return ""
    }

    $stageRoot = Join-Path $scriptDir "..\\build\\windows\\sparse_identity"
    $stageDir = Join-Path $stageRoot "package"
    $manifestPath = Join-Path $stageDir "AppxManifest.xml"
    $packagePath = Join-Path $outputDir "VertreeSparse.msix"

    if (Test-Path $stageDir) {
        Remove-Item $stageDir -Recurse -Force
    }
    if (Test-Path $packagePath) {
        Remove-Item $packagePath -Force
    }

    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    Copy-Item (Join-Path $sourceSparseDir "*") $stageDir -Recurse -Force

    if (-not (Test-Path $manifestPath)) {
        Write-Warning "未找到 sparse AppxManifest.xml，跳过 Win11 sparse MSIX。"
        return ""
    }

    $manifestContent = Get-Content $manifestPath -Raw
    $manifestContent = $manifestContent.Replace('Version="1.0.0.0"', "Version=`"$packageVersion`"")
    [System.IO.File]::WriteAllText(
        $manifestPath,
        $manifestContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $makeAppxExe pack /o /nv /d $stageDir /p $packagePath | Out-Null
    if ($LASTEXITCODE -ne 0 -or (-not (Test-Path $packagePath))) {
        Write-Warning "Win11 sparse MSIX 打包失败，已跳过。"
        $global:LASTEXITCODE = 0
        return ""
    }

    if (-not [string]::IsNullOrWhiteSpace($certificatePath)) {
        if (-not (Test-Path $certificatePath)) {
            Write-Warning "MSIX 证书不存在，保留未签名 sparse MSIX: $certificatePath"
            return $packagePath
        }

        $signToolExe = Resolve-SignTool -preferred $signToolPreferred
        if ([string]::IsNullOrWhiteSpace($signToolExe)) {
            Write-Warning "未找到 SignTool.exe，保留未签名 sparse MSIX。"
            return $packagePath
        }

        $signArgs = @("sign", "/fd", "SHA256", "/f", $certificatePath)
        if (-not [string]::IsNullOrWhiteSpace($certificatePassword)) {
            $signArgs += @("/p", $certificatePassword)
        }
        $signArgs += $packagePath
        & $signToolExe @signArgs | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Win11 sparse MSIX 已签名：" $packagePath
        } else {
            Write-Warning "Win11 sparse MSIX 签名失败，保留未签名包。"
            $global:LASTEXITCODE = 0
        }
    } else {
        Write-Warning "Win11 sparse MSIX 未签名；终端设备通常需要受信任签名后才能注册。"
    }

    return $packagePath
}


$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$currentDir = Get-Location


$projectRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
Set-Location $projectRoot

$flutterCmd = Resolve-ToolPath -preferred $Flutter -fallbackPath $flutterDefault -commandName "flutter"
if ([string]::IsNullOrWhiteSpace($flutterCmd)) {
    throw "Flutter not found. Provide -Flutter <path> or ensure 'flutter' is in PATH."
}

$pubspecVersion = Get-PubspecVersion -projectRoot $projectRoot
$versionInfoVersion = Get-VersionInfoVersion -pubspecVersion $pubspecVersion
$msiProductVersion = Get-MsiProductVersion -pubspecVersion $pubspecVersion
$msixPackageVersion = Get-MsixPackageVersion -pubspecVersion $pubspecVersion
$setupBaseName = "vertree-windows-x64-$pubspecVersion-setup"
$zipBaseName = "vertree-windows-x64-$pubspecVersion"
$msiBaseName = "vertree-windows-x64-$pubspecVersion"
$msixBaseName = "vertree-windows-x64-$pubspecVersion"
$symbolsBaseName = "vertree-windows-x64-$pubspecVersion-symbols"
$win11DevBaseName = "vertree-windows-x64-$pubspecVersion-win11-dev"
Write-Host "pubspec.yaml version=$pubspecVersion"
Write-Host "VersionInfoVersion=$versionInfoVersion"
Write-Host "MsiProductVersion=$msiProductVersion"
Write-Host "MsixPackageVersion=$msixPackageVersion"
Write-Host "Windows setup artifact=$setupBaseName.exe"
Write-Host "Windows zip artifact=$zipBaseName.zip"
Write-Host "Windows MSI artifact=$msiBaseName.msi"
Write-Host "Windows MSIX artifact=$msixBaseName.msix"
Write-Host "Windows symbols artifact=$symbolsBaseName.zip"
Write-Host "Windows Win11 dev artifact=$win11DevBaseName.zip"

Write-Host "正在执行 flutter build windows ($BuildMode)..."
& $flutterCmd build windows --target $Target --$($BuildMode.ToLower())

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter编译失败，请检查错误日志。"
    Set-Location $currentDir
    exit $LASTEXITCODE
}


Set-Location $scriptDir


$issFile = Join-Path $scriptDir "setup.iss"
$runnerOutputDir = (Resolve-Path (Join-Path $scriptDir "..\\build\\windows\\x64\\runner\\$BuildMode")).Path


$contextMenuDll = Join-Path $scriptDir "..\\build\\windows\\x64\\context_menu\\$BuildMode\\vertree_context_menu.dll"
$runnerDll = Join-Path $runnerOutputDir "vertree_context_menu.dll"
if (Test-Path $contextMenuDll) {
    try {
        Copy-Item $contextMenuDll $runnerDll -Force -ErrorAction Stop
        Write-Host "已复制右键菜单 DLL 到 Runner 目录"
    } catch {
        Write-Warning "复制右键菜单 DLL 失败（可能被 Explorer/DllHost 占用），尝试释放占用并重试..."
        try {
            try {
                & taskkill.exe /F /IM dllhost.exe /FI "MODULES eq vertree_context_menu.dll" | Out-Null
                Write-Host "已尝试结束加载 vertree_context_menu.dll 的 DllHost"
            } catch {
                Write-Warning "结束 DllHost 失败（可忽略）：$($_.Exception.Message)"
            }

            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            try {
                Copy-Item $contextMenuDll $runnerDll -Force -ErrorAction Stop
                Write-Host "已复制右键菜单 DLL 到 Runner 目录"
            } catch {
                Write-Warning "重启 Explorer 后仍无法复制 DLL（可能仍被占用）。"
            } finally {
                Start-Process explorer.exe | Out-Null
            }
            Write-Host "已重启 Explorer 并复制 DLL"
        } catch {
            Write-Warning "重启 Explorer 后仍无法复制 DLL，请手动重启后重试构建。"
        }
    }
}



$packagingSourceDir = Join-Path $scriptDir "packaging"
$packagingTargetDir = Join-Path $scriptDir "..\\build\\windows\\x64\\runner\\$BuildMode\\win11_packaging"
if (Test-Path $packagingSourceDir) {
    try {
        if (Test-Path $packagingTargetDir) {
            Remove-Item $packagingTargetDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $packagingTargetDir | Out-Null
        Copy-Item (Join-Path $packagingSourceDir "*") $packagingTargetDir -Recurse -Force
        Write-Host "已复制 Win11 sparse package 资源到 Runner 目录"
    } catch {
        Write-Warning "复制 Win11 sparse package 资源失败：$($_.Exception.Message)"
    }
}

$sparseIdentityPackage = New-SparseIdentityPackage `
    -sourceSparseDir (Join-Path $packagingSourceDir "sparse") `
    -outputDir $packagingTargetDir `
    -packageVersion $msixPackageVersion `
    -makeAppxPreferred $MakeAppx `
    -signToolPreferred $SignTool `
    -certificatePath $MsixCertificatePath `
    -certificatePassword $MsixCertificatePassword
if (-not [string]::IsNullOrWhiteSpace($sparseIdentityPackage)) {
    Write-Host "Win11 sparse identity package 已复制到 Runner 目录：" $sparseIdentityPackage
}

function New-PortableArchive([string]$sourceDir, [string]$archivePath, [string]$folderName) {
    $stageRoot = Join-Path $scriptDir "..\\build\\windows\\portable"
    $stageDir = Join-Path $stageRoot $folderName
    if (Test-Path $stageDir) {
        Remove-Item $stageDir -Recurse -Force
    }
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    Copy-Item (Join-Path $sourceDir "*") $stageDir -Recurse -Force
    Compress-Archive -Path $stageDir -DestinationPath $archivePath
    Write-Host "便携包已生成：" $archivePath
}

function New-SymbolArchive([string]$archivePath, [string]$folderName) {
    $stageRoot = Join-Path $scriptDir "..\\build\\windows\\symbols"
    $stageDir = Join-Path $stageRoot $folderName
    $contextMenuBuildDir = Join-Path $scriptDir "..\\build\\windows\\x64\\context_menu\\$BuildMode"
    if (Test-Path $stageDir) {
        Remove-Item $stageDir -Recurse -Force
    }
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }

    $copied = $false
    foreach ($pair in @(
        @{ Source = $runnerOutputDir; Target = "runner" },
        @{ Source = $contextMenuBuildDir; Target = "context_menu" }
    )) {
        if (-not (Test-Path $pair.Source)) {
            continue
        }
        $pdbs = Get-ChildItem -Path $pair.Source -Filter *.pdb -File -ErrorAction SilentlyContinue
        if (-not $pdbs) {
            continue
        }
        $targetDir = Join-Path $stageDir $pair.Target
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        foreach ($pdb in $pdbs) {
            Copy-Item $pdb.FullName (Join-Path $targetDir $pdb.Name) -Force
            $copied = $true
        }
    }

    if (-not $copied) {
        Write-Warning "未找到可打包的 Windows 符号文件，跳过 symbols zip。"
        return
    }

    Compress-Archive -Path $stageDir -DestinationPath $archivePath
    Write-Host "Windows symbols 包已生成：" $archivePath
}

function New-Win11DevArchive([string]$sourceDir, [string]$archivePath, [string]$folderName) {
    if (-not (Test-Path $sourceDir)) {
        Write-Warning "未找到 Win11 开发包资源目录，跳过 win11-dev zip。"
        return
    }

    $stageRoot = Join-Path $scriptDir "..\\build\\windows\\win11-dev"
    $stageDir = Join-Path $stageRoot $folderName
    if (Test-Path $stageDir) {
        Remove-Item $stageDir -Recurse -Force
    }
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }

    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    Copy-Item (Join-Path $sourceDir "*") $stageDir -Recurse -Force
    Compress-Archive -Path $stageDir -DestinationPath $archivePath
    Write-Host "Win11 开发包已生成：" $archivePath
}

$portableZip = Join-Path $scriptDir "$zipBaseName.zip"
New-PortableArchive -sourceDir $runnerOutputDir -archivePath $portableZip -folderName $zipBaseName

$symbolsZip = Join-Path $scriptDir "$symbolsBaseName.zip"
New-SymbolArchive -archivePath $symbolsZip -folderName $symbolsBaseName

$win11DevZip = Join-Path $scriptDir "$win11DevBaseName.zip"
New-Win11DevArchive -sourceDir $packagingTargetDir -archivePath $win11DevZip -folderName $win11DevBaseName

if (-not (Test-Path $innoSetupCompiler)) {
    $isccCmd = Resolve-ToolPath -preferred $ISCC -fallbackPath "" -commandName "ISCC"
    if ([string]::IsNullOrWhiteSpace($isccCmd)) {
        Write-Warning "未找到 Inno Setup 编译器: $innoSetupCompiler，跳过安装包打包。"
        $innoSetupCompiler = ""
    } else {
        $innoSetupCompiler = $isccCmd
    }
}

if ([string]::IsNullOrWhiteSpace($innoSetupCompiler)) {
} else {

Write-Host "正在使用Inno Setup进行打包..."
& $innoSetupCompiler /DBuildMode=$BuildMode /DAppVersion=$pubspecVersion /DAppVersionInfoVersion=$versionInfoVersion /DOutputBaseFilename=$setupBaseName $issFile

    if ($LASTEXITCODE -eq 0) {
        Write-Host "安装包已生成：" (Join-Path $scriptDir "$setupBaseName.exe")
    } else {
        Write-Error "打包失败！请检查上方日志。"
    }
}

$wixBin = Resolve-WixBin -preferred $WixBin
if ([string]::IsNullOrWhiteSpace($wixBin)) {
    Write-Warning "未找到 WiX Toolset，跳过 MSI 打包。"
} else {
    $heatExe = Join-Path $wixBin "heat.exe"
    $candleExe = Join-Path $wixBin "candle.exe"
    $lightExe = Join-Path $wixBin "light.exe"
    $productWxs = Join-Path $scriptDir "installer\\Product.wxs"
    $wixObjDir = Join-Path $scriptDir "..\\build\\windows\\wix"
    $harvestWxs = Join-Path $wixObjDir "AppFiles.wxs"
    $runnerDir = (Resolve-Path (Join-Path $scriptDir "..\\build\\windows\\x64\\runner\\$BuildMode")).Path
    $msiPath = Join-Path $scriptDir "$msiBaseName.msi"

    if ((-not (Test-Path $heatExe)) -or (-not (Test-Path $candleExe)) -or (-not (Test-Path $lightExe))) {
        Write-Warning "WiX Toolset 缺少 heat/candle/light，可执行文件不完整，跳过 MSI 打包。"
    } else {
        New-Item -ItemType Directory -Force -Path $wixObjDir | Out-Null
        $resolvedProjectRoot = $projectRoot
        $productGeneratedWxs = Join-Path $wixObjDir "Product.generated.wxs"
        $productWixObj = Join-Path $wixObjDir "Product.generated.wixobj"
        $harvestWixObj = Join-Path $wixObjDir "AppFiles.wixobj"
        if (Test-Path $harvestWxs) {
            Remove-Item $harvestWxs -Force
        }
        if (Test-Path $msiPath) {
            Remove-Item $msiPath -Force
        }
        if (Test-Path $productGeneratedWxs) {
            Remove-Item $productGeneratedWxs -Force
        }
        if (Test-Path $productWixObj) {
            Remove-Item $productWixObj -Force
        }
        if (Test-Path $harvestWixObj) {
            Remove-Item $harvestWixObj -Force
        }

        $productTemplate = Get-Content $productWxs -Raw
        $productTemplate = $productTemplate.Replace('$(var.ProductVersion)', (Escape-XmlAttribute $msiProductVersion))
        $productTemplate = $productTemplate.Replace('$(var.FullVersion)', (Escape-XmlAttribute $pubspecVersion))
        $productTemplate = $productTemplate.Replace('$(var.RootDir)', (Escape-XmlAttribute $resolvedProjectRoot))
        [System.IO.File]::WriteAllText(
            $productGeneratedWxs,
            $productTemplate,
            [System.Text.UTF8Encoding]::new($false)
        )

        Write-Host "正在使用 WiX 生成 MSI..."
        & $heatExe dir $runnerDir `
            -nologo `
            -gg `
            -g1 `
            -srd `
            -scom `
            -sreg `
            -cg AppFiles `
            -dr INSTALLDIR `
            -var var.SourceDir `
            -out $harvestWxs

        if ($LASTEXITCODE -ne 0) {
            Write-Error "heat 收集安装文件失败。"
            exit $LASTEXITCODE
        }

        & $candleExe `
            -nologo `
            -arch x64 `
            "-dSourceDir=$runnerDir" `
            -out "$wixObjDir\\" `
            $productGeneratedWxs `
            $harvestWxs

        if ($LASTEXITCODE -ne 0) {
            Write-Error "candle 编译 MSI 安装文件失败。"
            exit $LASTEXITCODE
        }

        & $lightExe `
            -nologo `
            -cultures:en-us `
            -out $msiPath `
            $productWixObj `
            $harvestWixObj

        if ($LASTEXITCODE -ne 0) {
            Write-Error "light 链接 MSI 安装包失败。"
            exit $LASTEXITCODE
        }

        Write-Host "MSI 打包完成：" $msiPath
    }
}

$enableUnsignedMsix = ($env:VERTREE_ENABLE_UNSIGNED_MSIX -eq '1')
if ($enableUnsignedMsix) {
    $makeAppxExe = Resolve-MakeAppx -preferred $MakeAppx
    if ([string]::IsNullOrWhiteSpace($makeAppxExe)) {
        Write-Warning "未找到 MakeAppx.exe，跳过 unsigned MSIX 打包。"
    } else {
        $msixStageRoot = Join-Path $scriptDir "..\\build\\windows\\msix"
        $msixStageDir = Join-Path $msixStageRoot "package"
        $msixManifest = Join-Path $msixStageDir "AppxManifest.xml"
        $msixPath = Join-Path $scriptDir "$msixBaseName.msix"

        try {
            if (Test-Path $msixStageDir) {
                Remove-Item $msixStageDir -Recurse -Force
            }
            if (Test-Path $msixPath) {
                Remove-Item $msixPath -Force
            }

            New-Item -ItemType Directory -Force -Path $msixStageDir | Out-Null
            Copy-Item (Join-Path $runnerOutputDir "*") $msixStageDir -Recurse -Force
            Copy-Item (Join-Path $packagingSourceDir "sparse\\*") $msixStageDir -Recurse -Force
            if (Test-Path $msixManifest) {
                $manifestContent = Get-Content $msixManifest -Raw
                $manifestContent = $manifestContent.Replace('Version="1.0.0.0"', "Version=`"$msixPackageVersion`"")
                [System.IO.File]::WriteAllText(
                    $msixManifest,
                    $manifestContent,
                    [System.Text.UTF8Encoding]::new($false)
                )
            }

            & $makeAppxExe pack /o /d $msixStageDir /p $msixPath | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $msixPath)) {
                Write-Host "unsigned MSIX 打包完成：" $msixPath
            } else {
                Write-Warning "unsigned MSIX 打包失败，已跳过。"
                $global:LASTEXITCODE = 0
            }
        } catch {
            Write-Warning "unsigned MSIX 打包失败：$($_.Exception.Message)"
            $global:LASTEXITCODE = 0
        }
    }
} else {
    Write-Host "默认发布流程跳过 unsigned MSIX 打包；如需生成，请设置 VERTREE_ENABLE_UNSIGNED_MSIX=1。"
    $global:LASTEXITCODE = 0
}

if ($Sparse -or $SparseRefresh) {
    $externalLocation = (Resolve-Path (Join-Path $scriptDir "..\\build\\windows\\x64\\runner\\$BuildMode")).Path

    if ($SparseRefresh) {
        $refreshScript = Join-Path $scriptDir "packaging\\refresh_win11_menu.ps1"
        if (-not (Test-Path $refreshScript)) {
            Write-Warning "未找到 Win11 菜单刷新脚本: $refreshScript"
            exit 0
        }
        Write-Host "刷新 Win11 新菜单（Sparse Package），ExternalLocation=$externalLocation"
        & $refreshScript -BuildMode $BuildMode -ExternalLocation $externalLocation
    } else {
        $sparseScript = Join-Path $scriptDir "packaging\\install_sparse_package.ps1"
        if (-not (Test-Path $sparseScript)) {
            Write-Warning "未找到 Sparse Package 脚本: $sparseScript"
            exit 0
        }
        Write-Host "注册 Sparse Package，ExternalLocation=$externalLocation"
        & $sparseScript -ExternalLocation $externalLocation -Force
    }
}
