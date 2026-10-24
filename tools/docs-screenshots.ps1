# Documentation screenshots. Runs the app with the sample player in its own data folder
# and on its own port (so it can run beside a copy already open), walks the pages in
# $Shots, and writes one PNG per entry to docs/images: the window cut at its frame,
# corners rounded like a Windows 11 window, a soft shadow, a plain background.
#
#   powershell -File tools/docs-screenshots.ps1             # build, then shoot
#   powershell -File tools/docs-screenshots.ps1 -NoBuild    # reuse the last build
#   powershell -File tools/docs-screenshots.ps1 -NoBuild -Only overview,maps
#
# Needs ImageMagick 7 (`magick`) on PATH. Don't touch the mouse while it runs: it clicks
# inside the app window. See docs/cli.md, "文档截图".
#
# Pages are reached by clicking, not by keyboard shortcuts: a Chinese input method
# catches injected keys before the app sees them. The window always has the same size
# and the sample player's data never changes, so every click point below is fixed;
# after a layout change, take one run, look at target/screenshots/raw and adjust them.
param(
  [switch]$NoBuild,
  [string[]]$Only,
  [string]$Out = "docs/images",
  [string]$Background = "#D9E0EA",
  [ValidateSet("dark", "light")][string]$Theme = "dark"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $repo "target\screenshots"
$appDir = Join-Path $stage "app"
$dataDir = Join-Path $stage "data"
$raw = Join-Path $stage "raw"
$port = 18380
# Outer window size; the visible frame comes out 1346 x 853.
$winW = 1360; $winH = 860

# A copy left running by an interrupted run holds files in $appDir: close it (only
# processes started from $stage, never another copy of the app).
Get-Process watch-overwatch, watchd -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -and $_.Path.StartsWith($stage) } | Stop-Process -Force
Start-Sleep -Milliseconds 500

# ---- Build: the sample player is only in development builds (docs/cli.md, 示例玩家) ----
if (-not $NoBuild) {
  Push-Location $repo
  try {
    # Own target folder: the normal one may hold a watchd.exe that is running.
    cargo build --release -p watchd --features demo --target-dir target/demo
    if ($LASTEXITCODE) { throw "cargo build failed" }
    Push-Location app
    flutter build windows --release --dart-define=WATCH_DEMO=true
    if ($LASTEXITCODE) { throw "flutter build failed" }
    Pop-Location
    if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
    New-Item -ItemType Directory $appDir | Out-Null
    Copy-Item "app\build\windows\x64\runner\Release\*" $appDir -Recurse
    Copy-Item "target\demo\release\watchd.exe" $appDir
  } finally { Pop-Location }
}
if (-not (Test-Path "$appDir\watch-overwatch.exe")) { throw "no build in $appDir; run without -NoBuild" }
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) { throw "ImageMagick 7 (magick) is not on PATH" }

# ---- Win32 ----
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, int f, int e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  // The visible frame, without the invisible resize border GetWindowRect includes.
  public static RECT Frame(IntPtr h) { RECT r; DwmGetWindowAttribute(h, 9, out r, 16); return r; }
}
"@
[Win]::SetProcessDPIAware() | Out-Null

# Brings the app to the front, and stops the run rather than click into another window.
function Front {
  for ($i = 0; $i -lt 10 -and [Win]::GetForegroundWindow() -ne $script:hwnd; $i++) {
    # A tap of Alt lets a background process take the foreground.
    [Win]::keybd_event(0x12, 0, 0, 0); [Win]::SetForegroundWindow($script:hwnd) | Out-Null; [Win]::keybd_event(0x12, 0, 2, 0)
    Start-Sleep -Milliseconds 200
  }
  if ([Win]::GetForegroundWindow() -ne $script:hwnd) { throw "the app window is not in front; stopped" }
}

# A left click at (x, y) in the visible frame, in pixels.
function Click([int]$x, [int]$y, [int]$wait = 1500) {
  Front
  $f = [Win]::Frame($script:hwnd)
  [Win]::SetCursorPos($f.L + $x, $f.T + $y) | Out-Null
  Start-Sleep -Milliseconds 120
  [Win]::mouse_event(2, 0, 0, 0, 0); [Win]::mouse_event(4, 0, 0, 0, 0)
  Start-Sleep -Milliseconds $wait
}

# Mouse wheel at (x, y): negative $notches scroll down.
function Wheel([int]$x, [int]$y, [int]$notches, [int]$wait = 1200) {
  Front
  $f = [Win]::Frame($script:hwnd)
  [Win]::SetCursorPos($f.L + $x, $f.T + $y) | Out-Null
  Start-Sleep -Milliseconds 120
  [Win]::mouse_event(0x0800, 0, 0, 120 * $notches, 0)
  Start-Sleep -Milliseconds $wait
}

# The window as it is now, cut exactly at the visible frame, to $raw\<name>.png. The
# pointer moves off the window first, so no hover state shows.
function Grab([string]$name) {
  Front
  $f = [Win]::Frame($script:hwnd)
  [Win]::SetCursorPos($f.R + 60, $f.B + 60) | Out-Null
  Start-Sleep -Milliseconds 700
  $w = $f.R - $f.L; $h = $f.B - $f.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($f.L, $f.T, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $raw "$name.png"))
  $g.Dispose(); $bmp.Dispose()
}

