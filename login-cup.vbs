Option Explicit

Dim shell, fso, scriptDir, ps1Path, stateRoot, resultPath, errorLogPath, autoStartFlagPath, reconnectFlagPath
Dim cmd, i, arg, exitCode, windowStyle, statusText, titleText, messageText, detailText
Dim runKey, runValueName, reconnectRunValueName, legacyRunValueName, autostartCmd, reconnectCmd, silentMode, reconnectMode, trayMode, forceAutoStartMode, forceReconnectMode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = scriptDir & "\login-cup.ps1"
stateRoot = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\srun-cup"
autoStartFlagPath = stateRoot & "\silent-startup.enabled"
reconnectFlagPath = stateRoot & "\reconnect.enabled"
runKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\"
runValueName = "CUP Login"
reconnectRunValueName = "CUP Login Reconnect"
legacyRunValueName = "srun-cup"
autostartCmd = Chr(34) & "wscript.exe" & Chr(34) & " //B //Nologo " & Chr(34) & scriptDir & "\login-cup.vbs" & Chr(34) & " --tray"
reconnectCmd = Chr(34) & "wscript.exe" & Chr(34) & " //B //Nologo " & Chr(34) & scriptDir & "\login-cup.vbs" & Chr(34) & " --tray"
silentMode = False
reconnectMode = False
trayMode = False
forceAutoStartMode = ""
forceReconnectMode = ""

cmd = QuoteArg("powershell.exe") & " -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File " & QuoteArg(ps1Path)

For i = 0 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    Select Case LCase(arg)
        Case "--silent", "/silent"
            silentMode = True
        Case "--reconnect", "/reconnect"
            reconnectMode = True
        Case "--tray", "/tray"
            trayMode = True
        Case "--set-autostart-on"
            forceAutoStartMode = "on"
        Case "--set-autostart-off"
            forceAutoStartMode = "off"
        Case "--set-reconnect-on"
            forceReconnectMode = "on"
        Case "--set-reconnect-off"
            forceReconnectMode = "off"
        Case Else
            cmd = cmd & " " & QuoteArg(arg)
    End Select
Next

If silentMode Then
    cmd = cmd & " " & QuoteArg("-Silent")
End If

If reconnectMode Then
    cmd = cmd & " " & QuoteArg("-Reconnect")
End If

If trayMode Then
    cmd = cmd & " " & QuoteArg("-Tray")
End If

If forceAutoStartMode = "on" Then
    Call SetAutoStart(True)
    WScript.Quit 0
ElseIf forceAutoStartMode = "off" Then
    Call SetAutoStart(False)
    WScript.Quit 0
End If

If forceReconnectMode = "on" Then
    Call SetReconnect(True)
    WScript.Quit 0
ElseIf forceReconnectMode = "off" Then
    Call SetReconnect(False)
    WScript.Quit 0
End If

windowStyle = 0

exitCode = shell.Run(cmd, windowStyle, True)

WScript.Quit exitCode

Sub SetAutoStart(enableIt)
    On Error Resume Next
    If enableIt Then
        Call WriteFlag(autoStartFlagPath)
        shell.RegWrite runKey & runValueName, autostartCmd, "REG_SZ"
        shell.RegDelete runKey & legacyRunValueName
        If Err.Number <> 0 Then
            Err.Clear
        End If
    Else
        Call DeleteFlag(autoStartFlagPath)
        shell.RegDelete runKey & runValueName
        If Err.Number <> 0 Then
            Err.Clear
        End If
        shell.RegDelete runKey & legacyRunValueName
        If Err.Number <> 0 Then
            Err.Clear
        End If
    End If
    On Error GoTo 0
End Sub

Sub SetReconnect(enableIt)
    On Error Resume Next
    If enableIt Then
        Call WriteFlag(reconnectFlagPath)
        shell.RegWrite runKey & reconnectRunValueName, reconnectCmd, "REG_SZ"
    Else
        Call DeleteFlag(reconnectFlagPath)
        shell.RegDelete runKey & reconnectRunValueName
        If Err.Number <> 0 Then
            Err.Clear
        End If
    End If
    On Error GoTo 0
End Sub

Sub EnsureStateRoot()
    On Error Resume Next
    If Not fso.FolderExists(stateRoot) Then
        fso.CreateFolder stateRoot
    End If
    If Err.Number <> 0 Then
        Err.Clear
    End If
    On Error GoTo 0
End Sub

Sub WriteFlag(flagPath)
    On Error Resume Next
    Call EnsureStateRoot()
    Dim stream
    Set stream = fso.CreateTextFile(flagPath, True, False)
    stream.Write "enabled"
    stream.Close
    If Err.Number <> 0 Then
        Err.Clear
    End If
    On Error GoTo 0
End Sub

Sub DeleteFlag(flagPath)
    On Error Resume Next
    If fso.FileExists(flagPath) Then
        fso.DeleteFile flagPath, True
    End If
    If Err.Number <> 0 Then
        Err.Clear
    End If
    On Error GoTo 0
End Sub

Function QuoteArg(value)
    QuoteArg = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
