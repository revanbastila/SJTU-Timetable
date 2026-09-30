$ErrorActionPreference = 'Stop'
$taskRoot = Join-Path $PSScriptRoot '..\..\work'
$taskRoot = (Resolve-Path $taskRoot).Path
$env:TEMP = "$taskRoot\temp"
$env:TMP = $env:TEMP
$env:APPDATA = "$taskRoot\flutter_appdata"
$env:LOCALAPPDATA = $env:APPDATA
$env:PUB_CACHE = "$taskRoot\pub-cache"
$env:GRADLE_USER_HOME = "$taskRoot\gradle-home-1-1"
$env:ANDROID_USER_HOME = "$taskRoot\java-home\.android"
$env:ANDROID_EMULATOR_HOME = $env:ANDROID_USER_HOME
$env:ANDROID_SDK_HOME = "$taskRoot\java-home"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$taskRoot\java-home"
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:JAVA_HOME = "$taskRoot\temurin17\jdk-17.0.20.1+1"
$env:Path = "$env:JAVA_HOME\bin;" + $env:Path
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2 -Dorg.gradle.daemon=false'
Set-Location $PSScriptRoot
& "$taskRoot\flutter-sdk\bin\flutter.bat" build apk --release --no-pub --build-name 1.1.9.3 --build-number 15 --verbose
exit $LASTEXITCODE
