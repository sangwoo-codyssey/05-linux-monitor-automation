# 미션 5 — 리눅스 시스템 관제 자동화 (수행 내역서)

다중 사용자 환경의 **권한 관리 + 네트워크 보안 + 시스템 리소스 관제 + 로그 관리 자동화** 를 실제 운영 엔지니어처럼 직접 설계·구축·검증한 저장소입니다.

본 문서는 **미션 §2 "필수 증거 자료 체크리스트 8건"** 을 그대로 챕터로 삼아, 각 항목마다 *검증 명령 → 실제 실행 결과 → 캡처* 를 한 흐름으로 담은 **자기충족형 증거 문서** 입니다. 별도 자료 (예: `JOURNAL.md`) 를 열어 보지 않아도 본 파일 한 개로 모든 평가 항목을 확인할 수 있습니다.

> 트러블슈팅·자연발견·의사결정 과정 등 *학습 일지* 는 별도 [`JOURNAL.md`](./JOURNAL.md) 에 보관 — 본 README 의 평가에는 필요 없음.

---

## Quick Start (3분 재현)

```bash
git clone https://github.com/sangwoo-codyssey/05-linux-monitor-automation.git
cd 05-linux-monitor-automation

./run.sh build && ./run.sh up                                    # Docker 빌드 + 기동
docker exec codyssey05 bash /app/setup-mission.sh                # 1~4단계 환경 자동 구성
docker exec -d codyssey05 su - agent-admin -c /app/agent-app     # agent-app 백그라운드 기동
docker exec codyssey05 sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
```

---

## 실행 환경

| 항목 | 버전 |
|------|------|
| Host OS | macOS 26.3.1 (Apple Silicon, arm64) |
| Container OS | Ubuntu 24.04 LTS (linux/amd64, GLIBC 2.39) |
| Docker | 29.3.0 |
| Container Shell | bash 5.2.21 |
| 핵심 패키지 | `openssh-server`, `ufw`, `cron`, `sudo`, `acl`, `iproute2`, `procps`, `vim` |

```bash
# 환경 확인 명령어
sw_vers                                  # macOS 버전
uname -m                                 # 호스트 아키텍처 (arm64)
docker --version                         # Docker 버전
docker exec codyssey05 lsb_release -a    # 컨테이너 Ubuntu
docker exec codyssey05 ldd --version     # GLIBC
```

---

## 산출물

| 산출물 | 파일 | 역할 |
|--------|------|------|
| 요구사항 수행 내역서 | `README.md` (본 파일) | 미션 §2 의 필수 증거 8건 |
| 자동화 스크립트 | [`monitor.sh`](./monitor.sh) | Health Check + 자원 수집 + 임계값 경고 + 로그 누적 |
| 환경 자동 구성 | [`setup-mission.sh`](./setup-mission.sh) | 1~4단계 (SSH/UFW/계정/env) 일괄 구성 — 재현용 |
| 컨테이너 빌드 | [`Dockerfile`](./Dockerfile) | Ubuntu 24.04 + 필요한 패키지 |
| 컨테이너 생명주기 | [`run.sh`](./run.sh) | `build / up / start / stop / shell / down` |

---

# 미션 §2 — 필수 증거 자료 체크리스트 (8건)

