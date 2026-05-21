#!/usr/bin/env bash
# monitor.sh — 미션 5: 시스템 관제 자동화 스크립트
#
# 책임:
#   1) Health Check — agent-app 프로세스 + 15034 LISTEN (실패 시 exit 1)
#   2) 상태 점검 — UFW 활성 여부 (실패 시 [WARNING], 종료 X)
#   3) 자원 수집 — CPU / MEM / DISK 사용률
#   4) 임계값 경고 — CPU>20%, MEM>10%, DISK>80% (warning만)
#   5) 로그 누적 — /var/log/agent-app/monitor.log
#   6) 로그 로테이션 — 10MB / 10개 파일 유지
#
# 실행 컨텍스트: cron이 매분 agent-admin 계정으로 호출
#   → cron 환경은 .profile 을 읽지 않으므로 envfile 명시 source 필요

set -u   # 미정의 변수 사용 시 즉시 에러 (운영 스크립트의 안전망)

# =====================================================
# 0. 환경 변수 로드 (cron 환경 대비)
# =====================================================
ENV_FILE="/home/agent-admin/agent-app.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

: "${AGENT_HOME:?AGENT_HOME not set — envfile missing?}"
: "${AGENT_PORT:?AGENT_PORT not set}"
: "${AGENT_LOG_DIR:?AGENT_LOG_DIR not set}"

LOG_FILE="$AGENT_LOG_DIR/monitor.log"
PROCESS_PATTERN="agent-app"
THRESH_CPU=20
THRESH_MEM=10
THRESH_DISK=80
LOG_MAX_SIZE=$((10 * 1024 * 1024))   # 10MB
LOG_MAX_FILES=10

# =====================================================
# 1. 자원 수집 함수들 — TODO(human)
# =====================================================

# CPU 사용률(%) — 소수 1자리
#   top -bn1 의 "%Cpu(s)" 라인에서 idle 값을 찾아 100 에서 차감
#   awk: -F'[ ,]+' 로 콤마/공백 모두 구분자 → 필드를 순회하며 "id" 직전 값을 얻음
get_cpu_usage() {
  top -bn1 | awk -F'[ ,]+' '
    /Cpu\(s\)/ {
      for (i=1; i<=NF; i++)
        if ($i == "id") { printf "%.1f", 100 - $(i-1); exit }
    }'
}

# 메모리 사용률(%) — 소수 1자리
#   free -m 의 "Mem:" 라인에서 used($3) / total($2) * 100
get_mem_usage() {
  free -m | awk '/^Mem:/ { printf "%.1f", $3/$2*100 }'
}

# 루트 파티션(/) 사용률 — 정수(%)
#   df -P / 의 두 번째 줄 5번째 컬럼에서 % 제거
get_disk_used() {
  df -P / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }'
}

# =====================================================
# 2. Health Check — TODO(human)
# =====================================================

# agent-app 프로세스 PID 찾기
#   - pgrep -f "/app/agent-app$" — cmdline 의 *끝*이 정확히 /app/agent-app 인 것만
#     매치 → su/bash 래퍼(끝이 "2>&1") 와 임의의 echo 잡음 제거
#   - 여러 개 매치되면 첫 번째 PID만 사용
#   - 없으면 stderr 로 [FAIL] + exit 1
check_process() {
  local pid
  pid=$(pgrep -f "/app/agent-app$" | head -1)
  if [[ -z "$pid" ]]; then
    echo "Checking process '${PROCESS_PATTERN}'... [FAIL]" >&2
    exit 1
  fi
  echo "$pid"
}

# 포트 LISTEN 확인 (참고 — 직접 작성된 예)
check_port() {
  if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${AGENT_PORT}\$"; then
    echo "Checking port ${AGENT_PORT}... [OK]"
    return 0
  fi
  echo "Checking port ${AGENT_PORT}... [FAIL]" >&2
  exit 1
}

# 방화벽 상태 (실패 시 WARNING만, 종료 X)
#   - ufw status는 root만 가능 → sudoers에 fine-grained 권한 부여됨
check_firewall() {
  if sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
    return 0
  fi
  echo "[WARNING] Firewall (UFW) is not active"
}

# =====================================================
# 3. 임계값 경고 — TODO(human)
# =====================================================

# 임계값 초과 시 [WARNING] 출력
#   - bash는 정수만 비교 가능 → awk 의 exit code 로 부동소수점 비교
#   - exit !(v>t): v>t 가 참(1)이면 exit 0, 거짓이면 exit 1
#   - 쉘의 `if` 가 exit code 로 분기
check_threshold() {
  local name=$1 value=$2 thresh=$3
  if awk -v v="$value" -v t="$thresh" 'BEGIN { exit !(v > t) }'; then
    echo "[WARNING] ${name} threshold exceeded (${value}% > ${thresh}%)"
  fi
}

# =====================================================
# 4. 로그 로테이션 (10MB / 10개)
# =====================================================
rotate_log_if_needed() {
  [[ ! -f "$LOG_FILE" ]] && return 0
  local size
  size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
  if (( size >= LOG_MAX_SIZE )); then
    # .9 → .10, .8 → .9, ..., .1 → .2 순으로 한 칸씩 밀고
    for ((i = LOG_MAX_FILES - 1; i >= 1; i--)); do
      [[ -f "${LOG_FILE}.${i}" ]] && mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))"
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
    rm -f "${LOG_FILE}.$((LOG_MAX_FILES+1))" 2>/dev/null || true
  fi
}

# =====================================================
# 5. 메인 흐름
# =====================================================
main() {
  echo "====== SYSTEM MONITOR RESULT ======"
  echo
  echo "[HEALTH CHECK]"

  # 서브쉘 안의 exit 1 은 메인까지 전파되지 않으므로 || exit 1 로 명시 catch
  local pid
  pid=$(check_process) || exit 1
  echo "Checking process '${PROCESS_PATTERN}'... [OK] (PID: $pid)"
  check_port
  check_firewall

  echo
  echo "[RESOURCE MONITORING]"
  local cpu mem disk
  cpu=$(get_cpu_usage)
  mem=$(get_mem_usage)
  disk=$(get_disk_used)
  printf "CPU Usage : %s%%\n" "$cpu"
  printf "MEM Usage : %s%%\n" "$mem"
  printf "DISK Used : %s%%\n" "$disk"

  echo
  check_threshold "CPU"  "$cpu"  "$THRESH_CPU"
  check_threshold "MEM"  "$mem"  "$THRESH_MEM"
  check_threshold "DISK" "$disk" "$THRESH_DISK"

  # 로그 누적
  rotate_log_if_needed
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf "[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n" \
    "$ts" "$pid" "$cpu" "$mem" "$disk" >> "$LOG_FILE"

  echo
  echo "[INFO] Log appended: $LOG_FILE"
}

main "$@"
