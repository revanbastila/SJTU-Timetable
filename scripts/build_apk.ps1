param(
    [switch]$Offline,
    [string]$AndroidBuildName,
    [string]$GitHubOwner,
    [string]$GitHubRepo
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'project_env.ps1')
Push-Location $projectRoot
try {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw '未找到 flutter。请先安装 Flutter stable，并将 flutter\bin 加入 PATH。'
    }

    if (-not (Test-Path -LiteralPath '.\android\gradlew.bat')) {
        flutter create --platforms=android .
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Android 工程初始化失败。' }
    }

    $versionLine = Select-String -LiteralPath '.\pubspec.yaml' -Pattern '^\s*version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$' | Select-Object -First 1
    if ($null -eq $versionLine) {
        throw '无法从 pubspec.yaml 读取应用版本号。'
    }
    $versionMatch = $versionLine.Matches[0]
    $androidVersionFile = Join-Path $projectRoot 'android\version-name.txt'
    $buildName = if (-not [string]::IsNullOrWhiteSpace($AndroidBuildName)) {
        $AndroidBuildName.Trim()
    } elseif (Test-Path -LiteralPath $androidVersionFile) {
        (Get-Content -LiteralPath $androidVersionFile -Raw).Trim()
    } else {
        $versionMatch.Groups[1].Value
    }
    $buildNumber = $versionMatch.Groups[2].Value

    $pubArgs = @('pub', 'get')
    if ($Offline) { $pubArgs += '--offline' }
    flutter @pubArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 依赖获取失败。' }

    $buildArgs = @('build', 'apk', '--release', '--no-pub', '--build-name', $buildName)
    if (-not [string]::IsNullOrWhiteSpace($buildNumber)) {
        $buildArgs += @('--build-number', $buildNumber)
    }
    if (-not [string]::IsNullOrWhiteSpace($GitHubOwner)) {
        $buildArgs += "--dart-define=GITHUB_OWNER=$GitHubOwner"
    }
    if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) {
        $buildArgs += "--dart-define=GITHUB_REPO=$GitHubRepo"
    }
    $apkRoot = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
    $deliveryRoot = Split-Path $projectRoot -Parent
    foreach ($mode in @('universal', 'split')) {
        $modeArgs = $buildArgs
        if ($mode -eq 'split') { $modeArgs += '--split-per-abi' }
        flutter @modeArgs
        if ($LASTEXITCODE -ne 0) { throw "APK 构建失败：$mode" }
        $architectures = if ($mode -eq 'split') {
            @('arm64-v8a', 'armeabi-v7a', 'x86_64')
        } else { @('universal') }
        foreach ($architecture in $architectures) {
            $sourceName = if ($architecture -eq 'universal') {
                'app-release.apk'
            } else { "app-$architecture-release.apk" }
            $apk = Join-Path $apkRoot $sourceName
            if (-not (Test-Path -LiteralPath $apk)) {
                throw "构建命令完成，但没有找到 $sourceName"
            }
            $delivery = Join-Path $deliveryRoot "jiaotong_course-$buildName-slim-test-$architecture.apk"
            Copy-Item -LiteralPath $apk -Destination $delivery -Force
            Write-Host "APK 已生成：$delivery"
        }
    }
}
finally {
    Pop-Location
}
