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
    [switch]$Reconnect,
    [switch]$Tray,
    [int]$ReconnectInterval = 5,
    [switch]$DetectIp = $true,
    [string]$BackupTestFile,
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
$backupCredentialFile = Join-Path $stateRoot '.login-cup.backup-credentials.json'
$activeLoginFile = Join-Path $stateRoot '.login-cup.active-login.json'
$autoStartFlagFile = Join-Path $stateRoot 'silent-startup.enabled'
$reconnectFlagFile = Join-Path $stateRoot 'reconnect.enabled'
$lastResultFile = Join-Path $stateRoot 'login-last-result.txt'
$lastErrorLogFile = Join-Path $stateRoot 'login-last-error.log'
$runSubKey = 'Software\Microsoft\Windows\CurrentVersion\Run'

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

function Protect-LogSecrets([string]$content) {
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $content
    }

    $sanitized = $content
    $sanitized = [regex]::Replace($sanitized, '(?im)(password\s*:\s*")([^"]*)(")', '$1******$3')
    $sanitized = [regex]::Replace($sanitized, '(?im)("password"\s*:\s*")([^"]*)(")', '$1******$3')
    $sanitized = [regex]::Replace($sanitized, '(?im)(password\s*=\s*)([^\s&]+)', '$1******')
    $sanitized = [regex]::Replace($sanitized, '(?im)(\s-p\s+)("[^"]*"|\S+)', '$1******')
    $sanitized = [regex]::Replace($sanitized, '(?im)(\s--password\s+)("[^"]*"|\S+)', '$1******')
    return $sanitized
}

function Write-ErrorLog([string]$content) {
    if ([string]::IsNullOrWhiteSpace($content)) {
        $content = "No detailed error output was captured."
    }
    $content = Protect-LogSecrets $content
    $header = "[" + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') + "]"
    Set-Content -Path $lastErrorLogFile -Value ($header + "`r`n" + $content) -Encoding utf8
}

$script:cupLoginUiLogWriter = $null
$script:cupLoginBackupTestTimers = New-Object System.Collections.ArrayList
$script:cupLoginBackupTestStates = @{}

function Write-UiLog([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) {
        return
    }

    if ($null -ne $script:cupLoginForm -and $script:cupLoginForm.InvokeRequired) {
        try {
            $callback = [System.Action[string]]{
                param([string]$uiMessage)
                if ($null -ne $script:cupLoginUiLogWriter) {
                    try {
                        & $script:cupLoginUiLogWriter $uiMessage
                    } catch {
                    }
                }
            }
            [void]$script:cupLoginForm.BeginInvoke($callback, @($message))
            return
        } catch {
        }
    }

    if ($null -ne $script:cupLoginUiLogWriter) {
        try {
            & $script:cupLoginUiLogWriter $message
        } catch {
        }
    }
}

function Set-CupLoginAppUserModelId {
    $type = 'CupLoginShell.AppUserModelId'
    if (-not ($type -as [type])) {
        Add-Type -TypeDefinition @'
namespace CupLoginShell {
    using System.Runtime.InteropServices;

    public static class AppUserModelId {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        public static extern void SetCurrentProcessExplicitAppUserModelID(string appId);
    }
}
'@ -ErrorAction Stop
    }

    [CupLoginShell.AppUserModelId]::SetCurrentProcessExplicitAppUserModelID('CUPLogin.CUPLogin')
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
        'failed_auth' { return '账号或密码错误，请重试。' }
        'failed_proxy' { return '请先关闭代理/VPN，再重试。' }
        'failed' { return '上次登录失败，请检查网络或设置后重试。' }
        'needs_credentials' { return '请输入一次账号和密码以启用登录。' }
        default { return '登录成功后会在本机保存凭据。' }
    }
}

function Get-DisplayAccountLabel([string]$label) {
    if (-not $label -or $label -eq 'Main account') {
        return '主账号'
    }

    $match = [regex]::Match($label, '^Backup account\s+(\d+)$')
    if ($match.Success) {
        return "备用账号 $($match.Groups[1].Value)"
    }

    return $label
}

function Get-MaskedPassword([string]$password) {
    if (-not $password) {
        return '******'
    }

    $count = [Math]::Min([Math]::Max($password.Length, 6), 12)
    return ''.PadLeft($count, '*')
}

function Remove-OperatorSuffix([string]$username) {
    if (-not $username) {
        return ''
    }

    return ($username -replace '@[^@\s]+$', '')
}

function Test-ProxyOrVpnPortalError([string]$text) {
    if (-not $text) {
        return $false
    }

    return ($text -match 'Unexpected EOF|unexpectedly closed|connection.*closed|WebException|Network Error')
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
            return (Remove-OperatorSuffix $saved)
        }
    }
    return ''
}

function Protect-LoginText([string]$value) {
    if ($null -eq $value) {
        $value = ''
    }

    $secure = ConvertTo-SecureString $value -AsPlainText -Force
    return ($secure | ConvertFrom-SecureString)
}

function Unprotect-LoginText([string]$value) {
    if (-not $value) {
        return ''
    }

    $secure = $value | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Save-LastUsername([string]$value) {
    if (-not $value) {
        return
    }
    $value = Remove-OperatorSuffix $value
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

        return @{
            Username = Remove-OperatorSuffix ([string]$obj.username)
            Password = [string](Unprotect-LoginText ([string]$obj.password))
        }
    } catch {
        return $null
    }
}

function Save-SavedCredential([string]$username, [string]$password) {
    if (-not $username -or -not $password) {
        return
    }

    $username = Remove-OperatorSuffix $username
    $payload = @{
        username = $username
        password = Protect-LoginText $password
    } | ConvertTo-Json

    Set-Content -Path $savedCredentialFile -Value $payload -Encoding ascii
}

function Get-BackupTestMark([string]$status) {
    switch ($status) {
        'ok' { return [char]0x221A }
        'failed' { return [char]0x00D7 }
        default { return [char]0x25CF }
    }
}

function Get-BackupTestStatus([string]$status) {
    switch ($status) {
        'ok' { return 'ok' }
        'failed' { return 'failed' }
        default { return 'untested' }
    }
}

function Clear-SavedCredential {
    Remove-Item -Path $savedCredentialFile -ErrorAction SilentlyContinue
}

function Get-BackupCredentials {
    $accounts = @()
    if (-not (Test-Path $backupCredentialFile)) {
        return $accounts
    }

    try {
        $raw = Get-Content $backupCredentialFile -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($item in @($obj.accounts)) {
            if (-not $item.username -or -not $item.password) {
                continue
            }

            $accounts += [pscustomobject]@{
                Username = [string]$item.username
                Password = [string](Unprotect-LoginText ([string]$item.password))
                TestStatus = Get-BackupTestStatus ([string]$item.test_status)
                TestTime = if ($item.test_time) { [string]$item.test_time } else { '' }
            }
        }
    } catch {
        return @()
    }

    return $accounts
}

function Save-BackupCredentials([object[]]$accounts) {
    $payloadAccounts = @()
    foreach ($account in @($accounts)) {
        if (-not $account.Username -or -not $account.Password) {
            continue
        }

        $payloadAccounts += [pscustomobject]@{
            username = [string]$account.Username
            password = Protect-LoginText ([string]$account.Password)
            test_status = Get-BackupTestStatus ([string]$account.TestStatus)
            test_time = if ($account.TestTime) { [string]$account.TestTime } else { '' }
        }
    }

    $payload = @{
        accounts = $payloadAccounts
    } | ConvertTo-Json -Depth 4
    Set-Content -Path $backupCredentialFile -Value $payload -Encoding ascii
}

