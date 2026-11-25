#!/usr/bin/env bash
set -euo pipefail

# Sol OS (BC-250 Edition) — Local Validation, OCI Image Build, and ISO Helper
# Strictly compatible with GNU Bash 3.2+.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
RECIPE_REL="recipes/recipe.yml"
RECIPE_PATH="${REPO_ROOT}/${RECIPE_REL}"
ISO_OUTPUT_DIR="${REPO_ROOT}/iso-output"
ISO_NAME="sol-os.iso"

VALIDATE_ONLY=0
BUILD_ISO=0
IMAGE_TAG="latest"

usage() {
  cat <<'EOF'
Usage: ./build-local.sh [OPTIONS]

Validate Sol OS recipes and scripts, build the OCI image locally with BlueBuild,
and optionally generate a bootable sol-os.iso installer image.

Options:
  --validate-only   Validate recipes/recipe.yml YAML syntax (plus 'bluebuild validate'
                    if installed) and check shell scripts with 'bash -n' (and
                    'shellcheck' if installed), then exit 0 without building.
  --iso             After building the OCI image locally, run:
                      sudo bluebuild generate-iso --output-dir ./iso-output \
                        --iso-name sol-os.iso recipe recipes/recipe.yml
  --tag <tag>       Custom local OCI image tag (default: latest).
  -h, --help        Show this help message and exit.

Examples:
  ./build-local.sh --validate-only
  ./build-local.sh
  ./build-local.sh --tag dev --iso
EOF
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --validate-only)
        VALIDATE_ONLY=1
        shift
        ;;
      --iso)
        BUILD_ISO=1
        shift
        ;;
      --tag)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          log_error "--tag requires a non-empty tag value."
          usage >&2
          exit 1
        fi
        IMAGE_TAG="$2"
        shift 2
        ;;
      --tag=*)
        IMAGE_TAG="${1#*=}"
        if [[ -z "${IMAGE_TAG}" ]]; then
          log_error "--tag= requires a non-empty tag value."
          usage >&2
          exit 1
        fi
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage >&2
        exit 1
        ;;
    esac
  done
}

validate_yaml_file() {
  local yaml_file="$1"
  local rel_label="$2"
  local checked=0

  log_info "Validating YAML syntax for ${rel_label}..."

  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
      content = File.read(ARGV[0])
      begin
        YAML.safe_load(content, aliases: true)
      rescue ArgumentError
        YAML.safe_load(content)
      end
    ' "${yaml_file}"
    log_info "YAML syntax OK for ${rel_label} (verified via ruby)."
    checked=1
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c 'import sys, yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    yaml.safe_load(fh)
' "${yaml_file}"
    log_info "YAML syntax OK for ${rel_label} (verified via python3 PyYAML)."
    checked=1
  fi

  if [[ "${checked}" -eq 1 ]]; then
    return 0
  fi

  return 1
}

validate_yaml() {
  local yaml_checked=0
  local workflow_path="${REPO_ROOT}/.github/workflows/build.yml"

  if [[ ! -f "${RECIPE_PATH}" ]]; then
    log_error "Recipe file not found: ${RECIPE_PATH}"
    exit 1
  fi

  if validate_yaml_file "${RECIPE_PATH}" "${RECIPE_REL}"; then
    yaml_checked=1
  fi

  if [[ -f "${workflow_path}" ]]; then
    if validate_yaml_file "${workflow_path}" ".github/workflows/build.yml"; then
      yaml_checked=1
    fi
  fi

  if command -v bluebuild >/dev/null 2>&1; then
    log_info "Running bluebuild validate ${RECIPE_REL}..."
    bluebuild validate "${RECIPE_PATH}"
    yaml_checked=1
  else
    log_info "bluebuild CLI not found; skipping 'bluebuild validate' schema check."
  fi

  if [[ "${yaml_checked}" -eq 0 ]]; then
    log_error "Cannot validate ${RECIPE_REL}: install 'bluebuild', 'ruby', or 'python3' with PyYAML."
    exit 1
  fi
}

validate_shell_script() {
  local script_file="$1"
  bash -n "${script_file}"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${script_file}"
  fi
}

validate_scripts() {
  local script_count=0
  local script_path=""

  log_info "Checking shell scripts with bash -n..."
  validate_shell_script "${REPO_ROOT}/build-local.sh"
  script_count=$((script_count + 1))

  if [[ -d "${REPO_ROOT}/files/scripts" ]]; then
    while IFS= read -r -d '' script_path; do
      validate_shell_script "${script_path}"
      script_count=$((script_count + 1))
    done < <(find "${REPO_ROOT}/files/scripts" -type f -name '*.sh' -print0)
  fi

  if [[ -d "${REPO_ROOT}/files/system/usr/libexec/sol-os" ]]; then
    while IFS= read -r -d '' script_path; do
      validate_shell_script "${script_path}"
      script_count=$((script_count + 1))
    done < <(find "${REPO_ROOT}/files/system/usr/libexec/sol-os" -type f -print0)
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    log_info "Validated ${script_count} shell script(s) with bash -n and shellcheck."
  else
    log_info "Validated ${script_count} shell script(s) with bash -n (shellcheck not installed)."
  fi
}

