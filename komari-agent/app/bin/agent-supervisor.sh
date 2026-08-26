#!/bin/bash
# Komari Agent - agent-supervisor.sh
# 常驻守护：拉起 komari-agent 子进程，崩溃后自动重启；将子进程 PID 写入 agent.pid。
# 收到 SIGTERM/SIGINT 时先停止子进程再退出。
# 由 cmd/main 在 start 时启动；配置页面的"重启 Agent"只需 kill agent.pid 指向的进程。
#
# 日志控制（读取 config.json 中 _fnos_ 前缀的自定义字段，komari-agent 会忽略这些字段）：
#   "_fnos_log_enabled": true       日志开关，false = 完全不写日志（agent 输出丢弃）
#   "_fnos_log_max_size_mb": 5      单文件轮转上限（MB）
#   "_fnos_log_keep": 3             轮转保留份数
# 也可通过环境变量覆盖：KOMARI_LOG_MAX_SIZE（字节）、KOMARI_LOG_KEEP、KOMARI_ROTATE_INTERVAL（秒）

set -u

APP_DIR="/var/apps/komari-agent/target"
CONFIG_PATH="/var/apps/komari-agent/etc/config.json"
VAR_DIR="/var/apps/komari-agent/var"
AGENT_BIN="${APP_DIR}/komari-agent"
AGENT_LOG="${VAR_DIR}/agent.log"
AGENT_PID_FILE="${VAR_DIR}/agent.pid"
RESTART_INTERVAL="${KOMARI_SUPERVISOR_INTERVAL:-1}"   # 崩溃后重启等待秒数
ROTATE_INTERVAL="${KOMARI_ROTATE_INTERVAL:-600}"        # 定时轮转间隔（秒）

LOG_ENABLED="true"
LOG_MAX_SIZE="${KOMARI_LOG_MAX_SIZE:-5242880}"         # 5MB（环境变量默认）
LOG_KEEP="${KOMARI_LOG_KEEP:-3}"                        # 保留 3 份

STOP=0
CHILD_PID=""
ROTATOR_PID=""

# 从 config.json 读取 _fnos_ 日志配置（每次拉起前调用，改动保存后重启即生效）
read_log_config() {
  LOG_ENABLED="true"
  LOG_MAX_SIZE="${KOMARI_LOG_MAX_SIZE:-5242880}"
  LOG_KEEP="${KOMARI_LOG_KEEP:-3}"
  [ -f "$CONFIG_PATH" ] || return 0

  local v
  v=$(grep -oE '"_fnos_log_enabled"[[:space:]]*:[[:space:]]*(true|false)' "$CONFIG_PATH" 2>/dev/null | head -1 | grep -oE '(true|false)[[:space:]]*$' | tr -d '[:space:]')
  [ -n "$v" ] && LOG_ENABLED="$v"

  v=$(grep -oE '"_fnos_log_max_size_mb"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_PATH" 2>/dev/null | head -1 | grep -oE '[0-9]+[[:space:]]*$' | tr -d '[:space:]')
  if [ -n "$v" ] && [ "$v" -ge 1 ] 2>/dev/null; then
    LOG_MAX_SIZE=$((v * 1024 * 1024))
  fi

  v=$(grep -oE '"_fnos_log_keep"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_PATH" 2>/dev/null | head -1 | grep -oE '[0-9]+[[:space:]]*$' | tr -d '[:space:]')
  if [ -n "$v" ] && [ "$v" -ge 1 ] && [ "$v" -le 10 ] 2>/dev/null; then
    LOG_KEEP="$v"
  fi
}

log_msg() {
  [ "$LOG_ENABLED" = "false" ] && return 0
  echo "$(date '+%Y-%m-%d %H:%M:%S') [supervisor] $*" >> "$AGENT_LOG"
}

# 日志轮转（copytruncate：复制后截断，不影响已打开 fd 的写入进程）
rotate_log() {
  local file="$1" size i
  [ -f "$file" ] || return 0
  size=$(stat -c %s "$file" 2>/dev/null || echo 0)
  [ "${size:-0}" -lt "$LOG_MAX_SIZE" ] && return 0
  rm -f "${file}.${LOG_KEEP}" 2>/dev/null
  i=$((LOG_KEEP - 1))
  while [ "$i" -ge 1 ]; do
    [ -f "${file}.${i}" ] && mv -f "${file}.${i}" "${file}.$((i + 1))" 2>/dev/null
    i=$((i - 1))
  done
  cp -f "$file" "${file}.1" 2>/dev/null && : > "$file"
  log_msg "log rotated (size exceeded ${LOG_MAX_SIZE} bytes, keeping ${LOG_KEEP})"
}

stop_child() {
  [ -n "$CHILD_PID" ] && kill -TERM "$CHILD_PID" 2>/dev/null || true
}

cleanup() {
  STOP=1
  [ -n "$ROTATOR_PID" ] && kill "$ROTATOR_PID" 2>/dev/null || true
  stop_child
  rm -f "$AGENT_PID_FILE"
  exit 0
}
trap cleanup TERM INT

mkdir -p "$VAR_DIR" 2>/dev/null

# 后台定时轮转（覆盖 agent 长时间运行的场景；日志关闭时不启动）
(
  while :; do
    sleep "$ROTATE_INTERVAL"
    [ "$STOP" = "1" ] && break
    read_log_config
    [ "$LOG_ENABLED" = "false" ] && continue
    rotate_log "$AGENT_LOG"
  done
) &
ROTATOR_PID=$!

while [ "$STOP" = "0" ]; do
  read_log_config   # 每次循环读取最新日志配置

  if [ ! -x "$AGENT_BIN" ]; then
    log_msg "binary not found or not executable: $AGENT_BIN"
    sleep 10
    continue
  fi
  if [ ! -f "$CONFIG_PATH" ]; then
    log_msg "config not found: $CONFIG_PATH"
    sleep 10
    continue
  fi

  if [ "$LOG_ENABLED" = "false" ]; then
    # 日志关闭：agent 输出直接丢弃
    "$AGENT_BIN" --config "$CONFIG_PATH" > /dev/null 2>&1 &
  else
    rotate_log "$AGENT_LOG"   # 拉起前检查轮转
    "$AGENT_BIN" --config "$CONFIG_PATH" >> "$AGENT_LOG" 2>&1 &
  fi
  CHILD_PID=$!
  echo "$CHILD_PID" > "$AGENT_PID_FILE"

  # 等待子进程退出（信号/崩溃/正常退出都会走到这里）
  wait "$CHILD_PID" 2>/dev/null
  RC=$?
  log_msg "agent exited with code $RC (signal=${STOP})"

  if [ "$STOP" = "1" ]; then
    break
  fi
  sleep "$RESTART_INTERVAL"
done

cleanup