function Set-ActiveLogin([string]$username, [string]$label) {
    if (-not $username) {
        return
    }

    $payload = @{
        username = $username
        label = if ($label) { $label } else { 'Main account' }
        time = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
    } | ConvertTo-Json
    Set-Content -Path $activeLoginFile -Value $payload -Encoding ascii
}

function Get-ActiveLogin {
    if (-not (Test-Path $activeLoginFile)) {
        return $null
    }

    try {
        $raw = Get-Content $activeLoginFile -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $obj.username) {
            return $null
        }

        return @{
            Username = [string]$obj.username
            Label = if ($obj.label) { [string]$obj.label } else { 'Main account' }
        }
    } catch {
        return $null
    }
}

function Clear-ActiveLogin {
    Remove-Item -Path $activeLoginFile -ErrorAction SilentlyContinue
}

function Get-AutoStartCommand {
    return '"wscript.exe" //B //Nologo "' + (Join-Path $PSScriptRoot 'login-cup.vbs') + '" --tray'
}

function Get-ReconnectCommand {
    return '"wscript.exe" //B //Nologo "' + (Join-Path $PSScriptRoot 'login-cup.vbs') + '" --tray'
}

function Get-RunValue([string]$name) {
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($runSubKey, $false)
        if ($null -eq $key) {
            return $null
        }
        return [string]$key.GetValue($name, $null)
    } catch {
        return $null
    } finally {
        if ($null -ne $key) {
            $key.Close()
        }
    }
}

function Set-RunValue([string]$name, [string]$value) {
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($runSubKey)
        $key.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]::String)
    } finally {
        if ($null -ne $key) {
            $key.Close()
        }
    }
}

function Remove-RunValue([string]$name) {
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($runSubKey, $true)
        if ($null -ne $key) {
            $key.DeleteValue($name, $false)
        }
    } finally {
        if ($null -ne $key) {
            $key.Close()
        }
    }
}

function Get-AutoStartEnabled {
    if (Test-Path $autoStartFlagFile) {
        return $true
    }

    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'CUP Login.lnk'

    if (Test-Path $startupShortcut) {
        return $true
    }

    $value = Get-RunValue 'CUP Login'
    if ($value -and $value -match 'login-cup\.vbs') {
        return $true
    }

    $legacyValue = Get-RunValue 'srun-cup'
    return ($legacyValue -and $legacyValue -match 'login-cup\.vbs')
}

function Update-TrayStartupEntry {
    $startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'CUP Login.lnk'
    $legacyStartupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'srun-cup.lnk'
    $cmd = Get-AutoStartCommand
    $enabled = (Test-Path $autoStartFlagFile) -or (Test-Path $reconnectFlagFile)

    if ($enabled) {
        Set-RunValue 'CUP Login' $cmd
        Remove-RunValue 'CUP Login Reconnect'
        Remove-RunValue 'srun-cup'
    } else {
        Remove-RunValue 'CUP Login'
        Remove-RunValue 'CUP Login Reconnect'
        Remove-RunValue 'srun-cup'
        Remove-Item -Path $startupShortcut -ErrorAction SilentlyContinue
        Remove-Item -Path $legacyStartupShortcut -ErrorAction SilentlyContinue
    }
}

function Sync-LegacyStartupState {
    $startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'CUP Login.lnk'
    $legacyStartupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'srun-cup.lnk'
    $autoStartValue = Get-RunValue 'CUP Login'
    $legacyAutoStartValue = Get-RunValue 'srun-cup'
    $reconnectValue = Get-RunValue 'CUP Login Reconnect'

    if ((-not (Test-Path $autoStartFlagFile)) -and (
        (Test-Path $startupShortcut) -or
        (Test-Path $legacyStartupShortcut) -or
        ($autoStartValue -and $autoStartValue -match 'login-cup\.vbs') -or
        ($legacyAutoStartValue -and $legacyAutoStartValue -match 'login-cup\.vbs')
    )) {
        Set-Content -Path $autoStartFlagFile -Value 'enabled' -Encoding ascii
    }

    if ((-not (Test-Path $reconnectFlagFile)) -and ($reconnectValue -and $reconnectValue -match 'login-cup\.vbs')) {
        Set-Content -Path $reconnectFlagFile -Value 'enabled' -Encoding ascii
    }
}

function Set-AutoStartEnabled([bool]$enabled) {
    if ($enabled) {
        Set-Content -Path $autoStartFlagFile -Value 'enabled' -Encoding ascii
    } else {
        Remove-Item -Path $autoStartFlagFile -ErrorAction SilentlyContinue
    }
    Update-TrayStartupEntry
}

function Get-ReconnectEnabled {
    return (Test-Path $reconnectFlagFile)
}

function Set-ReconnectEnabled([bool]$enabled) {
    if ($enabled) {
        Set-Content -Path $reconnectFlagFile -Value 'enabled' -Encoding ascii
    } else {
        Remove-Item -Path $reconnectFlagFile -ErrorAction SilentlyContinue
    }
    Update-TrayStartupEntry
}

function Resolve-UsernameCandidates([string]$rawUsername) {
    return @($rawUsername)
}

function Resolve-ServerCandidates {
    if ($Server) {
        return @($Server)
    }
    return @('https://login.cup.edu.cn', 'http://login.cup.edu.cn')
}

