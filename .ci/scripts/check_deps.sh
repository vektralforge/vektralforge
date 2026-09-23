#!/usr/bin/env bash
# .ci/scripts/check_deps.sh — Verifies (and installs, with confirmation) the
# system dependencies that setup.sh needs.
#
# Standalone use (to test it without touching setup.sh yet):
#   bash .ci/scripts/check_deps.sh
#
# Integrated use (pending — do NOT enable until confirmed):
#   source .ci/scripts/check_deps.sh && main
#   # leaves PYTHON_BIN exported with the absolute path of the validated interpreter
#
# Flow:
#   1. Banner.
#   2. A log is opened (everything that follows is mirrored to a file).
#   3. ALL dependencies are checked without modifying anything (it never stops
#      at the first one missing) and a summary is shown: what's present, what's
#      missing.
#   4. Whatever is missing and CAN be installed automatically (Homebrew on
#      macOS, Python, venv, pip, git) is offered for installation — but the
#      user is asked before touching the system, nothing is installed
#      silently.
#   5. Whatever is missing and CANNOT be installed automatically (a Linux
#      distro's own package manager, Docker, make, Xcode CLT on macOS) is
#      reported with manual instructions.
#
# Per-OS philosophy:
#   - GNU/Linux: everything automatable is installed if the user confirms.
#     The base package manager (apt-get/dnf/pacman/zypper, per distro) is
#     checked first — if IT is missing, the system itself is broken in a
#     way this script can't repair.
#   - macOS: automates what can be done without intervention. Homebrew
#     itself is the first dependency checked, and is installed
#     automatically (non-interactively) if missing, since everything else
#     installable on macOS goes through it. Xcode Command Line Tools is
#     checked but NEVER installed on its own.
#   - BSD: not supported — Docker does not run natively on these kernels.
#   - Docker: on all three families this ONLY verifies it's accessible.
#     It never installs it — having it installed beforehand is the user's
#     responsibility.
#
# Log style: every line is prefixed [INFO] / [WARN] / [ERROR] — [INFO] for
# normal progress and successful checks, [WARN] for a missing dependency
# found during the check phase (the script keeps checking the rest), [ERROR]
# for a fatal condition that stops the script.
set -euo pipefail

REQUIRED_PYTHON_MAJOR_MINOR="3.12"
REQUIRED_PYTHON_BIN="python3.12"

OS_FAMILY=""
DISTRO_FAMILY=""
PKG_MANAGER_BIN=""       # apt-get / dnf / pacman / zypper — set once DISTRO_FAMILY is known
IS_ROOT=0
LOG_FILE=""

MISSING_INSTALLABLE=()   # names: python3.12 / venv / pip / git
MISSING_MANUAL=()        # names: docker / make / xcode-clt
MANUAL_INSTRUCTIONS=()   # remediation text, one per MISSING_MANUAL entry

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Message helpers ──────────────────────────────────────────────────────────

_info() { echo "[INFO]  $1"; }
_ok()   { echo "[INFO]  $1 ... OK"; }
_bad()  { echo "[WARN]  $1 ... MISSING"; }
_err()  { echo "[ERROR] $1"; }

