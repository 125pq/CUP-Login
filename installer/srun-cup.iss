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
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "autostart"; Description: "Run on Windows startup (current user)"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}\CUP Login"; Filename: "{app}\{#MyAppLauncherName}"
Name: "{autoprograms}\{#MyAppName}\Silent login"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--silent"
Name: "{autoprograms}\{#MyAppName}\Debug login"; Filename: "{app}\{#MyAppDebugName}"
Name: "{autoprograms}\{#MyAppName}\Enable silent autostart"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-autostart-on"
Name: "{autoprograms}\{#MyAppName}\Disable silent autostart"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-autostart-off"
Name: "{autoprograms}\{#MyAppName}\Enable reconnect"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-reconnect-on"
Name: "{autoprograms}\{#MyAppName}\Disable reconnect"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-reconnect-off"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppLauncherName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--tray"; Tasks: autostart

[InstallDelete]
Type: files; Name: "{autoprograms}\{#MyAppName}\Silent login.lnk"
Type: files; Name: "{autoprograms}\{#MyAppName}\One-click login.lnk"
Type: files; Name: "{autoprograms}\srun-cup\Silent login.lnk"
Type: files; Name: "{autoprograms}\srun-cup\One-click login.lnk"
Type: dirifempty; Name: "{autoprograms}\srun-cup"
Type: files; Name: "{userstartup}\CUP Login.lnk"
Type: files; Name: "{userstartup}\srun-cup.lnk"

[Run]
Filename: "{app}\{#MyAppLauncherName}"; Description: "Run CUP Login now"; Flags: nowait postinstall skipifsilent shellexec