function Invoke-LoginAttempt([string]$inputUsername, [string]$inputPassword, [bool]$clearCredentialOnFailure = $true, [bool]$saveCredentialOnSuccess = $true, [string]$accountLabel = 'Main account') {
    $usernameCandidates = Resolve-UsernameCandidates $inputUsername
    $servers = Resolve-ServerCandidates
    $srunExe = Get-SrunExe
    $displayAccountLabel = Get-DisplayAccountLabel $accountLabel

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
        Write-ResultFile 'running' '正在登录' '正在尝试登录校园网...'
        Write-UiLog "开始登录：$displayAccountLabel"
        $attempt = 0
        $totalAttempts = $servers.Count * $usernameCandidates.Count
        $lastError = ''
        $lastFailureStatus = 'failed'
        $lastFailureMessage = "登录失败，详情见 $lastErrorLogFile"

        :serverLoop foreach ($serverCandidate in $servers) {
            foreach ($usernameCandidate in $usernameCandidates) {
                $attempt += 1
                Write-Host "[Attempt $attempt/$totalAttempts] server=$serverCandidate username=$usernameCandidate acid=$Acid type=$Type"
                Write-UiLog "尝试 $displayAccountLabel：服务器 $serverCandidate"

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
                        Write-ResultFile 'already_online' '已在线' '当前已在线。'
                    } else {
                        Write-ResultFile 'success' '登录成功' '登录成功！'
                    }
                    if ($saveCredentialOnSuccess) {
                        Save-LastUsername $inputUsername
                        Save-SavedCredential $inputUsername $inputPassword
                    }
                    Set-ActiveLogin $usernameCandidate $accountLabel
                    if ($alreadyOnline) {
                        Write-UiLog "已在线：$displayAccountLabel"
                    } else {
                        Write-UiLog "登录成功：$displayAccountLabel"
                    }

                    return @{
                        Success = $true
                        Status = if ($alreadyOnline) { 'already_online' } else { 'success' }
                        Message = if ($alreadyOnline) { '当前已在线。' } else { '登录成功！' }
                        Username = $usernameCandidate
                        AccountLabel = $accountLabel
                    }
                }

                $lastError = $text
                Write-ErrorLog $text

                $shouldStopThisAccount = $false
                if (Test-ProxyOrVpnPortalError $text) {
                    $lastFailureStatus = 'failed_proxy'
                    $lastFailureMessage = '请先关闭代理/VPN，再重试。'
                    $shouldStopThisAccount = $true
                    Write-UiLog "$displayAccountLabel 登录失败：检测到代理或 VPN 影响"
                } elseif ($text -match 'Authentication fail') {
                    $lastFailureStatus = 'failed_auth'
                    $lastFailureMessage = '账号或密码错误。'
                    $shouldStopThisAccount = $true
                    Write-UiLog "$displayAccountLabel 登录失败：账号或密码错误"
                } elseif ($text -match 'login_error|Unknow ac-type') {
                    $lastFailureStatus = 'failed'
                    $lastFailureMessage = "登录失败，详情见 $lastErrorLogFile"
                    Write-UiLog "$displayAccountLabel 登录失败：认证服务器返回错误"
                } else {
                    $lastFailureStatus = 'failed'
                    $lastFailureMessage = "登录失败，详情见 $lastErrorLogFile"
                    Write-UiLog "$displayAccountLabel 登录失败：网络或认证响应异常"
                }

                if ($exitCode -eq 0 -and $servers.Count -eq 1 -and $usernameCandidates.Count -eq 1) {
                    Write-Host 'Command exited 0 but portal did not return success payload.'
                }

                if ($text -match 'need username|need password|need ip|parse args error') {
                    break serverLoop
                }

                if ($shouldStopThisAccount) {
                    break serverLoop
                }
            }
        }

        if (-not (Test-Path $lastErrorLogFile)) {
            Write-ErrorLog $lastError
        }

        if ($clearCredentialOnFailure) {
            Clear-SavedCredential
        }
        Write-ResultFile $lastFailureStatus '登录失败' $lastFailureMessage

        $failureMessage = '登录失败，请检查网络后重试。'
        if ($lastFailureStatus -eq 'failed_auth') {
            $failureMessage = '账号或密码错误，请重试。'
        } elseif ($lastFailureStatus -eq 'failed_proxy') {
            $failureMessage = '请先关闭代理/VPN，再重试。'
        }

        return @{
            Success = $false
            Status = $lastFailureStatus
            Message = $failureMessage
            Username = $inputUsername
            AccountLabel = $accountLabel
        }
    } finally {
        Pop-Location
    }
}

function Invoke-LoginWithBackupAccounts([string]$inputUsername, [string]$inputPassword, [bool]$clearCredentialOnFailure = $true) {
    Write-UiLog '优先尝试主账号'
    $mainResult = Invoke-LoginAttempt $inputUsername $inputPassword $false $true 'Main account'
    if ($mainResult.Success) {
        return $mainResult
    }

    $backupAccounts = @(Get-BackupCredentials)
    if ($backupAccounts.Count -eq 0) {
        Write-UiLog '没有配置备用账号'
        return $mainResult
    }

    Write-UiLog "主账号失败，准备尝试备用账号（$($backupAccounts.Count) 个）"
    $backupIndex = 0
    foreach ($backup in $backupAccounts) {
        $backupIndex += 1
        if (-not $backup.Username -or -not $backup.Password) {
            continue
        }

        $backupLabel = "Backup account $backupIndex"
        $backupLabelText = Get-DisplayAccountLabel $backupLabel
        Write-ResultFile 'backup_running' '正在尝试备用账号' "正在尝试$backupLabelText..."
        Write-UiLog "尝试$backupLabelText"
        $backupResult = Invoke-LoginAttempt ([string]$backup.Username) ([string]$backup.Password) $false $false $backupLabel
        if ($backupResult.Success) {
            Save-LastUsername $inputUsername
            Save-SavedCredential $inputUsername $inputPassword
            $backupResult['Status'] = 'backup_success'
            $backupResult['Message'] = "主账号登录失败，已使用$backupLabelText登录。"
            Write-ResultFile 'backup_success' '备用账号登录成功' $backupResult['Message']
            Write-UiLog "备用账号登录成功：$backupLabelText"
            return $backupResult
        }
    }

    Write-ResultFile 'failed' '登录失败' '主账号和备用账号均登录失败。'
    Write-UiLog '主账号和备用账号均登录失败'
    return @{
        Success = $false
        Status = 'failed'
        Message = '主账号和备用账号均登录失败。'
        Username = $inputUsername
        AccountLabel = 'Main account'
    }
}

function Invoke-LogoutAttempt([string]$inputUsername) {
    $usernameCandidates = Resolve-UsernameCandidates $inputUsername
    $servers = Resolve-ServerCandidates
    $srunExe = Get-SrunExe
    Write-UiLog "开始注销：$(Remove-OperatorSuffix $inputUsername)"

    $baseArguments = @('logout', '--acid', $Acid)
    if ($Ip) {
        $baseArguments += @('-i', $Ip)
    } elseif ($DetectIp) {
        $baseArguments += '-d'
    } else {
        throw 'Provide -Ip or enable -DetectIp.'
    }

    Push-Location $PSScriptRoot
    try {
        Write-ResultFile 'running' '正在注销' '正在尝试注销校园网...'
        $lastError = ''

        foreach ($serverCandidate in $servers) {
            foreach ($usernameCandidate in $usernameCandidates) {
                $arguments = @('logout', '-s', $serverCandidate, '-u', $usernameCandidate) + $baseArguments[1..($baseArguments.Count - 1)]
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

                $lastError = ($output | Out-String)
                Write-ErrorLog $lastError

                if ($exitCode -eq 0) {
                    Write-ResultFile 'logout_success' '注销成功' '注销成功。'
                    Write-UiLog '注销成功'
                    return @{
                        Success = $true
                        Message = '注销成功。'
                    }
                }
            }
        }

        Write-ErrorLog $lastError
        Write-ResultFile 'failed' '注销失败' "注销失败，详情见 $lastErrorLogFile"
        Write-UiLog '注销失败'
        return @{
            Success = $false
            Message = '注销失败，请检查网络后重试。'
        }
    } finally {
        Pop-Location
    }
}

function Test-CaptivePortalLocation([string]$sourceUrl, [string]$location) {
    if ([string]::IsNullOrWhiteSpace($location)) {
        return $false
    }

    try {
        $source = [Uri]$sourceUrl
        $target = [Uri]$location
        if ($target.Host -eq $source.Host) {
            return $false
        }

        if ($target.Host -match '(^|\.)login\.cup\.edu\.cn$') {
            return $true
        }

        return ($target.AbsoluteUri -match '(?i)srun|portal|eportal|userportal|ac_id|wlanuserip')
    } catch {
        return ($location -match '(?i)login\.cup\.edu\.cn|srun|portal|eportal|userportal|ac_id|wlanuserip')
    }
}

