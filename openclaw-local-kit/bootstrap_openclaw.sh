#!/usr/bin/env bash
set -euo pipefail

# OpenClaw 外接硬盘部署脚本（研究所电脑友好）
# 目标：把 OpenClaw 程序、配置、日志、运行数据全部放到外接盘。
#
# 用法：
#   bash bootstrap_openclaw.sh
#
# 关键环境变量：
#   TARGET_ROOT=/mnt/d/OpenClawSystem   # 外接盘根目录（推荐）
#   INSTALL_NODE=1                      # 自动安装 fnm + Node 22（用户态）
#   NODE_VERSION=22                     # Node 主版本
#   PM=npm                              # npm/pnpm/bun
#   OPENCLAW_VERSION=latest             # openclaw 版本
#
# Windows 盘符 D 常见路径：
#   WSL:      /mnt/d
#   Git Bash: /d
#   Cygwin:   /cygdrive/d

NODE_VERSION="${NODE_VERSION:-22}"
PM="${PM:-npm}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
INSTALL_NODE="${INSTALL_NODE:-0}"
TARGET_ROOT="${TARGET_ROOT:-}"

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERROR] $*"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

pick_default_target_root() {
  if [[ -n "${TARGET_ROOT}" ]]; then
    return 0
  fi

  if [[ -d /mnt/d ]]; then
    TARGET_ROOT="/mnt/d/OpenClawSystem"
  elif [[ -d /d ]]; then
    TARGET_ROOT="/d/OpenClawSystem"
  elif [[ -d /cygdrive/d ]]; then
    TARGET_ROOT="/cygdrive/d/OpenClawSystem"
  else
    TARGET_ROOT="${HOME}/OpenClawSystem"
    warn "未检测到 D 盘挂载目录，临时回退到 ${TARGET_ROOT}。"
    warn "若你要强制使用外接硬盘，请手动设置 TARGET_ROOT。"
  fi
}

setup_layout() {
  ROOT_DIR="${TARGET_ROOT}"
  APP_DIR="${ROOT_DIR}/01-app"
  NODE_DIR="${ROOT_DIR}/02-node"
  CONFIG_DIR="${ROOT_DIR}/03-config"
  DATA_DIR="${ROOT_DIR}/04-data"
  LOG_DIR="${ROOT_DIR}/05-logs"
  BACKUP_DIR="${ROOT_DIR}/06-backups"
  SCRIPT_DIR="${ROOT_DIR}/07-scripts"
  TMP_DIR="${ROOT_DIR}/08-tmp"
  RUNTIME_DIR="${ROOT_DIR}/09-runtime"

  mkdir -p \
    "${APP_DIR}" "${NODE_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" \
    "${LOG_DIR}" "${BACKUP_DIR}" "${SCRIPT_DIR}" "${TMP_DIR}" "${RUNTIME_DIR}" \
    "${CONFIG_DIR}/openclaw" "${DATA_DIR}/workspace" "${DATA_DIR}/models" "${DATA_DIR}/channels"

  log "目录结构已创建：${ROOT_DIR}"
}

ensure_node() {
  if has_cmd node; then
    local current_major
    current_major="$(node -v | sed 's/^v//' | cut -d. -f1)"
    if [[ "${current_major}" -ge 22 ]]; then
      log "检测到 Node $(node -v)，满足 OpenClaw 要求（>=22）。"
      return 0
    fi
    warn "Node 版本过低：$(node -v)，需要 >=22。"
  else
    warn "未检测到 Node。"
  fi

  if [[ "${INSTALL_NODE}" != "1" ]]; then
    err "请先安装 Node >=22，或设置 INSTALL_NODE=1 自动安装。"
    return 1
  fi

  log "安装 fnm + Node ${NODE_VERSION}（用户态，无需 root）..."
  has_cmd curl || { err "未检测到 curl。"; return 1; }
  curl -fsSL https://fnm.vercel.app/install | bash

  export PATH="${HOME}/.local/share/fnm:${PATH}"
  eval "$(fnm env --use-on-cd --shell bash)"
  fnm install "${NODE_VERSION}"
  fnm default "${NODE_VERSION}"
  log "Node 已安装：$(node -v)"
}

ensure_package_manager() {
  case "${PM}" in
    npm)
      has_cmd npm || { err "未检测到 npm。"; return 1; }
      ;;
    pnpm)
      if ! has_cmd pnpm; then
        log "未检测到 pnpm，尝试用 corepack 启用。"
        has_cmd corepack || { err "未检测到 corepack。"; return 1; }
        corepack enable
        corepack prepare pnpm@latest --activate
      fi
      ;;
    bun)
      has_cmd bun || { err "未检测到 bun，请先安装 bun。"; return 1; }
      ;;
    *)
      err "不支持的包管理器：${PM}（支持 npm/pnpm/bun）"
      return 1
      ;;
  esac
}

