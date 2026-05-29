#!/usr/bin/env bash
# monitor.sh — 미션 5: 시스템 관제 자동화 스크립트
#
# 책임:
#   1) Health Check — agent-app 프로세스 + 15034 LISTEN (실패 시 exit 1)
#   2) 상태 점검 — UFW 활성 여부 (실패 시 [WARNING], 종료 X)
#   3) 자원 수집 — CPU / MEM / DISK 사용률
#   4) 임계값 경고 — CPU>20%, MEM>10%, DISK>80% (warning만)
#   5) 로그 누적 — /var/log/agent-app/monitor.log
#
# 로그 회전·보존은 logrotate (/etc/logrotate.d/agent-app-monitor) 가 회전·archive
# 이동·30일 삭제를, archive-compress.sh 가 7일 경과 압축을 분담 (패턴 B 책임 분리).
#   - 미션 §4.4 (10MB / 10개)            → logrotate
#   - 미션 §5 보너스 2 archive/삭제/예외 → logrotate
#   - 미션 §5 보너스 2 *7일 경과 압축*    → archive-compress.sh (find -mtime +7)
#   - 이전 사이클의 자체 회전 함수 rotate_log_if_needed() 는 *이중 회전 충돌
#     방지* 를 위해 제거.
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
# 로그 회전 임계는 logrotate 가 관리 → bash 상수 제거

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

# agent-app 자원 사용률 — 후보 PID 들의 %cpu / %mem 합산
#   - 입력: 공백 구분 PID 문자열 (get_app_pids 결과)
#   - 출력: "<cpu> <mem>" 한 줄, 각 소수 1자리
#   - 한 번의 ps 호출로 두 값 동시 측정 (race / 측정 시점 어긋남 최소화)
#   - 후보가 1개면 그 PID 의 사용률, 2개 이상이면 합산 → 부모/자식 판별 불필요
#   - "$pids" 는 반드시 따옴표로 묶어 단일 인자로 전달 → procps ps 가 공백/콤마
#     구분 PID 리스트로 파싱. 따옴표 빼면 워드 스플리팅으로 ps 가 깨진다.
#   - -o %cpu=,%mem= 의 "=" 는 헤더 제거 (필드명 = 빈 헤더)
get_app_usage() {
  local pids="$1"
  ps -p "$pids" -o %cpu=,%mem= \
    | awk '{ c += $1; m += $2 } END { printf "%.1f %.1f", c, m }'
}

# =====================================================
# 2. Health Check — TODO(human)
# =====================================================

# agent-app 후보 PID 목록 (공백 구분 한 줄)
#   - cmdline 의 *끝*이 /app/agent-app 인 것만 매치 (su/bash 래퍼 제외)
#   - Rosetta(Apple Silicon) 환경에서는 같은 패턴에 부모/자식 2개가 매치되고,
#     순수 리눅스에서는 1개만 매치된다.
#   - PID 번호 순서(작은 게 부모?)는 우연이므로 절대 정렬/선택 기준으로 쓰지 않는다.
#     "후보 전부" 를 그대로 반환하고, 자원 합산은 호출자(get_app_usage)가 ps 로 처리.
get_app_pids() {
  pgrep -f "/app/agent-app$" | xargs   # 줄바꿈 → 공백
}

# 프로세스 헬스체크 — 후보가 0개면 FAIL/exit 1, 1개 이상이면 PIDS 문자열 echo
check_process() {
  local pids
  pids=$(get_app_pids)
  if [[ -z "$pids" ]]; then
    echo "Checking process '${PROCESS_PATTERN}'... [FAIL]" >&2
    exit 1
  fi
  echo "$pids"
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
# 4. 로그 회전 — 외부 도구가 담당 (패턴 B 책임 분리)
#    - /etc/logrotate.d/agent-app-monitor  : 회전 + archive 이동 + 30일 삭제
#    - $AGENT_HOME/bin/archive-compress.sh : 7일 경과 .log → .gz
#    이전 bash 회전 함수는 이중 회전 충돌 방지로 제거됨
# =====================================================

# =====================================================
# 5. 메인 흐름
# =====================================================
main() {
  echo "====== SYSTEM MONITOR RESULT ======"
  echo
  echo "[HEALTH CHECK]"

  # 서브쉘 안의 exit 1 은 메인까지 전파되지 않으므로 || exit 1 로 명시 catch
  local pids
  pids=$(check_process) || exit 1
  echo "Checking process '${PROCESS_PATTERN}'... [OK] (PIDs: $pids)"
  check_port
  check_firewall

  echo
  echo "[RESOURCE MONITORING]"
  local cpu mem disk app_cpu app_mem
  cpu=$(get_cpu_usage)
  mem=$(get_mem_usage)
  disk=$(get_disk_used)
  read -r app_cpu app_mem < <(get_app_usage "$pids")

  printf "CPU   System: %5s%%   App: %5s%%\n" "$cpu" "$app_cpu"
  printf "MEM   System: %5s%%   App: %5s%%\n" "$mem" "$app_mem"
  printf "DISK  System: %5s%%\n"              "$disk"

  echo
  check_threshold "CPU"  "$cpu"  "$THRESH_CPU"
  check_threshold "MEM"  "$mem"  "$THRESH_MEM"
  check_threshold "DISK" "$disk" "$THRESH_DISK"

  # 로그 누적 (회전은 logrotate 가 별도 cron 으로 처리)
  local ts pids_csv
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  pids_csv=$(echo "$pids" | tr ' ' ',')
  printf "[%s] PIDS:%s SYS_CPU:%s%% SYS_MEM:%s%% APP_CPU:%s%% APP_MEM:%s%% DISK_USED:%s%%\n" \
    "$ts" "$pids_csv" "$cpu" "$mem" "$app_cpu" "$app_mem" "$disk" >> "$LOG_FILE"

  echo
  echo "[INFO] Log appended: $LOG_FILE"
}

main "$@"
