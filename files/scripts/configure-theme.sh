#!/usr/bin/env bash
set -euo pipefail

# Sol OS (BC-250 Edition) — System-wide Plymouth, KDE Plasma 6, and Gamescope theme configuration.

SOL_STARTUP_WEBM="${SOL_STARTUP_WEBM:-/usr/share/sol-os/theme/sol_startup.webm}"

log() {
  printf '[configure-theme] %s\n' "$*"
}

die() {
  printf '[configure-theme] ERROR: %s\n' "$*" >&2
  exit 1
}

update_ini_python() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"

  python3 - "$file" "$section" "$key" "$value" <<'PYEOF'
import os
import sys

file_path, target_section, target_key, target_value = sys.argv[1:5]
target_header = "[%s]" % target_section
new_kv = "%s=%s" % (target_key, target_value)

if os.path.exists(file_path):
    with open(file_path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        raw_lines = fh.read().splitlines()
else:
    raw_lines = []

out_lines = []
in_target = False
found_section = False
updated = False
pending_blanks = []

def flush_blanks():
    global pending_blanks
    if pending_blanks:
        out_lines.extend(pending_blanks)
        pending_blanks = []

for line in raw_lines:
    stripped = line.strip()

    if stripped.startswith("[") and stripped.endswith("]"):
        if in_target and not updated:
            out_lines.append(new_kv)
            updated = True
        flush_blanks()
        if stripped == target_header:
            in_target = True
            found_section = True
        else:
            in_target = False
        out_lines.append(line)
        continue

    if in_target:
        if stripped == "":
            pending_blanks.append(line)
            continue
        flush_blanks()
        if not stripped.startswith("#") and not stripped.startswith(";") and "=" in line:
            lhs = line.split("=", 1)[0].strip()
            if lhs == target_key:
                if not updated:
                    out_lines.append(new_kv)
                    updated = True
                continue
        out_lines.append(line)
    else:
        out_lines.append(line)

if in_target and not updated:
    out_lines.append(new_kv)
    updated = True
flush_blanks()

if not found_section:
    if out_lines and out_lines[-1].strip() != "":
        out_lines.append("")
    out_lines.append(target_header)
    out_lines.append(new_kv)

tmp_path = "%s.tmp.%d" % (file_path, os.getpid())
with open(tmp_path, "w", encoding="utf-8", errors="surrogateescape") as fh:
    fh.write("\n".join(out_lines) + "\n")
os.chmod(tmp_path, 0o644)
os.replace(tmp_path, file_path)
PYEOF
}

update_ini_awk() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local tmp_file="${file}.tmp.$$"

  if [ ! -f "${file}" ]; then
    printf '[%s]\n%s=%s\n' "${section}" "${key}" "${value}" > "${tmp_file}"
    chmod 0644 "${tmp_file}"
    mv -f "${tmp_file}" "${file}"
    return 0
  fi

  awk -v sec="[${section}]" -v k="${key}" -v v="${value}" '
    function flush_blanks(    i) {
      for (i = 1; i <= n_blanks; i++) {
        print blanks[i]
      }
      n_blanks = 0
    }
    BEGIN {
      in_target = 0
      found_sec = 0
      updated = 0
      n_blanks = 0
      last_nonblank = 0
    }
    {
      line = $0
      trimmed = line
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)

      if (trimmed ~ /^\[.*\]$/) {
        if (in_target && !updated) {
          print k "=" v
          updated = 1
        }
        flush_blanks()
        if (trimmed == sec) {
          in_target = 1
          found_sec = 1
        } else {
          in_target = 0
        }
        print line
        last_nonblank = 1
        next
      }

      if (in_target) {
        if (trimmed == "") {
          blanks[++n_blanks] = line
          next
        }
        flush_blanks()
        if (trimmed !~ /^[#;]/ && index(line, "=") > 0) {
          lhs = substr(line, 1, index(line, "=") - 1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
          if (lhs == k) {
            if (!updated) {
              print k "=" v
              updated = 1
            }
            last_nonblank = 1
            next
          }
        }
        print line
        last_nonblank = 1
      } else {
        print line
        last_nonblank = (trimmed != "")
      }
    }
    END {
      if (in_target && !updated) {
        print k "=" v
        updated = 1
        last_nonblank = 1
      }
      flush_blanks()
      if (!found_sec) {
        if (NR > 0 && last_nonblank) {
          print ""
        }
        print sec
        print k "=" v
      }
    }
  ' "${file}" > "${tmp_file}"

  chmod 0644 "${tmp_file}"
  mv -f "${tmp_file}" "${file}"
}