# Prints a two-column summary table. First argument is the title (its own
# row, spanning the full width); remaining arguments come in column1/column2
# pairs, one table row each. Both column widths auto-size to their content
# (and column 2 grows further if needed to fit the title).
print_summary_table() {
  local title="$1"; shift
  local -a col1=() col2=()
  while [ "$#" -gt 0 ]; do
    col1+=("$1")
    col2+=("$2")
    shift 2
  done

  local w1=0 w2=0 v
  for v in "${col1[@]+"${col1[@]}"}"; do
    [ "${#v}" -gt "$w1" ] && w1="${#v}"
  done
  for v in "${col2[@]+"${col2[@]}"}"; do
    [ "${#v}" -gt "$w2" ] && w2="${#v}"
  done

  local title_w="${#title}"
  local min_title_w=$((w1 + w2 + 3))
  if [ "$title_w" -gt "$min_title_w" ]; then
    w2=$((w2 + (title_w - min_title_w)))
  fi

  local total=$((w1 + w2 + 5))
  local full="" i=0
  while [ "$i" -lt "$total" ]; do full="${full}─"; i=$((i + 1)); done
  local seg1="" i=0
  while [ "$i" -lt "$((w1 + 2))" ]; do seg1="${seg1}─"; i=$((i + 1)); done
  local seg2="" i=0
  while [ "$i" -lt "$((w2 + 2))" ]; do seg2="${seg2}─"; i=$((i + 1)); done

  echo "  ┌${full}┐"
  printf '  │ %-*s │\n' "$((w1 + w2 + 3))" "$title"
  echo "  ├${seg1}┬${seg2}┤"
  local n=${#col1[@]} j=0
  while [ "$j" -lt "$n" ]; do
    printf '  │ %-*s │ %-*s │\n' "$w1" "${col1[$j]}" "$w2" "${col2[$j]}"
    j=$((j + 1))
  done
  echo "  └${seg1}┴${seg2}┘"
}

run_priv() {
  if [ "$IS_ROOT" -eq 1 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ── Log ───────────────────────────────────────────────────────────────────────

setup_logging() {
  local log_dir="$REPO_ROOT/.ci/logs"
  if ! mkdir -p "$log_dir" 2>/dev/null; then
    log_dir="/tmp"
  fi
  LOG_FILE="$log_dir/check_deps-$(date +%Y%m%d-%H%M%S).log"
  # From here on, everything printed (stdout and stderr) is mirrored to the
  # log exactly as it appears on screen — it's not reformatted line by line
  # so the existing error boxes don't break.
  exec > >(tee -a "$LOG_FILE") 2>&1
}

print_preparing() {
  echo "[INFO]  Preparing installation"
  echo ""
}

announce_and_detect_os() {
  echo "[INFO]  Detecting base system..."
  detect_os
  if [ "$OS_FAMILY" = "bsd" ]; then
    fail_bsd_unsupported
  fi
  echo "[INFO]  System detected: $OS_FAMILY${DISTRO_FAMILY:+/$DISTRO_FAMILY}"
  echo ""
}

# ── Banner ────────────────────────────────────────────────────────────────────

print_banner() {
    cat <<'BANNER'

────────────────────────────────────────────────────────────────────────────────

              ###    __     __   _    _             _ _____
        ###  ###     \ \   / /__| | _| |_ _ __ __ _| |  ___|__  _ __ __ _  ___
  ###  ###  ###       \ \ / / _ \ |/ / __| '__/ _` | | |_ / _ \| '__/ _` |/ _ \
 ###  ###  ###         \ V /  __/   <| |_| | | (_| | |  _| (_) | | | (_| |  __/
###  ###  ###           \_/ \___|_|\_\\__|_|  \__,_|_|_|  \___/|_|  \__, |\___|
                                                                    |___/

──────────────────── LAKEHOUSE OPEN SOURCE STACK - alpha v0.1 ──────────────────
BANNER

    echo ""

}

# ── OS detection ──────────────────────────────────────────────────────────────

detect_os() {
  case "$(uname -s)" in
    Linux)
      OS_FAMILY="linux"
      detect_linux_distro_family
      ;;
    Darwin)
      OS_FAMILY="macos"
      ;;
    FreeBSD|OpenBSD|NetBSD|DragonFly)
      OS_FAMILY="bsd"
      ;;
    *)
      echo ""
      _err "Unrecognized operating system ('$(uname -s)')"
      echo ""
      exit 1
      ;;
  esac
}

detect_linux_distro_family() {
  if [ ! -r /etc/os-release ]; then
    echo ""
    _err "Could not read /etc/os-release"
    echo ""
    echo "  check_deps.sh needs this file to identify the distribution and"
    echo "  pick the right package manager."
    echo ""
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  local id_all=" ${ID:-} ${ID_LIKE:-} "
  case "$id_all" in
    *" debian "*|*" ubuntu "*)              DISTRO_FAMILY="debian"; PKG_MANAGER_BIN="apt-get" ;;
    *" rhel "*|*" fedora "*|*" centos "*)   DISTRO_FAMILY="rhel";   PKG_MANAGER_BIN="dnf"     ;;
    *" arch "*)                             DISTRO_FAMILY="arch";  PKG_MANAGER_BIN="pacman"  ;;
    *" suse "*|*" opensuse "*)              DISTRO_FAMILY="suse";  PKG_MANAGER_BIN="zypper"  ;;
    *)
      echo ""
      _err "Unsupported Linux distribution (ID='${ID:-unknown}')"
      echo ""
      echo "  Supported families: Debian/Ubuntu, RHEL/Fedora/CentOS, Arch, openSUSE."
      echo "  Install manually: $REQUIRED_PYTHON_BIN (+ venv module), pip, git, make"
      echo "  and Docker, then run 'make dev-up' directly."
      echo ""
      exit 1
      ;;
  esac
}

