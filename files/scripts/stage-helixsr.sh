#!/usr/bin/env bash
set -euo pipefail

# Build-time staging script for Decky Loader, HelixSR core, and HelixSR Manager.
# Stages immutable artifacts into STAGE_DIR because /home is ephemeral during
# rpm-ostree / bootc container image builds.

STAGE_DIR="${STAGE_DIR:-/usr/share/sol-os/helixsr}"

DECKY_PLUGIN_LOADER_URL="https://github.com/SteamDeckHomebrew/decky-loader/releases/latest/download/PluginLoader"
DECKY_SERVICE_URL="https://raw.githubusercontent.com/SteamDeckHomebrew/decky-loader/main/dist/plugin_loader-release.service"
DECKY_INSTALLER_URL="https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh"
DECKY_RELEASE_API="https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest"

HELIXSR_REPO="lonewolf0622/HelixSR"
HELIXSR_MAIN_TARBALL="https://github.com/lonewolf0622/HelixSR/archive/refs/heads/main.tar.gz"
MANAGER_REPO="PeroTuncay/DeckyHelixSRManager"
MANAGER_MAIN_TARBALL="https://github.com/PeroTuncay/DeckyHelixSRManager/archive/refs/heads/main.tar.gz"

log() {
    printf '[stage-helixsr] %s\n' "$*" >&2
}

die() {
    printf '[stage-helixsr] ERROR: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        die "Required command not found: ${cmd}"
    fi
}

gh_curl() {
    local is_api=0
    local arg
    for arg in "$@"; do
        case "${arg}" in
            https://api.github.com/*) is_api=1 ;;
        esac
    done

    if [ "${is_api}" -eq 1 ]; then
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            curl -fsSL --retry 3 --retry-delay 2 \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "User-Agent: sol-os-helixsr-stager" \
                "$@"
        else
            curl -fsSL --retry 3 --retry-delay 2 \
                -H "Accept: application/vnd.github+json" \
                -H "User-Agent: sol-os-helixsr-stager" \
                "$@"
        fi
    else
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            curl -fsSL --retry 3 --retry-delay 2 \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "User-Agent: sol-os-helixsr-stager" \
                "$@"
        else
            curl -fsSL --retry 3 --retry-delay 2 \
                -H "User-Agent: sol-os-helixsr-stager" \
                "$@"
        fi
    fi
}

fetch_release_json() {
    local repo="$1"
    local json=""
    local first=""

    if json="$(gh_curl "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)" && [ -n "${json}" ]; then
        if printf '%s' "${json}" | jq -e '(.tag_name? // "") != ""' >/dev/null 2>&1; then
            printf '%s' "${json}"
            return 0
        fi
    fi

    if json="$(gh_curl "https://api.github.com/repos/${repo}/releases?per_page=10" 2>/dev/null)" && [ -n "${json}" ]; then
        first="$(printf '%s' "${json}" | jq -c 'if type == "array" then (.[0] // empty) else empty end' 2>/dev/null || true)"
        if [ -n "${first}" ] && printf '%s' "${first}" | jq -e '(.tag_name? // "") != ""' >/dev/null 2>&1; then
            printf '%s' "${first}"
            return 0
        fi
    fi

    return 1
}

download_nonempty() {
    local url="$1"
    local dest="$2"
    gh_curl "${url}" -o "${dest}"
    if [ ! -s "${dest}" ]; then
        die "Downloaded file is empty: ${dest} (from ${url})"
    fi
}

sanitize_filename() {
    local raw="$1"
    local base
    base="$(basename -- "${raw}")"
    printf '%s' "${base}" | tr -cd 'A-Za-z0-9._-'
}

