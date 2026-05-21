# 미션 5: 리눅스 시스템 관제 자동화 학습 환경
# - Ubuntu 24.04 LTS (amd64 강제: 제공된 agent-app이 x86-64 ELF 바이너리)
#   * 22.04(GLIBC 2.35)에선 agent-app(GLIBC 2.38 요구) 실행 불가 → 24.04(GLIBC 2.39)
# - Phase 1~4에서 학습한 필수 패키지를 통합
#   * openssh-server: SSH 데몬 (Phase 1)
#   * ufw           : 방화벽 (Phase 2)
#   * acl           : setfacl/getfacl (Phase 3)
#   * vim           : 텍스트 편집 (편의)
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Seoul \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y \
        openssh-server \
        ufw \
        acl \
        vim \
    && ln -sf /usr/share/zoneinfo/$TZ /etc/localtime \
    && rm -rf /var/lib/apt/lists/*

# sshd Privilege Separation 디렉터리 — Phase 1 트러블슈팅의 영구 해결
RUN mkdir -p /var/run/sshd

WORKDIR /app
CMD ["/bin/bash"]
