Option Explicit

Dim shell, fso, scriptDir, batPath, stateRoot, resultPath, errorLogPath
Dim cmd, i, arg, exitCode, statusText, titleText, messageText, detailText
Dim runKey, runValueName, autostartCmd, silentMode, forceAutoStartMode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = scriptDir & "\login-cup.bat"
stateRoot = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\srun-cup"
runKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\"
runValueName = "srun-cup"
autostartCmd = Chr(34) & "wscript.exe" & Chr(34) & " //B //Nologo " & Chr(34) & scriptDir & "\login-cup.vbs" & Chr(34) & " --silent"
silentMode = False
forceAutoStartMode = ""

cmd = "cmd.exe /c " & Chr(34) & Chr(34) & batPath & Chr(34)

For i = 0 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    Select Case LCase(arg)
        Case "--silent", "/silent"
            silentMode = True
        Case "--set-autostart-on"
            forceAutoStartMode = "on"
        Case "--set-autostart-off"
            forceAutoStartMode = "off"
        Case Else
            arg = Replace(arg, Chr(34), Chr(34) & Chr(34))
            cmd = cmd & " " & Chr(34) & arg & Chr(34)
    End Select
Next

cmd = cmd & Chr(34)

If silentMode Then
    cmd = cmd & " " & Chr(34) & "-Silent" & Chr(34)
End If

If forceAutoStartMode = "on" Then
    Call SetAutoStart(True)
    WScript.Quit 0
ElseIf forceAutoStartMode = "off" Then
    Call SetAutoStart(False)
    WScript.Quit 0
End If

exitCode = shell.Run(cmd, 0, True)

WScript.Quit exitCode

Sub SetAutoStart(enableIt)
    On Error Resume Next
    If enableIt Then
        shell.RegWrite runKey & runValueName, autostartCmd, "REG_SZ"
    Else
        shell.RegDelete runKey & runValueName
        If Err.Number <> 0 Then
            Err.Clear
        End If
    End If
    On Error GoTo 0
End Sub