main() {
    require_cmd curl
    require_cmd jq

    log "Staging HelixSR & Decky Loader components into ${STAGE_DIR}"

    rm -rf "${STAGE_DIR}/decky" "${STAGE_DIR}/helixsr-core" "${STAGE_DIR}/helixsr-manager"
    mkdir -p "${STAGE_DIR}/decky" "${STAGE_DIR}/helixsr-core" "${STAGE_DIR}/helixsr-manager"

    # 1. Stage Decky Loader
    log "Downloading Decky Loader PluginLoader..."
    download_nonempty "${DECKY_PLUGIN_LOADER_URL}" "${STAGE_DIR}/decky/PluginLoader"
    chmod 0755 "${STAGE_DIR}/decky/PluginLoader"

    log "Downloading Decky Loader systemd service template..."
    download_nonempty "${DECKY_SERVICE_URL}" "${STAGE_DIR}/decky/plugin_loader-release.service"
    chmod 0644 "${STAGE_DIR}/decky/plugin_loader-release.service"

    log "Downloading Decky Loader install_release.sh..."
    download_nonempty "${DECKY_INSTALLER_URL}" "${STAGE_DIR}/decky/install_release.sh"
    chmod 0755 "${STAGE_DIR}/decky/install_release.sh"

    local decky_version="latest"
    local decky_json=""
    if decky_json="$(gh_curl "${DECKY_RELEASE_API}" 2>/dev/null)" && [ -n "${decky_json}" ]; then
        local parsed_decky_tag=""
        parsed_decky_tag="$(printf '%s' "${decky_json}" | jq -r '.tag_name // empty' 2>/dev/null || true)"
        if [ -n "${parsed_decky_tag}" ]; then
            decky_version="${parsed_decky_tag}"
        fi
    else
        log "Warning: unable to query Decky Loader tag via GitHub API; recording version as 'latest'"
    fi
    printf '%s\n' "${decky_version}" > "${STAGE_DIR}/decky/version.txt"
    log "Staged Decky Loader (${decky_version})"

    # 2. Stage HelixSR Core (lonewolf0622/HelixSR)
    local helixsr_json=""
    local core_version=""
    local core_url=""
    local core_filename=""

    if helixsr_json="$(fetch_release_json "${HELIXSR_REPO}")"; then
        core_version="$(printf '%s' "${helixsr_json}" | jq -r '.tag_name // "unknown"')"
        local core_asset_json=""
        core_asset_json="$(printf '%s' "${helixsr_json}" | jq -c '
            (
                [.assets[]? | select(((.name // "") | ascii_downcase) as $n |
                    ($n | endswith(".tar.gz") or endswith(".tgz") or endswith(".zip")) and
                    (($n | contains(".exe") or contains(".msi") or contains("windows") or contains("win64") or contains("win32") or contains("manager") or contains("decky") or contains("plugin")) | not) and
                    ($n | contains("linux") or contains("deck") or contains("steamos"))
                )][0]
            ) // (
                [.assets[]? | select(((.name // "") | ascii_downcase) as $n |
                    ($n | endswith(".tar.gz") or endswith(".tgz") or endswith(".zip")) and
                    (($n | contains(".exe") or contains(".msi") or contains("windows") or contains("win64") or contains("win32") or contains("manager") or contains("decky") or contains("plugin")) | not)
                )][0]
            ) // (
                [.assets[]? | select(((.name // "") | ascii_downcase) as $n |
                    ($n | endswith(".tar.gz") or endswith(".tgz") or endswith(".zip")) and
                    (($n | contains(".exe") or contains(".msi") or contains("manager") or contains("decky") or contains("plugin")) | not)
                )][0]
            ) // empty
        ')"

        if [ -n "${core_asset_json}" ]; then
            core_url="$(printf '%s' "${core_asset_json}" | jq -r '.browser_download_url // empty')"
            core_filename="$(sanitize_filename "$(printf '%s' "${core_asset_json}" | jq -r '.name // empty')")"
        fi

        if [ -z "${core_url}" ]; then
            core_url="$(printf '%s' "${helixsr_json}" | jq -r '.tarball_url // empty')"
            core_filename="HelixSR-$(sanitize_filename "${core_version}").tar.gz"
        fi
    else
        log "Warning: unable to resolve ${HELIXSR_REPO} release via API; falling back to main tarball"
        core_version="main"
        core_url="${HELIXSR_MAIN_TARBALL}"
        core_filename="HelixSR-main.tar.gz"
    fi

    if [ -z "${core_url}" ] || [ -z "${core_filename}" ]; then
        die "Failed to determine HelixSR core download URL"
    fi

    log "Downloading HelixSR Core (${core_version}) from ${core_url}..."
    download_nonempty "${core_url}" "${STAGE_DIR}/helixsr-core/${core_filename}"
    printf '%s\n' "${core_version}" > "${STAGE_DIR}/helixsr-core/version.txt"

    # 3. Stage HelixSR Manager Decky Plugin
    local mgr_version=""
    local mgr_url=""
    local mgr_filename=""
    local mgr_source=""

    if [ -n "${helixsr_json}" ]; then
        local mgr_in_helixsr=""
        mgr_in_helixsr="$(printf '%s' "${helixsr_json}" | jq -c '
            [.assets[]? | select(((.name // "") | ascii_downcase) as $n |
                ($n | endswith(".zip") or endswith(".tar.gz") or endswith(".tgz")) and
                ($n | contains("manager") or contains("decky") or contains("plugin"))
            )][0] // empty
        ')"
        if [ -n "${mgr_in_helixsr}" ]; then
            mgr_url="$(printf '%s' "${mgr_in_helixsr}" | jq -r '.browser_download_url // empty')"
            mgr_filename="$(sanitize_filename "$(printf '%s' "${mgr_in_helixsr}" | jq -r '.name // empty')")"
            mgr_version="${core_version}"
            mgr_source="${HELIXSR_REPO}"
        fi
    fi

    if [ -z "${mgr_url}" ]; then
        local mgr_json=""
        if mgr_json="$(fetch_release_json "${MANAGER_REPO}")"; then
            local mgr_asset=""
            mgr_asset="$(printf '%s' "${mgr_json}" | jq -c '
                [.assets[]? | select(((.name // "") | ascii_downcase) as $n |
                    $n | endswith(".zip") or endswith(".tar.gz") or endswith(".tgz")
                )][0] // empty
            ')"
            if [ -n "${mgr_asset}" ]; then
                mgr_url="$(printf '%s' "${mgr_asset}" | jq -r '.browser_download_url // empty')"
                mgr_filename="$(sanitize_filename "$(printf '%s' "${mgr_asset}" | jq -r '.name // empty')")"
                mgr_version="$(printf '%s' "${mgr_json}" | jq -r '.tag_name // "latest"')"
                mgr_source="${MANAGER_REPO}"
            fi
        fi
    fi

    if [ -z "${mgr_url}" ]; then
        log "No tagged release archive found for HelixSR Manager; falling back to ${MANAGER_MAIN_TARBALL}"
        mgr_version="main"
        mgr_url="${MANAGER_MAIN_TARBALL}"
        mgr_filename="DeckyHelixSRManager-main.tar.gz"
        mgr_source="${MANAGER_REPO}"
    fi

    log "Downloading HelixSR Manager (${mgr_version}) from ${mgr_url}..."
    download_nonempty "${mgr_url}" "${STAGE_DIR}/helixsr-manager/${mgr_filename}"
    printf '%s\n' "${mgr_version}" > "${STAGE_DIR}/helixsr-manager/version.txt"

    # 4. Write manifest and normalize permissions
    local staged_at
    staged_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    cat > "${STAGE_DIR}/manifest.env" <<EOF
STAGED_AT="${staged_at}"
DECKY_VERSION="${decky_version}"
DECKY_PLUGIN_LOADER_URL="${DECKY_PLUGIN_LOADER_URL}"
DECKY_SERVICE_URL="${DECKY_SERVICE_URL}"
DECKY_INSTALLER_URL="${DECKY_INSTALLER_URL}"
HELIXSR_CORE_VERSION="${core_version}"
HELIXSR_CORE_URL="${core_url}"
HELIXSR_CORE_FILE="${core_filename}"
HELIXSR_MANAGER_VERSION="${mgr_version}"
HELIXSR_MANAGER_URL="${mgr_url}"
HELIXSR_MANAGER_FILE="${mgr_filename}"
HELIXSR_MANAGER_SOURCE="${mgr_source}"
EOF

    chmod -R a+rX "${STAGE_DIR}"
    chmod 0755 "${STAGE_DIR}/decky/PluginLoader" "${STAGE_DIR}/decky/install_release.sh"
    chmod 0644 "${STAGE_DIR}/decky/plugin_loader-release.service"

    log "Completed staging at ${staged_at}"
}

main "$@"
