# noraneko-ci の build コンテナ。bsys6 prepare が apt で入れるものを先に焼いておく(prepare の 4〜5 分 → 数十秒)。
# (.woodpecker/ の下に置くと Woodpecker が pipeline 設定と思って転ぶ)
# 一覧は .github/bsys6/src/prepare.sh の linux と macos の和 + .woodpecker/build.yml の基本 + LLVM 20。
# prepare.sh の apt はそのまま走らせる(全部入っていれば no-op、ずれていれば足りない分だけ入る=安全網)。
#
# 焼いて置くのは noraneko-ci の bin/ci-image-build(箱の上で podman build → podman save → B2 の images/)。
# 箱は起きるときに B2 から podman load して localhost/noraneko-ci:ubuntu24 と名づける(cloud-init)。
# ~/.mozbuild と rust は volume(上流の sync で版が動くので焼かない)。
FROM docker.io/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ARG LLVM_VERSION=20

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      sudo git ca-certificates curl xz-utils wget gnupg2 lsb-release jq \
      python3-pip build-essential autoconf2.13 yasm \
      libgtk-3-dev libxtst6 libxrandr2 libasound2-dev libpango1.0-dev libatk1.0-dev \
      libcairo-gobject2 libgdk-pixbuf2.0-dev libdbus-glib-1-dev xvfb mesa-utils msitools \
      rsync zip unzip python3-testresources file nodejs ruby \
 && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/llvm.gpg \
 && echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-$LLVM_VERSION main" > /etc/apt/sources.list.d/llvm.list \
 && apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      llvm-$LLVM_VERSION clang-$LLVM_VERSION lld-$LLVM_VERSION libclang-$LLVM_VERSION-dev libclang-rt-$LLVM_VERSION-dev-wasm32 \
 && ln -sf /usr/bin/clang-$LLVM_VERSION /usr/bin/clang \
 && ln -sf /usr/bin/clang++-$LLVM_VERSION /usr/bin/clang++ \
 && ln -sf /usr/bin/lld-$LLVM_VERSION /usr/bin/lld \
 && ln -sf /usr/bin/llvm-profdata-$LLVM_VERSION /usr/bin/llvm-profdata \
 && rm -rf /var/lib/apt/lists/*

# sccache(mozconfig が /usr/local/bin/sccache を見る。build.yml も同じ版を置くので、揃えておく)
ARG SCCACHE_VERSION=0.10.0
RUN curl -fsSL "https://github.com/mozilla/sccache/releases/download/v$SCCACHE_VERSION/sccache-v$SCCACHE_VERSION-$(uname -m)-unknown-linux-musl.tar.gz" \
      | tar xz -C /tmp \
 && install -m 755 "/tmp/sccache-v$SCCACHE_VERSION-$(uname -m)-unknown-linux-musl/sccache" /usr/local/bin/sccache \
 && rm -rf /tmp/sccache-*