set_ini_kv() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local parent_dir=""

  parent_dir="$(dirname "${file}")"
  mkdir -p "${parent_dir}"

  if command -v python3 >/dev/null 2>&1; then
    update_ini_python "${file}" "${section}" "${key}" "${value}"
  else
    update_ini_awk "${file}" "${section}" "${key}" "${value}"
  fi
}

set_kde_kv() {
  local file="$1"
  local group="$2"
  local key="$3"
  local value="$4"
  local parent_dir=""

  parent_dir="$(dirname "${file}")"
  mkdir -p "${parent_dir}"

  if command -v kwriteconfig6 >/dev/null 2>&1; then
    if kwriteconfig6 --file "${file}" --group "${group}" --key "${key}" "${value}"; then
      chmod 0644 "${file}" 2>/dev/null || true
      return 0
    fi
    log "WARNING: kwriteconfig6 failed on ${file} (${group}/${key}); falling back to INI updater."
  fi

  set_ini_kv "${file}" "${group}" "${key}" "${value}"
}

configure_plymouth() {
  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    log "Setting default Plymouth theme to sol-eclipse..."
    plymouth-set-default-theme sol-eclipse
  else
    log "plymouth-set-default-theme not found; configuring /etc/plymouth/plymouthd.conf directly."
  fi

  log "Ensuring /etc/plymouth/plymouthd.conf sets [Daemon] Theme=sol-eclipse..."
  set_ini_kv /etc/plymouth/plymouthd.conf "Daemon" "Theme" "sol-eclipse"
}

configure_kde_defaults() {
  log "Setting system-wide KDE Plasma 6 defaults under /etc/xdg/..."

  set_kde_kv /etc/xdg/kdeglobals "KDE" "LookAndFeelPackage" "org.sol-os.eclipse"
  set_kde_kv /etc/xdg/kdeglobals "General" "ColorScheme" "SolEclipse"
  set_kde_kv /etc/xdg/kdeglobals "Icons" "Theme" "breeze-dark"

  set_kde_kv /etc/xdg/plasmarc "Theme" "name" "SolEclipse"

  set_kde_kv /etc/xdg/ksplashrc "KSplash" "Engine" "KSplashQML"
  set_kde_kv /etc/xdg/ksplashrc "KSplash" "Theme" "org.sol-os.eclipse"
}

replace_preshipped_startup_webm() {
  local search_dir=""
  local target=""
  local replaced_count=0

  if [ ! -s "${SOL_STARTUP_WEBM}" ]; then
    log "WARNING: ${SOL_STARTUP_WEBM} missing or empty; skipping startup .webm replacement."
    return 0
  fi

  for search_dir in /usr/share/ublue-os /usr/share/gamescope-session-plus; do
    if [ ! -d "${search_dir}" ]; then
      continue
    fi

    while IFS= read -r target; do
      [ -n "${target}" ] || continue
      if [ "${target}" = "${SOL_STARTUP_WEBM}" ]; then
        continue
      fi
      log "Replacing pre-shipped startup video ${target} with ${SOL_STARTUP_WEBM}..."
      rm -f "${target}"
      install -m 0644 "${SOL_STARTUP_WEBM}" "${target}"
      replaced_count=$((replaced_count + 1))
    done < <(find "${search_dir}" \( -type f -o -type l \) \( -iname '*startup*.webm' -o -iname '*bazzite*.webm' \) 2>/dev/null | LC_ALL=C sort)
  done

  log "Startup video replacement complete (replaced ${replaced_count} file(s))."
}

update_icon_cache() {
  if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -d /usr/share/icons/hicolor ]; then
    log "Updating hicolor icon cache..."
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor || log "WARNING: gtk-update-icon-cache returned non-zero (non-fatal)."
  fi
}

main() {
  configure_plymouth
  configure_kde_defaults
  replace_preshipped_startup_webm
  update_icon_cache
  log "Done."
}

main "$@"
