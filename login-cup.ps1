param(
    [string]$Username,
    [string]$Password,
    [string]$Server,
    [string]$Ip,
    [string]$Operator = 'auto',
    [int]$Acid = 1,
    [int]$Type = 1,
    [switch]$DetectIp = $true,
    [string]$BuildMode = 'auto'
)

$ErrorActionPreference = 'Stop'
$lastUsernameFile = Join-Path $PSScriptRoot '.login-cup.last-username'
$savedCredentialFile = Join-Path $PSScriptRoot '.login-cup.credential.json'

function Get-LastUsername {
    if (Test-Path $lastUsernameFile) {
        $saved = (Get-Content $lastUsernameFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        if ($saved) {
            return $saved
        }
    }
    return ''
}

function Save-LastUsername([string]$value) {
    if (-not $value) {
        return
    }
    Set-Content -Path $lastUsernameFile -Value $value -Encoding ascii
}

function Get-SavedCredential {
    if (-not (Test-Path $savedCredentialFile)) {
        return $null
    }

    try {
        $raw = Get-Content $savedCredentialFile -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $obj.username -or -not $obj.password) {
            return $null
        }

        $secure = $obj.password | ConvertTo-SecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        return @{
            Username = [string]$obj.username
            Password = [string]$plain
        }
    } catch {
        return $null
    }
}

function Save-SavedCredential([string]$username, [string]$password) {
    if (-not $username -or -not $password) {
        return
    }

    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    $encrypted = $secure | ConvertFrom-SecureString
    $payload = @{
        username = $username
        password = $encrypted
    } | ConvertTo-Json

    Set-Content -Path $savedCredentialFile -Value $payload -Encoding ascii
}

function Get-SrunExe {
    $candidates = @(
        (Join-Path $PSScriptRoot 'target\debug\srun.exe'),
        (Join-Path $PSScriptRoot 'target\release\srun.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    if ($BuildMode -eq 'never') {
        throw 'srun.exe not found in target\\debug or target\\release.'
    }

    $cargoCommand = Get-Command cargo.exe -ErrorAction SilentlyContinue
    if ($cargoCommand) {
        $cargo = $cargoCommand.Source
    } else {
        $cargo = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
    }

    if (-not (Test-Path $cargo)) {
        throw 'cargo.exe not found. Install Rust or build the project first.'
    }

    if ($BuildMode -eq 'release') {
        $buildArgs = @('build', '--release')
    } else {
        $buildArgs = @('build')
    }

    Push-Location $PSScriptRoot
    try {
        & $cargo @buildArgs
    } finally {
        Pop-Location
    }

    if ($BuildMode -eq 'release') {
        $builtExe = Join-Path $PSScriptRoot 'target\release\srun.exe'
    } else {
        $builtExe = Join-Path $PSScriptRoot 'target\debug\srun.exe'
    }

    if (-not (Test-Path $builtExe)) {
        throw 'Build finished but srun.exe was not found.'
    }

    return $builtExe
}

$savedCredential = Get-SavedCredential

if (-not $Username) {
    if ($savedCredential -and $savedCredential.Username) {
        $Username = $savedCredential.Username
        Write-Host "Using saved username: $Username"
    } else {
        $lastUsername = Get-LastUsername
        if ($lastUsername) {
            $entered = Read-Host "Username [$lastUsername]"
            if ($entered) {
                $Username = $entered
            } else {
                $Username = $lastUsername
            }
        } else {
            $Username = Read-Host 'Username'
        }
    }
}

if (-not $Password) {
    if ($savedCredential -and $savedCredential.Password) {
        $Password = $savedCredential.Password
        Write-Host 'Using saved password.'
    } else {
        $Password = Read-Host 'Password'
    }
}

if ($Username -match '@') {
    $usernameCandidates = @($Username)
} else {
    if ($Operator -eq 'auto') {
        $usernameCandidates = @(
            $Username,
            "$Username@xn",
            "$Username@cmcc",
            "$Username@cucc",
            "$Username@ctcc"
        )
    } elseif ($Operator -eq 'none') {
        $usernameCandidates = @($Username)
    } else {
        $usernameCandidates = @("$Username@$Operator")
    }
}

$srunExe = Get-SrunExe

if ($Server) {
    $servers = @($Server)
} else {
    # Prefer HTTPS first, and fallback to HTTP for environments without TLS support.
    $servers = @('https://login.cup.edu.cn', 'http://login.cup.edu.cn')
}

$baseArguments = @('login', '-p', $Password, '--acid', $Acid, '--type', $Type)

if ($Ip) {
    $baseArguments += @('-i', $Ip)
} elseif ($DetectIp) {
    $baseArguments += '-d'
} else {
    throw 'Provide -Ip or enable -DetectIp.'
}

Push-Location $PSScriptRoot
try {
    $attempt = 0
    $totalAttempts = $servers.Count * $usernameCandidates.Count
    $lastError = ''

    foreach ($serverCandidate in $servers) {
        foreach ($usernameCandidate in $usernameCandidates) {
            $attempt += 1
            Write-Host "[Attempt $attempt/$totalAttempts] server=$serverCandidate username=$usernameCandidate acid=$Acid type=$Type"

            $arguments = @('login', '-s', $serverCandidate, '-u', $usernameCandidate) + $baseArguments[1..($baseArguments.Count - 1)]
            $output = & $srunExe @arguments 2>&1
            $exitCode = $LASTEXITCODE

            if ($output) {
                $output | ForEach-Object { Write-Host $_ }
            }

            $text = ($output | Out-String)

            if ($text -match 'error:\s*"ok"' -and $text -match 'res:\s*"ok"') {
                if ($text -match 'suc_msg:\s*"ip_already_online_error"') {
                    Write-Host 'Server says this IP is already online. This is usually acceptable.'
                }
                Save-LastUsername $usernameCandidate
                Save-SavedCredential $usernameCandidate $Password
                Write-Host "Login request accepted by portal on $serverCandidate with $usernameCandidate"
                exit 0
            }

            $lastError = $text

            if ($text -match 'Unknow ac-type') {
                Write-Host 'Portal rejected ac-type. Try a different operator suffix via -Operator xn|cmcc|cucc|ctcc.'
            }

            if ($text -match 'Authentication fail') {
                Write-Host 'Authentication failed for this username candidate, trying next one.'
            }

            if ($exitCode -eq 0 -and $servers.Count -eq 1 -and $usernameCandidates.Count -eq 1) {
                Write-Host 'Command exited 0 but portal did not return success payload.'
            }

            if ($text -match 'need username|need password|need ip|parse args error') {
                break
            }
        }
    }

    Write-Error "Login failed on all server candidates. Last error:`n$lastError"
    exit 1
} finally {
    Pop-Location
}