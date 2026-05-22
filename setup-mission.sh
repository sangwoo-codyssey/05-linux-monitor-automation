#!/bin/bash
# 미션 1~4단계 재현용 부트스트랩 스크립트.
# - 컨테이너 재빌드 후 매번 깨끗한 상태에서 학습 환경을 빠르게 복구한다.
# - idempotent 하지 않은 부분(useradd 등)은 있으면 skip 되도록 처리한다.
# - 자연 발견 거리 3건은 의도적으로 미적용 (각 단계 주석 참고):
#     1) setgid 비트 (Phase 6 monitor.log 그룹 발견 → chmod g+s)
#     2) /home/agent-admin traverse (Phase 5 monitor.sh 접근 실패 → chown :agent-common)
#     3) fine-grained sudo (Phase 6 sudo ufw status 실패 → /etc/sudoers.d 추가)

set -e

echo "=========================================="
echo "  미션 5: 1~4단계 환경 자동 구성"
echo "=========================================="

# -------------------------------------------
# 1단계: SSH 포트 변경 + Root 차단
# -------------------------------------------
echo ""
echo "[1단계] SSH 설정"

# 기존 Port/PermitRootLogin 라인을 주석 포함 모두 정리하고 새로 추가
sed -i '/^[#[:space:]]*Port[[:space:]]/d'             /etc/ssh/sshd_config
sed -i '/^[#[:space:]]*PermitRootLogin[[:space:]]/d'  /etc/ssh/sshd_config
{
  echo ""
  echo "# Codyssey mission 5"
  echo "Port 20022"
  echo "PermitRootLogin no"
} >> /etc/ssh/sshd_config

sshd -t && echo "  - sshd_config 문법 OK"

# Ubuntu 24.04에서도 컨테이너엔 systemd가 없으므로 service 명령 사용
service ssh restart >/dev/null
echo "  - sshd 재시작 완료"

ss -tlnp | grep -E ':20022\b' >/dev/null && echo "  - 20022 LISTEN 확인" || echo "  ! 20022 LISTEN 실패"

# -------------------------------------------
# 2단계: UFW 활성화 + 20022/15034 화이트리스트
# -------------------------------------------
echo ""
echo "[2단계] UFW 방화벽"

ufw --force reset >/dev/null
ufw default deny incoming   >/dev/null
ufw default allow outgoing  >/dev/null
ufw allow 20022/tcp         >/dev/null
ufw allow 15034/tcp         >/dev/null
ufw --force enable          >/dev/null
echo "  - UFW 활성화 + 두 포트 허용"
ufw status verbose | sed 's/^/    /'

# -------------------------------------------
# 3단계: 그룹/사용자/디렉터리/권한/ACL
# -------------------------------------------
echo ""
echo "[3단계] 계정/그룹/디렉터리/권한"

# 그룹
getent group agent-common >/dev/null || groupadd agent-common
getent group agent-core   >/dev/null || groupadd agent-core
echo "  - 그룹 생성: agent-common, agent-core"

# 사용자 (없을 때만 생성)
id agent-admin &>/dev/null || useradd -m -s /bin/bash -G agent-common,agent-core agent-admin
id agent-dev   &>/dev/null || useradd -m -s /bin/bash -G agent-common,agent-core agent-dev
id agent-test  &>/dev/null || useradd -m -s /bin/bash -G agent-common               agent-test
echo "  - 사용자 생성: agent-admin, agent-dev, agent-test"

# 기존 사용자에 보조 그룹 다시 정렬 (재실행 시 보정)
usermod -G agent-common,agent-core agent-admin
usermod -G agent-common,agent-core agent-dev
usermod -G agent-common              agent-test

# Ubuntu 24.04는 useradd -m 기본값이 chmod 750 + agent-admin:agent-admin.
# → agent-dev/test 가 /home/agent-admin 을 traverse 못 함.
# → Phase 5 monitor.sh (agent-dev 소유) 가 /home/agent-admin/agent-app/... 접근 시 실패하면서
#   "그룹 변경 (chown :agent-common) 으로 해결" 학습을 직접 경험하게 하는 자연 발견 거리.
# 의도적으로 chown/chmod 미적용 — 24.04 useradd -m 기본값 그대로 둠.

