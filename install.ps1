<#
  UnityZhKit installer  (ASCII only - PowerShell 5.1 parses .ps1 as ANSI)
  Usage:
    powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "D:\Games\SomeGame"
    powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "D:\Games\SomeGame" -DryRun
#>
param(
    [Parameter(Mandatory=$true)][string]$GameDir,
    [switch]$DryRun,
    [switch]$SkipXUnity
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

Say "=== UnityZhKit installer ===" Cyan
Say "GameDir : $GameDir"
Say "KitDir  : $here"
if ($DryRun) { Say "(DRY RUN - nothing will be written)" Yellow }

if (-not (Test-Path $GameDir)) { throw "GameDir not found: $GameDir" }

# 1. locate *_Data
$dataDir = Get-ChildItem -Path $GameDir -Directory -Filter "*_Data" | Select-Object -First 1
if (-not $dataDir) { throw "No *_Data folder found. Is this a Unity game?" }
Say "[1/5] Data folder: $($dataDir.Name)"

$isIL2CPP = Test-Path (Join-Path $dataDir.FullName "il2cpp_data\Metadata\global-metadata.dat")
if (-not $isIL2CPP) { throw "Not an IL2CPP build. Use BepInEx 5 + XUnity normal build instead (see SKILL.md)." }
Say "      IL2CPP build detected."

# read unity version from globalgamemanagers
$ggm = Join-Path $dataDir.FullName "globalgamemanagers"
$unityVer = $null
if (Test-Path $ggm) {
    $bytes = [System.IO.File]::ReadAllBytes($ggm)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $m = [regex]::Match($text, "(\d{4}\.\d+\.\d+[abfp]\d+)")
    if ($m.Success) { $unityVer = $m.Groups[1].Value }
}
Say "[2/5] Unity version: $(if($unityVer){$unityVer}else{'unknown'})"

$bepDir = Join-Path $GameDir "BepInEx"

# 3. BepInEx 6 IL2CPP
if (Test-Path (Join-Path $bepDir "core\BepInEx.Unity.IL2CPP.dll")) {
    Say "[3/5] BepInEx 6 already present, skip download."
} else {
    Say "[3/5] Download BepInEx 6 (IL2CPP) ..." Yellow
    $page = Invoke-WebRequest -UseBasicParsing -Uri "https://builds.bepinex.dev/projects/bepinex_be"
    $m = [regex]::Match($page.Content, 'href="([^"]*BepInEx-Unity\.IL2CPP-win-x64[^"]*\.zip)"')
    if (-not $m.Success) { throw "Cannot find BepInEx IL2CPP build on builds.bepinex.dev" }
    $url = $m.Groups[1].Value
    if ($url -notmatch "^https?://") { $url = "https://builds.bepinex.dev" + $url }
    Say "      $url"
    if (-not $DryRun) {
        $tmp = Join-Path $env:TEMP "bep.zip"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
        Expand-Archive -Path $tmp -DestinationPath $GameDir -Force
    }
}

# 4. unity base libraries
if ($unityVer) {
    $libsDir = Join-Path $bepDir "unity-libs"
    $libFile = Join-Path $libsDir "$unityVer.zip"
    if ((Test-Path $libFile)) {
        Say "[4/5] unity-libs for $unityVer already present."
    } else {
        Say "[4/5] Fetching unity base libraries for $unityVer ..." Yellow
        $cand = $unityVer
        $found = $false
        while (-not $found -and $cand) {
            $probe = "https://unity.bepinex.dev/libraries/$cand.zip"
            try {
                $r = Invoke-WebRequest -UseBasicParsing -Uri $probe -Method Head
                $found = ($r.StatusCode -eq 200)
            } catch { $found = $false }
            if (-not $found) {
                # downgrade patch number, e.g. 6000.3.27f2 -> 6000.3.26
                $mm = [regex]::Match($cand, "^(?<base>\d+\.\d+\.)(?<patch>\d+)")
                if (-not $mm.Success) { break }
                $p = [int]$mm.Groups["patch"].Value
                if ($p -le 0) { break }
                $cand = $mm.Groups["base"].Value + ($p - 1)
            }
        }
        if (-not $found) { throw "No unity-libs available near $unityVer. Get one manually from https://unity.bepinex.dev/libraries/" }
        Say "      using $cand.zip (renamed to $unityVer.zip)"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $libsDir | Out-Null
            Invoke-WebRequest -UseBasicParsing -Uri "https://unity.bepinex.dev/libraries/$cand.zip" -OutFile $libFile
        }
    }
} else {
    Say "[4/5] Unity version unknown - launch the game once and read BepInEx\LogOutput.log for the required library version." Yellow
}

# 5. XUnity + our plugin
if (-not $SkipXUnity) {
    Say "[5/5] XUnity.AutoTranslator: download manually from" Yellow
    Say "      https://github.com/bbepis/XUnity.AutoTranslator/releases"
    Say "      file: XUnity.AutoTranslator-BepInEx-IL2CPP-*.zip  ->  extract into $GameDir"
    Say "      IMPORTANT: copy BepInEx\core\XUnity.Common.dll too." Yellow
}

$plugins = Join-Path $bepDir "plugins"
if (-not (Test-Path $plugins)) { if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $plugins | Out-Null } }
$dll = Join-Path $here "ZhFontFix.dll"
if (-not (Test-Path $dll)) { $dll = Join-Path $here "dist\ZhFontFix.dll" }
if (Test-Path $dll) {
    Say "      copying ZhFontFix.dll -> $plugins"
    if (-not $DryRun) { Copy-Item $dll (Join-Path $plugins "ZhFontFix.dll") -Force }
} else {
    Say "      ZhFontFix.dll not found next to install.ps1" Red
}

Say ""
Say "Next:" Cyan
Say " 1. Launch the game once, then check BepInEx\LogOutput.log"
Say " 2. If you see 'could not load file or assembly XUnity.Common' -> copy BepInEx\core\XUnity.Common.dll"
Say " 3. If ZhFontFix fails to load (TypeLoadException) -> rebuild:"
$cmd = '      dotnet build -c Release -p:BepInExDir="' + $bepDir + '"  (inside src\)'
Say $cmd
Say " 4. Then run: python tools\zhpatch.py extract/translate/build  (see SKILL.md)"
