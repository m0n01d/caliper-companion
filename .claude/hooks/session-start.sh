#!/bin/bash
# SessionStart hook: on Claude Code on the web (Linux sandbox) install a Swift toolchain so
# `swift test` works for CaliperCore/CaliperFlow. No-op on the Mac, where Xcode provides Swift.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SWIFT_VERSION="6.3"
SWIFT_HOME="/opt/swift"
SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"

if [ ! -x "${SWIFT_HOME}/usr/bin/swift" ]; then
  echo "[session-start] installing Swift ${SWIFT_VERSION} to ${SWIFT_HOME}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev \
    libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata zlib1g-dev \
    > /dev/null
  tmp="$(mktemp -d)"
  curl -fsSL "${SWIFT_URL}" -o "${tmp}/swift.tar.gz"
  mkdir -p "${SWIFT_HOME}"
  tar -xzf "${tmp}/swift.tar.gz" -C "${SWIFT_HOME}" --strip-components=1
  rm -rf "${tmp}"
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${SWIFT_HOME}/usr/bin:\$PATH\"" >> "${CLAUDE_ENV_FILE}"
fi
export PATH="${SWIFT_HOME}/usr/bin:${PATH}"
swift --version | head -1

# Warm the build cache so the first `swift test` in the session is fast.
swift build --package-path "${CLAUDE_PROJECT_DIR}/CaliperCore" --build-tests > /dev/null
echo "[session-start] CaliperCore package builds"
