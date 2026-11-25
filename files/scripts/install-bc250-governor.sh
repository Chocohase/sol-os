#!/usr/bin/env bash
set -euo pipefail

# Sol OS (BC-250 Edition) — cyan-skillfish-governor-smu builder & installer.
# Supports BlueBuild multi-stage builds (default, OUT_PREFIX=/out) and
# direct host/image installation (SOL_DIRECT_INSTALL=1).

OUT_PREFIX="${OUT_PREFIX:-/out}"
SOL_DIRECT_INSTALL="${SOL_DIRECT_INSTALL:-0}"
GOVERNOR_PREBUILT_URL="${GOVERNOR_PREBUILT_URL:-}"
GOVERNOR_PREBUILT_SHA256="${GOVERNOR_PREBUILT_SHA256:-}"
GOVERNOR_REPO_URL="${GOVERNOR_REPO_URL:-https://github.com/filippor/cyan-skillfish-governor.git}"
GOVERNOR_REPO_BRANCH="${GOVERNOR_REPO_BRANCH:-smu}"

BUILD_DIR="$(mktemp -d /tmp/bc250-governor.XXXXXX)"
trap 'rm -rf "${BUILD_DIR}"' EXIT
export CARGO_HOME="${BUILD_DIR}/cargo"
export RUSTUP_HOME="${BUILD_DIR}/rustup"

log() {
  printf '[install-bc250-governor] %s\n' "$*"
}

die() {
  printf '[install-bc250-governor] ERROR: %s\n' "$*" >&2
  exit 1
}

detect_pkg_mgr() {
  if command -v dnf5 >/dev/null 2>&1; then
    printf 'dnf5\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf\n'
  else
    return 1
  fi
}

ensure_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi

  local pkg_mgr
  pkg_mgr="$(detect_pkg_mgr)" || die "curl is required and neither dnf5 nor dnf was found."
  log "Installing curl via ${pkg_mgr}..."
  "${pkg_mgr}" install -y curl
}

ensure_build_deps() {
  local missing=0
  local cmd

  for cmd in cargo rustc gcc pkg-config git curl; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing=1
      break
    fi
  done

  if [[ "${missing}" -eq 0 ]] && ! pkg-config --exists libdrm >/dev/null 2>&1; then
    missing=1
  fi

  if [[ "${missing}" -eq 0 ]]; then
    log "All governor build dependencies already present."
    return 0
  fi

  local pkg_mgr
  pkg_mgr="$(detect_pkg_mgr)" || die "Missing build dependencies and neither dnf5 nor dnf was found."

  log "Installing governor build dependencies via ${pkg_mgr}..."
  "${pkg_mgr}" install -y \
    cargo \
    rust \
    gcc \
    pkgconf-pkg-config \
    libdrm-devel \
    git \
    curl
}

verify_elf_binary() {
  local bin_path="$1"
  local magic

  [[ -s "${bin_path}" ]] || die "Binary at ${bin_path} is missing or empty."

  magic="$(LC_ALL=C od -An -N4 -tx1 "${bin_path}" | tr -d ' \n')"
  if [[ "${magic}" != "7f454c46" ]]; then
    die "File at ${bin_path} is not a valid ELF executable (magic=${magic})."
  fi
}

verify_sha256_if_configured() {
  local bin_path="$1"
  local actual_sha=""

  if [[ -z "${GOVERNOR_PREBUILT_SHA256}" ]]; then
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha="$(sha256sum "${bin_path}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual_sha="$(shasum -a 256 "${bin_path}" | awk '{print $1}')"
  else
    die "GOVERNOR_PREBUILT_SHA256 was set, but neither sha256sum nor shasum is available."
  fi

  local expected_sha
  expected_sha="$(printf '%s' "${GOVERNOR_PREBUILT_SHA256}" | tr '[:upper:]' '[:lower:]')"
  actual_sha="$(printf '%s' "${actual_sha}" | tr '[:upper:]' '[:lower:]')"

  if [[ "${actual_sha}" != "${expected_sha}" ]]; then
    die "SHA-256 mismatch for prebuilt binary: expected ${expected_sha}, got ${actual_sha}."
  fi
}

GOVERNOR_BIN=""

