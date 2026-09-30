param(
    [switch]$Offline,
    [string]$AndroidBuildName
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
    $buildName = if ([string]::IsNullOrWhiteSpace($AndroidBuildName)) {
        $versionMatch.Groups[1].Value
    } else {
        $AndroidBuildName.Trim()
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
    flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'APK 构建失败。' }

    $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $apk)) {
        throw '构建命令完成，但没有找到 APK 输出文件。'
    }

    $delivery = Join-Path (Split-Path $projectRoot -Parent) "jiaotong_course-$buildName.apk"
    Copy-Item -LiteralPath $apk -Destination $delivery -Force
    Write-Host "APK 已生成：$delivery"
}
finally {
    Pop-Location
}
