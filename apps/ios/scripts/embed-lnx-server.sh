#!/bin/sh
# Mac 版 lnx creare に lnx-server を同梱する（project.yml の postBuildScripts から。iOS では何もしない）。
#
#   Contents/MacOS/lnx-server                                     … repo の cargo build の成果物を写して署名
#   Contents/Library/LaunchAgents/tech.anycreative.lnx-server.plist … SMAppService.agent(plistName:) が登録する
#
# Debug は dev profile、Release は --release。cargo は Xcode の env を剥がして呼ぶ
# （MACOSX_DEPLOYMENT_TARGET などが端末の cargo build と違うと、rustc が全 crate を作り直す）
# PATH は rustup の cargo と、club-unison の build が呼ぶ protoc（brew）が見つかるだけにする
set -eu

[ "${PLATFORM_NAME:-}" = "macosx" ] || exit 0

ROOT="$(cd "${PROJECT_DIR}/../.." && pwd)"
case "${CONFIGURATION}" in
    Release) PROFILE=release; FLAG=--release ;;
    *) PROFILE=debug; FLAG= ;;
esac

echo "lnx-server を build（${PROFILE}）"
# shellcheck disable=SC2086 # FLAG は空か 1 語
env -i HOME="${HOME}" USER="${USER:-}" TMPDIR="${TMPDIR:-/tmp}" PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    cargo build -q -p lnx-server ${FLAG} --manifest-path "${ROOT}/Cargo.toml"
SOURCE="${ROOT}/target/${PROFILE}/lnx-server"
[ -x "${SOURCE}" ] || { echo "error: ${SOURCE} が無い（cargo build の成果物）" >&2; exit 1; }

CONTENTS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
DEST="${CONTENTS}/MacOS/lnx-server"
AGENTS="${CONTENTS}/Library/LaunchAgents"
mkdir -p "${CONTENTS}/MacOS" "${AGENTS}"
# 走っている常駐の実行ファイルを壊さないよう、隣に写してから rename で差し替える
cp "${SOURCE}" "${DEST}.new"
mv -f "${DEST}.new" "${DEST}"
cp "${PROJECT_DIR}/LaunchAgents/tech.anycreative.lnx-server.plist" "${AGENTS}/"
plutil -lint -s "${AGENTS}/tech.anycreative.lnx-server.plist"

# 入れ子の実行ファイルは .app より先に署名する（.app の署名は中身が署名済みであることを求める）。
# identity が無い（署名しないビルド）なら ad-hoc
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime \
    --identifier tech.anycreative.lnx-server "${DEST}"
echo "同梱: ${DEST}"
