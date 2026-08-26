# Komari Agent for fnOS

将 [Komari Agent](https://github.com/komari-monitor/komari-agent) 打包为飞牛 fnOS（fnOS）可安装的 `.fpk` 应用包。

Komari Agent 是一款轻量级服务器监控客户端，可将飞牛 NAS 的系统运行状态上报至 Komari 监控服务端。本应用包以**专用应用用户（非 root）**运行，纯 bash + CGI 实现，无任何第三方运行时依赖。

## 特性

- **零依赖**：纯 bash + fnOS 原生 CGI，不依赖 Node.js/Python 等运行时
- **非 root 运行**：`run-as: package` 专用应用用户，符合 komari 官方非 root 建议
- **JSON 编辑器配置页**：应用内直接编辑 `config.json` 原文，不做表单化映射
  - 保存时 JSON 语法校验，失败禁止写入并提示**具体行/列**（校验由 komari-agent 自身试运行完成）
  - 保存后一键重启 Agent 生效
  - 内嵌 Agent 运行日志面板，启动失败可直接查看
- **日志管理**：自动轮转（默认 5MB × 3 份），可通过配置开关完全关闭
- **卸载向导**：卸载时可选「保留配置」或「完全卸载」
- **双架构云构建**：GitHub Actions 一键产出 x86_64 / arm64 安装包，版本跟随 komari-agent 并带构建序号

## 安装

1. 从 [Releases](https://github.com/inxen/komari-agent-fpk/releases) 下载对应架构的 `.fpk`（x86_64 或 arm64）
2. 飞牛 fnOS → 应用中心 → 手动安装 → 选择 `.fpk` 文件
3. 安装向导填写 Komari 面板地址（endpoint）与 Agent Token
4. 安装完成后在桌面打开应用，可随时通过 JSON 编辑器调整全部配置

> 国内网络访问 GitHub 不稳定时，可手动下载 [komari-agent](https://github.com/komari-monitor/komari-agent/releases) 二进制后本地构建（见下文）。

## 配置说明

配置保存在 `config.json`（应用配置目录 `etc/`，升级保留；卸载时按选择保留或清除）。字段与 komari-agent 官方配置一致，另含以下 `_fnos_` 前缀扩展字段（komari-agent 会忽略，仅本应用使用）：

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `_fnos_log_enabled` | `true` | 日志开关，`false` 时完全不写日志 |
| `_fnos_log_max_size_mb` | `5` | 单日志文件轮转上限（MB） |
| `_fnos_log_keep` | `3` | 轮转保留份数 |

常用 komari 字段示例：

```json
{
  "endpoint": "https://monitor.example.com",
  "token": "your-agent-token",
  "interval": 3,
  "disable_auto_update": true,
  "protocol_version": 2
}
```

> `disable_auto_update` 默认开启，避免 komari-agent 自更新覆盖应用包内二进制（升级请通过应用包完成）。

## 日志位置

- Agent 日志：`/vol1/@appdata/komari-agent/agent.log`（数据卷 `@appdata` 目录，轮转后含 `.1/.2/.3`）
- 守护进程日志：同目录 `supervisor.log`
- 应用页面底部「Agent 运行日志」面板可查看末尾日志

## 卸载

卸载时应用中心会弹出选项：

- **保留配置文件**：下次安装沿用当前配置
- **完全卸载**：删除 `config.json`（含 token），下次安装为全新向导

## GitHub Actions 云构建

仓库已配置 `build-komari-agent-fpk` workflow（手动触发）：

1. Actions → build-komari-agent-fpk → **Run workflow**
2. 参数：
   - `version`：komari-agent 版本 tag（默认 `latest` = 最新正式版），如 `v1.2.60`
   - `publish`：`true` 时构建后自动发布 GitHub Release
3. 产物（Artifacts）：
   - `komari-agent-x86_64-{版本}-{构建序号}.fpk`
   - `komari-agent-arm64-{版本}-{构建序号}.fpk`

版本号规则：`{komari 版本}-{构建序号}`，如 `1.2.60-1`（构建序号随每次运行递增）。

## 本地构建

Windows（需 PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Version latest   # x86_64
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Version v1.2.60 -Arch arm64
```

脚本自动下载 komari-agent 二进制与 fnpack 打包工具，产物输出到仓库根目录 `komari-agent.fpk`。

## 目录结构

```
komari-agent/                 # fnpack 应用包目录
├── manifest                  # 应用元数据（版本跟随 komari-agent）
├── ICON.PNG / ICON_256.PNG   # 包图标
├── config/
│   ├── privilege             # 非 root 专用用户运行
│   └── resource
├── cmd/
│   ├── main                  # 启停/状态（管理 supervisor）
│   └── install_callback / uninstall_callback
├── wizard/
│   ├── install               # 安装向导（endpoint/token 等）
│   └── uninstall             # 卸载选项（保留/清除配置）
└── app/
    ├── komari-agent          # 构建时注入的二进制（不入库）
    ├── bin/
    │   ├── agent-supervisor.sh   # 常驻守护：崩溃自动拉起、日志轮转
    │   ├── gen-config.sh         # 向导值生成 config.json
    │   └── validate-config.sh    # 用 agent 自身试运行校验配置
    ├── etc/config.example.json   # 默认配置模板
    └── ui/
        ├── index.cgi         # 配置管理 CGI（零依赖 HTTP 层）
        ├── index.html        # JSON 编辑器页面
        └── config            # 桌面入口
```

## 相关链接

- 上游项目：[komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent)
- 官方文档：https://komari-document.pages.dev
- 飞牛应用开放平台：https://developer.fnnas.com

## 发布

- 开发者：Komari 社区
- 发布者：inxen
