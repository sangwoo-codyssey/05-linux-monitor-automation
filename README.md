# 미션 5 — 리눅스 시스템 관제 자동화

다중 사용자 환경의 **권한 관리 + 네트워크 보안 + 시스템 리소스 관제 + 로그 관리 자동화** 를 실제 운영 엔지니어처럼 직접 설계·구축·검증한 저장소입니다.

> 📓 **상세 학습 일지** (트러블슈팅 / 자연 발견 / 함정 모음 / 의사결정 흔적 / 캡처) → [`JOURNAL.md`](./JOURNAL.md) 참조

---

## ⚡ Quick Start (3분 재현)

```bash
git clone https://github.com/sangwoo-codyssey/05-linux-monitor-automation.git
cd 05-linux-monitor-automation

./run.sh build && ./run.sh up                                    # Docker 빌드 + 기동
docker exec codyssey05 bash /app/setup-mission.sh                # 1~6단계 환경 자동 구성
docker exec -d codyssey05 su - agent-admin -c /app/agent-app     # agent-app 백그라운드 기동
docker exec codyssey05 sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
docker exec codyssey05 sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh   # 보너스 1
```

---

## 1. 실행 환경

| 항목 | 버전 |
|------|------|
| Host OS | macOS 26.3.1 (Apple Silicon, arm64) |
| Container OS | Ubuntu 24.04 LTS (linux/amd64, GLIBC 2.39) |
| Docker | 29.3.0 |
| 핵심 패키지 | `openssh-server`, `ufw`, `cron`, `sudo`, `acl`, `iproute2`, `procps`, `logrotate`, `vim`, `less`, `man-db` |

---

## 2. 산출물 일람

### 필수 산출물 (미션 §2)

| 산출물 | 파일 | 역할 |
|--------|------|------|
| 요구사항 수행 내역서 | `JOURNAL.md` | 미션 §3·§4·§5 전체 흐름 + 트러블슈팅 |
| 자동화 스크립트 | `monitor.sh` | Health Check + 자원 수집 + 임계값 경고 + 로그 누적 |

### 보너스 산출물 (미션 §5)

| 산출물 | 파일 | 역할 |
|--------|------|------|
| 통계 리포트 (보너스 1) | `report.sh` | CPU/MEM/DISK 평균·최대·최소·샘플 수 + 시간 구간 필터 |
| 7일 압축 (보너스 2) | `archive-compress.sh` | `find -mtime +7 -exec gzip` 멱등 패턴 |
| 회전·아카이브 정책 | `agent-app-monitor.logrotate` | logrotate config (회전 + olddir + maxage) |

### 환경 구성

| 파일 | 역할 |
|------|------|
| `Dockerfile` | Ubuntu 24.04 + 패키지 통합 + 24.04 minimal 함정 2단 해제 |
| `run.sh` | 컨테이너 생명주기 명령 (`build / up / start / stop / shell / down`) |
| `setup-mission.sh` | 1~6단계 환경 자동 구성 (SSH/UFW/계정/env/logrotate/cron) |

---

## 3. 미션 요구사항 충족 매트릭스

### 3.1 §2 필수 증거 자료 체크리스트 (8건)

| # | 미션 요구 | 충족 | JOURNAL 위치 |
|---|----------|:----:|--------------|
| 1 | SSH 포트 변경(20022) + Root 원격 차단 | ✅ | §5 |
| 2 | UFW 활성화 + 20022/tcp, 15034/tcp 만 허용 | ✅ | §6 |
| 3 | 계정/그룹 (agent-admin/dev/test, agent-common/core) | ✅ | §7-1, §7-2 |
| 4 | 디렉토리 구조 + 권한 (ACL 포함) | ✅ | §7-3 ~ §7-7 |
| 5 | Boot Sequence 5단계 [OK] + "Agent READY" | ✅ | §9-6 |
| 6 | `monitor.sh` 실행 결과 (프로세스/포트/리소스/경고) | ✅ | §10-6 |
| 7 | `/var/log/agent-app/monitor.log` 누적 | ✅ | §10-7, §11-3 |
| 8 | crontab 매분 실행 + 자동 누적 확인 | ✅ | §11-2, §11-3 |

