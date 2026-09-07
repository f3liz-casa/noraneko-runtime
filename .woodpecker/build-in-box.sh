#!/usr/bin/env bash
# 箱の build コンテナの中で走る本体(.woodpecker/build.yml が checkout のあとに呼ぶ)。
# yml に置かず file にしてある理由: Woodpecker は step の script を `base64 -d | sh` で stdin から流し込む。
# 8 KiB を超えると sh が先に読み切れず、子(bsys6 の中の何か)が stdin の続きを食べて
# 「end of file unexpected (expecting fi)」で落ちる(#26)。file なら誰も食べない。
# 期待する env: WORK HOME BUILD_TARGET BUILD_ARCH CI_COMMIT_SHA と /etc/ci-box/sccache.env の中身(yml が export 済)。
set -e
cd "$(dirname "$0")/../.github/bsys6"

export UP=$SCCACHE_ENDPOINT S3="--aws-sigv4 aws:amz:$SCCACHE_REGION:s3 --user $AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" T=$BUILD_TARGET-$BUILD_ARCH

# apt の deb を捨てない(image の docker-clean が消す)。置き場は volume、種は B2 の cache/apt/<target>-<arch>.tar。
# prepare の apt(build-essential、gtk の dev、LLVM 20 …)は毎回数百 MB 落としていた。展開と設定は残る
APT_CACHE=$WORK/apt-cache
rm -f /etc/apt/apt.conf.d/docker-clean
mkdir -p "$APT_CACHE/archives/partial"
if [ -n "$SCCACHE_BUCKET" ] && ! ls "$APT_CACHE"/archives/*.deb >/dev/null 2>&1; then
  curl -sf $S3 "$UP/$SCCACHE_BUCKET/cache/apt/$T.tar" | tar -x -C "$APT_CACHE" || true
fi
rm -rf /var/cache/apt/archives && ln -s "$APT_CACHE/archives" /var/cache/apt/archives
apt_stamp() { ls "$APT_CACHE"/archives/*.deb 2>/dev/null | md5sum | cut -c1-32; }
APT_STAMP0=$(apt_stamp)
echo "apt-cache: $(ls "$APT_CACHE"/archives/*.deb 2>/dev/null | wc -l) 個の deb"

# 圧縮は多スレッドで(mach package の xz は外部 xz を呼ぶが -T は付けない。mac の package.sh は自前で -T0)
export XZ_OPT=-T0

export SCCACHE_LOG=sccache::compiler::compiler=debug SCCACHE_ERROR_LOG=/srv/ci/telemetry/sccache-$BUILD_TARGET-$BUILD_ARCH.log
rm -f "$SCCACHE_ERROR_LOG"
if [ -n "$SCCACHE_BUCKET" ]; then
  if curl -sf $S3 -o "$HOME/bin/sccache-proxy" "$SCCACHE_ENDPOINT/$SCCACHE_BUCKET/bin/sccache-proxy-linux-arm64"; then
    chmod 755 "$HOME/bin/sccache-proxy"
    curl -sf $S3 -o /tmp/prefetch.list "$SCCACHE_ENDPOINT/$SCCACHE_BUCKET/prefetch/$T.list" || : > /tmp/prefetch.list
    rm -f /srv/ci/telemetry/proxy-$T.jsonl
    "$HOME/bin/sccache-proxy" -store "$WORK/proxy-store" -log /srv/ci/telemetry/proxy-$T.jsonl \
      -record /srv/ci/telemetry/proxy-$T.list -prefetch /tmp/prefetch.list >/srv/ci/telemetry/proxy-$T.err 2>&1 &
    for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf -o /dev/null http://127.0.0.1:9800/healthz 2>/dev/null && break; sleep 1; done
    echo "sccache-proxy: 先読み $(wc -l < /tmp/prefetch.list) 鍵"
    export SCCACHE_ENDPOINT=http://127.0.0.1:9800
  fi
fi

sccache --start-server >/dev/null 2>&1 || true
/usr/local/bin/ci-record build_start target=$BUILD_TARGET arch=$BUILD_ARCH commit=$CI_COMMIT_SHA kind=woodpecker
rc=0
TARGET=$BUILD_TARGET ARCH=$BUILD_ARCH ./bsys6 prepare build package || rc=$?
/usr/local/bin/ci-record build_end target=$BUILD_TARGET arch=$BUILD_ARCH rc=$rc dur_s=$SECONDS kind=woodpecker
sccache --show-stats > /srv/ci/telemetry/sccache-$(date +%s)-$BUILD_TARGET-$BUILD_ARCH.txt 2>&1 || true
# 産物(bsys6 package が置く tar.xz)を B2 の artifacts/<commit 10 桁>/ に。release step は GH_TOKEN が無いと skip で、
# 箱は使い捨てなので、ここに置かないと消える
if [ "$rc" = 0 ] && [ -n "$SCCACHE_BUCKET" ]; then
  sha=$(echo "$CI_COMMIT_SHA" | cut -c1-10)
  for f in "$(pwd)"/noraneko-*.tar.xz; do
    [ -f "$f" ] || continue
    curl -sf $S3 -T "$f" "$UP/$SCCACHE_BUCKET/artifacts/$sha/$(basename "$f")" && echo "artifact: artifacts/$sha/$(basename "$f")" || true
  done
fi
# apt の deb が増えていたら B2 の種を差し替える(target で入れる物が違うので鍵は target 別)
if [ -n "$SCCACHE_BUCKET" ] && [ "$(apt_stamp)" != "$APT_STAMP0" ]; then
  tar -C "$APT_CACHE" -cf /tmp/apt-cache.tar archives
  curl -sf $S3 -T /tmp/apt-cache.tar "$UP/$SCCACHE_BUCKET/cache/apt/$T.tar" \
    && echo "apt-cache: B2 に置いた($(ls "$APT_CACHE"/archives/*.deb | wc -l) 個)" || true
fi
# 箱は使い捨てなので、ログは B2(sccache と同じ bucket)の logs/sccache/<target>/ に置く。読むのは noraneko-ci の bin/sccache-report
if [ -s "$SCCACHE_ERROR_LOG" ] && [ -n "$SCCACHE_BUCKET" ]; then
  key="logs/sccache/$BUILD_TARGET-$BUILD_ARCH/$(date -u +%Y%m%dT%H%M%SZ)-$(echo "$CI_COMMIT_SHA" | cut -c1-10)-rc$rc.log.xz"
  xz -T0 -c "$SCCACHE_ERROR_LOG" > /tmp/sccache-log.xz
  curl -sf $S3 -T /tmp/sccache-log.xz "$UP/$SCCACHE_BUCKET/$key" \
    && /usr/local/bin/ci-record sccache_log target=$BUILD_TARGET arch=$BUILD_ARCH key=$key || true
  # プロキシの記録(同じ名前で .access.jsonl.xz)と、次の先読みの列(通ったときだけ差し替える)
  if [ -s /srv/ci/telemetry/proxy-$T.jsonl ]; then
    xz -T0 -c /srv/ci/telemetry/proxy-$T.jsonl > /tmp/proxy-log.xz
    curl -sf $S3 -T /tmp/proxy-log.xz "$UP/$SCCACHE_BUCKET/${key%.log.xz}.access.jsonl.xz" || true
    # 次の先読みの列: 通っていて、しかも前の列の半分以上あるときだけ差し替える(増分ビルドの小さな記録で上書きしない。#28→#30 でやった)
    if [ "$rc" = 0 ] && [ -s /srv/ci/telemetry/proxy-$T.list ]; then
      new=$(wc -l < /srv/ci/telemetry/proxy-$T.list); old=$(wc -l < /tmp/prefetch.list)
      if [ $((new * 2)) -ge "$old" ]; then
        curl -sf $S3 -T /srv/ci/telemetry/proxy-$T.list "$UP/$SCCACHE_BUCKET/prefetch/$T.list" && echo "prefetch: 列を差し替えた($old → $new 鍵)" || true
      else
        echo "prefetch: 列は前のまま($old 鍵、今回の記録は $new 鍵)"
      fi
    fi
  fi
fi
exit $rc

