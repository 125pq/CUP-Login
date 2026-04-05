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
# Keep native command stderr as captured output instead of terminating,
# so HTTPS errors can fall back to HTTP server candidates.
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$stateRoot = Join-Path $env:LOCALAPPDATA 'srun-cup'
$lastUsernameFile = Join-Path $stateRoot '.login-cup.last-username'
$savedCredentialFile = Join-Path $stateRoot '.login-cup.credential.json'
$lastResultFile = Join-Path $stateRoot 'login-last-result.txt'
$lastErrorLogFile = Join-Path $stateRoot 'login-last-error.log'

if (-not (Test-Path $stateRoot)) {
    New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null
}

function Write-ResultFile([string]$status, [string]$title, [string]$message) {
    $lines = @(
        "status=$status",
        "title=$title",
        "message=$message",
        "time=$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))"
    )
    Set-Content -Path $lastResultFile -Value $lines -Encoding utf8
}

function Write-ErrorLog([string]$content) {
    if ([string]::IsNullOrWhiteSpace($content)) {
        $content = "No detailed error output was captured."
    }
    $header = "[" + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') + "]"
    Set-Content -Path $lastErrorLogFile -Value ($header + "`r`n" + $content) -Encoding utf8
}

function Get-LastPortalResponseBlock([string]$text) {
    if (-not $text) {
        return ''
    }

    $matches = [regex]::Matches($text, 'PortalResponse\s*\{[\s\S]*?\}')
    if ($matches.Count -gt 0) {
        return $matches[$matches.Count - 1].Value
    }

    return ''
}

trap {
    $errText = ($_ | Out-String)
    Write-ErrorLog $errText
    Write-ResultFile 'failed' 'Login failed' "Script runtime error. See $lastErrorLogFile"
    throw
}

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

function Clear-SavedCredential {
    Remove-Item -Path $savedCredentialFile -ErrorAction SilentlyContinue
    Remove-Item -Path $lastUsernameFile -ErrorAction SilentlyContinue
}

function Prompt-CredentialGui([string]$defaultUsername) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        Clear-SavedCredential
    } catch {
        return $null
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'srun-cup login'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(360, 170)
    $form.TopMost = $true

    $labelUser = New-Object System.Windows.Forms.Label
    $labelUser.Text = 'Username'
    $labelUser.Location = New-Object System.Drawing.Point(20, 20)
    $labelUser.AutoSize = $true

    $textUser = New-Object System.Windows.Forms.TextBox
    $textUser.Location = New-Object System.Drawing.Point(110, 18)
    $textUser.Size = New-Object System.Drawing.Size(220, 20)
    if ($defaultUsername) {
        $textUser.Text = $defaultUsername
    }

    $labelPass = New-Object System.Windows.Forms.Label
    $labelPass.Text = 'Password'
    $labelPass.Location = New-Object System.Drawing.Point(20, 58)
    $labelPass.AutoSize = $true

    $textPass = New-Object System.Windows.Forms.TextBox
    $textPass.Location = New-Object System.Drawing.Point(110, 56)
    $textPass.Size = New-Object System.Drawing.Size(220, 20)
    $textPass.UseSystemPasswordChar = $true

    $labelTip = New-Object System.Windows.Forms.Label
    $labelTip.Text = 'Credentials are saved to your user profile after successful login.'
    $labelTip.Location = New-Object System.Drawing.Point(20, 88)
    $labelTip.Size = New-Object System.Drawing.Size(320, 24)

    $buttonOk = New-Object System.Windows.Forms.Button
    $buttonOk.Text = 'Login'
    $buttonOk.Location = New-Object System.Drawing.Point(174, 122)
    $buttonOk.Size = New-Object System.Drawing.Size(75, 28)
    $buttonOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Text = 'Cancel'
    $buttonCancel.Location = New-Object System.Drawing.Point(255, 122)
    $buttonCancel.Size = New-Object System.Drawing.Size(75, 28)
    $buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($labelUser, $textUser, $labelPass, $textPass, $labelTip, $buttonOk, $buttonCancel))
    $form.AcceptButton = $buttonOk
    $form.CancelButton = $buttonCancel

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $u = $textUser.Text.Trim()
    $p = $textPass.Text
    if (-not $u -or -not $p) {
        return $null
    }

    return @{ Username = $u; Password = $p }
}