function Test-CaptivePortalEndpoint([string]$url, [int]$expectedStatus, [string]$expectedBody) {
    try {
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.AllowAutoRedirect = $false
        $request.Method = 'GET'
        $request.Timeout = 3000
        $request.ReadWriteTimeout = 3000
        $request.UserAgent = 'CUP Login connectivity check'

        try {
            $response = $request.GetResponse()
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $response = $_.Exception.Response
            } else {
                return @{
                    Online = $false
                    Redirected = $false
                    Status = 0
                }
            }
        }

        try {
            $status = [int]$response.StatusCode
            $location = $response.Headers['Location']

            if ($status -ge 300 -and $status -lt 400) {
                $isPortalRedirect = Test-CaptivePortalLocation $url $location
                return @{
                    Online = $false
                    Redirected = $isPortalRedirect
                    Status = $status
                    Location = $location
                }
            }

            if ($status -eq $expectedStatus) {
                if ($expectedBody) {
                    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                    try {
                        $body = $reader.ReadToEnd()
                    } finally {
                        $reader.Dispose()
                    }

                    return @{
                        Online = ($body -like "*$expectedBody*")
                        Redirected = $false
                        Status = $status
                    }
                }

                return @{
                    Online = $true
                    Redirected = $false
                    Status = $status
                }
            }

            return @{
                Online = $false
                Redirected = $false
                Status = $status
            }
        } finally {
            if ($response) {
                $response.Close()
            }
        }
    } catch {
        return @{
            Online = $false
            Redirected = $false
            Status = 0
        }
    }
}

function Test-CaptivePortalRedirect {
    $checks = @(
        @{ Url = 'http://www.msftconnecttest.com/connecttest.txt'; Status = 200; Body = 'Microsoft Connect Test' },
        @{ Url = 'http://connectivitycheck.gstatic.com/generate_204'; Status = 204; Body = '' },
        @{ Url = 'http://connect.rom.miui.com/generate_204'; Status = 204; Body = '' }
    )

    foreach ($check in $checks) {
        $result = Test-CaptivePortalEndpoint $check.Url $check.Status $check.Body
        if ($result.Online) {
            return $false
        }

        if ($result.Redirected) {
            Write-UiLog '检测到认证页重定向'
            return $true
        }
    }

    return $false
}

