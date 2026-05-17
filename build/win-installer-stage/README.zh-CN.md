# srun-cup

这是 [zu1k/srun](https://github.com/zu1k/srun) 的实用化分支，增加了适用于中国石油大学（北京）校园网的开箱即用登录脚本。

英文文档： [README.md](README.md)

## 这个分支新增了什么

- Windows 一键启动脚本：`login-cup.bat`
- CUP 定制登录脚本：`login-cup.ps1`
- 服务器自动回退：`https://login.cup.edu.cn` -> `http://login.cup.edu.cn`
- 用户名自动候选（无后缀和常见运营商后缀）
- 支持本地凭据缓存，实现真正双击自动登录

## 安全说明

脚本可在本机缓存凭据（仅当前 Windows 用户可解密使用）：

- `.login-cup.credential.json`
- `.login-cup.last-username`

这两个文件已加入 `.gitignore`，不会被提交到仓库。

清理本地缓存：

```powershell
Remove-Item .\.login-cup.credential.json, .\.login-cup.last-username -ErrorAction SilentlyContinue
```

## 快速开始（Windows）

1. 首次构建（若不存在 `target\debug\srun.exe`）：

```powershell
cargo build
```

2. 首次登录（成功后会保存账号和密码）：

```powershell
.\login-cup.ps1 -Username 学号 -Password 密码
```

3. 后续登录：

- 直接双击 `login-cup.bat`，或
- 在 PowerShell 中运行 `./login-cup.ps1`（不传参数）

## 打包一键安装版 Windows 软件

仓库已提供 Inno Setup 安装脚本，可生成标准 `.exe` 安装包。

1. 先安装 Inno Setup 6（确保有 `ISCC.exe`）。
2. 一条命令完成构建与打包：

```powershell
.\build\build-windows-installer.ps1
```

输出位置：

- `build\release\srun-cup-setup-<version>.exe`

安装包会：

- 安装 `srun.exe`、`login-cup.ps1`、`login-cup.bat`
- 安装 `login-cup.vbs`（默认一键启动器）
- 创建开始菜单快捷方式（CUP Login / 调试登录）
- 可选创建桌面快捷方式和开机启动快捷方式

安装后使用体验：

- 双击快捷方式即可登录，无需安装 Rust 或手动配置命令
- 首次运行若无已保存凭据，会弹出图形化窗口输入账号密码
- 登录成功后自动保存，下次可直接一键登录
- 图形界面提供注销按钮、备用账号管理，以及开机静默启动/断线重连开关

调试参数（给脚本/自动化使用）：

- `login-cup.vbs --set-autostart-on`：开启开机静默自启动
- `login-cup.vbs --set-autostart-off`：关闭开机静默自启动
- `login-cup.vbs --silent`：静默运行（不弹窗）

安装后凭据存储位置：

- `%LOCALAPPDATA%\srun-cup\.login-cup.credential.json`
- `%LOCALAPPDATA%\srun-cup\.login-cup.last-username`

开机静默启动和断线重连会写入当前用户的 Windows 启动项，可在图形界面里勾选或取消。关闭窗口后 CUP Login 会继续在系统托盘运行，可通过托盘菜单显示窗口或真正退出。断线重连会保持托盘后台，并只在轻量 HTTP Portal 检测出现重定向时重新登录。

备用账号通过 `备用账号...` 按钮管理。CUP Login 总是先尝试主账号；主账号失败后再按顺序尝试备用账号，备用账号登录成功也不会替换下次打开时显示的主账号。

## 脚本默认行为

`login-cup.ps1` 默认：

- server：先尝试 `https://login.cup.edu.cn`，失败后回退 `http://login.cup.edu.cn`
- IP：自动探测（`-d`）
- 认证参数：`--acid 1 --type 1`
- 若用户名不含 `@`，自动按顺序尝试：
  - `username`
  - `username@xn`
  - `username@cmcc`
  - `username@cucc`
  - `username@ctcc`

常用参数示例：

```powershell
# 强制某个后缀
.\login-cup.ps1 -Username 学号 -Password 密码 -Operator xn

# 禁用后缀尝试，只用原始用户名
.\login-cup.ps1 -Username 学号 -Password 密码 -Operator none

# 指定固定 IP
.\login-cup.ps1 -Username 学号 -Password 密码 -Ip 10.x.x.x

# 如果学校参数不同，可覆盖 acid/type
.\login-cup.ps1 -Username 学号 -Password 密码 -Acid 1 -Type 1
```

## 上游项目能力

上游 `srun` 原生支持：

- 命令行与配置文件两种模式
- 多种 IP 获取方式
- 严格绑定
- 多用户支持
- 跨平台

上游地址：<https://github.com/zu1k/srun>

## License

本仓库沿用上游 GPL-3.0 许可证。