# 디렉터리
AGENT_HOME="/home/agent-admin/agent-app"
mkdir -p "$AGENT_HOME/upload_files"
mkdir -p "$AGENT_HOME/api_keys"
mkdir -p /var/log/agent-app

# 소유권 + 모드 — setgid 비트는 의도적으로 미적용.
# Phase 6 (cron monitor.sh) 에서 monitor.log 의 그룹이 agent-admin 으로 박히는 것을
# 자연스럽게 발견하고, chmod g+s 로 직접 fix 하는 학습 흐름을 유지하기 위함.
chown agent-admin:agent-common "$AGENT_HOME"
chmod 750                      "$AGENT_HOME"

chown agent-admin:agent-common "$AGENT_HOME/upload_files"
chmod 770                      "$AGENT_HOME/upload_files"

chown agent-admin:agent-core   "$AGENT_HOME/api_keys"
chmod 770                      "$AGENT_HOME/api_keys"

chown agent-admin:agent-core   /var/log/agent-app
chmod 770                      /var/log/agent-app

# 기본 ACL (앞으로 만들어질 파일에도 정책 자동 적용)
setfacl -m  g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -d -m g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m  g:agent-core:rwx   "$AGENT_HOME/api_keys"
setfacl -d -m g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m  g:agent-core:rwx   /var/log/agent-app
setfacl -d -m g:agent-core:rwx /var/log/agent-app

echo "  - 디렉터리/권한/ACL 적용 완료"

# -------------------------------------------
# 4단계: 환경 변수(envfile) + 키 파일
#   B+E 조합: envfile 진실의 원천 + .profile source
# -------------------------------------------
echo ""
echo "[4단계] 환경 변수 + 키 파일"

# (1) envfile — 5개 변수의 진실의 원천
cat > /home/agent-admin/agent-app.env <<'EOF'
# Codyssey mission 5 - agent-app 환경 변수
# (수정 시 이 파일만 고치면 .profile/monitor.sh 모두 반영됨)
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
EOF
chown agent-admin:agent-core /home/agent-admin/agent-app.env
chmod 640                    /home/agent-admin/agent-app.env
echo "  - envfile 생성: /home/agent-admin/agent-app.env (agent-admin:agent-core, 640)"

# (2) .profile 에서 source — 중복 방지
if ! grep -qF 'agent-app.env' /home/agent-admin/.profile 2>/dev/null; then
  cat >> /home/agent-admin/.profile <<'EOF'

# Codyssey mission 5 - envfile auto load
[ -f /home/agent-admin/agent-app.env ] && source /home/agent-admin/agent-app.env
EOF
  chown agent-admin:agent-admin /home/agent-admin/.profile
  echo "  - .profile 에 source 라인 추가"
else
  echo "  - .profile 이미 source 라인 보유 (skip)"
fi

# (3) fine-grained sudo (ufw status NOPASSWD) — 의도적 미적용.
#     Phase 6 cron monitor.sh 의 check_firewall 이 `sudo ufw status` 호출 →
#     "agent-admin is not in the sudoers file" / 패스워드 요구로 실패하는 것을 직접 확인하고,
#     /etc/sudoers.d/agent-admin-monitor 를 추가하여 최소 권한 원칙으로 해결하는 학습 흐름.

# (4) 키 파일
KEY_FILE="$AGENT_HOME/api_keys/t_secret.key"
echo 'agent_api_key_test' > "$KEY_FILE"
chown agent-admin:agent-core "$KEY_FILE"
chmod 640                    "$KEY_FILE"
echo "  - 키 파일 생성: $KEY_FILE (640, agent-admin:agent-core)"

echo ""
echo "=========================================="
echo "  완료! 검증: ./setup-mission.sh verify"
echo "=========================================="

# -------------------------------------------
# 검증 모드: ./setup-mission.sh verify
# -------------------------------------------
if [[ "${1:-}" == "verify" ]]; then
  echo ""
  echo "==== 검증 ===="
  echo "[id]";        id agent-admin; id agent-dev; id agent-test
  echo "[group]";     getent group agent-common; getent group agent-core
  echo "[dirs]";      ls -la "$AGENT_HOME"; ls -la /var/log/agent-app
  echo "[acl]";       getfacl "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" /var/log/agent-app
fi