function Register-ReconnectNetworkEvents {
    try {
        Get-EventSubscriber -SourceIdentifier 'CupLoginNetworkAddressChanged' -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
        Get-EventSubscriber -SourceIdentifier 'CupLoginNetworkAvailabilityChanged' -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
        Register-ObjectEvent -InputObject ([System.Net.NetworkInformation.NetworkChange]) -EventName NetworkAddressChanged -SourceIdentifier 'CupLoginNetworkAddressChanged' | Out-Null
        Register-ObjectEvent -InputObject ([System.Net.NetworkInformation.NetworkChange]) -EventName NetworkAvailabilityChanged -SourceIdentifier 'CupLoginNetworkAvailabilityChanged' | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Clear-ReconnectNetworkEvents {
    Get-EventSubscriber -SourceIdentifier 'CupLoginNetworkAddressChanged' -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
    Get-EventSubscriber -SourceIdentifier 'CupLoginNetworkAvailabilityChanged' -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier 'CupLoginNetworkAddressChanged' -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier 'CupLoginNetworkAvailabilityChanged' -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
}

function Invoke-ReconnectLoginIfNeeded([string]$inputUsername, [string]$inputPassword) {
    if (-not (Test-CaptivePortalRedirect)) {
        Write-ResultFile 'online' '网络正常' '未检测到认证页重定向。'
        return $true
    }

    Write-ResultFile 'reconnecting' '正在重连' '检测到认证页重定向。'
    $reconnectResult = Invoke-LoginWithBackupAccounts $inputUsername $inputPassword $false
    if (-not $reconnectResult.Success -and $reconnectResult.Status -eq 'failed_auth') {
        Start-InteractiveLoginWindow
        return $false
    }

    return $true
}

function Show-BackupAccountsWindow([System.Windows.Forms.Form]$owner, [string]$mainUsername, [string]$mainPassword, [scriptblock]$setReconnectUi) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '备用账号'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(480, 310)

    $accounts = New-Object System.Collections.ArrayList
    foreach ($account in @(Get-BackupCredentials)) {
        [void]$accounts.Add([pscustomobject]@{
            Username = [string]$account.Username
            Password = [string]$account.Password
            TestStatus = Get-BackupTestStatus ([string]$account.TestStatus)
            TestTime = if ($account.TestTime) { [string]$account.TestTime } else { '' }
        })
    }

    $listAccounts = New-Object System.Windows.Forms.ListBox
    $listAccounts.Location = New-Object System.Drawing.Point(15, 15)
    $listAccounts.Size = New-Object System.Drawing.Size(190, 225)
    $listAccounts.Font = New-Object System.Drawing.Font('Consolas', 9)

    $labelBackupUser = New-Object System.Windows.Forms.Label
    $labelBackupUser.Text = '账号'
    $labelBackupUser.Location = New-Object System.Drawing.Point(225, 20)
    $labelBackupUser.AutoSize = $true

    $textBackupUser = New-Object System.Windows.Forms.TextBox
    $textBackupUser.Location = New-Object System.Drawing.Point(305, 18)
    $textBackupUser.Size = New-Object System.Drawing.Size(150, 20)

    $labelBackupPass = New-Object System.Windows.Forms.Label
    $labelBackupPass.Text = '密码'
    $labelBackupPass.Location = New-Object System.Drawing.Point(225, 58)
    $labelBackupPass.AutoSize = $true

    $textBackupPass = New-Object System.Windows.Forms.TextBox
    $textBackupPass.Location = New-Object System.Drawing.Point(305, 56)
    $textBackupPass.Size = New-Object System.Drawing.Size(150, 20)
    $textBackupPass.UseSystemPasswordChar = $true

    $labelBackupTip = New-Object System.Windows.Forms.Label
    $labelBackupTip.Text = '主账号登录失败后，才会按顺序尝试备用账号。'
    $labelBackupTip.Location = New-Object System.Drawing.Point(225, 92)
    $labelBackupTip.Size = New-Object System.Drawing.Size(230, 42)

    $buttonAdd = New-Object System.Windows.Forms.Button
    $buttonAdd.Text = '添加'
    $buttonAdd.Location = New-Object System.Drawing.Point(225, 145)
    $buttonAdd.Size = New-Object System.Drawing.Size(70, 28)

    $buttonUpdate = New-Object System.Windows.Forms.Button
    $buttonUpdate.Text = '更新'
    $buttonUpdate.Location = New-Object System.Drawing.Point(305, 145)
    $buttonUpdate.Size = New-Object System.Drawing.Size(70, 28)

    $buttonDelete = New-Object System.Windows.Forms.Button
    $buttonDelete.Text = '删除'
    $buttonDelete.Location = New-Object System.Drawing.Point(385, 145)
    $buttonDelete.Size = New-Object System.Drawing.Size(70, 28)

    $buttonUp = New-Object System.Windows.Forms.Button
    $buttonUp.Text = '上移'
    $buttonUp.Location = New-Object System.Drawing.Point(225, 185)
    $buttonUp.Size = New-Object System.Drawing.Size(70, 28)

    $buttonDown = New-Object System.Windows.Forms.Button
    $buttonDown.Text = '下移'
    $buttonDown.Location = New-Object System.Drawing.Point(305, 185)
    $buttonDown.Size = New-Object System.Drawing.Size(70, 28)

    $buttonTest = New-Object System.Windows.Forms.Button
    $buttonTest.Text = '测试'
    $buttonTest.Location = New-Object System.Drawing.Point(385, 185)
    $buttonTest.Size = New-Object System.Drawing.Size(70, 28)

    $buttonSave = New-Object System.Windows.Forms.Button
    $buttonSave.Text = '保存'
    $buttonSave.Location = New-Object System.Drawing.Point(300, 260)
    $buttonSave.Size = New-Object System.Drawing.Size(75, 30)

    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Text = '取消'
    $buttonCancel.Location = New-Object System.Drawing.Point(385, 260)
    $buttonCancel.Size = New-Object System.Drawing.Size(75, 30)

    $refreshList = {
        $previousIndex = $listAccounts.SelectedIndex
        $listAccounts.Items.Clear()
        for ($i = 0; $i -lt $accounts.Count; $i++) {
            $name = [string]$accounts[$i].Username
            if (-not $name) {
                $name = '(未填写账号)'
            }
            $mask = Get-MaskedPassword ([string]$accounts[$i].Password)
            $mark = Get-BackupTestMark ([string]$accounts[$i].TestStatus)
            [void]$listAccounts.Items.Add(("{0} {1}   {2}" -f $mark, $name, $mask))
        }

        if ($accounts.Count -gt 0) {
            if ($previousIndex -lt 0) {
                $previousIndex = 0
            }
            if ($previousIndex -ge $accounts.Count) {
                $previousIndex = $accounts.Count - 1
            }
            $listAccounts.SelectedIndex = $previousIndex
        } else {
            $textBackupUser.Text = ''
            $textBackupPass.Text = ''
        }
    }

    $loadSelected = {
        $index = $listAccounts.SelectedIndex
        if ($index -lt 0 -or $index -ge $accounts.Count) {
            return
        }
        $textBackupUser.Text = [string]$accounts[$index].Username
        $textBackupPass.Text = [string]$accounts[$index].Password
    }

    $listAccounts.Add_SelectedIndexChanged($loadSelected)

    $buttonAdd.Add_Click({
        $u = $textBackupUser.Text.Trim()
        $p = $textBackupPass.Text
        if (-not $u -or -not $p) {
            $labelBackupTip.Text = '请输入账号和密码。'
            return
        }

        [void]$accounts.Add([pscustomobject]@{
            Username = $u
            Password = $p
            TestStatus = 'untested'
            TestTime = ''
        })
        & $refreshList
        $listAccounts.SelectedIndex = $accounts.Count - 1
        $labelBackupTip.Text = '已添加备用账号。'
    })

    $buttonUpdate.Add_Click({
        $index = $listAccounts.SelectedIndex
        if ($index -lt 0 -or $index -ge $accounts.Count) {
            $labelBackupTip.Text = '请先选择一个备用账号。'
            return
        }

        $u = $textBackupUser.Text.Trim()
        $p = $textBackupPass.Text
        if (-not $u -or -not $p) {
            $labelBackupTip.Text = '请输入账号和密码。'
            return
        }

        $accounts[$index] = [pscustomobject]@{
            Username = $u
            Password = $p
            TestStatus = 'untested'
            TestTime = ''
        }
        & $refreshList
        $listAccounts.SelectedIndex = $index
        $labelBackupTip.Text = '已更新备用账号。'
    })

    $buttonDelete.Add_Click({
        $index = $listAccounts.SelectedIndex
        if ($index -lt 0 -or $index -ge $accounts.Count) {
            return
        }

        $accounts.RemoveAt($index)
        & $refreshList
        $labelBackupTip.Text = '已删除备用账号。'
    })

    $buttonUp.Add_Click({
        $index = $listAccounts.SelectedIndex
        if ($index -le 0) {
            return
        }

        $item = $accounts[$index]
        $accounts.RemoveAt($index)
        $accounts.Insert($index - 1, $item)
        & $refreshList
        $listAccounts.SelectedIndex = $index - 1
    })

    $buttonDown.Add_Click({
        $index = $listAccounts.SelectedIndex
        if ($index -lt 0 -or $index -ge ($accounts.Count - 1)) {
            return
        }

        $item = $accounts[$index]
        $accounts.RemoveAt($index)
        $accounts.Insert($index + 1, $item)
        & $refreshList
        $listAccounts.SelectedIndex = $index + 1
    })

    $buttonTest.Add_Click({
        $index = $listAccounts.SelectedIndex
        if ($index -lt 0 -or $index -ge $accounts.Count) {
            $labelBackupTip.Text = '请先选择一个备用账号。'
            return
        }

        $backupUsername = [string]$accounts[$index].Username
        $backupPassword = [string]$accounts[$index].Password
        if (-not $backupUsername -or -not $backupPassword) {
            $labelBackupTip.Text = '备用账号或密码为空。'
            return
        }

        $mainUsernameForRestore = Remove-OperatorSuffix $mainUsername
        $mainPasswordForRestore = $mainPassword
        if (-not $mainUsernameForRestore -or -not $mainPasswordForRestore) {
            $savedCredential = Get-SavedCredential
            if ($savedCredential) {
                $mainUsernameForRestore = [string]$savedCredential.Username
                $mainPasswordForRestore = [string]$savedCredential.Password
            }
        }

        $buttons = @($buttonAdd, $buttonUpdate, $buttonDelete, $buttonUp, $buttonDown, $buttonTest, $buttonSave, $buttonCancel)
        foreach ($button in $buttons) {
            $button.Enabled = $false
        }
        $labelBackupTip.Text = '正在测试，请稍候...'
        $wasReconnectEnabled = Get-ReconnectEnabled
        if ($setReconnectUi) {
            & $setReconnectUi $false
        }

        $testId = [Guid]::NewGuid().ToString('N')
        $testFile = Join-Path $stateRoot "backup-test-$testId.json"
        $resultFile = Join-Path $stateRoot "backup-test-$testId.result.json"
        $payload = [pscustomobject]@{
            backup_username = [string]$backupUsername
            backup_password = Protect-LoginText ([string]$backupPassword)
            main_username = [string]$mainUsernameForRestore
            main_password = Protect-LoginText ([string]$mainPasswordForRestore)
            restore_reconnect = if ($wasReconnectEnabled) { 'true' } else { 'false' }
            result_path = $resultFile
        }
        $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $testFile -Encoding UTF8

        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $PSScriptRoot 'login-cup.ps1' }
        $arguments = @(
            '-WindowStyle', 'Hidden',
            '-STA',
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"' + $scriptPath.Replace('"', '""') + '"'),
            '-BackupTestFile', ('"' + $testFile.Replace('"', '""') + '"')
        )
        try {
            Write-UiLog "开始测试备用账号：$(Remove-OperatorSuffix $backupUsername)"
            $testProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
        } catch {
            if ($setReconnectUi) {
                & $setReconnectUi $wasReconnectEnabled
            }
            foreach ($button in $buttons) {
                $button.Enabled = $true
            }
            Remove-Item -Path $testFile, $resultFile -ErrorAction SilentlyContinue
            $labelBackupTip.Text = '测试启动失败。'
            return
        }

        $pollTimer = New-Object System.Windows.Forms.Timer
        $pollTimer.Interval = 500
        $timerKey = [string]$pollTimer.GetHashCode()
        $script:cupLoginBackupTestStates[$timerKey] = [pscustomobject]@{
            TestFile = $testFile
            ResultFile = $resultFile
            Process = $testProcess
            StartedAt = [DateTime]::Now
            RestoreReconnect = [bool]$wasReconnectEnabled
            SetReconnectUi = $setReconnectUi
            Buttons = $buttons
            Label = $labelBackupTip
            Accounts = $accounts
            Index = [int]$index
            RefreshList = $refreshList
            List = $listAccounts
        }
        [void]$script:cupLoginBackupTestTimers.Add($pollTimer)
        $pollTimer.Add_Tick({
            param($sender, $eventArgs)

            $stateKey = [string]$sender.GetHashCode()
            $state = $script:cupLoginBackupTestStates[$stateKey]
            if (-not $state) {
                $sender.Stop()
                $sender.Dispose()
                [void]$script:cupLoginBackupTestTimers.Remove($sender)
                return
            }

            $hasResult = ($state.ResultFile -and (Test-Path $state.ResultFile))
            try {
                $state.Process.Refresh()
            } catch {
            }

            $processExited = $true
            try {
                $processExited = [bool]$state.Process.HasExited
            } catch {
                $processExited = $true
            }

            $timedOut = (([DateTime]::Now - $state.StartedAt).TotalSeconds -ge 120)
            if ((-not $hasResult) -and (-not $processExited) -and (-not $timedOut)) {
                return
            }

            $sender.Stop()
            $sender.Dispose()
            [void]$script:cupLoginBackupTestTimers.Remove($sender)
            $script:cupLoginBackupTestStates.Remove($stateKey)
            if ($state.SetReconnectUi) {
                & $state.SetReconnectUi ([bool]$state.RestoreReconnect)
            }
            foreach ($button in @($state.Buttons)) {
                $button.Enabled = $true
            }

            if ($timedOut -and (-not $hasResult)) {
                try {
                    if (-not $state.Process.HasExited) {
                        $state.Process.Kill()
                    }
                } catch {
                }
                Remove-Item -Path @($state.TestFile, $state.ResultFile) -ErrorAction SilentlyContinue
                $state.Label.Text = '测试超时，请稍后重试。'
                Write-UiLog '备用账号测试超时'
                return
            }

            $result = $null
            if ($hasResult) {
                try {
                    $result = Get-Content -Path $state.ResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
                } catch {
                    $result = $null
                }
            }
            Remove-Item -Path @($state.TestFile, $state.ResultFile) -ErrorAction SilentlyContinue

            if (-not $result) {
                $state.Label.Text = '测试失败，请检查备用账号。'
                Write-UiLog '备用账号测试未返回结果'
                return
            }

            $resultIndex = [int]$state.Index
            if ($resultIndex -lt 0 -or $resultIndex -ge $state.Accounts.Count) {
                $state.Label.Text = '测试已完成，但账号列表已变化。'
                return
            }

            if ([bool]$result.backup_success) {
                $state.Accounts[$resultIndex].TestStatus = 'ok'
                $state.Accounts[$resultIndex].TestTime = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
                Save-BackupCredentials @($state.Accounts)
                & $state.RefreshList
                $state.List.SelectedIndex = $resultIndex
                if ([bool]$result.restore_success) {
                    $state.Label.Text = '测试成功，已切回主账号。'
                } elseif ([bool]$result.has_main_credential) {
                    $state.Label.Text = '测试成功，但切回主账号失败；当前可能仍在备用账号。'
                } else {
                    $state.Label.Text = '测试成功，请手动登录主账号。'
                }
            } else {
                $state.Accounts[$resultIndex].TestStatus = 'failed'
                $state.Accounts[$resultIndex].TestTime = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
                Save-BackupCredentials @($state.Accounts)
                & $state.RefreshList
                $state.List.SelectedIndex = $resultIndex
                if ([bool]$result.restore_success) {
                    $state.Label.Text = '测试失败，已切回主账号。'
                } else {
                    $state.Label.Text = '测试失败，请检查备用账号。'
                }
            }
        })
        $pollTimer.Start()
    })

    $buttonSave.Add_Click({
        $toSave = @()
        foreach ($account in $accounts) {
            $toSave += $account
        }
        Save-BackupCredentials $toSave
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })

    $buttonCancel.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $dialog.Controls.AddRange(@($listAccounts, $labelBackupUser, $textBackupUser, $labelBackupPass, $textBackupPass, $labelBackupTip, $buttonAdd, $buttonUpdate, $buttonDelete, $buttonUp, $buttonDown, $buttonTest, $buttonSave, $buttonCancel))
    $dialog.AcceptButton = $buttonSave
    $dialog.CancelButton = $buttonCancel
    & $refreshList
    [void]$dialog.ShowDialog($owner)
}

