param(
    [string]$WorkerUrl = 'https://guzzini.peresehan145.workers.dev',
    [switch]$SkipLogin,
    [switch]$UseCloudflareApiToken
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$adminKeyFile = Join-Path $root 'registration_admin_key.txt'

function ConvertFrom-SecureStringToPlain {
    param([Security.SecureString]$Value)

    if ($null -eq $Value) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Add-CodexNodeToPath {
    $nodeDir = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
    $binDir = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\bin'
    foreach ($dir in @($nodeDir, $binDir)) {
        if (Test-Path -LiteralPath $dir -PathType Container) {
            $parts = @($env:PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if (-not ($parts | Where-Object { [string]::Equals($_, $dir, [StringComparison]::OrdinalIgnoreCase) })) {
                $env:PATH = "$dir;$env:PATH"
            }
        }
    }
}

function Get-GusPnpm {
    Add-CodexNodeToPath

    $cmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return [string]$cmd.Source }

    $candidate = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\pnpm.cmd'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }

    throw 'pnpm not found. Install Node.js or run from Codex runtime.'
}

function Invoke-Wrangler {
    param([string[]]$Arguments)

    $pnpm = Get-GusPnpm
    & $pnpm dlx wrangler @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "wrangler failed: $($Arguments -join ' ')"
    }
}

function Set-WranglerSecret {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { throw "Empty secret: $Name" }
    $pnpm = Get-GusPnpm
    $oldLocation = Get-Location
    try {
        Set-Location -LiteralPath $root
        $Value | & $pnpm dlx wrangler secret put $Name
        if ($LASTEXITCODE -ne 0) { throw "Could not save secret $Name" }
    }
    finally {
        Set-Location -LiteralPath $oldLocation
    }
}

function New-AdminKey {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return 'GusAdmin-' + (($bytes | ForEach-Object { $chars[$_ % $chars.Length] }) -join '')
}

if (-not (Test-Path -LiteralPath (Join-Path $root 'registration_worker.js') -PathType Leaf)) {
    throw 'registration_worker.js not found near this script.'
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'wrangler.toml') -PathType Leaf)) {
    throw 'wrangler.toml not found near this script.'
}

Push-Location -LiteralPath $root
try {
    if ($UseCloudflareApiToken) {
        $cloudflareToken = ConvertFrom-SecureStringToPlain (Read-Host 'Paste Cloudflare API token with Workers Scripts Edit' -AsSecureString)
        if ([string]::IsNullOrWhiteSpace($cloudflareToken)) {
            throw 'Cloudflare API token is empty.'
        }
        $accountId = Read-Host 'Paste Cloudflare Account ID'
        if ([string]::IsNullOrWhiteSpace($accountId)) {
            throw 'Cloudflare Account ID is empty.'
        }
        $env:CLOUDFLARE_API_TOKEN = $cloudflareToken
        $env:CLOUDFLARE_ACCOUNT_ID = $accountId
    }
    elseif (-not $SkipLogin) {
        Write-Host 'Checking Cloudflare login...'
        try {
            Invoke-Wrangler -Arguments @('whoami')
        }
        catch {
            Write-Host 'Cloudflare login will open. In the browser press Allow/Authorize.'
            Invoke-Wrangler -Arguments @('login')
        }
    }

    $githubToken = ConvertFrom-SecureStringToPlain (Read-Host 'Paste GitHub token with repo Contents Read/Write' -AsSecureString)
    if ([string]::IsNullOrWhiteSpace($githubToken)) {
        throw 'GitHub token is empty.'
    }

    $adminKey = ''
    if (Test-Path -LiteralPath $adminKeyFile -PathType Leaf) {
        $adminKey = [string]((Get-Content -LiteralPath $adminKeyFile -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1))
    }
    if ([string]::IsNullOrWhiteSpace($adminKey)) {
        $adminKey = New-AdminKey
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($adminKeyFile, $adminKey, $utf8NoBom)
    }

    Write-Host 'Saving Worker secrets...'
    Set-WranglerSecret -Name 'GITHUB_TOKEN' -Value $githubToken
    Set-WranglerSecret -Name 'ADMIN_KEY' -Value $adminKey

    Write-Host 'Deploying Worker...'
    Invoke-Wrangler -Arguments @('deploy')

    Write-Host ''
    Write-Host 'Done.'
    Write-Host "Worker URL: $WorkerUrl"
    Write-Host "Admin Key saved locally: $adminKeyFile"
    Write-Host 'Put this Admin Key into the admin page API settings.'
}
finally {
    Pop-Location
}
