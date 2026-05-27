#!/usr/bin/env bash
# report.sh — monitor.log 통계 리포트 (미션 5 보너스 1)
#
# CPU / MEM / DISK 의 평균·최대·최소 + 샘플 수를 콘솔로 출력.
#
# 사용법:
#   ./report.sh                                              # 전체 분석
#   ./report.sh '2026-05-26 12:00:00' '2026-05-26 18:00:00'  # 구간 분석 (선택)
#
# 분석 대상: 현재 monitor.log 한 파일만 (미션 보너스 1 원문 정확 매핑).
#            회전본 (archive/*) 은 분석 범위 외 — 필요 시 별도 사이클.

set -u

LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
FROM="${1:-}"
TO="${2:-}"

if [[ ! -r "$LOG_FILE" ]]; then
  echo "[ERROR] $LOG_FILE 읽기 불가" >&2
  exit 1
fi

awk -v from="$FROM" -v to="$TO" '
{
  # 라인 포맷: [YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%
  # 타임스탬프: 첫 두 필드의 대괄호 제거
  ts = $1 " " $2
  gsub(/[\[\]]/, "", ts)

  # 구간 필터 (lexicographic 문자열 비교 — ISO 8601 포맷이라 정확)
  if (from != "" && ts < from) next
  if (to   != "" && ts > to)   next

  # CPU / MEM / DISK 값 추출 (필드 순회)
  cpu = mem = disk = ""
  for (i = 1; i <= NF; i++) {
    if      ($i ~ /^CPU:/)       { cpu  = substr($i, 5);  sub(/%$/, "", cpu) }
    else if ($i ~ /^MEM:/)       { mem  = substr($i, 5);  sub(/%$/, "", mem) }
    else if ($i ~ /^DISK_USED:/) { disk = substr($i, 11); sub(/%$/, "", disk) }
  }

  # 값 누락 라인은 skip (방어적 파싱)
  if (cpu == "" || mem == "" || disk == "") next

  if (count == 0) {
    # 첫 샘플로 min/max 초기화
    cpu_min  = cpu_max  = cpu;  cpu_min_ts  = cpu_max_ts  = ts
    mem_min  = mem_max  = mem;  mem_min_ts  = mem_max_ts  = ts
    disk_min = disk_max = disk; disk_min_ts = disk_max_ts = ts
  } else {
    if (cpu+0  > cpu_max+0)  { cpu_max  = cpu;  cpu_max_ts  = ts }
    if (cpu+0  < cpu_min+0)  { cpu_min  = cpu;  cpu_min_ts  = ts }
    if (mem+0  > mem_max+0)  { mem_max  = mem;  mem_max_ts  = ts }
    if (mem+0  < mem_min+0)  { mem_min  = mem;  mem_min_ts  = ts }
    if (disk+0 > disk_max+0) { disk_max = disk; disk_max_ts = ts }
    if (disk+0 < disk_min+0) { disk_min = disk; disk_min_ts = ts }
  }

  count++
  cpu_sum  += cpu
  mem_sum  += mem
  disk_sum += disk
}
END {
  printf "====== STATISTICS REPORT ======\n"
  if (from != "" || to != "") {
    printf "Range : %s ~ %s\n", (from != "" ? from : "(begin)"), (to != "" ? to : "(end)")
  }
  if (count == 0) {
    printf "[INFO] 분석할 샘플 없음\n"
    exit
  }
  printf "[CPU]\n"
  printf "  Average : %.1f%%\n",    cpu_sum / count
  printf "  Maximum : %s%% at %s\n", cpu_max, cpu_max_ts
  printf "  Minimum : %s%% at %s\n", cpu_min, cpu_min_ts
  printf "[Memory]\n"
  printf "  Average : %.1f%%\n",    mem_sum / count
  printf "  Maximum : %s%% at %s\n", mem_max, mem_max_ts
  printf "  Minimum : %s%% at %s\n", mem_min, mem_min_ts
  printf "[Disk]\n"
  printf "  Average : %.1f%%\n",    disk_sum / count
  printf "  Maximum : %s%% at %s\n", disk_max, disk_max_ts
  printf "  Minimum : %s%% at %s\n", disk_min, disk_min_ts
  printf "[Samples]\n"
  printf "  Data Points: %d samples\n", count
}
' "$LOG_FILE"