### 3.2 §3 학습 목표 6건 — *스스로 설명 가능* 한지

| # | 학습 목표 | 설명 위치 |
|---|----------|-----------|
| 1 | SSH 포트 변경 + Root 차단의 보안 의미 | JOURNAL §5-2-a, §5-7 |
| 2 | UFW "필요 포트만 허용" 정책 구성·검증 | JOURNAL §6-1, §6-2 |
| 3 | 역할 기반 계정/그룹 + ACL 로 공유/보안 디렉토리 분리 | JOURNAL §7-3-1 (메커니즘 비교) |
| 4 | `AGENT_HOME` 등 환경 변수로 실행 환경 고정 | JOURNAL §8-1 (위치별 비교) |
| 5 | 쉘 스크립트로 프로세스/포트/리소스 수집 + 로그 추적 | JOURNAL §10 전체 |
| 6 | crontab 주기 실행 + 로그 보존 정책의 필요성 | JOURNAL §11, §12, §13 |

### 3.3 §4 기능 요구사항 (4.1 ~ 4.5)

| § | 요구사항 | 충족 |
|---|---------|:----:|
| 4.1 | SSH (포트 20022 + Root 차단) + UFW (20022/15034 화이트리스트) | ✅ |
| 4.2 | 계정·그룹·디렉토리·ACL 정책 (`upload_files=common`, `api_keys`+`/var/log/agent-app`=core ONLY) | ✅ |
| 4.3 | 환경 변수 5개 + 키 파일 (`t_secret.key`) + Boot Sequence 5/5 [OK] | ✅ |
| 4.4 | `monitor.sh` — Health Check / 상태 점검 / 자원 수집 / 임계값 경고 / 로그 누적 + **로그 회전 (10MB / 10개)** | ✅ |
| 4.5 | crontab 매분 자동 실행 + 1~2분 내 로그 누적 확인 | ✅ |

### 3.4 §5 보너스 1·2 (선택 과제 모두 충족)

| 보너스 | 충족 | 구현 위치 |
|--------|:----:|----------|
| **1** report.sh — 통계 리포트 (평균/최대/최소/샘플 수) | ✅ | `report.sh` (awk 한 줄 파싱) |
| 1+ (선택) 시작/종료 시간 입력 구간 분석 | ✅ | `report.sh "$FROM" "$TO"` |
| **2** 7일 경과 로그 압축 | ✅ | `archive-compress.sh` (find -mtime +7) |
| 2 아카이브 이동 (`/var/log/monitor/agent-app/archive/`) | ✅ | logrotate `olddir` + `createolddir` |
| 2 30일 경과 아카이브 삭제 | ✅ | logrotate `maxage 30` |
| 2 예외 처리 (디렉토리 미존재 / 권한 부족 / 대상 0개) | ✅ | archive-compress.sh 의 3단 가드 + logrotate `missingok`/`notifempty` |

