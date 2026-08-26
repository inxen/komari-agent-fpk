#!/bin/bash
# Komari Agent - index.cgi
# 配置管理 CGI：提供 JSON 编辑器前端与 API（零第三方依赖，纯 bash + 系统工具）
#
# 路由（基于 REQUEST_URI 中 index.cgi 之后的子路径）：
#   GET  /                -> JSON 编辑器页面
#   GET  /api/config      -> 返回 config.json 原文
#   POST /api/config      -> 保存：validate-config.sh（agent 自身试运行校验）通过后原子写回并重启 agent
#   GET  /api/status      -> agent 运行状态
#   POST /api/restart     -> 重启 agent（supervisor 自动拉起）
#   GET  /api/log         -> agent 日志尾部（便于排查启动失败）
#
# 说明：CGI 由系统 nginx 按需调用，登录态由系统在调用前校验。
# 写操作仅允许管理员（X-Trim-Isadmin: true）；Header 缺失时放行（便于本地调试）。

set -u

APP_DIR="/var/apps/komari-agent/target"
ETC_DIR="/var/apps/komari-agent/etc"
VAR_DIR="/var/apps/komari-agent/var"
TMP_DIR="/var/apps/komari-agent/tmp"

UI_DIR="${APP_DIR}/ui"
INDEX_HTML="${UI_DIR}/index.html"
CONFIG_PATH="${ETC_DIR}/config.json"
CONFIG_BAK="${ETC_DIR}/config.json.bak"
AGENT_PID_FILE="${VAR_DIR}/agent.pid"
AGENT_LOG="${VAR_DIR}/agent.log"
VALIDATE_SH="${APP_DIR}/bin/validate-config.sh"
APP_USER="komari"    # 与 config/privilege 的 username 保持一致

mkdir -p "$VAR_DIR" "$TMP_DIR" 2>/dev/null || true

# ---------------- 工具函数 ----------------

json_escape_str() { # JSON 字符串转义（纯 bash，零依赖）
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

json_out() { # json_out <code> <json-string>
  local code="$1" body="$2"
  echo "Status: $code"
  echo "Content-Type: application/json; charset=utf-8"
  echo "Cache-Control: no-store"
  echo ""
  printf '%s\n' "$body"
}

text_out() { # text_out <code> <content-type> <text>
  local code="$1" ctype="$2" body="$3"
  echo "Status: $code"
  echo "Content-Type: $ctype"
  echo "Cache-Control: no-store"
  echo ""
  printf '%s\n' "$body"
}

is_admin() {
  # 网关转发管理员状态到 HTTP_X_TRIM_ISADMIN；缺失时放行（本地/直连调试）
  local v="${HTTP_X_TRIM_ISADMIN:-}"
  [ -z "$v" ] && return 0
  [ "$v" = "true" ] && return 0
  return 1
}

read_body() { # read_body <outfile>；返回 0 成功 / 1 失败
  local out="$1" len="${CONTENT_LENGTH:-0}"
  if [ -n "$len" ] && [ "$len" -gt 0 ] 2>/dev/null; then
    dd bs=1 count="$len" 2>/dev/null > "$out" || return 1
  else
    cat > "$out" 2>/dev/null || return 1
  fi
  [ -s "$out" ] || return 1
  return 0
}

agent_pid() {
  [ -f "$AGENT_PID_FILE" ] || return 1
  local pid
  pid="$(head -n 1 "$AGENT_PID_FILE" | tr -d '[:space:]')"
  [ -n "$pid" ] || return 1
  printf '%s' "$pid"
}

agent_running() {
  local pid
  pid="$(agent_pid)" || return 1
  kill -0 "$pid" 2>/dev/null
}

restart_agent() {
  # kill 当前 agent，supervisor 检测到退出后会自动拉起（加载新配置）
  local pid
  pid="$(agent_pid)" || return 0
  kill -TERM "$pid" 2>/dev/null || true
  return 0
}

# ---------------- 路由 ----------------

URI="${REQUEST_URI:-/}"
URI_NO_QUERY="${URI%%\?*}"
SUB="${URI_NO_QUERY#*index.cgi}"    # 子路径，如 /api/config

case "${REQUEST_METHOD:-GET} $SUB" in
  "GET /"|"GET ")
    if [ -f "$INDEX_HTML" ]; then
      ctype="text/html; charset=utf-8"
      case "${INDEX_HTML##*.}" in
        html|htm) ctype="text/html; charset=utf-8" ;;
      esac
      text_out "200" "$ctype" "$(cat "$INDEX_HTML")"
    else
      text_out "404" "text/plain; charset=utf-8" "index.html not found"
    fi
    ;;

  "GET /api/config")
    if [ ! -f "$CONFIG_PATH" ]; then
      json_out "404" '{"ok":false,"error":"config.json 不存在，请先在应用设置中确认安装向导已填写" }'
    else
      echo "Status: 200"
      echo "Content-Type: application/json; charset=utf-8"
      echo "Cache-Control: no-store"
      echo ""
      cat "$CONFIG_PATH"
    fi
    ;;

  "POST /api/config")
    if ! is_admin; then
      json_out "403" '{"ok":false,"error":"仅管理员可修改配置"}'
      exit 0
    fi
    BODY_FILE="${TMP_DIR}/save.$$.json"
    trap 'rm -f "$BODY_FILE"' EXIT
    if ! read_body "$BODY_FILE"; then
      json_out "400" '{"ok":false,"error":"请求体为空"}'
      exit 0
    fi
    # 校验：agent 自身试运行（失败会返回错误日志，此时不写正式文件 -> 禁止保存）
    VALID_MSG="$(bash "$VALIDATE_SH" "$BODY_FILE" 2>&1)"
    if [ $? -ne 0 ]; then
      json_out "400" "{\"ok\":false,\"error\":\"$(json_escape_str "$VALID_MSG")\"}"
      exit 0
    fi
    # 校验通过：备份旧配置 -> 原子写回 -> 重启 agent
    [ -f "$CONFIG_PATH" ] && cp -f "$CONFIG_PATH" "$CONFIG_BAK" 2>/dev/null || true
    if ! mv -f "$BODY_FILE" "$CONFIG_PATH" 2>/dev/null; then
      json_out "500" '{"ok":false,"error":"写入 config.json 失败（权限？）"}'
      exit 0
    fi
    chmod 600 "$CONFIG_PATH" 2>/dev/null || true
    chown "$APP_USER:$APP_USER" "$CONFIG_PATH" 2>/dev/null || true
    restart_agent
    json_out "200" '{"ok":true,"message":"配置已保存，Agent 正在重启以应用新配置"}'
    ;;

  "GET /api/status")
    if agent_running; then
      json_out "200" "{\"ok\":true,\"running\":true,\"pid\":$(agent_pid)}"
    else
      json_out "200" '{"ok":true,"running":false,"pid":null}'
    fi
    ;;

  "POST /api/restart")
    if ! is_admin; then
      json_out "403" '{"ok":false,"error":"仅管理员可重启 Agent"}'
      exit 0
    fi
    restart_agent
    json_out "200" '{"ok":true,"message":"Agent 正在重启"}'
    ;;

  "GET /api/log")
    if [ -f "$AGENT_LOG" ]; then
      text_out "200" "text/plain; charset=utf-8" "$(tail -n 100 "$AGENT_LOG")"
    else
      text_out "404" "text/plain; charset=utf-8" "日志文件不存在"
    fi
    ;;

  *)
    json_out "404" '{"ok":false,"error":"not found"}'
    ;;
esac
