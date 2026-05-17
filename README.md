# CUP Login

这是基于 [zu1k/srun](https://github.com/zu1k/srun) 改造的中国石油大学（北京）校园网登录工具。项目保留上游 `srun` 的命令行能力，同时提供面向 Windows 用户的图形界面、安装包、系统托盘后台、开机静默启动、断线重连和备用账号功能。

## 主要功能

- 一键登录中国石油大学（北京）深澜校园网。
- 图形化登录窗口，支持保存账号密码到本机。
- 关闭窗口后驻留系统托盘，可从托盘菜单重新打开或退出。
- 开机静默启动：开机后在后台托盘运行，不主动弹出登录窗口。
- 断线自动重连：通过轻量 204 重定向检测判断是否掉认证，发现掉线后自动登录。
- 备用账号池：主账号登录失败后按顺序尝试备用账号，但界面默认仍显示主账号。
- 软件内注销：手动注销会关闭断线重连，避免主动注销后又被自动登录。
- 启动 PowerShell 窗口完全隐藏，普通用户只看到 CUP Login 界面。

## 下载安装

推荐直接下载最新 Release 里的安装包：

- [CUP Login 0.9.1](https://github.com/125pq/srun-CUP/releases/tag/v0.9.1)
- 安装包文件：`srun-cup-setup-0.9.1.exe`

安装后可以从开始菜单或桌面快捷方式打开 `CUP Login`。

## 使用方式

首次打开软件时，输入校园网账号和密码，然后点击“登录”。登录成功后，账号密码会保存在当前 Windows 用户本地，下次打开可以直接登录。

常用选项：

- 勾选“开机静默启动”：开机后自动在托盘后台运行。
- 勾选“断线自动重连”：检测到校园网认证掉线后自动重新登录。
- 点击“备用账号...”：添加备用账号。主账号失败后才会尝试备用账号。
- 点击“注销”：注销当前登录账号，并关闭断线自动重连。

## 安全说明

凭据只保存在本机当前 Windows 用户目录下，并使用 Windows 用户上下文加密。安装版默认位置：

- `%LOCALAPPDATA%\srun-cup\.login-cup.credential.json`
- `%LOCALAPPDATA%\srun-cup\.login-cup.backup-credentials.json`
- `%LOCALAPPDATA%\srun-cup\.login-cup.last-username`

这些文件不应该提交到仓库。若要清理本地保存的登录数据，可以删除 `%LOCALAPPDATA%\srun-cup` 下对应文件。

## 从源码运行

如果你需要自己调试或构建：

```powershell
cargo build
.\login-cup.ps1 -Username 学号 -Password 密码
```

后续也可以直接运行：

```powershell
.\login-cup.ps1
```

脚本默认行为：

- 服务器：先尝试 `https://login.cup.edu.cn`，失败后回退到 `http://login.cup.edu.cn`
- IP：自动检测
- 认证参数：`--acid 1 --type 1`
- 账号：只使用输入的原始账号，不自动追加运营商后缀

## 构建安装包

需要先安装 Inno Setup 6，并确保 `ISCC.exe` 可用。

```powershell
$env:AUTH_SERVER_IP='10.0.0.1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\build-windows-installer.ps1 -Version 0.9.1
```

输出位置：

- `build\release\srun-cup-setup-<version>.exe`

安装包会包含：

- `srun.exe`
- `login-cup.ps1`
- `login-cup.vbs`
- `login-cup.bat`
- 说明文档

## 上游能力

上游 `srun` 原生支持：

- 命令行与配置文件登录
- 多种 IP 获取方式
- 严格绑定
- 多用户配置
- 跨平台运行

上游仓库：[zu1k/srun](https://github.com/zu1k/srun)

## 许可证

本项目沿用上游 GPL-3.0 许可证。
