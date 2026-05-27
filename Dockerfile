# 미션 5: 리눅스 시스템 관제 자동화 학습 환경
# - Ubuntu 24.04 LTS (amd64 강제: 제공된 agent-app이 x86-64 ELF 바이너리)
#   * 22.04(GLIBC 2.35)에선 agent-app(GLIBC 2.38 요구) 실행 불가 → 24.04(GLIBC 2.39)
# - Phase 1~7에서 학습한 필수 패키지를 통합
#   * openssh-server: SSH 데몬 (Phase 1)
#   * ufw           : 방화벽 (Phase 2)
#   * acl           : setfacl/getfacl (Phase 3)
#   * iproute2      : ss (Phase 4 — agent-app 포트 리스닝 검증)
#                     ※ 24.04 minimal 에 기본 미포함 → 학습 중 발견된 함정
#   * sudo          : visudo / agent-admin 의 fine-grained sudo (Phase 4 + monitor.sh)
#                     ※ 24.04 minimal 에 기본 미포함 → 학습 중 발견된 함정
#   * cron          : 매분 monitor.sh 자동 실행 (Phase 6)
#                     ※ 24.04 minimal 에 기본 미포함 → 학습 중 발견된 함정
#   * procps        : top / free / pgrep / ps (monitor.sh 자원 수집·Health Check)
#                     ※ base 에 우연히 포함되나, 의존을 명시적으로 박아둠
#   * logrotate     : monitor.log 회전 + 시간 기반 보존 (Phase 7 — §4.4 필수 + §5 보너스 2)
#   * vim           : 텍스트 편집 (편의)
#   * less          : man 페이지 pager (man logrotate 등 매뉴얼 학습 시 필수)
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Seoul \
    LANG=C.UTF-8

# Ubuntu 24.04 minimal 함정 해제 — base 이미지가 /usr/share/man/* 를
# dpkg path-exclude 로 설치 시점에 차단하고 있어 `man logrotate` 가 빈 응답.
# excludes 파일을 apt install *이전* 에 제거하면 이후 설치되는 패키지의
# manpage 가 정상적으로 디스크에 기록됨. (학습 단계의 man 페이지 가독성 확보)
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes

RUN apt-get update && apt-get install -y \
        openssh-server \
        ufw \
        acl \
        iproute2 \
        sudo \
        cron \
        procps \
        logrotate \
        vim \
        less \
        man-db \
    && ln -sf /usr/share/zoneinfo/$TZ /etc/localtime \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 minimal 함정 해제 (2단) — base 이미지가 /usr/bin/man 을
# dpkg-divert 로 man.REAL 로 빼두고 그 자리에 안내 메시지만 출력하는
# 320 바이트 shell stub 을 박아둠. excludes 만 제거해서는 풀리지 않고,
# placeholder 를 먼저 지운 뒤 divert 를 --rename 으로 풀어야 진짜 man 복원.
RUN rm -f /usr/bin/man \
 && dpkg-divert --remove --rename /usr/bin/man

# sshd Privilege Separation 디렉터리 — Phase 1 트러블슈팅의 영구 해결
RUN mkdir -p /var/run/sshd

WORKDIR /app
CMD ["/bin/bash"]
