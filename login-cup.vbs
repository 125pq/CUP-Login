Option Explicit

Dim shell, fso, scriptDir, batPath, stateRoot, resultPath, errorLogPath
Dim cmd, i, arg, exitCode, statusText, titleText, messageText, detailText
Dim runKey, runValueName, autostartCmd, silentMode, forceAutoStartMode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = scriptDir & "\login-cup.bat"
stateRoot = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\srun-cup"
resultPath = stateRoot & "\login-last-result.txt"
errorLogPath = stateRoot & "\login-last-error.log"
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

If forceAutoStartMode = "on" Then
    Call SetAutoStart(True)
    WScript.Quit 0
ElseIf forceAutoStartMode = "off" Then
    Call SetAutoStart(False)
    WScript.Quit 0
End If

exitCode = shell.Run(cmd, 0, True)

statusText = ""
titleText = "srun-cup"
messageText = ""
Call LoadResult(resultPath, statusText, titleText, messageText)

If exitCode = 0 Then
    If statusText = "already_online" Then
        If Not silentMode Then
            MsgBox Zh("already_online"), vbInformation, "srun-cup"
            Call PromptAutoStartToggle()
        End If
    ElseIf statusText = "success" Then
        If Not silentMode Then
            MsgBox Zh("success"), vbInformation, "srun-cup"
            Call PromptAutoStartToggle()
        End If
    Else
        If Not silentMode Then
            MsgBox Zh("unknown"), vbExclamation, "srun-cup"
        End If
    End If
Else
    detailText = ReadUtf8Text(errorLogPath)
    If Len(detailText) > 1800 Then
        detailText = Left(detailText, 1800) & vbCrLf & vbCrLf & "...(truncated)"
    End If

    If statusText = "failed_auth" And Len(messageText) = 0 Then
        messageText = Zh("failed_auth")
    ElseIf Len(messageText) = 0 Then
        messageText = Zh("failed")
    End If

    If Len(detailText) > 0 Then
        messageText = messageText & vbCrLf & vbCrLf & Zh("details") & vbCrLf & detailText
    Else
        messageText = messageText & vbCrLf & vbCrLf & Zh("no_log")
    End If

    If Not silentMode Then
        MsgBox messageText, vbExclamation, "srun-cup"
    End If
End If

Sub PromptAutoStartToggle()
    Dim currentEnabled, answer
    currentEnabled = IsAutoStartEnabled()

    If currentEnabled Then
        answer = MsgBox(Zh("autostart_prompt_on"), vbQuestion + vbYesNoCancel, "srun-cup")
    Else
        answer = MsgBox(Zh("autostart_prompt_off"), vbQuestion + vbYesNoCancel, "srun-cup")
    End If

    If answer = vbCancel Then
        Exit Sub
    End If

    If answer = vbYes Then
        Call SetAutoStart(True)
        MsgBox Zh("autostart_enabled"), vbInformation, "srun-cup"
    ElseIf answer = vbNo Then
        Call SetAutoStart(False)
        MsgBox Zh("autostart_disabled"), vbInformation, "srun-cup"
    End If
End Sub

Function IsAutoStartEnabled()
    Dim valueText
    On Error Resume Next
    valueText = shell.RegRead(runKey & runValueName)
    If Err.Number <> 0 Then
        Err.Clear
        IsAutoStartEnabled = False
        Exit Function
    End If
    On Error GoTo 0

    IsAutoStartEnabled = (InStr(1, valueText, "login-cup.vbs", vbTextCompare) > 0)
End Function

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

