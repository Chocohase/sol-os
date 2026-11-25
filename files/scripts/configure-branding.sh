#!/usr/bin/env bash
set -euo pipefail

# Sol OS (BC-250 Edition) — Image branding, hostname, and libexec permissions.

WORK_DIR="$(mktemp -d /tmp/sol-branding.XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

log() {
  printf '[configure-branding] %s\n' "$*"
}

set_os_release_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file="${WORK_DIR}/os-release.tmp"
  local line
  local found=0

  : > "${tmp_file}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      "${key}="*)
        if [[ "${found}" -eq 0 ]]; then
          printf '%s="%s"\n' "${key}" "${value}" >> "${tmp_file}"
          found=1
        fi
        ;;
      *)
        printf '%s\n' "${line}" >> "${tmp_file}"
        ;;
    esac
  done < "${file}"

  if [[ "${found}" -eq 0 ]]; then
    printf '%s="%s"\n' "${key}" "${value}" >> "${tmp_file}"
  fi

  cat "${tmp_file}" > "${file}"
}

apply_branding_to_file() {
  local target_file="$1"

  log "Patching branding keys in ${target_file}..."
  set_os_release_kv "${target_file}" "NAME" "Sol OS"
  set_os_release_kv "${target_file}" "PRETTY_NAME" "Sol OS (BC-250 Edition)"
  set_os_release_kv "${target_file}" "VARIANT" "BC-250 Edition"
  set_os_release_kv "${target_file}" "VARIANT_ID" "bc250"
  set_os_release_kv "${target_file}" "DEFAULT_HOSTNAME" "sol-os"
}

main() {
  local etc_target=""
  local current_hostname=""

  if [[ -f /usr/lib/os-release ]]; then
    apply_branding_to_file /usr/lib/os-release
  else
    log "WARNING: /usr/lib/os-release not found; skipping."
  fi

  if [[ ! -L /etc/os-release && -f /etc/os-release ]]; then
    apply_branding_to_file /etc/os-release
  elif [[ -L /etc/os-release ]]; then
    etc_target="$(readlink /etc/os-release || true)"
    if [[ "${etc_target}" != "../usr/lib/os-release" && "${etc_target}" != "/usr/lib/os-release" ]]; then
      if [[ -f /usr/lib/os-release ]]; then
        log "Aligning /etc/os-release symlink to ../usr/lib/os-release..."
        ln -sfn ../usr/lib/os-release /etc/os-release
      elif [[ -f /etc/os-release ]]; then
        apply_branding_to_file /etc/os-release
      fi
    fi
  elif [[ ! -e /etc/os-release && -f /usr/lib/os-release ]]; then
    log "Creating /etc/os-release -> ../usr/lib/os-release symlink..."
    ln -s ../usr/lib/os-release /etc/os-release
  fi

  if [[ -f /etc/hostname ]]; then
    current_hostname="$(tr -d ' \t\r\n' < /etc/hostname || true)"
  fi
  if [[ "${current_hostname}" != "sol-os" ]]; then
    log "Setting /etc/hostname to sol-os..."
    printf 'sol-os\n' > /etc/hostname
    chmod 0644 /etc/hostname
  fi

  if [[ -d /usr/libexec/sol-os ]]; then
    log "Ensuring executable permissions in /usr/libexec/sol-os/..."
    find /usr/libexec/sol-os -type f -exec chmod 0755 {} +
  fi

  log "Done."
}

main "$@"
