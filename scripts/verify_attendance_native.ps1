param([string]$CacheRoot = $env:GRADLE_USER_HOME)
$ErrorActionPreference='Stop'
if (-not $CacheRoot) { $CacheRoot=Join-Path $env:USERPROFILE '.gradle' }
$modules=Join-Path $CacheRoot 'caches/modules-2/files-2.1'
function Find-Jar([string]$group,[string]$artifact,[string]$version) {
  $jar=Get-ChildItem -LiteralPath "$modules/$group/$artifact/$version" -Recurse -Filter "$artifact-$version.jar" | Select-Object -First 1
  if (-not $jar) { throw "Missing cached dependency: $artifact $version" }
  return $jar.FullName
}
$stdlib=Find-Jar 'org.jetbrains.kotlin' 'kotlin-stdlib' '2.2.20'
$annotations=Find-Jar 'org.jetbrains' 'annotations' '13.0'
$runtime="$stdlib;$annotations"
$compiler=@(
 (Find-Jar 'org.jetbrains.kotlin' 'kotlin-compiler-embeddable' '2.2.20'),
 $stdlib,
 (Find-Jar 'org.jetbrains.kotlin' 'kotlin-script-runtime' '2.2.20'),
 (Find-Jar 'org.jetbrains.kotlin' 'kotlin-reflect' '1.6.10'),
 (Find-Jar 'org.jetbrains.kotlin' 'kotlin-daemon-embeddable' '2.2.20'),
 (Find-Jar 'org.jetbrains.kotlinx' 'kotlinx-coroutines-core-jvm' '1.8.0'),
 $annotations
) -join ';'
$projectRoot=Split-Path $PSScriptRoot -Parent
$output=Join-Path $projectRoot 'build/native-attendance-smoke'
New-Item -ItemType Directory -Force -Path $output | Out-Null
& "$env:JAVA_HOME/bin/java.exe" -cp $compiler org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $runtime -d "$output/smoke.jar" "$projectRoot/android/app/src/main/kotlin/cn/sjtu/jiaotong_course/AttendancePolling.kt" "$projectRoot/test/native/AttendancePollingSmoke.kt"
if ($LASTEXITCODE -ne 0) { throw 'Native polling smoke compilation failed' }
& "$env:JAVA_HOME/bin/java.exe" -cp "$output/smoke.jar;$runtime" cn.sjtu.jiaotong_course.AttendancePollingSmokeKt
if ($LASTEXITCODE -ne 0) { throw 'Native polling smoke checks failed' }