Function Zh(key)
    Select Case key
        Case "success"
            Zh = ChrW(&H767B) & ChrW(&H5F55) & ChrW(&H6210) & ChrW(&H529F) & ChrW(&HFF01)
        Case "already_online"
            Zh = ChrW(&H5DF2) & ChrW(&H767B) & ChrW(&H5F55) & ChrW(&H3002)
        Case "failed_auth"
            Zh = ChrW(&H8D26) & ChrW(&H53F7) & ChrW(&H6216) & ChrW(&H5BC6) & ChrW(&H7801) & _
                 ChrW(&H9519) & ChrW(&H8BEF) & ChrW(&HFF0C) & ChrW(&H8BF7) & ChrW(&H68C0) & _
                 ChrW(&H67E5) & ChrW(&H540E) & ChrW(&H91CD) & ChrW(&H8BD5) & ChrW(&H3002)
        Case "failed"
            Zh = ChrW(&H767B) & ChrW(&H5F55) & ChrW(&H5931) & ChrW(&H8D25) & ChrW(&HFF0C) & _
                 ChrW(&H8BF7) & ChrW(&H7A0D) & ChrW(&H540E) & ChrW(&H91CD) & ChrW(&H8BD5) & ChrW(&H3002)
        Case "details"
            Zh = ChrW(&H9519) & ChrW(&H8BEF) & ChrW(&H8BE6) & ChrW(&H60C5) & ChrW(&HFF1A)
        Case "no_log"
            Zh = ChrW(&H672A) & ChrW(&H627E) & ChrW(&H5230) & ChrW(&H9519) & ChrW(&H8BEF) & _
                 ChrW(&H65E5) & ChrW(&H5FD7) & ChrW(&HFF0C) & ChrW(&H8BF7) & ChrW(&H4F7F) & _
                 ChrW(&H7528) & " Debug login " & ChrW(&H67E5) & ChrW(&H770B) & ChrW(&H8BE6) & ChrW(&H60C5) & ChrW(&H3002)
        Case "autostart_prompt_on"
            Zh = ChrW(&H5F53) & ChrW(&H524D) & ChrW(&H5DF2) & ChrW(&H5F00) & ChrW(&H542F) & ChrW(&H5F00) & ChrW(&H673A) & ChrW(&H9759) & ChrW(&H9ED8) & ChrW(&H767B) & ChrW(&H5F55) & ChrW(&H3002) & _
                 vbCrLf & ChrW(&H662F) & ChrW(&HFF1A) & ChrW(&H4FDD) & ChrW(&H6301) & ChrW(&H5F00) & ChrW(&H542F) & _
                 vbCrLf & ChrW(&H5426) & ChrW(&HFF1A) & ChrW(&H5173) & ChrW(&H95ED) & _
                 vbCrLf & ChrW(&H53D6) & ChrW(&H6D88) & ChrW(&HFF1A) & ChrW(&H4E0D) & ChrW(&H4FEE) & ChrW(&H6539)
        Case "autostart_prompt_off"
            Zh = ChrW(&H662F) & ChrW(&H5426) & ChrW(&H5F00) & ChrW(&H542F) & ChrW(&H5F00) & ChrW(&H673A) & ChrW(&H9759) & ChrW(&H9ED8) & ChrW(&H767B) & ChrW(&H5F55) & ChrW(&HFF1F) & _
                 vbCrLf & ChrW(&H662F) & ChrW(&HFF1A) & ChrW(&H5F00) & ChrW(&H542F) & _
                 vbCrLf & ChrW(&H5426) & ChrW(&HFF1A) & ChrW(&H4FDD) & ChrW(&H6301) & ChrW(&H5173) & ChrW(&H95ED) & _
                 vbCrLf & ChrW(&H53D6) & ChrW(&H6D88) & ChrW(&HFF1A) & ChrW(&H4E0D) & ChrW(&H4FEE) & ChrW(&H6539)
        Case "autostart_enabled"
            Zh = ChrW(&H5DF2) & ChrW(&H5F00) & ChrW(&H542F) & ChrW(&H5F00) & ChrW(&H673A) & ChrW(&H9759) & ChrW(&H9ED8) & ChrW(&H81EA) & ChrW(&H542F) & ChrW(&H52A8) & ChrW(&H3002)
        Case "autostart_disabled"
            Zh = ChrW(&H5DF2) & ChrW(&H5173) & ChrW(&H95ED) & ChrW(&H5F00) & ChrW(&H673A) & ChrW(&H9759) & ChrW(&H9ED8) & ChrW(&H81EA) & ChrW(&H542F) & ChrW(&H52A8) & ChrW(&H3002)
        Case Else
            Zh = ChrW(&H767B) & ChrW(&H5F55) & ChrW(&H72B6) & ChrW(&H6001) & ChrW(&H5F02) & ChrW(&H5E38) & _
                 ChrW(&HFF0C) & ChrW(&H8BF7) & ChrW(&H4F7F) & ChrW(&H7528) & " Debug login " & _
                 ChrW(&H67E5) & ChrW(&H770B) & ChrW(&H8BE6) & ChrW(&H60C5) & ChrW(&H3002)
    End Select
End Function

Sub LoadResult(filePath, ByRef statusOut, ByRef titleOut, ByRef messageOut)
    Dim txt, lines, line, p, k, v, idx
    statusOut = ""
    If Len(titleOut) = 0 Then
        titleOut = "srun-cup"
    End If
    messageOut = ""

    txt = ReadUtf8Text(filePath)
    If Len(txt) = 0 Then
        Exit Sub
    End If

    ' Remove UTF-8 BOM if present; otherwise key parsing for the first line can fail.
    If Len(txt) > 0 Then
        If AscW(Left(txt, 1)) = 65279 Then
            txt = Mid(txt, 2)
        End If
    End If

    lines = Split(txt, vbCrLf)
    For idx = 0 To UBound(lines)
        line = lines(idx)
        p = InStr(line, "=")
        If p > 0 Then
            k = LCase(Trim(Left(line, p - 1)))
            v = Trim(Mid(line, p + 1))
            If k = "status" Then statusOut = v
            If k = "title" Then titleOut = v
            If k = "message" Then messageOut = v
        End If
    Next
End Sub

Function ReadUtf8Text(filePath)
    Dim stream
    On Error Resume Next
    If Not fso.FileExists(filePath) Then
        ReadUtf8Text = ""
        Exit Function
    End If

    Set stream = CreateObject("ADODB.Stream")
    stream.Type = 2
    stream.Mode = 3
    stream.Charset = "utf-8"
    stream.Open
    stream.LoadFromFile filePath

    If Err.Number <> 0 Then
        Err.Clear
        ReadUtf8Text = ""
        Exit Function
    End If

    ReadUtf8Text = stream.ReadText(-1)
    stream.Close
    On Error GoTo 0
End Function
