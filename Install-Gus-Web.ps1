param(
    [string]$BaseUrl = 'https://danzedark.github.io/gus-updates'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Info {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Гусь - установка', 'OK', 'Information') | Out-Null
}

function Show-Error {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Гусь - установка', 'OK', 'Error') | Out-Null
}

function New-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$IconPath
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
        $shortcut.IconLocation = $IconPath
    }
    $shortcut.Save()
}

try {
    $base = $BaseUrl.TrimEnd('/')
    $packageUrl = "$base/Gus-MaxContactTool-update.zip"
    $defaultRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Гусь'

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Выбери папку, куда установить программу Гусь'
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $defaultRoot -PathType Container) {
        $dialog.SelectedPath = $defaultRoot
    }
    else {
        $dialog.SelectedPath = [Environment]::GetFolderPath('Desktop')
    }

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        exit 0
    }

    $installDir = $dialog.SelectedPath
    if ([IO.Path]::GetFileName($installDir) -notmatch '^(Гусь|Gus|MaxContactTool)$') {
        $installDir = Join-Path $installDir 'Гусь'
    }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    $tempZip = Join-Path ([IO.Path]::GetTempPath()) ('GusUpdate_' + [Guid]::NewGuid().ToString('N') + '.zip')
    Invoke-WebRequest -Uri $packageUrl -OutFile $tempZip -UseBasicParsing

    $tempExtract = Join-Path ([IO.Path]::GetTempPath()) ('GusInstall_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)

    foreach ($item in @(Get-ChildItem -LiteralPath $tempExtract -Force)) {
        $target = Join-Path $installDir $item.Name
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $item.FullName -Destination $target -Force
    }

    $baseWithSlash = $base + '/'
    Set-Content -LiteralPath (Join-Path $installDir 'update_source.txt') -Encoding UTF8 -Value $baseWithSlash
    Set-Content -LiteralPath (Join-Path $installDir 'update_channel.txt') -Encoding UTF8 -Value $baseWithSlash

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Гусь.lnk'
    $launcher = Join-Path $installDir 'Gus-MaxContactTool.exe'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        $launcher = Join-Path $installDir 'Гусь.bat'
    }
    $icon = Join-Path $installDir 'assets\goose.ico'
    New-Shortcut -ShortcutPath $shortcutPath -TargetPath $launcher -WorkingDirectory $installDir -IconPath $icon

    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    Show-Info "Гусь установлен.`nПапка: $installDir`nЯрлык создан на рабочем столе."
}
catch {
    Show-Error ("Не удалось установить программу:`n" + $_.Exception.Message)
    exit 1
}