function Show-LoginWindow([string]$defaultUsername, [string]$defaultPassword, [bool]$startInTray = $false) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        throw
    }
    [System.Windows.Forms.Application]::EnableVisualStyles()
    try {
        Set-CupLoginAppUserModelId
    } catch {
    }

    $appContext = New-Object System.Windows.Forms.ApplicationContext
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'CUP Login'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(420, 420)
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    $script:cupLoginAllowExit = $false

    $appIcon = $null
    $iconPath = Join-Path $PSScriptRoot 'cup-login.ico'
    if (Test-Path $iconPath) {
        try {
            $appIcon = New-Object System.Drawing.Icon($iconPath)
            $form.Icon = $appIcon
        } catch {
            $appIcon = $null
        }
    }

    $labelUser = New-Object System.Windows.Forms.Label
    $labelUser.Text = '账号'
    $labelUser.Location = New-Object System.Drawing.Point(20, 20)
    $labelUser.AutoSize = $true

    $textUser = New-Object System.Windows.Forms.TextBox
    $textUser.Location = New-Object System.Drawing.Point(110, 18)
    $textUser.Size = New-Object System.Drawing.Size(280, 20)
    if ($defaultUsername) {
        $textUser.Text = $defaultUsername
    }

    $labelPass = New-Object System.Windows.Forms.Label
    $labelPass.Text = '密码'
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
    $checkAutoStart.Text = '开机静默启动'
    $checkAutoStart.Location = New-Object System.Drawing.Point(110, 92)
    $checkAutoStart.AutoSize = $true
    $checkAutoStart.Checked = Get-AutoStartEnabled

    $checkReconnect = New-Object System.Windows.Forms.CheckBox
    $checkReconnect.Text = '断线自动重连'
    $checkReconnect.Location = New-Object System.Drawing.Point(110, 118)
    $checkReconnect.AutoSize = $true
    $checkReconnect.Checked = Get-ReconnectEnabled

    $labelTip = New-Object System.Windows.Forms.Label
    $labelTip.Text = Get-LoginHintText
    $labelTip.Location = New-Object System.Drawing.Point(20, 150)
    $labelTip.Size = New-Object System.Drawing.Size(380, 36)
    $labelTip.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Location = New-Object System.Drawing.Point(20, 192)
    $logBox.Size = New-Object System.Drawing.Size(380, 112)
    $logBox.Multiline = $true
    $logBox.ReadOnly = $true
    $logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $logBox.WordWrap = $false
    $logBox.BackColor = [System.Drawing.SystemColors]::Window
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 8)

    $labelActive = New-Object System.Windows.Forms.Label
    $labelActive.Location = New-Object System.Drawing.Point(20, 318)
    $labelActive.Size = New-Object System.Drawing.Size(380, 20)
    $labelActive.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)

    $addLog = {
        param([string]$message)
        if ([string]::IsNullOrWhiteSpace($message)) {
            return
        }

        $entry = "$(Get-Date -Format 'HH:mm:ss') $message"
        $lines = @($logBox.Lines)
        if ($lines.Count -eq 1 -and [string]::IsNullOrWhiteSpace($lines[0])) {
            $lines = @()
        }
        $lines += $entry
        if ($lines.Count -gt 100) {
            $lines = $lines[($lines.Count - 100)..($lines.Count - 1)]
        }
        $logBox.Lines = $lines
        $logBox.SelectionStart = $logBox.TextLength
        $logBox.ScrollToCaret()
        $logBox.Refresh()
    }
    $script:cupLoginUiLogWriter = $addLog
    Write-UiLog 'CUP Login 已启动'

    $updateActiveLabel = {
        $active = Get-ActiveLogin
        if ($active -and $active.Username) {
            $labelActive.Text = "当前登录：$(Get-DisplayAccountLabel $active.Label) ($(Remove-OperatorSuffix $active.Username))"
        } else {
            $labelActive.Text = ''
        }
    }
    & $updateActiveLabel

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    if ($null -ne $appIcon) {
        $notifyIcon.Icon = $appIcon
    } else {
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    }
    $notifyIcon.Text = 'CUP Login'
    $notifyIcon.Visible = $true

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $menuShow = New-Object System.Windows.Forms.ToolStripMenuItem('显示窗口')
    $menuLogin = New-Object System.Windows.Forms.ToolStripMenuItem('立即登录')
    $menuExit = New-Object System.Windows.Forms.ToolStripMenuItem('退出')
    [void]$trayMenu.Items.Add($menuShow)
    [void]$trayMenu.Items.Add($menuLogin)
    [void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$trayMenu.Items.Add($menuExit)
    $notifyIcon.ContextMenuStrip = $trayMenu
    $script:cupLoginNotifyIcon = $notifyIcon
    $script:cupLoginTrayMenu = $trayMenu
    $script:cupLoginForm = $form

    $showWindow = {
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Activate()
    }

    $notifyIcon.Add_DoubleClick($showWindow)
    $menuShow.Add_Click($showWindow)

    $checkAutoStart.Add_CheckedChanged({
        try {
            Set-AutoStartEnabled $checkAutoStart.Checked
            if ($checkAutoStart.Checked) {
                $labelTip.Text = '已开启开机静默启动。'
                Write-UiLog '已开启开机静默启动'
            } else {
                $labelTip.Text = '已关闭开机静默启动。'
                Write-UiLog '已关闭开机静默启动'
            }
        } catch {
            $labelTip.Text = '更新开机静默启动设置失败。'
            Write-UiLog '开机静默启动设置保存失败'
        }
    })

    $checkReconnect.Add_CheckedChanged({
        try {
            Set-ReconnectEnabled $checkReconnect.Checked
            if ($checkReconnect.Checked) {
                $labelTip.Text = '已开启断线自动重连。'
                Write-UiLog '已开启断线自动重连'
            } else {
                $labelTip.Text = '已关闭断线自动重连。'
                Write-UiLog '已关闭断线自动重连'
            }
        } catch {
            $labelTip.Text = '更新断线重连设置失败。'
            Write-UiLog '断线重连设置保存失败'
        }
    })

    $buttonLogin = New-Object System.Windows.Forms.Button
    $buttonLogin.Text = '登录'
    $buttonLogin.Location = New-Object System.Drawing.Point(245, 360)
    $buttonLogin.Size = New-Object System.Drawing.Size(75, 30)

    $buttonLogout = New-Object System.Windows.Forms.Button
    $buttonLogout.Text = '注销'
    $buttonLogout.Location = New-Object System.Drawing.Point(325, 360)
    $buttonLogout.Size = New-Object System.Drawing.Size(75, 30)

    $buttonBackup = New-Object System.Windows.Forms.Button
    $buttonBackup.Text = '备用账号...'
    $buttonBackup.Location = New-Object System.Drawing.Point(20, 360)
    $buttonBackup.Size = New-Object System.Drawing.Size(140, 30)
    $runReconnectCheck = $null

    $buttonLogout.Add_Click({
        $active = Get-ActiveLogin
        $u = if ($active -and $active.Username) { [string]$active.Username } else { $textUser.Text.Trim() }
        if (-not $u) {
            $labelTip.Text = '请先输入账号再注销。'
            Write-UiLog '注销取消：未输入账号'
            return
        }

        $buttonLogin.Enabled = $false
        $buttonLogout.Enabled = $false
        $labelTip.Text = '正在注销，请稍候...'
        Write-UiLog '用户点击注销'
        $form.Refresh()

        try {
            $result = Invoke-LogoutAttempt $u
            $labelTip.Text = $result.Message
            if ($result.Success) {
                Clear-ActiveLogin
                & $updateActiveLabel
                if ($checkReconnect.Checked) {
                    $checkReconnect.Checked = $false
                    Set-ReconnectEnabled $false
                    $labelTip.Text = '注销成功，已关闭断线重连。'
                    Write-UiLog '注销后已关闭断线重连'
                }
            }
        } catch {
            $labelTip.Text = '注销失败，请重试。'
            Write-UiLog '注销过程异常'
        } finally {
            $buttonLogin.Enabled = $true
            $buttonLogout.Enabled = $true
        }
    })

    $buttonLogin.Add_Click({
        $u = $textUser.Text.Trim()
        $p = $textPass.Text

        if (-not $u -or -not $p) {
            $labelTip.Text = '请输入账号和密码。'
            Write-UiLog '登录取消：账号或密码为空'
            return
        }

        $buttonLogin.Enabled = $false
        $labelTip.Text = '正在登录，请稍候...'
        Write-UiLog '用户点击登录'
        $form.Refresh()

        $startupWarning = ''
        try {
            Set-AutoStartEnabled $checkAutoStart.Checked
        } catch {
            $startupWarning = ' 启动项设置保存失败。'
            Write-UiLog '启动项设置保存失败，登录继续'
        }

        try {
            $result = Invoke-LoginWithBackupAccounts $u $p
            if ($result.Success) {
                $labelTip.Text = $result.Message + $startupWarning
                & $updateActiveLabel
            } else {
                $labelTip.Text = $result.Message + $startupWarning
                $textPass.Text = ''
                $textPass.Focus()
            }
        } catch {
            $labelTip.Text = '登录失败，请重试。'
            Write-UiLog '登录过程异常'
            $textPass.Text = ''
            $textPass.Focus()
        } finally {
            $buttonLogin.Enabled = $true
        }
    })

    $buttonBackup.Add_Click({
        $setReconnectUi = {
            param($enabled)
            $checkReconnect.Checked = [bool]$enabled
        }
        Show-BackupAccountsWindow $form $textUser.Text.Trim() $textPass.Text $setReconnectUi
        $backupCount = @(Get-BackupCredentials).Count
        if ($backupCount -eq 0) {
            $labelTip.Text = '未配置备用账号。'
            Write-UiLog '备用账号未配置'
        } elseif ($backupCount -eq 1) {
            $labelTip.Text = '已配置 1 个备用账号。'
            Write-UiLog '已配置 1 个备用账号'
        } else {
            $labelTip.Text = "已配置 $backupCount 个备用账号。"
            Write-UiLog "已配置 $backupCount 个备用账号"
        }
    })

    $menuLogin.Add_Click({
        $buttonLogin.PerformClick()
    })

    $reconnectTimer = New-Object System.Windows.Forms.Timer
    $reconnectTimer.Interval = 5000
    $script:cupLoginLastReconnectCheck = [DateTime]::MinValue
    $reconnectBusy = $false
    $eventsRegistered = Register-ReconnectNetworkEvents

    $runReconnectCheck = {
        if (-not $checkReconnect.Checked -or $reconnectBusy) {
            return
        }

        $u = $textUser.Text.Trim()
        $p = $textPass.Text
        if (-not $u -or -not $p) {
            $labelTip.Text = '请先输入并保存账号密码，再启用重连。'
            Write-UiLog '重连暂停：缺少账号或密码'
            & $showWindow
            return
        }

        $reconnectBusy = $true
        try {
            if (Test-CaptivePortalRedirect) {
                $labelTip.Text = '检测到认证页重定向，正在重连...'
                Write-UiLog '开始自动重连'
                $result = Invoke-LoginWithBackupAccounts $u $p $false
                $labelTip.Text = $result.Message
                if ($result.Success) {
                    & $updateActiveLabel
                }
                if (-not $result.Success -and $result.Status -eq 'failed_auth') {
                    & $showWindow
                }
            }
        } catch {
            $labelTip.Text = '重连检测失败。'
            Write-UiLog '重连检测异常'
        } finally {
            $script:cupLoginLastReconnectCheck = [DateTime]::Now
            $reconnectBusy = $false
        }
    }

    $reconnectTimer.Add_Tick({
        if (-not $checkReconnect.Checked) {
            return
        }

        $hasNetworkEvent = $false
        if ($eventsRegistered) {
            $events = Get-Event -ErrorAction SilentlyContinue | Where-Object { $_.SourceIdentifier -like 'CupLoginNetwork*' }
            if ($events) {
                $hasNetworkEvent = $true
                $events | Remove-Event
            }
        }

        $dueFallback = (([DateTime]::Now - $script:cupLoginLastReconnectCheck).TotalSeconds -ge [Math]::Max(5, $ReconnectInterval))
        if ($hasNetworkEvent -or $dueFallback) {
            & $runReconnectCheck
        }
    })
    $reconnectTimer.Start()

    $form.Add_FormClosing({
        if (-not $script:cupLoginAllowExit) {
            $_.Cancel = $true
            $form.Hide()
        }
    })

    $form.Add_FormClosed({
        $reconnectTimer.Stop()
        $reconnectTimer.Dispose()
        Clear-ReconnectNetworkEvents
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        if ($null -ne $appIcon) {
            $appIcon.Dispose()
        }
        $trayMenu.Dispose()
        $script:cupLoginUiLogWriter = $null
        $appContext.ExitThread()
    })

    $menuExit.Add_Click({
        $script:cupLoginAllowExit = $true
        $form.Close()
    })

    $form.Controls.AddRange(@($labelUser, $textUser, $labelPass, $textPass, $checkAutoStart, $checkReconnect, $labelTip, $logBox, $labelActive, $buttonBackup, $buttonLogin, $buttonLogout))
    $form.AcceptButton = $buttonLogin
    if ($startInTray) {
        if ($checkReconnect.Checked) {
            & $runReconnectCheck
        }
    } else {
        [void]$form.Show()
    }
    [System.Windows.Forms.Application]::Run($appContext)
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

function Start-InteractiveLoginWindow {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $PSScriptRoot 'login-cup.ps1' }
    $quotedScriptPath = '"' + $scriptPath.Replace('"', '""') + '"'
    $arguments = @('-WindowStyle', 'Hidden', '-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedScriptPath)
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $PSScriptRoot | Out-Null
}

function Invoke-BackupAccountTestFile([string]$testFile) {
    $payload = Get-Content -Path $testFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $backupUsername = [string]$payload.backup_username
    $backupPassword = Unprotect-LoginText ([string]$payload.backup_password)
    $mainUsername = [string]$payload.main_username
    $mainPassword = Unprotect-LoginText ([string]$payload.main_password)
    $resultPath = [string]$payload.result_path
    $restoreReconnect = ([string]$payload.restore_reconnect -eq 'true')

    $backupResult = $null
    $restoreResult = $null
    try {
        Set-ReconnectEnabled $false

        $active = Get-ActiveLogin
        $logoutUsername = if ($active -and $active.Username) { [string]$active.Username } elseif ($mainUsername) { $mainUsername } else { $backupUsername }
        if ($logoutUsername) {
            [void](Invoke-LogoutAttempt $logoutUsername)
        }

        $backupResult = Invoke-LoginAttempt $backupUsername $backupPassword $false $false 'Backup account test'
        if ($backupResult -and $backupResult.Success) {
            [void](Invoke-LogoutAttempt $backupUsername)
        }

        if ($mainUsername -and $mainPassword) {
            $restoreResult = Invoke-LoginAttempt $mainUsername $mainPassword $false $true 'Main account'
        }

        $result = [pscustomobject]@{
            backup_success = [bool]($backupResult -and $backupResult.Success)
            restore_success = [bool]($restoreResult -and $restoreResult.Success)
            has_main_credential = [bool]($mainUsername -and $mainPassword)
            restore_reconnect = [bool]$restoreReconnect
            error = ''
        }
    } catch {
        $result = [pscustomobject]@{
            backup_success = $false
            restore_success = [bool]($restoreResult -and $restoreResult.Success)
            has_main_credential = [bool]($mainUsername -and $mainPassword)
            restore_reconnect = [bool]$restoreReconnect
            error = ($_ | Out-String)
        }
    } finally {
        Set-ReconnectEnabled $restoreReconnect
    }

    $result | ConvertTo-Json -Depth 4 | Set-Content -Path $resultPath -Encoding UTF8
}

$savedCredential = Get-SavedCredential

$defaultUsername = if ($Username) { $Username } elseif ($savedCredential -and $savedCredential.Username) { $savedCredential.Username } else { Get-LastUsername }
$defaultPassword = if ($Password) { $Password } elseif ($savedCredential -and $savedCredential.Password) { $savedCredential.Password } else { '' }

if ($BackupTestFile) {
    Invoke-BackupAccountTestFile $BackupTestFile
    exit 0
}

Sync-LegacyStartupState
Update-TrayStartupEntry

if ($Tray) {
    $startInTray = ($defaultUsername -and $defaultPassword)
    if ($startInTray -and (Get-AutoStartEnabled)) {
        $silentResult = Invoke-LoginWithBackupAccounts $defaultUsername $defaultPassword $false
        if (-not $silentResult.Success) {
            $startInTray = $false
        }
    }

    Show-LoginWindow $defaultUsername $defaultPassword $startInTray
    exit 0
}

if ($Silent) {
    if (-not $defaultUsername -or -not $defaultPassword) {
        Write-ResultFile 'needs_credentials' '未配置登录' '请先输入一次账号和密码，再启用开机静默启动。'
        Start-InteractiveLoginWindow
        exit 0
    }

    $silentResult = Invoke-LoginWithBackupAccounts $defaultUsername $defaultPassword
    if ($silentResult.Success) {
        exit 0
    }

    Start-InteractiveLoginWindow
    exit 1
}

if ($Reconnect) {
    if (-not $defaultUsername -or -not $defaultPassword) {
        Write-ResultFile 'needs_credentials' '未配置登录' '请先输入一次账号和密码，再启用断线重连。'
        Start-InteractiveLoginWindow
        exit 0
    }

    $eventsRegistered = Register-ReconnectNetworkEvents
    try {
        if (-not (Invoke-ReconnectLoginIfNeeded $defaultUsername $defaultPassword)) {
            exit 1
        }

        while ($true) {
            if ($eventsRegistered) {
                $event = Wait-Event -Timeout ([Math]::Max(5, $ReconnectInterval))
                if ($event) {
                    Get-Event | Remove-Event
                }
            } else {
                Start-Sleep -Seconds ([Math]::Max(5, $ReconnectInterval))
            }

            if (-not (Invoke-ReconnectLoginIfNeeded $defaultUsername $defaultPassword)) {
                exit 1
            }
        }
    } finally {
        Clear-ReconnectNetworkEvents
    }
}

Show-LoginWindow $defaultUsername $defaultPassword $false
exit 0
