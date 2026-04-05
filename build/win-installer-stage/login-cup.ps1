param(
    [string]$Username,
    [string]$Password,
    [string]$Server,
    [string]$Ip,
    [string]$Operator = 'auto',
    [int]$Acid = 1,
    [int]$Type = 1,
    [int]$RetryTimes = 1,
    [int]$RetryDelay = 100,
    [switch]$Silent,
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

function Get-ResultField([string]$name) {
    if (-not (Test-Path $lastResultFile)) {
        return ''
    }

    $line = Get-Content $lastResultFile -ErrorAction SilentlyContinue | Where-Object { $_ -like "$name=*" } | Select-Object -First 1
    if (-not $line) {
        return ''
    }
    return $line.Substring($name.Length + 1)
}

function Get-LoginHintText {
    $status = Get-ResultField 'status'
    switch ($status) {
        'failed_auth' { return 'Username or password is incorrect. Please retry.' }
        'failed' { return 'Last login failed. Check network/settings and retry.' }
        default { return 'Credentials are saved locally after successful login.' }
    }
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
}

function Get-AutoStartEnabled {
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        $value = (Get-ItemProperty -Path $runPath -Name 'srun-cup' -ErrorAction Stop).'srun-cup'
        return ($value -and $value -match 'login-cup\.vbs')
    } catch {
        return $false
    }
}

function Set-AutoStartEnabled([bool]$enabled) {
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $cmd = '"wscript.exe" //B //Nologo "' + (Join-Path $PSScriptRoot 'login-cup.vbs') + '" --silent'

    if ($enabled) {
        New-Item -Path $runPath -Force | Out-Null
        Set-ItemProperty -Path $runPath -Name 'srun-cup' -Value $cmd
    } else {
        Remove-ItemProperty -Path $runPath -Name 'srun-cup' -ErrorAction SilentlyContinue
    }
}

function Resolve-UsernameCandidates([string]$rawUsername) {
    if ($rawUsername -match '@') {
        return @($rawUsername)
    }

    if ($Operator -eq 'auto') {
        return @($rawUsername, "$rawUsername@xn")
    }

    if ($Operator -eq 'none') {
        return @($rawUsername)
    }

    return @("$rawUsername@$Operator")
}

function Resolve-ServerCandidates {
    if ($Server) {
        return @($Server)
    }
    return @('https://login.cup.edu.cn', 'http://login.cup.edu.cn')
}

function Invoke-LoginAttempt([string]$inputUsername, [string]$inputPassword) {
    $usernameCandidates = Resolve-UsernameCandidates $inputUsername
    $servers = Resolve-ServerCandidates
    $srunExe = Get-SrunExe

    $baseArguments = @('login', '-p', $inputPassword, '--acid', $Acid, '--type', $Type, '--retry-times', $RetryTimes, '--retry-delay', $RetryDelay)
    if ($Ip) {
        $baseArguments += @('-i', $Ip)
    } elseif ($DetectIp) {
        $baseArguments += '-d'
    } else {
        throw 'Provide -Ip or enable -DetectIp.'
    }

    Push-Location $PSScriptRoot
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
                try {
                    $output = & $srunExe @arguments 2>&1
                    $exitCode = $LASTEXITCODE
                } catch {
                    $output = @($_ | Out-String)
                    $exitCode = 1
                }

                if ($output) {
                    $output | ForEach-Object { Write-Host $_ }
                }

                $text = ($output | Out-String)
                $portalBlock = Get-LastPortalResponseBlock $text

                $isPortalOk = $false
                $alreadyOnline = $false
                $hasAccessToken = $false

                if ($portalBlock) {
                    $isPortalOk = ($portalBlock -match 'error:\s*"ok"' -and $portalBlock -match 'res:\s*"ok"')
                    $alreadyOnline = ($portalBlock -match 'suc_msg:\s*"ip_already_online_error"')
                    $tokenMatch = [regex]::Match($portalBlock, 'access_token:\s*"([^"]*)"')
                    if ($tokenMatch.Success) {
                        $hasAccessToken = [string]::IsNullOrWhiteSpace($tokenMatch.Groups[1].Value) -eq $false
                    }
                }

                if ($isPortalOk -and ($hasAccessToken -or $alreadyOnline)) {
                    if ($alreadyOnline) {
                        Write-ResultFile 'already_online' 'Already online' 'Already online.'
                    } else {
                        Write-ResultFile 'success' 'Login succeeded' 'Login succeeded!'
                    }
                    Save-LastUsername $usernameCandidate
                    Save-SavedCredential $usernameCandidate $inputPassword

                    return @{
                        Success = $true
                        Status = if ($alreadyOnline) { 'already_online' } else { 'success' }
                        Message = if ($alreadyOnline) { 'Already online.' } else { 'Login succeeded!' }
                    }
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

        Clear-SavedCredential
        Write-ResultFile $lastFailureStatus 'Login failed' $lastFailureMessage

        return @{
            Success = $false
            Status = $lastFailureStatus
            Message = if ($lastFailureStatus -eq 'failed_auth') { 'Username or password is incorrect. Please retry.' } else { 'Login failed. Check network and retry.' }
        }
    } finally {
        Pop-Location
    }
}

