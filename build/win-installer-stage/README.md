# srun-cup

A practical fork of [zu1k/srun](https://github.com/zu1k/srun) with ready-to-use login scripts for China University of Petroleum, Beijing (CUP).

Chinese documentation: [README.zh-CN.md](README.zh-CN.md)

## What This Fork Adds

- Windows one-click launcher: `login-cup.bat`
- CUP-oriented PowerShell script: `login-cup.ps1`
- Auto server fallback: `https://login.cup.edu.cn` -> `http://login.cup.edu.cn`
- Auto username candidate attempts (no suffix and common operator suffixes)
- Optional local credential cache for true double-click auto login

## Security

The script can cache credentials locally **on your machine only**:

- `.login-cup.credential.json` (encrypted by Windows user context)
- `.login-cup.last-username`

Both files are ignored by git and are never intended to be pushed.

To clear local saved data:

```powershell
Remove-Item .\.login-cup.credential.json, .\.login-cup.last-username -ErrorAction SilentlyContinue
```

## Quick Start (Windows)

1. Build once (if `target\debug\srun.exe` does not exist):

```powershell
cargo build
```

2. First login (saves account/password after success):

```powershell
.\login-cup.ps1 -Username YOUR_ID -Password YOUR_PASSWORD
```

3. Next login:

- Double-click `login-cup.bat`, or
- Run `./login-cup.ps1` with no args

## Build One-Click Windows Installer

This project includes an Inno Setup script so you can ship a standard `.exe` installer.

1. Install Inno Setup 6 (so `ISCC.exe` is available).
2. Build and package in one command:

```powershell
.\build\build-windows-installer.ps1
```

Output installer:

- `build\release\srun-cup-setup-<version>.exe`

What the installer does:

- installs `srun.exe`, `login-cup.ps1`, `login-cup.bat`, `login-cup.vbs`
- creates Start Menu shortcuts: `CUP Login` and `Debug login`
- optional desktop shortcut and startup shortcut

Installed user experience:

- end users only need to download, install, and click the shortcut (no Rust toolchain required)
- if no saved credential exists, a GUI dialog asks for username and password on first run
- credentials are saved after successful login for future one-click use
- the GUI includes a logout button, backup account management, and optional silent startup/reconnect toggles

Runtime credential storage location (installed mode):

- `%LOCALAPPDATA%\srun-cup\.login-cup.credential.json`
- `%LOCALAPPDATA%\srun-cup\.login-cup.last-username`

Silent startup and reconnect are stored in the current user's Windows startup settings and can be changed from the GUI. Closing the window keeps CUP Login running in the system tray; use the tray menu to show the window or exit. Reconnect mode keeps the tray process alive and retries login only when the lightweight HTTP captive-portal check is redirected.

Backup accounts are configured from the `Backup accounts...` button. CUP Login always tries the main account first; if it fails, backup accounts are tried in order without replacing the main account shown on the next launch.

## Script Behavior

Default behavior of `login-cup.ps1`:

- server: auto try `https://login.cup.edu.cn`, then fallback to `http://login.cup.edu.cn`
- IP mode: auto-detect (`-d`)
- auth params: `--acid 1 --type 1`
- username candidates (when no `@`):
  - `username`
  - `username@xn`
  - `username@cmcc`
  - `username@cucc`
  - `username@ctcc`

Useful options:

```powershell
# Force one operator suffix
.\login-cup.ps1 -Username YOUR_ID -Password YOUR_PASSWORD -Operator xn

# Disable suffix attempts
.\login-cup.ps1 -Username YOUR_ID -Password YOUR_PASSWORD -Operator none

# Specify fixed IP
.\login-cup.ps1 -Username YOUR_ID -Password YOUR_PASSWORD -Ip 10.x.x.x

# Override acid/type if your portal differs
.\login-cup.ps1 -Username YOUR_ID -Password YOUR_PASSWORD -Acid 1 -Type 1
```

## Original srun Features

From upstream `srun`:

- Command-line and config-file login
- Multiple IP acquisition modes
- Strict bind support
- Multi-user support
- Cross-platform support

Upstream repository: <https://github.com/zu1k/srun>

## License

This fork keeps the original GPL-3.0 license from upstream.
