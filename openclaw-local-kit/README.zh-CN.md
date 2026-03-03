# OpenClaw 本地开箱部署包（10T 外接盘 D 盘专用）

你现在的需求是：在研究所电脑上，把 OpenClaw 的**程序+配置+数据+日志**都放进外接 10T 硬盘（D 盘），并且目录层次清晰。

本目录已经按这个目标改造好。

---

## 1) 目录规划（层次分明）

默认根目录（自动识别）：
- WSL: `/mnt/d/OpenClawSystem`
- Git Bash: `/d/OpenClawSystem`
- Cygwin: `/cygdrive/d/OpenClawSystem`

最终会生成：

- `01-app/`：OpenClaw 可执行文件、全局包
- `02-node/`：Node 相关预留目录
- `03-config/`：配置文件
- `04-data/`：核心数据（workspace/models/channels）
- `05-logs/`：日志
- `06-backups/`：备份
- `07-scripts/`：运维脚本（doctor/onboard/gateway/test）
- `08-tmp/`：临时文件
- `09-runtime/`：运行态文件
- `openclaw.env`：统一环境变量入口

---

## 2) 一键部署命令

```bash
cd /workspace/Trial
chmod +x openclaw-local-kit/bootstrap_openclaw.sh
TARGET_ROOT=/mnt/d/OpenClawSystem INSTALL_NODE=1 bash openclaw-local-kit/bootstrap_openclaw.sh
```

> 如果你不是 WSL，请把 `TARGET_ROOT` 改成 `/d/OpenClawSystem` 或你的 D 盘挂载点。

---

## 3) 部署后操作（按顺序）

```bash
/mnt/d/OpenClawSystem/07-scripts/doctor.sh
/mnt/d/OpenClawSystem/07-scripts/onboard.sh
/mnt/d/OpenClawSystem/07-scripts/run_gateway.sh
/mnt/d/OpenClawSystem/07-scripts/quick_test.sh
```

如果你使用的是 Git Bash，路径改成 `/d/OpenClawSystem/...`。

---

## 4) 研究所电脑可以用吗？

**大概率可以**，原因是这个方案尽量走“用户态”安装，不依赖管理员权限。你主要确认 4 件事：

1. 允许你在外接盘写文件（D 盘可读写）。
2. 允许访问 npm 等依赖源（或可配置代理）。
3. 允许终端监听端口（默认 18789）。
4. 单位合规允许调用你要用的模型服务。

若网络受限，请先配置：

```bash
export HTTP_PROXY=http://你的代理:端口
export HTTPS_PROXY=http://你的代理:端口
```

---

## 5) 你最关心的“全放 D 盘”说明

此脚本已经做到：
- OpenClaw 安装位置放在 `D盘/OpenClawSystem/01-app`
- 配置、数据、日志、运行时都在 `D盘/OpenClawSystem/` 下分层存放
- 并通过 `openclaw.env` 和专用脚本统一调用

也就是说，后续迁移/备份时，只要拷贝整个 `OpenClawSystem` 目录即可。

