# Installs the patched CopyQ build from this repository's latest release.
# One-line install (PowerShell):
#   irm https://raw.githubusercontent.com/geekzeino/copyq-windows/master/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'geekzeino/copyq-windows'
$appId = '{9DF1F443-EA0B-4C75-A4D3-767A7783228E}_is1'

function Get-CopyQExe {
    foreach ($root in 'HKCU:', 'HKLM:') {
        $key = "$root\Software\Microsoft\Windows\CurrentVersion\Uninstall\$appId"
        $dir = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallLocation
        if ($dir -and (Test-Path (Join-Path $dir 'copyq.exe'))) { return Join-Path $dir 'copyq.exe' }
    }
    return $null
}

# Resolve the latest tag from the releases/latest redirect; the REST API is rate-limited.
$latest = Invoke-WebRequest "https://github.com/$repo/releases/latest" -UseBasicParsing -Method Head
$uri = if ($latest.BaseResponse.ResponseUri) { $latest.BaseResponse.ResponseUri } else { $latest.BaseResponse.RequestMessage.RequestUri }
$tag = $uri.Segments[-1].Trim('/')
if ($tag -notmatch '^v\d') { throw "Could not find the latest release of $repo." }
$name = "copyq-$($tag.Substring(1))-setup.exe"

$setup = Join-Path $env:TEMP $name
Write-Host "Downloading $name..."
Invoke-WebRequest "https://github.com/$repo/releases/download/$tag/$name" -UseBasicParsing -OutFile $setup

# Ask a running CopyQ to quit so the installer can replace its files.
$old = Get-CopyQExe
if ($old -and (Get-Process copyq -ErrorAction SilentlyContinue)) {
    & $old exit | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host 'Installing CopyQ...'
$proc = Start-Process $setup -Wait -PassThru -ArgumentList `
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CURRENTUSER', '/TASKS=startup'
if ($proc.ExitCode -ne 0) { throw "Installer failed with exit code $($proc.ExitCode)." }
Remove-Item $setup -ErrorAction SilentlyContinue

$exe = Get-CopyQExe
if (-not $exe) { throw 'CopyQ was installed but copyq.exe could not be found.' }

Start-Process $exe -ArgumentList '--start-server'
$ready = $false
for ($i = 0; $i -lt 30 -and -not $ready; $i++) {
    Start-Sleep -Milliseconds 500
    & $exe eval '1' 2>$null | Out-Null
    $ready = ($LASTEXITCODE -eq 0)
}
if (-not $ready) { throw 'CopyQ did not start.' }

# Add the bundled commands (pin, tags, Ctrl+W close, ...) that are not already present.
$ini = Join-Path $env:TEMP 'copyq-commands.ini'
Invoke-WebRequest "https://raw.githubusercontent.com/$repo/master/windows/copyq-commands.ini" -UseBasicParsing -OutFile $ini
$path = $ini -replace '\\', '/'
$js = "var f = new File('$path'); f.openReadOnly(); var add = importCommands(str(f.readAll())); f.close();" +
      " var have = commands().map(function(c) { return c.name; });" +
      " add = add.filter(function(c) { return have.indexOf(c.name) < 0; });" +
      " setCommands(commands().concat(add)); print(add.length);"
& $exe eval $js | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not add the bundled commands.' }
Remove-Item $ini -ErrorAction SilentlyContinue

& $exe show | Out-Null
Write-Host "CopyQ $tag installed. It starts automatically at sign-in."
