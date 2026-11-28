#!/usr/bin/env bash
set -euo pipefail

# Sol OS (BC-250 Edition) — Stage opt-in BC-250 live GPU CU & CPU core manager.
# Installs WinnieLV/bc250-cu-live-manager into /usr/libexec/sol-os without
# enabling any persistent systemd unit by default (safe 24-CU boot preserved).

CU_MGR_URL="${CU_MGR_URL:-https://raw.githubusercontent.com/WinnieLV/bc250-cu-live-manager/refs/heads/main/bc250-cu-live-manager.sh}"
INSTALL_TARGET="${INSTALL_TARGET:-/usr/libexec/sol-os/bc250-cu-live-manager}"
WORK_DIR="$(mktemp -d /tmp/sol-cu-mgr.XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

log() {
  printf '[install-bc250-cu-manager] %s\n' "$*" >&2
}

die() {
  printf '[install-bc250-cu-manager] ERROR: %s\n' "$*" >&2
  exit 1
}

main() {
  if ! command -v curl >/dev/null 2>&1; then
    die "Required command not found: curl"
  fi

  local tmp_script="${WORK_DIR}/bc250-cu-live-manager.sh"
  log "Downloading bc250-cu-live-manager from ${CU_MGR_URL}..."
  curl -fsSL --retry 3 --retry-delay 2 \
    -H "User-Agent: sol-os-cu-manager-installer" \
    "${CU_MGR_URL}" -o "${tmp_script}"

  if [ ! -s "${tmp_script}" ]; then
    die "Downloaded script is empty: ${tmp_script}"
  fi

  local first_line=""
  IFS= read -r first_line < "${tmp_script}" || true
  case "${first_line}" in
    '#!'*bash*)
      ;;
    *)
      die "Unexpected header in downloaded script: ${first_line}"
      ;;
  esac

  bash -n "${tmp_script}"

  mkdir -p "$(dirname -- "${INSTALL_TARGET}")"
  install -m 0755 "${tmp_script}" "${INSTALL_TARGET}"
  log "Installed opt-in CU manager -> ${INSTALL_TARGET}"
}

main "$@"