require_build_tools() {
  local missing=0

  if ! command -v bluebuild >/dev/null 2>&1; then
    log_error "Required tool 'bluebuild' is not installed or not on PATH."
    cat >&2 <<'EOF'
Install BlueBuild CLI:
  curl -fsSL https://raw.githubusercontent.com/blue-build/cli/main/install.sh | bash
  export PATH="${HOME}/.local/bin:${PATH}"
See also: https://blue-build.org/how-to/local-build/
EOF
    missing=1
  fi

  if ! command -v podman >/dev/null 2>&1; then
    log_error "Required tool 'podman' is not installed or not on PATH."
    cat >&2 <<'EOF'
Install Podman:
  Fedora / Bazzite:  sudo dnf install -y podman
  Ubuntu / Debian:   sudo apt-get update && sudo apt-get install -y podman
EOF
    missing=1
  fi

  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi
}

warn_if_missing_cosign_pub() {
  if [[ ! -f "${REPO_ROOT}/cosign.pub" ]]; then
    log_warn "cosign.pub is missing from repository root (${REPO_ROOT}/cosign.pub)."
    cat >&2 <<'EOF'
[WARN] Image signing verification in recipes/recipe.yml expects cosign.pub.
       Generate a signing key pair (press Enter for an empty password):
         cosign generate-key-pair
       Then commit cosign.pub (NEVER commit cosign.key) and save cosign.key
       as the SIGNING_SECRET repository secret in GitHub Actions.
EOF
  fi
}

print_iso_instructions() {
  cat <<EOF

================================================================================
ISO Generation Commands (USB-flashable sol-os.iso)
================================================================================

1. From this local BlueBuild recipe (writes ./iso-output/sol-os.iso):
   mkdir -p ./iso-output
   sudo bluebuild generate-iso --output-dir ./iso-output --iso-name sol-os.iso recipe recipes/recipe.yml

2. From a published GHCR image (writes ./iso-output/sol-os.iso):
   mkdir -p ./iso-output
   sudo bluebuild generate-iso --output-dir ./iso-output --iso-name sol-os.iso image ghcr.io/<github-user>/sol-os:${IMAGE_TAG}

3. Verify checksum and flash to USB (replace /dev/sdX with your USB block device):
   (cd iso-output && sha256sum sol-os.iso > sol-os.iso.sha256)
   sudo dd if=iso-output/sol-os.iso of=/dev/sdX bs=4M status=progress oflag=sync
EOF
}

build_local_image() {
  log_info "Building Sol OS OCI image locally from ${RECIPE_REL} (tag: ${IMAGE_TAG})..."

  if bluebuild build --help 2>&1 | grep -q -- '--tag'; then
    bluebuild build --tag "${IMAGE_TAG}" "${RECIPE_REL}"
  else
    bluebuild build "${RECIPE_REL}"
    if [[ "${IMAGE_TAG}" != "latest" ]]; then
      if podman image exists "localhost/sol-os:latest"; then
        podman tag "localhost/sol-os:latest" "localhost/sol-os:${IMAGE_TAG}"
        log_info "Tagged local image as localhost/sol-os:${IMAGE_TAG}."
      elif podman image exists "sol-os:latest"; then
        podman tag "sol-os:latest" "sol-os:${IMAGE_TAG}"
        log_info "Tagged local image as sol-os:${IMAGE_TAG}."
      else
        log_warn "Custom tag '${IMAGE_TAG}' requested, but 'localhost/sol-os:latest' was not found for podman tag."
      fi
    fi
  fi

  log_info "Local OCI image build completed."
}

generate_local_iso() {
  local bluebuild_bin=""
  bluebuild_bin="$(command -v bluebuild)"

  mkdir -p "${ISO_OUTPUT_DIR}"
  log_info "Generating bootable ${ISO_NAME} in ${ISO_OUTPUT_DIR}..."
  sudo "${bluebuild_bin}" generate-iso \
    --output-dir ./iso-output \
    --iso-name "${ISO_NAME}" \
    recipe "${RECIPE_REL}"

  if command -v sha256sum >/dev/null 2>&1 && [[ -f "${ISO_OUTPUT_DIR}/${ISO_NAME}" ]]; then
    (cd "${ISO_OUTPUT_DIR}" && sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256")
  fi

  sudo chown -R "$(id -u):$(id -g)" "${ISO_OUTPUT_DIR}"
  log_info "ISO generated: ${ISO_OUTPUT_DIR}/${ISO_NAME}"
}

main() {
  parse_args "$@"
  cd "${REPO_ROOT}"

  validate_yaml
  validate_scripts

  if [[ "${VALIDATE_ONLY}" -eq 1 ]]; then
    log_info "Validation passed (--validate-only). Exiting without building."
    exit 0
  fi

  require_build_tools
  warn_if_missing_cosign_pub
  build_local_image

  if [[ "${BUILD_ISO}" -eq 1 ]]; then
    generate_local_iso
  fi

  print_iso_instructions
}

main "$@"