# ── BSD: not supported ────────────────────────────────────────────────────────

fail_bsd_unsupported() {
  echo ""
  _err "$(uname -s) is not supported"
  echo ""
  echo "  VektralForge runs on Docker Compose, which depends on Linux kernel"
  echo "  namespaces and cgroups. BSD systems don't have them — FreeBSD jails"
  echo "  are not compatible with Docker images — so there is no possible"
  echo "  native installation for this stack."
  echo ""
  echo "  Alternative: spin up a Linux VM (e.g. with bhyve on FreeBSD) and run"
  echo "  this installer inside it."
  echo ""
  exit 1
}

# ── Privileges (Linux) ────────────────────────────────────────────────────────
# Only needed for the INSTALL step, not for checking — this is called only
# if the user confirms they want to install something.

require_privilege_linux() {
  if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
    return
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    IS_ROOT=0
    return
  fi
  echo ""
  _err "Privileges are required to install system dependencies"
  echo ""
  echo "  Run this script as root, or make sure sudo is available without"
  echo "  blocking on an interactive password prompt ('sudo -n true' must"
  echo "  succeed with no prompt)."
  echo ""
  exit 1
}

# ── Package manager (first dependency checked on every OS) ────────────────────
# The rest of the checks/fixes assume this is present: on macOS everything
# installable goes through Homebrew, on Linux through $PKG_MANAGER_BIN. Only
# Homebrew is auto-installable — a Linux system that's missing its own base
# package manager is broken in a way this script can't repair.

check_homebrew() {
  command -v brew >/dev/null 2>&1
}

fix_homebrew() {
  ensure_homebrew_macos
  if ! check_homebrew; then
    echo ""
    _err "Could not install Homebrew correctly"
    echo ""
    exit 1
  fi
  _ok "Homebrew installed"
}

check_pkg_manager_linux() {
  command -v "$PKG_MANAGER_BIN" >/dev/null 2>&1
}

# ── macOS: Homebrew + Xcode CLT ───────────────────────────────────────────────

ensure_homebrew_macos() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi
  _info "Homebrew not found, installing (non-interactive)..."
  if ! NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    echo ""
    _err "Could not install Homebrew automatically"
    echo ""
    echo "  Install it manually from https://brew.sh and run this script again."
    echo ""
    exit 1
  fi
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

check_xcode_clt() {
  xcode-select -p >/dev/null 2>&1
}

# ── Python 3.12 ────────────────────────────────────────────────────────────────

check_python312() {
  command -v "$REQUIRED_PYTHON_BIN" >/dev/null 2>&1 || return 1
  local ver
  ver="$("$REQUIRED_PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  [ "$ver" = "$REQUIRED_PYTHON_MAJOR_MINOR" ]
}

fix_python312() {
  case "$OS_FAMILY" in
    linux) fix_python312_linux ;;
    macos) fix_python312_macos ;;
  esac

  if ! check_python312; then
    echo ""
    _err "Could not install $REQUIRED_PYTHON_BIN correctly"
    echo ""
    exit 1
  fi
  _ok "$($REQUIRED_PYTHON_BIN --version) installed"
}