install_openclaw() {
  log "将 OpenClaw 安装到外接盘：${APP_DIR}"

  case "${PM}" in
    npm)
      npm config set prefix "${APP_DIR}" >/dev/null 2>&1
      npm install -g "openclaw@${OPENCLAW_VERSION}"
      OPENCLAW_BIN="${APP_DIR}/bin/openclaw"
      ;;
    pnpm)
      export PNPM_HOME="${APP_DIR}/bin"
      mkdir -p "${PNPM_HOME}"
      pnpm add -g "openclaw@${OPENCLAW_VERSION}"
      OPENCLAW_BIN="${PNPM_HOME}/openclaw"
      ;;
    bun)
      export BUN_INSTALL="${APP_DIR}/bun"
      mkdir -p "${BUN_INSTALL}"
      bun add -g "openclaw@${OPENCLAW_VERSION}"
      OPENCLAW_BIN="${BUN_INSTALL}/bin/openclaw"
      ;;
  esac

  if [[ ! -x "${OPENCLAW_BIN}" ]]; then
    err "未在预期位置找到 openclaw：${OPENCLAW_BIN}"
    err "请检查包管理器全局安装目录。"
    return 1
  fi

  log "OpenClaw 安装成功：$(${OPENCLAW_BIN} --version)"
}

write_env_file() {
  cat > "${ROOT_DIR}/openclaw.env" <<ENV
export OPENCLAW_ROOT="${ROOT_DIR}"
export OPENCLAW_CONFIG_DIR="${CONFIG_DIR}/openclaw"
export OPENCLAW_DATA_DIR="${DATA_DIR}"
export OPENCLAW_LOG_DIR="${LOG_DIR}"
export OPENCLAW_RUNTIME_DIR="${RUNTIME_DIR}"
export OPENCLAW_TMP_DIR="${TMP_DIR}"
export PATH="${APP_DIR}/bin:\$PATH"
ENV
  log "环境文件已生成：${ROOT_DIR}/openclaw.env"
}

write_helpers() {
  cat > "${SCRIPT_DIR}/run_gateway.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT
  cat >> "${SCRIPT_DIR}/run_gateway.sh" <<SCRIPT
source "${ROOT_DIR}/openclaw.env"
exec "${OPENCLAW_BIN}" gateway --port 18789 --verbose
SCRIPT

  cat > "${SCRIPT_DIR}/doctor.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT
  cat >> "${SCRIPT_DIR}/doctor.sh" <<SCRIPT
source "${ROOT_DIR}/openclaw.env"
exec "${OPENCLAW_BIN}" doctor
SCRIPT

  cat > "${SCRIPT_DIR}/onboard.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT
  cat >> "${SCRIPT_DIR}/onboard.sh" <<SCRIPT
source "${ROOT_DIR}/openclaw.env"
exec "${OPENCLAW_BIN}" onboard --install-daemon
SCRIPT

  cat > "${SCRIPT_DIR}/quick_test.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT
  cat >> "${SCRIPT_DIR}/quick_test.sh" <<SCRIPT
source "${ROOT_DIR}/openclaw.env"
exec "${OPENCLAW_BIN}" agent --message "请输出：OpenClaw 已部署到外接盘。" --thinking low
SCRIPT

  chmod +x "${SCRIPT_DIR}"/*.sh
  log "辅助脚本已生成：${SCRIPT_DIR}"
}

post_install_hint() {
  cat <<TXT

部署完成：
  根目录：${ROOT_DIR}

目录说明：
  01-app      OpenClaw 可执行与全局包
  02-node     预留 Node 相关资产
  03-config   配置文件
  04-data     业务数据/模型/渠道数据
  05-logs     日志
  06-backups  备份
  07-scripts  运维脚本
  08-tmp      临时文件
  09-runtime  运行态文件

推荐执行顺序：
  ${SCRIPT_DIR}/doctor.sh
  ${SCRIPT_DIR}/onboard.sh
  ${SCRIPT_DIR}/run_gateway.sh
  ${SCRIPT_DIR}/quick_test.sh

你也可以在 shell 中加载环境：
  source "${ROOT_DIR}/openclaw.env"
TXT
}

main() {
  pick_default_target_root
  setup_layout
  ensure_node
  ensure_package_manager
  install_openclaw
  write_env_file
  write_helpers
  post_install_hint
}

main "$@"