# The picture for the docs: corners rounded like the window's own (8 px, which also
# drops the desktop showing through them), a soft shadow, a plain background.
function Finish([string]$name) {
  $src = Join-Path $raw "$name.png"
  $dst = Join-Path $repo (Join-Path $Out "$name.png")
  # -shave 1: the frame's outermost pixel is see-through (the window behind, the
  # system accent line) and is dropped before the corners are cut.
  magick $src -shave 1x1 `
    "(" +clone -alpha extract -fill black -colorize 100 -fill white -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] 8,8" ")" `
    -alpha off -compose CopyOpacity -composite `
    "(" +clone -background "#0B1220" -shadow 40x16+0+8 ")" +swap `
    -background none -compose Over -layers merge +repage `
    -bordercolor none -border 40 -background $Background -flatten -strip $dst
  if ($LASTEXITCODE) { throw "magick failed on $name" }
}

# ---- The app on its own data folder and port ----
$utf8 = New-Object Text.UTF8Encoding $false
function Launch([bool]$withSample) {
  # Image cache kept between runs (the pictures come from the provider's CDN); every
  # other file starts fresh.
  New-Item -ItemType Directory -Force $dataDir | Out-Null
  Get-ChildItem $dataDir -Exclude img-cache | Remove-Item -Recurse -Force
  # Theme, mode and the sample player, set before start in the app's settings file
  # (no byte-order mark: the app's JSON reader rejects one). No update check: its
  # dialog would cover the first page.
  $state = @{ version = 1; theme = $Theme; mode = "competitive"; autoCheckUpdates = $false }
  if ($withSample) {
    $state.lastPlayer = "示例玩家#0000"
    # The service's player library, so the sample player is there to restore.
    [IO.File]::WriteAllText((Join-Path $dataDir "players.json"), '["示例玩家#0000"]', $utf8)
  }
  [IO.File]::WriteAllText((Join-Path $dataDir "ui-state.json"), ($state | ConvertTo-Json), $utf8)

  $psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $appDir "watch-overwatch.exe")
  $psi.WorkingDirectory = $appDir
  $psi.UseShellExecute = $false
  $psi.Environment["WATCH_DATA_DIR"] = $dataDir
  $psi.Environment["WATCHD_PORT"] = "$port"
  $psi.Environment["WATCHD_PATH"] = Join-Path $appDir "watchd.exe"
  $script:proc = [System.Diagnostics.Process]::Start($psi)
  for ($i = 0; $i -lt 50 -and $script:proc.MainWindowHandle -eq 0; $i++) {
    Start-Sleep -Milliseconds 200; $script:proc.Refresh()
  }
  $script:hwnd = $script:proc.MainWindowHandle
  if ($script:hwnd -eq 0) { throw "the app window did not open" }
  [Win]::ShowWindow($script:hwnd, 9) | Out-Null
  [Win]::MoveWindow($script:hwnd, 40, 40, $winW, $winH, $true) | Out-Null
  Start-Sleep -Seconds 6
}
function Quit {
  if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill(); $script:proc.WaitForExit(5000) | Out-Null }
  # The service exits with the app (WATCHD_EXIT_ON_STDIN_EOF); give it a moment.
  Start-Sleep -Seconds 1
}

# ---- Click points in the 1346 x 853 frame ----
$tab = @{ overview = 312; daily = 405; matches = 500; heroes = 583; maps = 662; strength = 752
          people = 860; growth = 953; trend = 1047; profile = 1137 }
function Tab([string]$id, [int]$wait = 2500) { Click $tab[$id] 162 $wait }
$firstRow = 333     # first row of the match and hero lists
$recapButton = @(1248, 240)
$exportButton = @(1312, 93)   # the export icon at the right end of the player header

# ---- The pictures: name -> steps from the sample player's 概览 ----
# Each entry starts from a fresh launch, so entries do not depend on each other.
$Shots = [ordered]@{
  "overview"       = { }
  "recap"          = { Click $recapButton[0] $recapButton[1] 2500 }
  "daily"          = { Tab daily }
  "matches"        = { Tab matches }
  "match-detail"   = { Tab matches; Click 700 $firstRow 2500 }
  "player-card"    = { Tab matches; Click 700 $firstRow 2500; Click 360 410 2500 }
  "heroes"         = { Tab heroes }
  "hero-detail"    = { Tab heroes; Click 600 $firstRow 3000 }
  "hero-stats"     = { Tab heroes; Click 600 $firstRow 3000; Wheel 800 600 -5 }
  "maps"           = { Tab maps }
  "strength"       = { Tab strength; Click 945 255 15000 }
  "strength-chart" = { Tab strength; Click 945 255 15000; Wheel 800 600 -6 }
  "people"         = { Tab people }
  "growth"         = { Tab growth 4000 }
  "trend"          = { Tab trend 4000 }
  "profile"        = { Tab profile 3000 }
  "export"         = { Click $exportButton[0] $exportButton[1] 2000 }
}

New-Item -ItemType Directory -Force $raw | Out-Null
New-Item -ItemType Directory -Force (Join-Path $repo $Out) | Out-Null
# -File passes "a,b" as one string; split it here.
$names = if ($Only) { @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ }) } else { @("first-run") + @($Shots.Keys) }
try {
  # Warm the image cache once, so no picture is shot while its images still load.
  if (-not $Only) {
    Launch $true
    foreach ($id in $tab.Keys) { Tab $id 3000 }
    Quit
  }
  foreach ($name in $names) {
    Write-Host "shooting $name"
    if ($name -eq "first-run") {
      Launch $false
    } else {
      if (-not $Shots.Contains($name)) { throw "no shot named $name" }
      Launch $true
      & $Shots[$name]
    }
    Grab $name
    Quit
    Finish $name
  }
} finally { Quit }
Write-Host "done: $($names.Count) pictures in $Out (raw grabs in $raw)"