fix_python312_linux() {
  case "$DISTRO_FAMILY" in
    debian)
      _info "Installing $REQUIRED_PYTHON_BIN (apt)..."
      run_priv apt-get update -qq
      if ! apt-cache show "$REQUIRED_PYTHON_BIN" >/dev/null 2>&1; then
        _info "Not in the default repos, adding deadsnakes..."
        run_priv apt-get install -y -qq software-properties-common
        run_priv add-apt-repository -y ppa:deadsnakes/ppa
        run_priv apt-get update -qq
      fi
      run_priv apt-get install -y -qq "$REQUIRED_PYTHON_BIN" "${REQUIRED_PYTHON_BIN}-venv"
      ;;
    rhel)
      _info "Installing $REQUIRED_PYTHON_BIN (dnf)..."
      if ! run_priv dnf install -y -q "$REQUIRED_PYTHON_BIN"; then
        echo ""
        _err "dnf could not find $REQUIRED_PYTHON_BIN"
        echo ""
        echo "  On RHEL/Rocky/Alma this may require EPEL, or may not be available"
        echo "  depending on the version. Install it manually:"
        echo "    sudo dnf install epel-release && sudo dnf install $REQUIRED_PYTHON_BIN"
        echo ""
        exit 1
      fi
      ;;
    arch)
      echo ""
      _err "Arch does not offer $REQUIRED_PYTHON_BIN as a versioned package"
      echo ""
      echo "  Arch is a rolling release: 'python' always tracks the latest"
      echo "  stable version, there's no reliable way to pin 3.12 via pacman."
      echo "  Install it with pyenv or the 'python312' AUR package, then run"
      echo "  this again."
      echo ""
      exit 1
      ;;
    suse)
      _info "Installing $REQUIRED_PYTHON_BIN (zypper)..."
      if ! run_priv zypper --non-interactive install "$REQUIRED_PYTHON_BIN" "${REQUIRED_PYTHON_BIN}-venv"; then
        echo ""
        _err "zypper could not find $REQUIRED_PYTHON_BIN"
        echo ""
        exit 1
      fi
      ;;
  esac
}

fix_python312_macos() {
  ensure_homebrew_macos
  _info "Installing python@3.12 (Homebrew)..."
  brew install python@3.12
  if ! command -v "$REQUIRED_PYTHON_BIN" >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix="$(brew --prefix python@3.12 2>/dev/null || true)"
    if [ -n "$brew_prefix" ] && [ -x "$brew_prefix/bin/python3.12" ]; then
      export PATH="$brew_prefix/bin:$PATH"
    fi
  fi
}

check_venv() {
  command -v "$REQUIRED_PYTHON_BIN" >/dev/null 2>&1 || return 1
  local tmp_venv
  tmp_venv="$(mktemp -d)"
  if "$REQUIRED_PYTHON_BIN" -m venv "$tmp_venv/probe" >/dev/null 2>&1; then
    rm -rf "$tmp_venv"
    return 0
  fi
  rm -rf "$tmp_venv"
  return 1
}

fix_venv() {
  if [ "$OS_FAMILY" = "linux" ] && [ "$DISTRO_FAMILY" = "debian" ]; then
    run_priv apt-get install -y -qq "${REQUIRED_PYTHON_BIN}-venv"
  fi
  if ! check_venv; then
    echo ""
    _err "$REQUIRED_PYTHON_BIN still can't create virtual environments"
    echo ""
    exit 1
  fi
  _ok "venv module functional"
}

check_pip() {
  command -v "$REQUIRED_PYTHON_BIN" >/dev/null 2>&1 || return 1
  "$REQUIRED_PYTHON_BIN" -m pip --version >/dev/null 2>&1
}

fix_pip() {
  # Check first: on macOS, Homebrew's python@3.12 formula already bundles
  # pip as part of the bottle (its own caveats say so — pip/pip3 land next
  # to python3.12), and Homebrew deliberately strips the wheels ensurepip
  # needs to avoid shipping two competing pips. So right after fix_python312
  # installs it, pip is usually already there — running ensurepip
  # unconditionally would fail even though nothing is actually missing.
  if check_pip; then
    _ok "pip already available"
    return
  fi
  _info "Getting pip via ensurepip..."
  if ! "$REQUIRED_PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1; then
    echo ""
    _err "Could not get pip for $REQUIRED_PYTHON_BIN"
    echo ""
    exit 1
  fi
  _ok "pip installed via ensurepip"
}

# ── git ────────────────────────────────────────────────────────────────────────

check_git() {
  command -v git >/dev/null 2>&1
}

fix_git() {
  case "$OS_FAMILY" in
    linux)
      _info "Installing git..."
      case "$DISTRO_FAMILY" in
        debian) run_priv apt-get install -y -qq git ;;
        rhel)   run_priv dnf install -y -q git ;;
        arch)   run_priv pacman -Sy --noconfirm git ;;
        suse)   run_priv zypper --non-interactive install git ;;
      esac
      ;;
    macos)
      ensure_homebrew_macos
      _info "Installing git (Homebrew)..."
      brew install git
      ;;
  esac
  if ! check_git; then
    echo ""
    _err "Could not install git"
    echo ""
    exit 1
  fi
  _ok "$(git --version)"
}

# ── make, Docker (defensive check only, never installed) ───────────────────────