> **설계 의사결정 흔적** — 패턴 A (logrotate 단일 통합 + delaycompress 흉내) 시도 후 *"7일 정확 표현 불가"* 한계 인지 → 패턴 B (logrotate 회전·이동·삭제 + archive-compress.sh 7일 압축) 로 전환. logrotate = *시점 도구*, archive-compress.sh = *상태 기반 도구* 의 자연스러운 분리. 자세한 흐름은 [JOURNAL §12-1, §12-3, §13-1](./JOURNAL.md#12).

---

## 4. 디렉터리 구조

```
05-linux-monitor-automation/
├── README.md                         ← 본 파일 (평가용 요약)
├── JOURNAL.md                        ← 상세 학습 일지
├── Dockerfile                        ← Ubuntu 24.04 + 패키지 + minimal 함정 해제
├── run.sh                            ← 컨테이너 생명주기
├── setup-mission.sh                  ← 1~6단계 환경 자동 구성
├── monitor.sh                        ← 미션 핵심 (§4.4)
├── report.sh                         ← 보너스 1
├── archive-compress.sh               ← 보너스 2 (7일 압축)
├── agent-app-monitor.logrotate       ← 보너스 2 (회전·아카이브·삭제)
└── screenshots/                      ← 학습 일지의 캡처 자산 (39 컷)
```

### 컨테이너 안 배치 (setup-mission.sh 가 구성)

```
/home/agent-admin/
├── agent-app.env                     ← 환경 변수 5개 (envfile)
├── .profile                          ← envfile auto load
└── agent-app/                        ← $AGENT_HOME (agent-admin:agent-common, 750)
    ├── upload_files/                 ← agent-common R/W (770 + ACL)
    ├── api_keys/                     ← agent-core ONLY (770 + ACL)
    │   └── t_secret.key              ← 키 파일 (640)
    └── bin/                          ← agent-dev:agent-core, 750
        ├── monitor.sh                ← 미션 핵심
        ├── report.sh                 ← 보너스 1
        └── archive-compress.sh       ← 보너스 2

/var/log/agent-app/                   ← agent-core ONLY (770 + ACL)
└── monitor.log                       ← cron 매분 누적, logrotate 회전 대상

/var/log/monitor/agent-app/archive/   ← 회전본 보관 (logrotate olddir)
```

---

## 5. 평가자 검증 흐름 — 5분 안에 모든 것을 확인하는 길

```bash
# (1) 환경 빌드 + 기동
./run.sh build && ./run.sh up
docker exec codyssey05 bash /app/setup-mission.sh

# (2) §2 체크리스트 1~4 — SSH/UFW/계정/디렉토리
docker exec codyssey05 ss -tlnp | grep -E '20022|15034'
docker exec codyssey05 ufw status verbose
docker exec codyssey05 bash /app/setup-mission.sh verify

# (3) §2 체크리스트 5 — agent-app Boot Sequence
docker exec -it codyssey05 su - agent-admin -c /app/agent-app
# (백그라운드로 띄우려면 -d 모드 + 별도 셸)

# (4) §2 체크리스트 6 — monitor.sh 실행 결과
docker exec codyssey05 sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh

# (5) §2 체크리스트 7 — monitor.log 누적
docker exec codyssey05 tail -5 /var/log/agent-app/monitor.log

# (6) §2 체크리스트 8 — cron 자동 누적 (1~2 분 대기 후)
docker exec codyssey05 crontab -u agent-admin -l
sleep 70
docker exec codyssey05 tail -3 /var/log/agent-app/monitor.log

# (7) §4.4 로그 회전 — 10MB 자연 트리거
docker exec codyssey05 bash -c '
  dd if=/dev/zero bs=1M count=11 2>/dev/null | tr "\0" "x" >> /var/log/agent-app/monitor.log
  logrotate /etc/logrotate.d/agent-app-monitor
  ls -la /var/log/monitor/agent-app/archive/
'

# (8) 보너스 1 — report.sh
docker exec codyssey05 sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh

# (9) 보너스 2 — archive-compress.sh (7일 경계)
docker exec codyssey05 bash -c '
  touch -d "10 days ago" /var/log/monitor/agent-app/archive/old.log
  chown agent-admin:agent-core /var/log/monitor/agent-app/archive/old.log
  sudo -u agent-admin /home/agent-admin/agent-app/bin/archive-compress.sh
  ls /var/log/monitor/agent-app/archive/
'
```

---

## 6. 코딧세이 미션 시리즈 흐름

| 미션 | 디렉터리 | 주제 |
|------|---------|------|
| 1 | `01-infra-basics-study` | Nginx + Docker 기초 |
| 2 | `02-git-python-first-steps` | Git 브랜치 전략 + Python 퀴즈 |
| 3 | `03-mini-npu-simulator` | MAC 연산 기반 Mini NPU |
| 5 | **`05-linux-monitor-automation`** | **본 미션 — 리눅스 시스템 관제 자동화** |