fetch_prebuilt_binary() {
  local dest_bin="${BUILD_DIR}/cyan-skillfish-governor-smu"

  ensure_curl
  log "Fetching prebuilt cyan-skillfish-governor-smu from ${GOVERNOR_PREBUILT_URL}..."
  curl -fsSL --retry 3 --connect-timeout 15 -o "${dest_bin}" "${GOVERNOR_PREBUILT_URL}"

  verify_elf_binary "${dest_bin}"
  verify_sha256_if_configured "${dest_bin}"
  chmod 0755 "${dest_bin}"

  GOVERNOR_BIN="${dest_bin}"
}

build_from_source() {
  local src_dir="${BUILD_DIR}/src"
  local built_bin=""

  ensure_build_deps

  log "Cloning ${GOVERNOR_REPO_URL} (branch: ${GOVERNOR_REPO_BRANCH})..."
  git clone --depth 1 --branch "${GOVERNOR_REPO_BRANCH}" "${GOVERNOR_REPO_URL}" "${src_dir}"

  log "Building cyan-skillfish-governor-smu with cargo..."
  (
    cd "${src_dir}"
    cargo build --release --all-features
  )

  if [[ -x "${src_dir}/target/release/cyan-skillfish-governor-smu" ]]; then
    built_bin="${src_dir}/target/release/cyan-skillfish-governor-smu"
  elif [[ -x "${src_dir}/target/release/cyan-skillfish-governor" ]]; then
    built_bin="${src_dir}/target/release/cyan-skillfish-governor"
  else
    die "Built binary not found under ${src_dir}/target/release/."
  fi

  verify_elf_binary "${built_bin}"

  if command -v strip >/dev/null 2>&1; then
    log "Stripping debug symbols from ${built_bin}..."
    strip "${built_bin}" || true
  fi

  chmod 0755 "${built_bin}"
  GOVERNOR_BIN="${built_bin}"
}

write_default_config() {
  local config_path="$1"

  cat <<'EOF' > "${config_path}"
# Sol OS (BC-250 Edition) — Conservative default AMD BC-250 GPU SMU governor config.
# Ceiling is capped at 2000 MHz with a conservative 950–1000 mV voltage floor to
# prevent silicon lockups across varying BC-250 APU bins.
# After editing /etc/cyan-skillfish-governor-smu/config.toml, apply changes with:
#   sudo systemctl restart cyan-skillfish-governor-smu.service

[timing.intervals]
sample = 500
adjust = 200_000

[timing.ramp-rates]
normal = 1
burst = 50

[timing]
burst-samples = 60
down-events = 5

[frequency-thresholds]
adjust = 10

[load-target]
upper = 0.80
lower = 0.65

[temperature]
throttling = 85
throttling_recovery = 80

[[safe-points]]
frequency = 1000
voltage = 950

[[safe-points]]
frequency = 1500
voltage = 975

[[safe-points]]
frequency = 2000
voltage = 1000
EOF
}

main() {
  local default_cfg="${BUILD_DIR}/config.toml"

  if [[ -n "${GOVERNOR_PREBUILT_URL}" ]]; then
    fetch_prebuilt_binary
  else
    build_from_source
  fi

  [[ -n "${GOVERNOR_BIN}" ]] || die "Governor binary path is empty."
  write_default_config "${default_cfg}"

  if [[ "${SOL_DIRECT_INSTALL}" == "1" ]]; then
    log "Installing directly onto host/image..."
    install -D -m 0755 "${GOVERNOR_BIN}" /usr/libexec/sol-os/cyan-skillfish-governor-smu
    mkdir -p /usr/local/bin
    ln -sfn /usr/libexec/sol-os/cyan-skillfish-governor-smu /usr/local/bin/cyan-skillfish-governor-smu

    if [[ ! -f /etc/cyan-skillfish-governor-smu/config.toml ]]; then
      install -D -m 0644 "${default_cfg}" /etc/cyan-skillfish-governor-smu/config.toml
    else
      log "Existing /etc/cyan-skillfish-governor-smu/config.toml preserved."
    fi
  else
    log "Staging into multi-stage output prefix ${OUT_PREFIX}..."
    install -D -m 0755 "${GOVERNOR_BIN}" "${OUT_PREFIX}/usr/libexec/sol-os/cyan-skillfish-governor-smu"
    install -D -m 0644 "${default_cfg}" "${OUT_PREFIX}/etc/cyan-skillfish-governor-smu/config.toml"
  fi

  log "Done."
}

main "$@"