check_make() {
  command -v make >/dev/null 2>&1
}

DOCKER_FAIL_REASON=""

check_docker_engine() {
  if ! command -v docker >/dev/null 2>&1; then
    DOCKER_FAIL_REASON="not-installed"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    DOCKER_FAIL_REASON="daemon-not-running"
    return 1
  fi
  return 0
}

check_docker_compose() {
  docker compose version >/dev/null 2>&1
}

docker_instructions() {
  case "$DOCKER_FAIL_REASON" in
    not-installed)
      cat <<EOF
  Docker is not installed — VektralForge requires Docker Engine + Compose v2.
  This installer does NOT install it: it's a prerequisite you must have in
  place beforehand.

    Linux:  https://docs.docker.com/engine/install/
    macOS:  https://docs.docker.com/desktop/setup/install/mac-install/
            (or Colima as a lightweight alternative:
             brew install colima docker docker-compose && colima start)
EOF
      ;;
    daemon-not-running)
      cat <<EOF
  Docker is installed but the daemon isn't responding.
EOF
      case "$OS_FAMILY" in
        linux) echo "    sudo systemctl start docker" ;;
        macos) echo "    Start Docker Desktop (or 'colima start' if you use Colima)" ;;
      esac
      ;;
    no-compose-v2)
      cat <<EOF
  Docker was found, but the Compose v2 plugin is missing ('docker compose',
  not the standalone v1 'docker-compose' binary).

    Linux:  sudo apt install docker-compose-plugin   (or your distro's equivalent)
    macOS:  update Docker Desktop, or 'brew install docker-compose' with Colima
EOF
      ;;
  esac
}

# ── Result ──────────────────────────────────────────────────────────────────

resolve_and_export_python_bin() {
  PYTHON_BIN="$(command -v "$REQUIRED_PYTHON_BIN")"
  export PYTHON_BIN
  _ok "PYTHON_BIN=$PYTHON_BIN"
}

# ── Check phase: goes through EVERYTHING without installing anything ───────────

