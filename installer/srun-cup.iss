#define MyAppName "srun-cup"
#define MyAppPublisher "srun-cup"
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
Name: "{autoprograms}\{#MyAppName}\One-click login"; Filename: "{app}\{#MyAppLauncherName}"
Name: "{autoprograms}\{#MyAppName}\Debug login"; Filename: "{app}\{#MyAppDebugName}"
Name: "{autoprograms}\{#MyAppName}\Enable silent autostart"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-autostart-on"
Name: "{autoprograms}\{#MyAppName}\Disable silent autostart"; Filename: "{app}\{#MyAppLauncherName}"; Parameters: "--set-autostart-off"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppLauncherName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppLauncherName}"; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppLauncherName}"; Description: "Run one-click login now"; Flags: nowait postinstall skipifsilent shellexec
