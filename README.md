# CUP Login

CUP Login 是基于 [zu1k/srun](https://github.com/zu1k/srun) 改造的中国石油大学（北京）校园网登录工具。

项目保留上游 `srun` 的命令行能力，同时提供面向 Windows 用户的图形界面、安装包、系统托盘后台、开机静默启动、断线自动重连和备用账号功能。

## 当前版本

- 稳定版：`v1.0.0`
- 最新稳定安装包：`srun-cup-setup-1.0.0.exe`
- 开发预览：Tauri 版 UI 正在 `develop` 分支试验中，尚未替代稳定版。

## 下载

推荐直接下载 GitHub Release 中的稳定安装包：

- [CUP Login 1.0.0](https://github.com/125pq/CUP-Login/releases/tag/v1.0.0)
- 安装包文件：`srun-cup-setup-1.0.0.exe`

安装后可以从开始菜单或桌面快捷方式打开 `CUP Login`。

## 主要功能

- 一键登录中国石油大学（北京）深澜校园网。
- 图形化登录窗口，支持保存账号密码到本机。
- 关闭窗口后驻留系统托盘，可从托盘菜单重新打开或退出。
- 开机静默启动：开机后在后台托盘运行，成功时不主动弹出登录窗口。
- 断线自动重连：通过轻量 204/Portal 重定向检测判断认证是否掉线，掉线后自动重新登录。
- 备用账号池：主账号登录失败后按顺序尝试备用账号，但界面默认仍显示主账号。
- 备用账号测试：可单独测试备用账号是否可用，并记录测试状态。
- 软件内注销：手动注销会关闭断线重连，避免主动注销后又被自动登录。
- 启动时隐藏 PowerShell 窗口，普通用户只看到 CUP Login 界面和托盘图标。

## 使用方式

首次打开软件时，输入校园网账号和密码，然后点击“登录”。登录成功后，账号密码会保存在当前 Windows 用户本地，下次打开可以直接登录。

常用选项：

- 勾选“开机静默启动”：开机后自动在托盘后台运行。
- 勾选“断线自动重连”：检测到校园网认证掉线后自动重新登录。
- 点击“备用账号管理”：添加备用账号。只有主账号失败后才会尝试备用账号。
- 点击“注销”：注销当前登录账号，并关闭断线自动重连。

## 安全说明

凭据只保存在本机当前 Windows 用户目录下，并使用 Windows 用户上下文加密。

默认位置：

- `%LOCALAPPDATA%\srun-cup\.login-cup.credential.json`
- `%LOCALAPPDATA%\srun-cup\.login-cup.backup-credentials.json`
- `%LOCALAPPDATA%\srun-cup\.login-cup.last-username`

这些文件不应该提交到仓库。若要清理本地保存的登录数据，可以删除 `%LOCALAPPDATA%\srun-cup` 下对应文件。

错误日志写入前会隐藏密码，避免把明文密码保存到 `login-last-error.log`。

## 从源码运行

如果需要自己调试或构建：

```powershell
cargo build
.\login-cup.ps1 -Username 学号 -Password 密码
```

也可以直接运行图形界面：

```powershell
.\login-cup.ps1
```

默认行为：

- 服务器：先尝试 `https://login.cup.edu.cn`，失败后回退到 `http://login.cup.edu.cn`
- IP：自动检测
- 认证参数：`--acid 1 --type 1`
- 账号：只使用输入的原始账号，不自动追加运营商后缀

## 构建安装包

需要先安装 Inno Setup 6，并确保 `ISCC.exe` 可用。

```powershell
$env:AUTH_SERVER_IP='10.0.0.1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\build-windows-installer.ps1 -Version 1.0.0
```

输出位置：

- `build\release\srun-cup-setup-<version>.exe`

安装包会包含：

- `srun.exe`
- `login-cup.ps1`
- `login-cup.vbs`
- `login-cup.bat`
- `cup-login.ico`
- `README.md`

## 上游能力

上游 `srun` 原生支持：

- 命令行与配置文件登录
- 多种 IP 获取方式
- 严格绑定
- 多用户配置
- 跨平台运行

上游仓库：[zu1k/srun](https://github.com/zu1k/srun)

## 许可

本项目沿用上游 GPL-3.0 许可证。
