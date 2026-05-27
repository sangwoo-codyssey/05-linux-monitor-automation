#!/usr/bin/env bash
# archive-compress.sh — 7일 경과 회전 로그를 gzip 으로 압축
#
# 미션 5 보너스 2 의 "7일 경과 로그 압축" 항목을 정확히 구현.
#
# 책임 분리 (패턴 B):
#   - 회전 / archive 이동 / 30일 경과 삭제 → logrotate (/etc/logrotate.d/agent-app-monitor)
#   - 7일 경과 압축 (시간 기반 상태)        → 본 스크립트 (매일 cron)
#
# 실행 컨텍스트: cron 이 매일 새벽 agent-admin 계정으로 호출
# 멱등성: find -mtime 패턴은 *이미 .gz 인 건 매칭 안 됨* → 매일 돌려도 안전.

set -u

ARCHIVE_DIR="/var/log/monitor/agent-app/archive"
AGE_DAYS=7
TS="$(date '+%Y-%m-%d %H:%M:%S')"

echo "[${TS}] [archive-compress] start (target: ${ARCHIVE_DIR}, age: >${AGE_DAYS}d)"

# 예외 처리 1 — archive 디렉터리 미존재
if [[ ! -d "$ARCHIVE_DIR" ]]; then
  echo "[${TS}] [archive-compress] [WARN] 디렉터리 없음 — skip (${ARCHIVE_DIR})"
  exit 0
fi

# 예외 처리 2 — 권한 부족
if [[ ! -r "$ARCHIVE_DIR" || ! -w "$ARCHIVE_DIR" ]]; then
  echo "[${TS}] [archive-compress] [WARN] 권한 부족 — skip (${ARCHIVE_DIR})"
  exit 0
fi

# 7일 경과 *.log 만 (이미 .gz 인 건 매칭 X) 카운트
mapfile -t TARGETS < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$AGE_DAYS" 2>/dev/null)
COUNT="${#TARGETS[@]}"

# 예외 처리 3 — 대상 파일 0개
if [[ "$COUNT" -eq 0 ]]; then
  echo "[${TS}] [archive-compress] [INFO] 7일 경과 .log 없음 — skip"
  exit 0
fi

echo "[${TS}] [archive-compress] [INFO] ${COUNT}개 파일 압축 시작"
for f in "${TARGETS[@]}"; do
  if gzip -- "$f" 2>/dev/null; then
    echo "  - $f → ${f}.gz"
  else
    echo "  ! $f 압축 실패 (skip)"
  fi
done
echo "[${TS}] [archive-compress] done"
