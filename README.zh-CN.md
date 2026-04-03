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