function Show-LoginWindow([string]$defaultUsername, [string]$defaultPassword) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        throw
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'srun-cup login'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(420, 260)
    $form.TopMost = $true

    $labelUser = New-Object System.Windows.Forms.Label
    $labelUser.Text = 'Username'
    $labelUser.Location = New-Object System.Drawing.Point(20, 20)
    $labelUser.AutoSize = $true

    $textUser = New-Object System.Windows.Forms.TextBox
    $textUser.Location = New-Object System.Drawing.Point(110, 18)
    $textUser.Size = New-Object System.Drawing.Size(280, 20)
    if ($defaultUsername) {
        $textUser.Text = $defaultUsername
    }

    $labelPass = New-Object System.Windows.Forms.Label
    $labelPass.Text = 'Password'
    $labelPass.Location = New-Object System.Drawing.Point(20, 58)
    $labelPass.AutoSize = $true

    $textPass = New-Object System.Windows.Forms.TextBox
    $textPass.Location = New-Object System.Drawing.Point(110, 56)
    $textPass.Size = New-Object System.Drawing.Size(280, 20)
    $textPass.UseSystemPasswordChar = $true
    if ($defaultPassword) {
        $textPass.Text = $defaultPassword
    }

    $checkAutoStart = New-Object System.Windows.Forms.CheckBox
    $checkAutoStart.Text = 'Enable silent startup'
    $checkAutoStart.Location = New-Object System.Drawing.Point(110, 92)
    $checkAutoStart.AutoSize = $true
    $checkAutoStart.Checked = Get-AutoStartEnabled

    $labelTip = New-Object System.Windows.Forms.Label
    $labelTip.Text = Get-LoginHintText
    $labelTip.Location = New-Object System.Drawing.Point(20, 124)
    $labelTip.Size = New-Object System.Drawing.Size(380, 56)
    $labelTip.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

    $buttonLogin = New-Object System.Windows.Forms.Button
    $buttonLogin.Text = 'Login'
    $buttonLogin.Location = New-Object System.Drawing.Point(245, 205)
    $buttonLogin.Size = New-Object System.Drawing.Size(75, 30)

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = 'Close'
    $buttonClose.Location = New-Object System.Drawing.Point(325, 205)
    $buttonClose.Size = New-Object System.Drawing.Size(75, 30)

    $buttonClose.Add_Click({ $form.Close() })

    $buttonLogin.Add_Click({
        $u = $textUser.Text.Trim()
        $p = $textPass.Text

        if (-not $u -or -not $p) {
            $labelTip.Text = 'Please enter username and password.'
            return
        }

        Set-AutoStartEnabled $checkAutoStart.Checked

        $buttonLogin.Enabled = $false
        $labelTip.Text = 'Logging in, please wait...'
        $form.Refresh()

        try {
            $result = Invoke-LoginAttempt $u $p
            if ($result.Success) {
                $labelTip.Text = $result.Message
            } else {
                $labelTip.Text = $result.Message
                $textPass.Text = ''
                $textPass.Focus()
            }
        } catch {
            $labelTip.Text = 'Login failed. Please try again.'
            $textPass.Text = ''
            $textPass.Focus()
        } finally {
            $buttonLogin.Enabled = $true
        }
    })

    $form.Controls.AddRange(@($labelUser, $textUser, $labelPass, $textPass, $checkAutoStart, $labelTip, $buttonLogin, $buttonClose))
    $form.AcceptButton = $buttonLogin
    $form.CancelButton = $buttonClose
    [void]$form.ShowDialog()
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

$defaultUsername = if ($Username) { $Username } elseif ($savedCredential -and $savedCredential.Username) { $savedCredential.Username } else { Get-LastUsername }
$defaultPassword = if ($Password) { $Password } elseif ($savedCredential -and $savedCredential.Password) { $savedCredential.Password } else { '' }

if ($Silent) {
    if (-not $defaultUsername -or -not $defaultPassword) {
        Write-ResultFile 'failed' 'Login failed' 'Silent login skipped because credentials are missing.'
        exit 1
    }

    $silentResult = Invoke-LoginAttempt $defaultUsername $defaultPassword
    if ($silentResult.Success) {
        exit 0
    }
    exit 1
}

Show-LoginWindow $defaultUsername $defaultPassword
exit 0