function Get-SrunExe {
    $candidates = @(
        (Join-Path $PSScriptRoot 'srun.exe'),
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
        # Hidden launcher has no usable console. Let GUI handle first-run input.
        $Username = Get-LastUsername
    }
}

if (-not $Password) {
    if ($savedCredential -and $savedCredential.Password) {
        $Password = $savedCredential.Password
        Write-Host 'Using saved password.'
    }
}

if (-not $Username -or -not $Password) {
    $defaultUsername = ''
    if ($Username) {
        $defaultUsername = $Username
    } elseif ($savedCredential -and $savedCredential.Username) {
        $defaultUsername = $savedCredential.Username
    } else {
        $defaultUsername = Get-LastUsername
    }

    $guiCredential = Prompt-CredentialGui $defaultUsername
    if ($guiCredential) {
        $Username = $guiCredential.Username
        $Password = $guiCredential.Password
    }
}

if (-not $Username) {
    throw 'Username is required. Run One-click login and complete GUI prompt, or use Debug login with parameters.'
}

if (-not $Password) {
    throw 'Password is required. Run One-click login and complete GUI prompt, or use Debug login with parameters.'
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
$loginSucceeded = $false
try {
    Write-ResultFile 'running' 'Login running' 'Trying campus network login...'
    $attempt = 0
    $totalAttempts = $servers.Count * $usernameCandidates.Count
    $lastError = ''
    $lastFailureStatus = 'failed'
    $lastFailureMessage = "Login failed. See $lastErrorLogFile"

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
            $portalBlock = Get-LastPortalResponseBlock $text

            $isPortalOk = $false
            $alreadyOnline = $false
            $accessToken = ''
            $hasAccessToken = $false

            if ($portalBlock) {
                $isPortalOk = ($portalBlock -match 'error:\s*"ok"' -and $portalBlock -match 'res:\s*"ok"')
                $alreadyOnline = ($portalBlock -match 'suc_msg:\s*"ip_already_online_error"')
                $tokenMatch = [regex]::Match($portalBlock, 'access_token:\s*"([^"]*)"')
                if ($tokenMatch.Success) {
                    $accessToken = $tokenMatch.Groups[1].Value
                    $hasAccessToken = [string]::IsNullOrWhiteSpace($accessToken) -eq $false
                }
            }

            if ($isPortalOk -and ($hasAccessToken -or $alreadyOnline)) {
                if ($alreadyOnline) {
                    Write-Host 'Server says this IP is already online. This is usually acceptable.'
                    Write-ResultFile 'already_online' 'Already online' 'Already online.'
                } else {
                    Write-ResultFile 'success' 'Login succeeded' 'Login succeeded!'
                }
                Save-LastUsername $usernameCandidate
                Save-SavedCredential $usernameCandidate $Password
                $loginSucceeded = $true
                Write-Host "Login request accepted by portal on $serverCandidate with $usernameCandidate"
                exit 0
            }

            $lastError = $text
            Write-ErrorLog $text

            if ($text -match 'Authentication fail|login_error|Unknow ac-type') {
                $lastFailureStatus = 'failed_auth'
                $lastFailureMessage = 'Username or password is incorrect.'
            } else {
                $lastFailureStatus = 'failed'
                $lastFailureMessage = "Login failed. See $lastErrorLogFile"
            }

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

    if (-not (Test-Path $lastErrorLogFile)) {
        Write-ErrorLog $lastError
    }
    Write-ResultFile $lastFailureStatus 'Login failed' $lastFailureMessage
    Write-Error "Login failed on all server candidates. Last error:`n$lastError"
    exit 1
} finally {
    if (-not $loginSucceeded) {
        Clear-SavedCredential
    }
    Pop-Location
}