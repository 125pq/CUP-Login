#define MyAppName "CUP Login"
#define MyAppPublisher "CUP Login"
#define MyAppLauncherName "login-cup.vbs"
#define MyAppDebugName "login-cup.bat"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef SourceDir
  #error SourceDir is not defined. Pass /DSourceDir="..."
#endif

#ifndef OutputDir
  #define OutputDir SourceDir
#endif

[Setup]
AppId={{4E9A4DFB-2506-4CE4-A835-E3572A21DE5E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
ChangesEnvironment=no
Compression=lzma
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=srun-cup-setup-{#MyAppVersion}
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayIcon={app}\srun.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式："; Flags: unchecked
Name: "autostart"; Description: "开机启动（当前用户）"; GroupDescription: "启动项："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}\CUP Login"; Filename: "{app}\{#MyAppLauncherName}"; IconFilename: "{app}\cup-login.ico"
Name: "{autoprograms}\{#MyAppName}\静默登录"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--silent"; IconFilename: "{app}\cup-login.ico"
Name: "{autoprograms}\{#MyAppName}\调试登录"; Filename: "{app}\{#MyAppDebugName}"; IconFilename: "{app}\cup-login.ico"
Name: "{autoprograms}\{#MyAppName}\开启开机静默启动"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-autostart-on"; IconFilename: "{app}\cup-login.ico"
Name: "{autoprograms}\{#MyAppName}\关闭开机静默启动"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-autostart-off"; IconFilename: "{app}\cup-login.ico"
Name: "{autoprograms}\{#MyAppName}\开启断线重连"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-reconnect-on"; IconFilename: "{app}\cup-login.ico"
Name: "{autoprograms}\{#MyAppName}\关闭断线重连"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-reconnect-off"; IconFilename: "{app}\cup-login.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppLauncherName}"; IconFilename: "{app}\cup-login.ico"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--tray"; IconFilename: "{app}\cup-login.ico"; Tasks: autostart

[InstallDelete]
Type: files; Name: "{autoprograms}\{#MyAppName}\Silent login.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\One-click login.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\Debug login.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\Enable silent autostart.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\Disable silent autostart.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\Enable reconnect.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\Disable reconnect.lnk"
Type: files; Name: "{autoprograms}\srun-cup\Silent login.lnk"
Type: files; Name: "{autoprograms}\srun-cup\One-click login.lnk"
Type: dirifempty; Name: "{autoprograms}\srun-cup"
Type: files; Name: "{userstartup}\CUP Login.lnk"
Type: files; Name: "{userstartup}\srun-cup.lnk"

[Run]
Filename: "{app}\{#MyAppLauncherName}"; Description: "立即运行 CUP Login"; Flags: nowait postinstall skipifsilent shellexec
