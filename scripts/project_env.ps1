$ErrorActionPreference = 'Stop'

$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$taskWork = Join-Path $workspaceRoot 'work'
$localFlutter = Join-Path $taskWork 'flutter'
$localAndroidSdk = Join-Path $taskWork 'android-sdk'

foreach ($directory in @(
    'temp', 'flutter_appdata', 'pub-cache', 'gradle-home',
    'android-user', 'java-home'
)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $taskWork $directory) | Out-Null
}

$env:TEMP = Join-Path $taskWork 'temp'
$env:TMP = $env:TEMP
$env:APPDATA = Join-Path $taskWork 'flutter_appdata'
$env:LOCALAPPDATA = $env:APPDATA
$env:PUB_CACHE = Join-Path $taskWork 'pub-cache'
$env:GIT_CONFIG_GLOBAL = Join-Path $taskWork 'gitconfig'
$env:GRADLE_USER_HOME = Join-Path $taskWork 'gradle-home'
$env:ANDROID_USER_HOME = Join-Path $taskWork 'android-user'
$env:ANDROID_AVD_HOME = Join-Path $env:ANDROID_USER_HOME 'avd'
$env:ANDROID_HOME = $localAndroidSdk
$env:ANDROID_SDK_ROOT = $localAndroidSdk
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $taskWork 'java-home')"
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

$projectJdk = Join-Path $taskWork 'jdk21.0.12_12'
$bundledJava = 'D:\IntelliJ IDEA 2025.3.4.1\jbr'
if (Test-Path -LiteralPath (Join-Path $projectJdk 'bin\jlink.exe')) {
    $env:JAVA_HOME = $projectJdk
    $env:Path = "$(Join-Path $projectJdk 'bin');$env:Path"
} elseif (-not $env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $bundledJava 'bin\java.exe'))) {
    $env:JAVA_HOME = $bundledJava
    $env:Path = "$(Join-Path $bundledJava 'bin');$env:Path"
}

if (Test-Path -LiteralPath (Join-Path $localFlutter 'bin\flutter.bat')) {
    $env:FLUTTER_ROOT = $localFlutter
    $env:Path = "$(Join-Path $localFlutter 'bin');$env:Path"
}