run_checks() {
  echo "[INFO]  Checking dependencies"
  echo ""

  if [ "$OS_FAMILY" = "macos" ]; then
    if check_homebrew; then
      _ok "Homebrew"
    else
      _bad "Homebrew"
      MISSING_INSTALLABLE+=("homebrew")
    fi
  else
    if check_pkg_manager_linux; then
      _ok "$PKG_MANAGER_BIN"
    else
      _bad "$PKG_MANAGER_BIN"
      MISSING_MANUAL+=("pkg-manager")
      MANUAL_INSTRUCTIONS+=("  The package manager expected for this distribution ('$PKG_MANAGER_BIN')
  was not found. This usually means an unusual or broken base image —
  check_deps.sh cannot repair a missing package manager. Reinstall it, or
  start from a standard $DISTRO_FAMILY-family base image, then run this
  script again.")
    fi
  fi

  if check_python312; then
    _ok "$($REQUIRED_PYTHON_BIN --version)"
  else
    _bad "$REQUIRED_PYTHON_BIN (not found, or a version other than $REQUIRED_PYTHON_MAJOR_MINOR)"
    MISSING_INSTALLABLE+=("python3.12")
  fi

  if check_venv; then
    _ok "venv module"
  else
    _bad "venv module"
    MISSING_INSTALLABLE+=("venv")
  fi

  if check_pip; then
    _ok "pip"
  else
    _bad "pip"
    MISSING_INSTALLABLE+=("pip")
  fi

  if check_git; then
    _ok "$(git --version)"
  else
    _bad "git"
    MISSING_INSTALLABLE+=("git")
  fi

  if check_make; then
    _ok "$(make --version | head -1)"
  else
    _bad "make"
    MISSING_MANUAL+=("make")
    MANUAL_INSTRUCTIONS+=("  'make' is not installed and this script does not install it.
    Debian/Ubuntu: sudo apt install make
    macOS:         brew install make   (or install Xcode CLT)")
  fi

  if [ "$OS_FAMILY" = "macos" ]; then
    if check_xcode_clt; then
      _ok "Xcode Command Line Tools"
    else
      _bad "Xcode Command Line Tools"
      MISSING_MANUAL+=("xcode-clt")
      MANUAL_INSTRUCTIONS+=("  Xcode Command Line Tools are missing — this is the only macOS step
  that isn't automated (installing it unattended relies on fragile tricks
  that vary across macOS versions). Install it like this:
    xcode-select --install
  Accept the dialog, then run this script again.")
    fi
  fi

  if check_docker_engine; then
    _ok "docker ($(docker --version))"
    if check_docker_compose; then
      _ok "docker compose ($(docker compose version --short 2>/dev/null || echo present))"
    else
      _bad "docker compose"
      DOCKER_FAIL_REASON="no-compose-v2"
      MISSING_MANUAL+=("docker")
      MANUAL_INSTRUCTIONS+=("$(docker_instructions)")
    fi
  else
    _bad "docker ($DOCKER_FAIL_REASON)"
    _bad "docker compose"
    MISSING_MANUAL+=("docker")
    MANUAL_INSTRUCTIONS+=("$(docker_instructions)")
  fi

  echo ""
}

# ── Report + confirmation phase ─────────────────────────────────────────────────

report_and_confirm() {
  if [ "${#MISSING_INSTALLABLE[@]}" -eq 0 ] && [ "${#MISSING_MANUAL[@]}" -eq 0 ]; then
    return 0
  fi

  local -a table_rows=()
  local dep
  for dep in "${MISSING_INSTALLABLE[@]+"${MISSING_INSTALLABLE[@]}"}"; do
    table_rows+=("$dep" "Will be installed automatically")
  done
  for dep in "${MISSING_MANUAL[@]+"${MISSING_MANUAL[@]}"}"; do
    table_rows+=("$dep" "Manual installation required (see instructions below)")
  done
  print_summary_table "Missing dependencies" "${table_rows[@]+"${table_rows[@]}"}"
  echo ""

  if [ "${#MISSING_MANUAL[@]}" -gt 0 ]; then
    echo "[WARN]  These require manual action — they are not installed automatically:"
    echo ""
    local msg
    for msg in "${MANUAL_INSTRUCTIONS[@]+"${MANUAL_INSTRUCTIONS[@]}"}"; do
      echo "$msg"
      echo ""
    done
  fi

  if [ "${#MISSING_INSTALLABLE[@]}" -eq 0 ]; then
    # Only manual ones are missing: nothing to offer to install, stop here.
    exit 1
  fi

  if [ ! -t 0 ]; then
    echo ""
    _err "An interactive terminal is required to confirm the installation"
    echo ""
    echo "  Run this script in an interactive terminal, or install manually:"
    echo "    ${MISSING_INSTALLABLE[*]}"
    echo ""
    exit 1
  fi

  local reply
  read -r -p "[INFO]  Proceed with installing the missing dependencies? [y/N] " reply
  echo ""
  case "$reply" in
    y|Y|yes|Yes|YES) ;;
    *)
      echo "[INFO]  Installation cancelled. No changes were made to the system."
      echo ""
      exit 1
      ;;
  esac

  if [ "$OS_FAMILY" = "linux" ]; then
    require_privilege_linux
  fi

  install_missing

  if [ "${#MISSING_MANUAL[@]}" -gt 0 ]; then
    # The installable ones are resolved now, but we still can't continue
    # while something manual (typically Docker) is missing.
    exit 1
  fi
}

install_missing() {
  local dep
  for dep in "${MISSING_INSTALLABLE[@]+"${MISSING_INSTALLABLE[@]}"}"; do
    case "$dep" in
      homebrew)   fix_homebrew ;;
      python3.12) fix_python312 ;;
      venv)       fix_venv ;;
      pip)        fix_pip ;;
      git)        fix_git ;;
    esac
  done
  echo ""
}

main() {
  setup_logging           # 0. invisible: from here on, everything is mirrored to the log too
  print_banner            # 1. banner
  print_preparing          # 2. "Preparing installation"
  announce_and_detect_os   # 3. "detecting base system..." (stops here if BSD)
  run_checks                # 4-5. "checking dependencies" + OK/MISSING for each
  report_and_confirm       # 6-8. summary box + manual instructions, asks, installs on yes (or aborts on no)

  resolve_and_export_python_bin

  echo "[INFO]  Dependencies ok 😄"
  echo ""
}

# Run directly (bash check_deps.sh): runs main and exits with its exit code.
# Imported via `source`: only defines functions/variables, whoever imports it
# decides when to call main() — so it's ready to be integrated into setup.sh
# later without changing anything in this file.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main
fi