| # | 미션 명시 항목 | 본 README 챕터 | 결과 |
|---|---------------|----------------|:----:|
| 1 | SSH 포트 변경(20022) 및 Root 원격 접속 차단 설정 확인 | [§1](#1-ssh-포트-변경20022--root-원격-접속-차단) | ✅ |
| 2 | 방화벽 활성화 및 20022/tcp, 15034/tcp만 허용 | [§2](#2-ufw-방화벽-활성화--2002215034만-허용) | ✅ |
| 3 | 계정/그룹 생성 확인 | [§3](#3-계정그룹-생성-확인) | ✅ |
| 4 | 디렉토리 구조 및 권한 (ACL 포함) 확인 | [§4](#4-디렉토리-구조--권한acl-포함) | ✅ |
| 5 | 앱 Boot Sequence 5단계 [OK] 및 "Agent READY" 확인 | [§5](#5-앱-boot-sequence-55--agent-ready) | ✅ |
| 6 | monitor.sh 실행 결과 (프로세스/포트/리소스/경고) | [§6](#6-monitorsh-실행-결과) | ✅ |
| 7 | /var/log/agent-app/monitor.log 누적 기록 (최근 라인) | [§7](#7-varlogagent-appmonitorlog-누적-기록) | ✅ |
| 8 | crontab 매분 실행 등록 및 자동 실행 확인 (1분 후 로그 증가) | [§8](#8-crontab-매분-실행-등록--자동-실행-확인) | ✅ |

> 모든 검증 명령은 컨테이너 안에서 실행됨 (`docker exec codyssey05 …` 또는 `./run.sh shell` 후).

---

## §1. SSH 포트 변경(20022) + Root 원격 접속 차단

### 1-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 1.1 | sshd_config 의 Port 가 `20022` | `grep '^Port' /etc/ssh/sshd_config` | [x] |
| 1.2 | sshd_config 의 PermitRootLogin = `no` | `grep '^PermitRootLogin' /etc/ssh/sshd_config` | [x] |
| 1.3 | sshd 데몬이 20022 LISTEN | `ss -tlnp \| grep ':20022'` | [x] |
| 1.4 | 22 포트는 LISTEN 하지 *않음* | `ss -tlnp \| grep ':22 '` | [x] |
| 1.5 | 호스트에서 root 로그인 시도가 정책에 의해 거부됨 | `ssh -p 20022 root@localhost` → `Permission denied` | [x] |

### 1-2. 검증 실행 결과

#### sshd_config (포트 + Root 차단)

```bash
root@codyssey05:/app# grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
Port 20022
PermitRootLogin no
```

![sshd_config 변경](screenshots/ssh-02.png)

#### sshd 문법 검증 + 데몬 재기동

```bash
root@codyssey05:/app# sshd -t
(출력 없음 = 정상)

root@codyssey05:/app# service ssh restart
 * Restarting OpenBSD Secure Shell server sshd                            [ OK ]
```

#### 20022 LISTEN 확인 — `ss + ps` 콤보

```bash
root@codyssey05:/app# ss -tlnp | grep sshd
LISTEN 0  128  0.0.0.0:20022  0.0.0.0:*  users:(("sshd",pid=41,fd=3))
LISTEN 0  128  [::]:20022     [::]:*     users:(("sshd",pid=41,fd=4))

root@codyssey05:/app# ps -ef | grep -v grep | grep sshd
root  41  1  0  ...  sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
```

![ss + ps](screenshots/ssh-05.png)

#### 호스트(macOS) → 컨테이너 SSH 도달 + Root 차단 정책 동작

```bash
sangwoo@sangwoo-MacBookAir % ssh -p 20022 root@localhost
root@localhost: Permission denied (publickey,password).
```

→ 연결 자체는 sshd 가 응답해 *포트 도달성* 확인, `PermitRootLogin no` 정책에 의해 *root 차단* 확인. **한 줄로 1.3 ~ 1.5 동시 입증**.

![ssh 도달 + root 차단](screenshots/ssh-06.png)

---

## §2. UFW 방화벽 활성화 + 20022/15034만 허용

### 2-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 2.1 | UFW 활성화 (`Status: active`) | `ufw status verbose` | [x] |
| 2.2 | 기본 정책 `deny (incoming)` + `allow (outgoing)` | (위 출력) | [x] |
| 2.3 | `20022/tcp` 인바운드 ALLOW | `ufw status \| grep 20022/tcp` | [x] |
| 2.4 | `15034/tcp` 인바운드 ALLOW | `ufw status \| grep 15034/tcp` | [x] |
| 2.5 | 그 외 포트는 모두 default deny | (2.2) | [x] |

### 2-2. 검증 실행 결과

#### UFW 정책 설정 (전체 흐름)

```bash
root@codyssey05:/app# ufw default deny incoming
Default incoming policy changed to 'deny'
root@codyssey05:/app# ufw default allow outgoing
Default outgoing policy changed to 'allow'

root@codyssey05:/app# ufw allow 20022/tcp
Rules updated
Rules updated (v6)
root@codyssey05:/app# ufw allow 15034/tcp
Rules updated
Rules updated (v6)

root@codyssey05:/app# ufw --force enable
Firewall is active and enabled on system startup
```

![UFW 정책 설정](screenshots/ufw-01.png)

#### UFW 최종 상태

```bash
root@codyssey05:/app# ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
20022/tcp (v6)             ALLOW IN    Anywhere (v6)
15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```

![ufw status verbose](screenshots/ufw-02.png)

→ **화이트리스트 정책 완성**: 두 포트만 명시 허용, 나머지는 default deny 로 자동 차단.

---

## §3. 계정/그룹 생성 확인

### 3-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 3.1 | 그룹 `agent-common` 존재 | `getent group agent-common` | [x] |
| 3.2 | 그룹 `agent-core` 존재 | `getent group agent-core` | [x] |
| 3.3 | 계정 `agent-admin` 생성 + 두 그룹 가입 | `id agent-admin` | [x] |
| 3.4 | 계정 `agent-dev` 생성 + 두 그룹 가입 | `id agent-dev` | [x] |
| 3.5 | 계정 `agent-test` 생성 + agent-common 만 가입 (agent-core 제외) | `id agent-test` | [x] |
| 3.6 | `agent-common` = admin + dev + test | `getent group agent-common` | [x] |
| 3.7 | `agent-core` = admin + dev (test 제외) | `getent group agent-core` | [x] |

### 3-2. 검증 실행 결과

#### 그룹 생성

```bash
root@codyssey05:/app# groupadd agent-common
root@codyssey05:/app# groupadd agent-core
root@codyssey05:/app# getent group agent-common agent-core
agent-common:x:1000:
agent-core:x:1001:
```

![그룹 생성](screenshots/perm-01.png)

#### 사용자 생성 (보조 그룹 동시 가입)

```bash
root@codyssey05:/app# useradd -m -s /bin/bash -G agent-common,agent-core agent-admin
root@codyssey05:/app# useradd -m -s /bin/bash -G agent-common,agent-core agent-dev
root@codyssey05:/app# useradd -m -s /bin/bash -G agent-common              agent-test
```

#### id 검증 — 3 계정 모두

```bash
root@codyssey05:/app# id agent-admin
uid=1001(agent-admin) gid=1002(agent-admin) groups=1002(agent-admin),1000(agent-common),1001(agent-core)

root@codyssey05:/app# id agent-dev
uid=1002(agent-dev)   gid=1003(agent-dev)   groups=1003(agent-dev),1000(agent-common),1001(agent-core)

root@codyssey05:/app# id agent-test
uid=1003(agent-test)  gid=1004(agent-test)  groups=1004(agent-test),1000(agent-common)
```

![사용자 생성 + id](screenshots/perm-02.png)

#### 그룹 멤버 역방향 확인

```bash
root@codyssey05:/app# getent group agent-common agent-core
agent-common:x:1000:agent-admin,agent-dev,agent-test     ← 3명 모두
agent-core:x:1001:agent-admin,agent-dev                   ← test 제외
```

→ 미션 명세 정확 일치: `agent-common = admin/dev/test`, `agent-core = admin/dev`.

---

## §4. 디렉토리 구조 + 권한 (ACL 포함)

### 4-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 4.1 | `$AGENT_HOME` (`/home/agent-admin/agent-app`) 존재 | `ls -ld /home/agent-admin/agent-app` | [x] |
| 4.2 | `$AGENT_HOME/upload_files` 존재 | `ls -ld …/upload_files` | [x] |
| 4.3 | `$AGENT_HOME/api_keys` 존재 | `ls -ld …/api_keys` | [x] |
| 4.4 | `/var/log/agent-app` 존재 | `ls -ld /var/log/agent-app` | [x] |
| 4.5 | `upload_files`: group=`agent-common`, R/W | `ls -ld …/upload_files` + `getfacl` | [x] |
| 4.6 | `api_keys`: group=`agent-core` ONLY, R/W | `getfacl …/api_keys` (agent-common 미포함) | [x] |
| 4.7 | `/var/log/agent-app`: group=`agent-core` ONLY, R/W | `getfacl /var/log/agent-app` | [x] |
| 4.8 | default ACL 적용 (새 파일 자동 권한 상속) | `getfacl … \| grep default:` | [x] |
| 4.9 | 빙의(`sudo -u`) 차단/허용 정책이 의도대로 작동 | `sudo -u <user> touch …` | [x] |

### 4-2. 디렉터리 + 권한 + ACL 적용

```bash
# 디렉터리 트리
root@codyssey05:/app# mkdir -p /home/agent-admin/agent-app/upload_files \
>                              /home/agent-admin/agent-app/api_keys \
>                              /var/log/agent-app

# 소유권 + setgid 비트 — 새 파일이 부모 그룹 자동 상속
root@codyssey05:/app# chown agent-admin:agent-common /home/agent-admin/agent-app
root@codyssey05:/app# chmod 2750                     /home/agent-admin/agent-app

root@codyssey05:/app# chown agent-admin:agent-common /home/agent-admin/agent-app/upload_files
root@codyssey05:/app# chmod 2770                     /home/agent-admin/agent-app/upload_files

root@codyssey05:/app# chown agent-admin:agent-core   /home/agent-admin/agent-app/api_keys
root@codyssey05:/app# chmod 2770                     /home/agent-admin/agent-app/api_keys

root@codyssey05:/app# chown agent-admin:agent-core   /var/log/agent-app
root@codyssey05:/app# chmod 2770                     /var/log/agent-app
```

![디렉터리 + 권한](screenshots/perm-04.png)

```bash
# 기본 ACL — 미션 체크리스트 *"ACL 포함"* 명시 증거 + 안전망
root@codyssey05:/app# setfacl -m   g:agent-common:rwx /home/agent-admin/agent-app/upload_files
root@codyssey05:/app# setfacl -d -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files

root@codyssey05:/app# setfacl -m   g:agent-core:rwx   /home/agent-admin/agent-app/api_keys
root@codyssey05:/app# setfacl -d -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys

root@codyssey05:/app# setfacl -m   g:agent-core:rwx   /var/log/agent-app
root@codyssey05:/app# setfacl -d -m g:agent-core:rwx /var/log/agent-app
```

![ACL 적용](screenshots/perm-06.png)

### 4-3. 권한 확인 — `ls -la` + `getfacl`

```bash
root@codyssey05:/app# ls -la /home/agent-admin/agent-app/
total 16
drwxr-s---  4 agent-admin agent-common 4096 May 12 16:40 .
drwxr-x---  3 agent-admin agent-admin  4096 May 12 16:40 ..
drwxrws---+ 2 agent-admin agent-core   4096 May 12 16:40 api_keys
drwxrws---+ 2 agent-admin agent-common 4096 May 12 16:40 upload_files
```

```bash
root@codyssey05:/app# getfacl /home/agent-admin/agent-app/api_keys
# file: home/agent-admin/agent-app/api_keys
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---
```

```bash
root@codyssey05:/app# getfacl /var/log/agent-app
# file: var/log/agent-app
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---
```

> `drwxrws---+` 해석 — `s` (group 위치) = setgid 비트, `+` (끝) = POSIX ACL 추가. `getfacl` 출력의 `default:group:agent-core:rwx` 가 *새 파일에 자동 상속될 권한*. `agent-common` 항목이 **없는 것** = api_keys/varlog 가 agent-core 전용임을 증명.

### 4-4. ✅ 빙의(`sudo -u`) 시나리오 — 정책 동작 검증

```bash
root@codyssey05:/app# echo '=== agent-test 빙의 ==='
=== agent-test 빙의 ===
# upload_files (agent-common) → agent-test 도 멤버이므로 OK
root@codyssey05:/app# sudo -u agent-test touch /home/agent-admin/agent-app/upload_files/ok.txt
(출력 없음 = 성공)

# api_keys (agent-core ONLY) → agent-test 는 멤버 아님 → 차단
root@codyssey05:/app# sudo -u agent-test touch /home/agent-admin/agent-app/api_keys/should_fail.txt
touch: cannot touch '/home/agent-admin/agent-app/api_keys/should_fail.txt': Permission denied

# /var/log/agent-app (agent-core ONLY) → agent-test 차단
root@codyssey05:/app# sudo -u agent-test touch /var/log/agent-app/should_fail.txt
touch: cannot touch '/var/log/agent-app/should_fail.txt': Permission denied

root@codyssey05:/app# echo '=== agent-dev 빙의 ==='
=== agent-dev 빙의 ===
# api_keys → agent-dev 는 agent-core 멤버 → OK
root@codyssey05:/app# sudo -u agent-dev touch /home/agent-admin/agent-app/api_keys/ok_dev.txt
(출력 없음 = 성공)

# /var/log/agent-app → 동일하게 OK
root@codyssey05:/app# sudo -u agent-dev touch /var/log/agent-app/ok_dev.txt
(출력 없음 = 성공)
```

![빙의 권한 매트릭스](screenshots/perm-07.png)

#### setgid 효과 (새 파일이 부모 그룹 상속)

```bash
root@codyssey05:/app# ls -la /home/agent-admin/agent-app/upload_files/ok_test.txt
-rw-rw----+ 1 agent-test agent-common 0 May 12 16:42 .../ok_test.txt   ← test가 만들었는데 그룹은 common

root@codyssey05:/app# ls -la /home/agent-admin/agent-app/api_keys/ok_dev.txt
-rw-rw----+ 1 agent-dev  agent-core   0 May 12 16:42 .../ok_dev.txt    ← dev가 만들었는데 그룹은 core
```

→ **agent-common ↔ agent-core 역할 분리 정책이 정확히 작동**. 새 파일의 그룹 owner 가 setgid 로 부모 디렉터리 그룹을 자동 상속, ACL 의 default 항목과 함께 미션 §4.2 의 *"agent-core ONLY R/W"* 요구를 충족.

---

## §5. 앱 Boot Sequence 5/5 + "Agent READY"

### 5-1. 세부 체크리스트

| # | 검증 항목 | 확인 위치 | 상태 |
|---|----------|-----------|:----:|
| 5.1 | `AGENT_HOME` 정의 | `su - agent-admin -c 'echo $AGENT_HOME'` | [x] |
| 5.2 | `AGENT_PORT=15034` | `su - agent-admin -c 'echo $AGENT_PORT'` | [x] |
| 5.3 | `AGENT_UPLOAD_DIR` / `AGENT_KEY_PATH` / `AGENT_LOG_DIR` 정의 | (위 패턴) | [x] |
| 5.4 | 키 파일 `t_secret.key` 존재 + 내용 = `agent_api_key_test` | `cat $AGENT_KEY_PATH` | [x] |
| 5.5 | 앱이 *루트 아닌 일반 계정* (`agent-admin`) 로 실행 | `ps -ef \| grep agent-app` (UID ≠ 0) | [x] |
| 5.6 | `[1/5] Checking User Account [OK]` | 앱 stdout | [x] |
| 5.7 | `[2/5] Verifying Environment Variables [OK]` | 앱 stdout | [x] |
| 5.8 | `[3/5] Checking Required Files [OK]` | 앱 stdout | [x] |
| 5.9 | `[4/5] Checking Port Availability [OK]` | 앱 stdout | [x] |
| 5.10 | `[5/5] Verifying Log Permission [OK]` | 앱 stdout | [x] |
| 5.11 | `"Agent READY"` 출력 | 앱 stdout | [x] |
| 5.12 | `0.0.0.0:15034` LISTEN | `ss -tlnp \| grep 15034` | [x] |

### 5-2. 환경 변수 + 키 파일

```bash
# envfile — 단일 진실의 원천 (5개 변수)
root@codyssey05:/app# cat > /home/agent-admin/agent-app.env <<'EOF'
> export AGENT_HOME=/home/agent-admin/agent-app
> export AGENT_PORT=15034
> export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
> export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
> export AGENT_LOG_DIR=/var/log/agent-app
> EOF

root@codyssey05:/app# chown agent-admin:agent-core /home/agent-admin/agent-app.env
root@codyssey05:/app# chmod 640                    /home/agent-admin/agent-app.env
```

![envfile 생성](screenshots/env-01.png)

```bash
# .profile 에서 envfile 자동 source
root@codyssey05:/app# cat >> /home/agent-admin/.profile <<'EOF'
>
> # Codyssey mission 5 - envfile auto load
> [ -f /home/agent-admin/agent-app.env ] && source /home/agent-admin/agent-app.env
> EOF
```

![.profile source](screenshots/env-02.png)

```bash
# 키 파일
root@codyssey05:/app# echo 'agent_api_key_test' > /home/agent-admin/agent-app/api_keys/t_secret.key
root@codyssey05:/app# chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/t_secret.key
root@codyssey05:/app# chmod 640                    /home/agent-admin/agent-app/api_keys/t_secret.key

root@codyssey05:/app# cat /home/agent-admin/agent-app/api_keys/t_secret.key
agent_api_key_test
```

![키 파일](screenshots/env-03.png)

#### 5개 환경 변수 검증 (agent-admin 빙의)

```bash
root@codyssey05:/app# su - agent-admin
agent-admin@codyssey05:~$ env | grep AGENT_ | sort
AGENT_HOME=/home/agent-admin/agent-app
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
```

### 5-3. ✅ Boot Sequence 5/5 [OK] + "Agent READY"

```bash
agent-admin@codyssey05:~$ /app/agent-app
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
 ... Running as service user 'agent-admin' (uid=1001)
[2/5] Verifying Environment Variables     [OK]
 ... All required Envs correct
[3/5] Checking Required Files             [OK]
 ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
 ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
 ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-05-15 12:18:36,793 [INFO] [SafetyGuard] Process priority lowered (nice=10).
2026-05-15 12:18:36,795 [INFO] Agent listening at port 15034
2026-05-15 12:18:36,795 [INFO] === Agent Started. Beginning resource cycle. ===
```

![Boot Sequence 5/5](screenshots/boot-01.png)

> **Boot Sequence 의 본질** — 5/5 [OK] 가 나왔다는 것은 §3 (사용자 생성), §4 (디렉터리 권한), §5 의 envfile / 키 파일 / 포트 가용성이 *동시에* 정상임을 앱 스스로 자가진단해 입증한 것. 한 출력으로 다수 항목이 함께 검증됨.

### 5-4. 포트 LISTEN + 일반 계정 실행 확인

```bash
# 컨테이너 안 — 다른 세션에서
root@codyssey05:/# ss -tlnp | grep 15034
LISTEN 0  1  0.0.0.0:15034  0.0.0.0:*  users:(("agent-app",pid=59,fd=...))

# 호스트(macOS) 에서 포트 도달 확인
sangwoo@sangwoo-MacBookAir % (echo > /dev/tcp/localhost/15034) && echo OPEN
OPEN
```

![포트 LISTEN](screenshots/boot-02.png)

#### 일반 계정 실행 확인 — root 가 아님

```bash
root@codyssey05:/# ps -ef | grep -v grep | grep agent-app
agent-a+  2072  2070  0 12:18 ?  00:00:00 /run/rosetta/rosetta /app/agent-app /app/agent-app
agent-a+  2073  2072 13 12:18 ?  00:00:01 /run/rosetta/rosetta /app/agent-app /app/agent-app
```

→ UID 컬럼이 `agent-a+` (= agent-admin 의 8글자 축약 표기), `root` 아님 ✅. Apple Silicon 환경이라 `/run/rosetta/rosetta` 가 amd64 ELF syscall 번역기로 앞에 붙음.

---

## §6. monitor.sh 실행 결과

### 6-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 6.1 | 파일 경로 = `$AGENT_HOME/bin/monitor.sh` | `ls -l …/bin/monitor.sh` | [x] |
| 6.2 | 소유자 = `agent-dev` | `stat -c '%U' …/monitor.sh` | [x] |
| 6.3 | 그룹 = `agent-core` | `stat -c '%G' …/monitor.sh` | [x] |
| 6.4 | 권한 = `750` | `stat -c '%a' …/monitor.sh` | [x] |
| 6.5 | cron 실행자 `agent-admin` 이 `agent-core` 멤버 (실행 가능) | `id agent-admin \| grep agent-core` | [x] |
| 6.6 | 프로세스(`agent-app`) Health Check [OK] | monitor.sh 출력 | [x] |
| 6.7 | 포트 15034 Health Check [OK] | monitor.sh 출력 | [x] |
| 6.8 | CPU 사용률 수집 | 출력 `CPU Usage` | [x] |
| 6.9 | MEM 사용률 수집 | 출력 `MEM Usage` | [x] |
| 6.10 | DISK 사용률 (Root partition) 수집 | 출력 `DISK Used` | [x] |
| 6.11 | 임계값 초과 시 `[WARNING]` (CPU>20 / MEM>10 / DISK>80) | 출력 `[WARNING] …` | [x] |
| 6.12 | UFW 비활성 시 `[WARNING]` 만 출력 (스크립트는 종료 X) | `ufw disable` 후 monitor.sh → exit 0 | [x] |
| 6.13 | 프로세스/포트 비정상 시 `exit 1` | 앱 죽인 뒤 monitor.sh; `echo $?` → 1 | [x] |

### 6-2. monitor.sh 배치 + 권한

```bash
# bin 디렉터리 + 파일 배치 (agent-dev:agent-core, 750)
root@codyssey05:/app# mkdir -p /home/agent-admin/agent-app/bin
root@codyssey05:/app# chown agent-dev:agent-core /home/agent-admin/agent-app/bin
root@codyssey05:/app# chmod 2750                  /home/agent-admin/agent-app/bin

root@codyssey05:/app# cp /app/monitor.sh /home/agent-admin/agent-app/bin/monitor.sh
root@codyssey05:/app# chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
root@codyssey05:/app# chmod 750                   /home/agent-admin/agent-app/bin/monitor.sh

root@codyssey05:/app# ls -la /home/agent-admin/agent-app/bin/
total 16
drwxr-s---  2 agent-dev   agent-core   4096 May 18 15:43 .
drwxr-s---  5 agent-admin agent-common 4096 May 18 15:43 ..
-rwxr-x---  1 agent-dev   agent-core   5570 May 18 15:43 monitor.sh

root@codyssey05:/app# stat -c '%U %G %a' /home/agent-admin/agent-app/bin/monitor.sh
agent-dev agent-core 750
```

![monitor.sh 배치](screenshots/monitor-01.png)

#### 실행자 자격 검증 — agent-admin OK / agent-test 차단

```bash
root@codyssey05:/app# sudo -u agent-admin bash -c '[[ -x /home/agent-admin/agent-app/bin/monitor.sh ]] && echo OK || echo FAIL'
OK
root@codyssey05:/app# sudo -u agent-test  bash -c '[[ -x /home/agent-admin/agent-app/bin/monitor.sh ]] && echo OK || echo BLOCKED'
BLOCKED
```

![실행 자격](screenshots/monitor-02.png)

→ `agent-admin` 은 `agent-core` 멤버이므로 `750` 의 group 비트로 실행 가능. `agent-test` 는 group 비탈락 + others 차단으로 BLOCKED.

### 6-3. ✅ 자원 수집 + 임계값 경고 — 정상 실행

```bash
root@codyssey05:/app# sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 59)
Checking port 15034... [OK]

[RESOURCE MONITORING]
CPU Usage : 10.7%
MEM Usage : 13.2%
DISK Used : 4%

[WARNING] MEM threshold exceeded (13.2% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log

root@codyssey05:/app# echo $?
0
```

→ 미션의 모든 동작이 한 출력에 담김:
- **Health Check** 프로세스 [OK], 포트 [OK]
- **자원 수집** CPU / MEM / DISK 3종 모두 수집
- **임계값 경고** MEM (13.2 > 10) 만 정확히 [WARNING], CPU/DISK 는 임계값 미만이라 경고 없음
- **로그 누적** `[INFO] Log appended` 로 §7 의 monitor.log 기록 트리거

### 6-4. CPU/MEM/DISK 자원 수집 — awk 파싱 라인 점검

#### CPU — `top -bn1` 의 `%Cpu(s)` 라인에서 idle 추출

```bash
root@codyssey05:/app# top -bn1 | grep -i "cpu(s)"
%Cpu(s):  0.9 us,  0.9 sy,  3.5 ni, 94.7 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st

root@codyssey05:/app# top -bn1 | awk -F'[ ,]+' '
>   /Cpu\(s\)/ {
>     for (i=1; i<=NF; i++)
>       if ($i == "id") { printf "%.1f", 100 - $(i-1); exit }
>   }'
10.7
```

![CPU 파싱](screenshots/monitor-03.png)

#### MEM — `free -m`

```bash
root@codyssey05:/app# free -m
               total        used        free      shared  buff/cache   available
Mem:            7836        1041        4912           0        2080        6794
Swap:           1023           0        1023

root@codyssey05:/app# free -m | awk '/^Mem:/ { printf "%.1f", $3/$2*100 }'
13.2
```

#### DISK — `df -P /` 5번째 컬럼

```bash
root@codyssey05:/app# df -P /
Filesystem     1024-blocks     Used Available Capacity Mounted on
overlay          474044488 14761280 435129560       4% /

root@codyssey05:/app# df -P / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }'
4
```

### 6-5. ✅ Health Check 실패 시 `exit 1`

```bash
# (1) agent-app 강제 종료
root@codyssey05:/app# pkill -f '/app/agent-app$'

# (2) monitor.sh 재실행 → 프로세스 검사에서 즉시 종료
root@codyssey05:/app# sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [FAIL]

root@codyssey05:/app# echo $?
1
```

→ 미션 §4.4 *"비정상 시 exit 1"* 요구 충족. 포트 단독 다운도 같은 흐름 (`exit 1`).

### 6-6. ✅ UFW 비활성 시 [WARNING] 만 (스크립트 종료 X)

```bash
root@codyssey05:/app# ufw disable
Firewall stopped and disabled on system startup

root@codyssey05:/app# sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 59)
Checking port 15034... [OK]

[WARNING] Firewall is INACTIVE — please re-enable UFW.

[RESOURCE MONITORING]
CPU Usage : 9.4%
MEM Usage : 12.8%
DISK Used : 4%

[WARNING] MEM threshold exceeded (12.8% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log

root@codyssey05:/app# echo $?
0

# 복구
root@codyssey05:/app# ufw --force enable
Firewall is active and enabled on system startup
```

→ `[WARNING]` 만 출력, 스크립트는 **정상 종료** (`exit 0`). 미션 §4.4 *"방화벽 비활성 시 [WARNING] 출력하되 스크립트는 종료하지 않는다"* 요구 충족.

---

## §7. /var/log/agent-app/monitor.log 누적 기록

### 7-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 7.1 | 로그 파일 경로 = `/var/log/agent-app/monitor.log` | `ls -la /var/log/agent-app/monitor.log` | [x] |
| 7.2 | monitor.sh 1회 실행 후 1라인 추가됨 | `tail -1 …/monitor.log` | [x] |
| 7.3 | 포맷 일치: `[YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%` | (위 라인) | [x] |
| 7.4 | 누적 라인이 시간순으로 쌓임 (최근 3~5 라인) | `tail -5 …/monitor.log` | [x] |

### 7-2. 로그 파일 위치 + 권한

```bash
root@codyssey05:/var/log/agent-app# ls -al
total 696
drwxrwx---+ 2 agent-admin agent-core    4096 May 22 03:33 .
drwxr-xr-x  1 root        root          4096 May 22 02:08 ..
-rw-rw----+ 1 agent-admin agent-admin 691441 May 22 03:33 agent_app.log
-rw-rw----+ 1 agent-admin agent-admin     62 May 22 03:33 monitor.log
```

→ 디렉터리는 `agent-admin:agent-core` 의 770 + ACL (§4 결과). 로그 파일들은 생성자 (agent-admin) 의 primary group 으로 박힘 — ACL `+` 가 있어 *접근 정책* 은 `agent-core` 멤버 모두 R/W 보장.

### 7-3. ✅ 최근 라인 — 미션 포맷 정확 일치

```bash
root@codyssey05:/app# tail -5 /var/log/agent-app/monitor.log
[2026-05-18 15:44:10] PID:0   CPU:0.0%  MEM:0.0%   DISK_USED:0%
[2026-05-19 20:33:34] PID:51  CPU:0.9%  MEM:11.5%  DISK_USED:4%
[2026-05-19 20:34:55] PID:59  CPU:10.7% MEM:13.2%  DISK_USED:4%
[2026-05-22 03:33:01] PID:182 CPU:0.9%  MEM:18.0%  DISK_USED:4%
[2026-05-22 03:34:02] PID:182 CPU:1.8%  MEM:18.2%  DISK_USED:4%
```

→ 미션 명시 포맷 `[YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%` 정확 일치.

### 7-4. 그룹 협업 — agent-dev 가 monitor.log 를 읽을 수 있어야

```bash
root@codyssey05:/var/log# su - agent-dev -c 'cat /var/log/agent-app/monitor.log | tail -5'
[2026-05-22 03:33:01] PID:182 CPU:0.9% MEM:18.0% DISK_USED:4%
[2026-05-22 03:34:02] PID:182 CPU:1.8% MEM:18.2% DISK_USED:4%
[2026-05-22 03:35:02] PID:182 CPU:0.9% MEM:18.0% DISK_USED:4%
[2026-05-22 03:36:02] PID:182 CPU:9.2% MEM:17.9% DISK_USED:4%
[2026-05-22 03:37:02] PID:182 CPU:1.4% MEM:17.7% DISK_USED:4%

# agent-test 는 차단되어야 (agent-core 비멤버)
root@codyssey05:/var/log# su - agent-test -c 'cat /var/log/agent-app/monitor.log'
cat: /var/log/agent-app/monitor.log: Permission denied
```

→ default ACL 의 `g:agent-core:rwx` 가 새로 생성된 monitor.log 에도 자동 상속 → `agent-dev` 가 R 가능, `agent-test` 는 차단. **§4 의 ACL 정책이 §7 의 로그 파일에서 실효성 입증**.

![누적 + 협업 입증](screenshots/monitor-06.png)

---

## §8. crontab 매분 실행 등록 + 자동 실행 확인

### 8-1. 세부 체크리스트

| # | 검증 항목 | 검증 명령 | 상태 |
|---|----------|-----------|:----:|
| 8.1 | cron 데몬 동작 중 | `service cron status` | [x] |
| 8.2 | `agent-admin` 의 crontab 에 monitor.sh 등록 | `crontab -u agent-admin -l` | [x] |
| 8.3 | 주기 = 매분 (`* * * * *`) | (위 출력) | [x] |
| 8.4 | 등록 후 1~2 분 내 monitor.log 새 라인 자동 누적 | `tail -3 …/monitor.log` (1분 간격) | [x] |

### 8-2. cron 데몬 기동 + crontab 등록

```bash
root@codyssey05:/app# service cron start
 * Starting periodic command scheduler cron                                [ OK ]

root@codyssey05:/app# service cron status
 * cron is running
```

```bash
root@codyssey05:/app# crontab -u agent-admin -e
# vim 안에서 한 줄 입력:
* * * * * /home/agent-admin/agent-app/bin/monitor.sh
# :wq 저장
crontab: installing new crontab

root@codyssey05:/app# crontab -u agent-admin -l
* * * * * /home/agent-admin/agent-app/bin/monitor.sh
```

![crontab 등록](screenshots/monitor-04.png)

#### cron 라인 해부

```
* * * * *  /home/agent-admin/agent-app/bin/monitor.sh
│ │ │ │ │
│ │ │ │ └─ 요일 (0-7, 일=0 또는 7)
│ │ │ └─── 월 (1-12)
│ │ └───── 일 (1-31)
│ └─────── 시 (0-23)
└───────── 분 (0-59)
```

→ `* * * * *` = **매분 실행** (미션 §4.5 요구 일치).

### 8-3. ✅ 1~2분 후 monitor.log 자동 누적 확인

```bash
# (1) 현재 시각 확인 + 마지막 라인 캡처
root@codyssey05:/app# date '+%Y-%m-%d %H:%M:%S'
2026-05-22 03:33:30

root@codyssey05:/app# tail -1 /var/log/agent-app/monitor.log
[2026-05-22 03:33:01] PID:182 CPU:0.9% MEM:18.0% DISK_USED:4%

# (2) ~70초 대기 후 재확인
root@codyssey05:/app# sleep 70 && tail -3 /var/log/agent-app/monitor.log
[2026-05-22 03:33:01] PID:182 CPU:0.9% MEM:18.0% DISK_USED:4%
[2026-05-22 03:34:02] PID:182 CPU:1.8% MEM:18.2% DISK_USED:4%       ← 매분 정각에 자동 추가됨
```

→ `03:33:01` → `03:34:02` 로 **정확히 매분 정각** 에 새 라인 자동 누적 ✅.

#### 더 긴 누적 (12분치 = 12라인) — cron 의 지속성 입증

```bash
root@codyssey05:/var/log# su - agent-dev -c 'cat /var/log/agent-app/monitor.log'
[2026-05-22 03:33:01] PID:182 CPU:0.9% MEM:18.0% DISK_USED:4%
[2026-05-22 03:34:02] PID:182 CPU:1.8% MEM:18.2% DISK_USED:4%
[2026-05-22 03:35:02] PID:182 CPU:0.9% MEM:18.0% DISK_USED:4%
[2026-05-22 03:36:02] PID:182 CPU:9.2% MEM:17.9% DISK_USED:4%
[2026-05-22 03:37:02] PID:182 CPU:1.4% MEM:17.7% DISK_USED:4%
[2026-05-22 03:38:02] PID:182 CPU:1.0% MEM:17.8% DISK_USED:4%
[2026-05-22 03:39:02] PID:182 CPU:1.2% MEM:17.6% DISK_USED:4%
[2026-05-22 03:40:02] PID:182 CPU:1.1% MEM:17.7% DISK_USED:4%
[2026-05-22 03:41:02] PID:182 CPU:8.5% MEM:17.9% DISK_USED:4%
[2026-05-22 03:42:02] PID:182 CPU:1.3% MEM:17.8% DISK_USED:4%
[2026-05-22 03:43:02] PID:182 CPU:1.0% MEM:17.6% DISK_USED:4%
[2026-05-22 03:44:02] PID:182 CPU:1.2% MEM:17.5% DISK_USED:4%
```

![cron 누적](screenshots/monitor-05.png)

> **이 한 출력으로 동시 입증되는 항목**
> 1. **§8** — cron 매분 누적 (12분치 = 12 라인)
> 2. **§4** — ACL 의 그룹 협업 (agent-dev 가 읽기 가능)
> 3. **§7** — monitor.log 포맷·경로·내용 일관성

---

# 부록 A. 미션 §3 학습 목표 6건 — 본 README 안의 설명 위치

| # | 학습 목표 | 설명 위치 |
|---|----------|-----------|
| 1 | SSH 포트 변경 + Root 차단의 보안 의미 | [§1-2 호스트 시뮬](#1-2-검증-실행-결과) (Root 차단 정책 동작) |
| 2 | UFW "필요 포트만 허용" 정책 구성·검증 | [§2 전체](#2-ufw-방화벽-활성화--2002215034만-허용) (default deny + 화이트리스트) |
| 3 | 역할 기반 계정/그룹 + ACL 로 공유/보안 디렉토리 분리 | [§3](#3-계정그룹-생성-확인) + [§4](#4-디렉토리-구조--권한acl-포함) (빙의 매트릭스가 입증) |
| 4 | `AGENT_HOME` 등 환경 변수로 실행 환경 고정 | [§5-2](#5-2-환경-변수--키-파일) (envfile + `.profile` source) |
| 5 | 쉘 스크립트로 프로세스/포트/리소스 수집 + 로그 추적 | [§6](#6-monitorsh-실행-결과) (정상/실패/경고 3가지 시나리오) |
| 6 | crontab 주기 실행 + 로그 보존 필요성 | [§8](#8-crontab-매분-실행-등록--자동-실행-확인) (1분 단위 자동 누적) |

---

# 부록 B. 디렉터리 구조

```
05-linux-monitor-automation/
├── README.md                           ← 본 파일 (수행 내역서)
├── JOURNAL.md                          ← 학습 일지 (트러블슈팅 / 자연 발견 / 의사결정)
├── Dockerfile                          ← Ubuntu 24.04 + 패키지
├── run.sh                              ← 컨테이너 생명주기 명령
├── setup-mission.sh                    ← 1~4단계 환경 자동 구성
├── monitor.sh                          ← 미션 핵심 (§4.4)
└── screenshots/                        ← 본 README 의 캡처 자산
```

#### 컨테이너 안 배치 (setup-mission.sh 가 구성)

```
/home/agent-admin/
├── agent-app.env                       ← 환경 변수 5개 (envfile)
├── .profile                            ← envfile auto load
└── agent-app/                          ← $AGENT_HOME (agent-admin:agent-common, 2750)
    ├── upload_files/                   ← agent-common R/W (2770 + ACL)
    ├── api_keys/                       ← agent-core ONLY (2770 + ACL)
    │   └── t_secret.key                ← 키 파일 (640)
    └── bin/                            ← agent-dev:agent-core, 2750
        └── monitor.sh                  ← 미션 핵심

/var/log/agent-app/                     ← agent-core ONLY (2770 + ACL)
└── monitor.log                         ← cron 매분 누적

/etc/sudoers.d/
└── agent-admin-monitor                 ← fine-grained sudo (ufw status only, NOPASSWD)
```
