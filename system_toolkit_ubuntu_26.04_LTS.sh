#!/usr/bin/env bash
# SYSTEM_TOOLKIT_SEVERITY_V3
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    ST_GREEN=$'\033[32m'; ST_YELLOW=$'\033[33m'; ST_RED=$'\033[31m'
    ST_CYAN=$'\033[36m'; ST_RESET=$'\033[0m'
else
    ST_GREEN=''; ST_YELLOW=''; ST_RED=''; ST_CYAN=''; ST_RESET=''
fi
ST_GREEN_COUNT=0; ST_YELLOW_COUNT=0; ST_RED_COUNT=0
st_green()  { ((ST_GREEN_COUNT++)) || true; printf '%b[GREEN]%b %s\n' "$ST_GREEN" "$ST_RESET" "$*"; }
st_yellow() { ((ST_YELLOW_COUNT++)) || true; printf '%b[YELLOW]%b %s\n' "$ST_YELLOW" "$ST_RESET" "$*"; }
st_red()    { ((ST_RED_COUNT++)) || true; printf '%b[RED]%b %s\n' "$ST_RED" "$ST_RESET" "$*"; }
st_info()   { printf '%b[INFO]%b %s\n' "$ST_CYAN" "$ST_RESET" "$*"; }
st_summary() {
    local label="HEALTHY" c="$ST_GREEN"
    if (( ST_RED_COUNT > 0 )); then label="CRITICAL / NEEDS ATTENTION"; c="$ST_RED"
    elif (( ST_YELLOW_COUNT > 0 )); then label="HEALTHY WITH WARNINGS"; c="$ST_YELLOW"; fi
    echo
    printf '%b==================================================%b\n' "$ST_CYAN" "$ST_RESET"
    printf '%bSYSTEM HEALTH SUMMARY%b\n' "$ST_CYAN" "$ST_RESET"
    printf '%b==================================================%b\n' "$ST_CYAN" "$ST_RESET"
    printf '%bGREEN%b   %d\n' "$ST_GREEN" "$ST_RESET" "$ST_GREEN_COUNT"
    printf '%bYELLOW%b  %d\n' "$ST_YELLOW" "$ST_RESET" "$ST_YELLOW_COUNT"
    printf '%bRED%b     %d\n' "$ST_RED" "$ST_RESET" "$ST_RED_COUNT"
    printf '\nOverall: %b%s%b\n' "$c" "$label" "$ST_RESET"
    printf '%b==================================================%b\n' "$ST_CYAN" "$ST_RESET"
}

st_green() { ((ST_GREEN_COUNT++)) || true; printf '%b[GREEN]%b %s\n' "$ST_GREEN" "$ST_RESET" "$*"; }
st_yellow() { ((ST_YELLOW_COUNT++)) || true; printf '%b[YELLOW]%b %s\n' "$ST_YELLOW" "$ST_RESET" "$*"; }
st_red() { ((ST_RED_COUNT++)) || true; printf '%b[RED]%b %s\n' "$ST_RED" "$ST_RESET" "$*"; }

st_summary() {
    local label="HEALTHY" c="$ST_GREEN"
    if ((ST_RED_COUNT > 0 )); then
        label="CRITICAL / NEEDS ATTENTION"; c="$ST_RED"
    elif ((ST_YELLOW_COUNT > 0 )); then
        label="HEALTHY WITH WARNINGS"; c="$ST_YELLOW"
    fi
    echo
    printf '%b==================================================%b\n' "$ST_CYAN" "$ST_RESET"
    printf '%bSYSTEM HEALTH SUMMARY%b\n' "$ST_CYAN" "$ST_RESET"
    printf '%b==================================================%b\n' "$ST_CYAN" "$ST_RESET"
    printf '%bGREEN%b   %d\n' "$ST_GREEN" "$ST_RESET" "$ST_GREEN_COUNT"
    printf '%bYELLOW%b  %d\n' "$ST_YELLOW" "$ST_RESET" "$ST_YELLOW_COUNT"
    printf '%bRED%b     %d\n' "$ST_RED" "$ST_RESET" "$ST_RED_COUNT"
    printf '\nOverall: %b%s%b\n' "$c" "$label" "$ST_RESET"
    printf '%b==================================================%b\n' "$ST_CYAN" "$ST_RESET"
}

 #
# System Toolkit — Ubuntu 26.04 LTS
# Maintenance, package-source inventory, updates, audit and optional deep scan.
#
# Design goals:
#   - Safe defaults: no automatic hardening, no blind third-party installation.
#   - Understand where installed software came from.
#   - Update the package managers that are actually present.
#   - Keep dry-run genuinely non-destructive.
#
# Supported package sources:
#   APT/dpkg, Snap, Flatpak
#
# Inventory-only sources:
#   pip/pipx/npm/cargo and locally installed .deb packages are reported when
#   their tools are present, but are NOT automatically upgraded.
#
# Tested conceptually for Ubuntu 26.04 LTS (Resolute Raccoon).
#

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
VERSION="2.3"

MODE=""
DRY_RUN=false
FULL_UPGRADE=false
ASSUME_YES=false
DEEP_AFTER_MAINTAIN=false
LOG_FILE=""
APT_UPDATED=false

# -----------------------------
# OUTPUT / HELP
# -----------------------------

show_help() {
    cat <<EOF

System Toolkit ${VERSION} — Ubuntu 26.04 LTS

USAGE:
  ./${SCRIPT_NAME} [MODE] [OPTIONS]

MODES:
  --maintain
      Update APT/dpkg, Snap and Flatpak.
      Clean safe-to-remove packages/cache.
      Report package sources and reboot status.

  --audit
      Read-only system/security audit.
      Includes firewall, SSH, AppArmor, users, listening ports,
      package health, held packages, repositories and package origins.

  --sources
      Read-only package-source inventory.
      Shows APT repositories and where installed packages come from,
      plus Snap/Flatpak and other package ecosystems when present.

  --deep-scan
      Optional rkhunter/chkrootkit/debsums checks.
      Does not install missing tools.

  --maintain --deep-scan
      Run maintenance followed by deep scan.

OPTIONS:
  --dry-run
      Do not change the system. Shows source classification and simulated package transactions.

  --full-upgrade
      Use apt full-upgrade instead of the conservative apt upgrade.
      This may install/remove packages to resolve dependencies.

  --yes
      Non-interactive confirmation for supported maintenance operations.

  --help
      Show this help.

EXAMPLES:
  ./${SCRIPT_NAME} --maintain
  ./${SCRIPT_NAME} --maintain --dry-run
  ./${SCRIPT_NAME} --maintain --full-upgrade
  ./${SCRIPT_NAME} --sources
  ./${SCRIPT_NAME} --audit
  ./${SCRIPT_NAME} --deep-scan

NOTES:
  - Third-party APT repositories are not disabled or modified automatically.
  - Packages from PPAs/vendor repositories are updated by APT when their
    repository is enabled and has a newer candidate version.
  - pip, npm, cargo, etc. are inventory-only by design because blindly
    upgrading them can break development environments.
  - A warning is a finding to investigate, not proof of compromise.

EOF
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

log_section() {
    printf '\n=== %s ===\n' "$1"
}

ok() {
    printf '[OK] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
}

check() {
    printf '[CHECK] %s\n' "$1"
}

info() {
    printf '[INFO] %s\n' "$1"
}

run_cmd() {
    if "$DRY_RUN"; then
        printf '[DRY-RUN]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    # Keep normal console output concise. Full command output is retained in
    # the run log; failed commands are echoed to the console as well.
    local output rc
    set +e
    output="$($@ 2>&1)"
    rc=$?
    set -e

    if [[ -n "${LOG_FILE:-}" ]]; then
        printf '%s\n' "$output" >> "$LOG_FILE"
    fi

    if (( rc != 0 )); then
        printf '%s\n' "$output"
        return "$rc"
    fi
    return 0
}

need_root() {
    if [[ "$EUID" -eq 0 ]]; then
        SUDO=()
        return
    fi
    SUDO=(sudo)
    if ! sudo -v; then
        die "sudo authentication failed."
    fi
}

# -----------------------------
# ERROR HANDLING
# -----------------------------

on_error() {
    local exit_code=$?
    printf '\n[ERROR] Command failed (exit %s) near line %s.\n' \
        "$exit_code" "${BASH_LINENO[0]}" >&2
    if [[ -n "$LOG_FILE" ]]; then
        printf '[ERROR] Log: %s\n' "$LOG_FILE" >&2
    fi
    exit "$exit_code"
}
trap on_error ERR

# -----------------------------
# ARGUMENT PARSING
# -----------------------------

parse_args() {
    while (($#)); do
        case "$1" in
            --maintain|--audit|--sources|--deep-scan)
                if [[ -z "$MODE" ]]; then
                    MODE="$1"
                elif [[ "$MODE" == "--maintain" && "$1" == "--deep-scan" ]]; then
                    DEEP_AFTER_MAINTAIN=true
                else
                    die "Choose one primary mode. Only --maintain --deep-scan is a valid combination."
                fi
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --full-upgrade)
                FULL_UPGRADE=true
                ;;
            --yes|-y)
                ASSUME_YES=true
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                die "Unknown option: $1 (use --help)"
                ;;
        esac
        shift
    done
}

# -----------------------------
# UBUNTU CHECK
# -----------------------------

check_platform() {
    [[ -r /etc/os-release ]] || die "/etc/os-release not found."

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        warn "This toolkit is designed for Ubuntu; detected ID=${ID:-unknown}."
    fi

    if [[ "${VERSION_ID:-}" != "26.04" ]]; then
        warn "This version targets Ubuntu 26.04 LTS; detected ${PRETTY_NAME:-unknown}."
    else
        ok "Ubuntu 26.04 LTS detected (${VERSION_CODENAME:-resolute})."
    fi
}

# -----------------------------
# LOGGING
# -----------------------------

start_logging() {
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/system-toolkit"
    mkdir -p "$state_dir"
    LOG_FILE="${state_dir}/run-$(date '+%Y%m%d-%H%M%S').log"

    # Best effort: do not make the toolkit fail just because logging cannot
    # be initialized.
    if ! exec > >(tee -a "$LOG_FILE") 2>&1; then
        LOG_FILE=""
    fi

    info "Log: ${LOG_FILE:-disabled}"
}

# -----------------------------
# APT HELPERS
# -----------------------------

apt_available() {
    command -v apt-get >/dev/null 2>&1 &&
    command -v dpkg >/dev/null 2>&1
}

apt_update() {
    log_section "APT UPDATE"

    if "$DRY_RUN"; then
        info "Dry-run: apt package indexes are not refreshed because apt update changes local state."
        info "Run without --dry-run to refresh repository metadata."
        return 0
    fi

    run_cmd "${SUDO[@]}" apt-get update
    APT_UPDATED=true
}

apt_upgradable_count() {
    # apt list emits a warning on stderr; suppress it.
    apt list --upgradable 2>/dev/null |
        awk 'NR > 1 && $0 ~ /\[upgradable from:/ {n++} END {print n+0}'
}

apt_upgrade() {
    log_section "APT / DPKG MAINTENANCE"

    apt_available || {
        warn "APT/dpkg not available — skipping."
        return
    }

    apt_update

    local count
    count="$(apt_upgradable_count || echo 0)"
    info "Upgradable APT packages: $count"

    if (( count == 0 )); then
        ok "APT packages are already up to date."
    else
        if "$FULL_UPGRADE"; then
            info "Running conservative policy override: apt full-upgrade requested."
            run_cmd "${SUDO[@]}" apt-get full-upgrade ${ASSUME_YES:+-y}
        else
            run_cmd "${SUDO[@]}" apt-get upgrade ${ASSUME_YES:+-y}
        fi
    fi

    log_section "APT CLEANUP"

    # These are intentionally conservative.
    run_cmd "${SUDO[@]}" apt-get autoremove ${ASSUME_YES:+-y}
    run_cmd "${SUDO[@]}" apt-get autoclean

    # Purge obsolete dpkg configuration-only packages.
    local rc_packages
    rc_packages="$(dpkg-query -W -f='${binary:Package} ${Status}\n' 2>/dev/null |
        awk '$2=="ok" && $3=="installed" && $4=="rc" {print $1}')"

    if [[ -n "$rc_packages" ]]; then
        info "Purging obsolete configuration-only packages:"
        printf '%s\n' "$rc_packages"
        if "$DRY_RUN"; then
            printf '[DRY-RUN] %q apt-get purge %s\n' \
                "${SUDO[*]}" "$rc_packages"
        else
            # dpkg package names are generated locally, not interpreted as shell code.
            mapfile -t rc_array < <(printf '%s\n' "$rc_packages")
            ((${#rc_array[@]})) && run_cmd "${SUDO[@]}" dpkg --purge "${rc_array[@]}"
        fi
    else
        ok "No obsolete dpkg configuration-only packages."
    fi
}

# -----------------------------
# APT SOURCE INVENTORY
# -----------------------------

show_apt_sources() {
    log_section "APT REPOSITORIES"

    if ! command -v apt-get >/dev/null 2>&1; then
        check "APT not installed."
        return
    fi

    local source_files=()
    while IFS= read -r -d '' f; do
        source_files+=("$f")
    done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \
        \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null || true)

    if [[ -f /etc/apt/sources.list ]]; then
        source_files=("/etc/apt/sources.list" "${source_files[@]}")
    fi

    if ((${#source_files[@]} == 0)); then
        warn "No traditional APT source files found."
    else
        for f in "${source_files[@]}"; do
            echo "--- $f"
            # Show enabled entries only; comments/blank lines are not useful here.
            awk '
                BEGIN { IGNORECASE=1 }
                /^[[:space:]]*#/ { next }
                /^[[:space:]]*$/ { next }
                /^[[:space:]]*Types:/ { print }
                /^[[:space:]]*URIs?:/ { print }
                /^[[:space:]]*Suites:/ { print }
                /^[[:space:]]*Components:/ { print }
                /^[[:space:]]*Enabled:[[:space:]]*(no|false)/ { print }
                /^[[:space:]]*deb([[:space:]])/ { print }
                /^[[:space:]]*deb-src([[:space:]])/ { print }
            ' "$f" 2>/dev/null || true
        done
    fi

    if [[ -d /etc/apt/preferences.d ]]; then
        local pins
        pins="$(find /etc/apt/preferences.d -maxdepth 1 -type f -print 2>/dev/null | sort || true)"
        if [[ -n "$pins" ]]; then
            echo
            info "APT pinning/preferences files:"
            printf '%s\n' "$pins"
        fi
    fi

    if command -v add-apt-repository >/dev/null 2>&1; then
        echo
        info "Potential PPA/vendor repositories can also be identified from the source files above."
    fi
}

# Get the candidate source for a package. This deliberately uses APT's own
# resolver rather than guessing from filenames.
apt_package_origin() {
    local pkg="$1"
    local output
    output="$(apt-cache policy "$pkg" 2>/dev/null || true)"

    # Prefer an actual repository line (contains a URI and "Packages").
    local origin
    origin="$(printf '%s\n' "$output" |
        awk '
            /[0-9]+ (http|https|file):\/\// && /Packages$/ {
                sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
                print
                exit
            }
        ')"

    if [[ -n "$origin" ]]; then
        printf '%s\n' "$origin"
    else
        # No current candidate can mean locally installed, obsolete,
        # disabled repository, or package not available in current indexes.
        printf '%s\n' "NO-CURRENT-CANDIDATE"
    fi
}

# Classify repositories using the actual APT candidate URI.
# This is intentionally conservative: a repository is only considered a
# "trusted vendor" when its hostname is explicitly recognized here.
classify_origin() {
    local origin="$1"
    case "$origin" in
        *archive.ubuntu.com*|*security.ubuntu.com*|*ports.ubuntu.com*|*old-releases.ubuntu.com*|*ubuntu.com/ubuntu*)
            printf 'Ubuntu official'
            ;;
        *launchpad.net*|ppa:*)
            printf 'PPA / Launchpad'
            ;;
        *brave-browser-apt-release.s3.brave.com*)
            printf 'Trusted vendor'
            ;;
        *pkgs.tailscale.com*)
            printf 'Trusted vendor'
            ;;
        *mega.nz*)
            printf 'Trusted vendor'
            ;;
        NO-CURRENT-CANDIDATE)
            printf 'No current candidate'
            ;;
        *)
            printf 'Unknown third-party'
            ;;
    esac
}

origin_host() {
    local origin="$1"
    if [[ "$origin" =~ ^https?://([^/[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ "$origin" =~ ^[[:alnum:]][[:alnum:]._-]*://([^/[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' "-"
    fi
}

apt_installed_version() {
    local pkg="$1"
    dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null || printf '%s\n' "-"
}

apt_candidate_version() {
    local pkg="$1"
    apt-cache policy "$pkg" 2>/dev/null |
        awk '/Candidate:/ {print $2; exit}'
}

apt_package_details() {
    local pkg="$1"
    local origin="$2"
    local class="$3"
    local installed candidate host

    installed="$(apt_installed_version "$pkg")"
    candidate="$(apt_candidate_version "$pkg")"
    host="$(origin_host "$origin")"

    printf '  Installed: %s\n' "$installed"
    printf '  Candidate: %s\n' "${candidate:--}"
    printf '  Repository: %s\n' "$host"
    printf '  Classification: %s\n' "$class"

    if [[ -n "$candidate" && "$candidate" != "(none)" && "$installed" != "-" ]]; then
        if dpkg --compare-versions "$candidate" gt "$installed"; then
            printf '  Upgrade: YES\n'
        else
            printf '  Upgrade: NO\n'
        fi
    else
        printf '  Upgrade: UNKNOWN\n'
    fi

    # Show the repository metadata/signing configuration that applies to the
    # source line. We do not alter keys or repository configuration.
    local source_refs
    source_refs="$(grep -RhsE \
        "^[[:space:]]*(deb|Types:|URIs:|Suites:|Components:|Signed-By:)" \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null |
        grep -F "$host" || true)"

    if [[ -n "$source_refs" ]]; then
        echo "  Source configuration:"
        printf '%s\n' "$source_refs" | sed 's/^/    /'
    fi
}

trusted_vendor_packages() {
    local package="$1"
    case "$package" in
        brave-browser)
            printf 'Brave Software\n'
            ;;
        megasync)
            printf 'MEGA\n'
            ;;
        tailscale|tailscale-archive-keyring)
            printf 'Tailscale\n'
            ;;
        *)
            printf 'Unknown\n'
            ;;
    esac
}

show_installed_apt_origins() {
    log_section "INSTALLED APT PACKAGE ORIGINS"

    apt_available || {
        check "APT/dpkg not available."
        return
    }

    info "Checking manually installed packages and their current APT candidates."
    info "Candidate origin is determined by APT's current resolver."

    mapfile -t manual_packages < <(
        apt-mark showmanual 2>/dev/null | sed '/^$/d' | sort -u
    )

    if ((${#manual_packages[@]} == 0)); then
        check "No manually installed APT packages found."
        return
    fi

    local ubuntu=0 trusted=0 ppa=0 unknown=0 none=0
    local pkg origin class installed candidate host vendor
    local -a vendor_packages=()
    local -a unknown_packages=()
    local -a ppa_packages=()
    local -a no_candidate_packages=()

    printf '%-38s %-22s %s\n' "PACKAGE" "CLASS" "CURRENT CANDIDATE"
    printf '%-38s %-22s %s\n' "-------" "-----" "------------------"

    for pkg in "${manual_packages[@]}"; do
        origin="$(apt_package_origin "$pkg")"
        class="$(classify_origin "$origin")"
        printf '%-38s %-22s %s\n' "$pkg" "$class" "$origin"

        case "$class" in
            "Ubuntu official") ubuntu=$((ubuntu + 1)) || true ;;
            "Trusted vendor") ((trusted++)) || true; vendor_packages+=("$pkg|$origin") ;;
            "PPA / Launchpad") ppa=$((ppa + 1)) || true; ppa_packages+=("$pkg|$origin") ;;
            "Unknown third-party") unknown=$((unknown + 1)) || true; unknown_packages+=("$pkg|$origin") ;;
            "No current candidate") ((none++)) || true; no_candidate_packages+=("$pkg|$origin") ;;
        esac
    done

    echo
    info "Origin summary:"
    printf '  Ubuntu official:       %d\n' "$ubuntu"
    printf '  Trusted vendor:        %d\n' "$trusted"
    printf '  PPA / Launchpad:       %d\n' "$ppa"
    printf '  Unknown third-party:   %d\n' "$unknown"
    printf '  No current candidate:  %d\n' "$none"

    if ((${#vendor_packages[@]})); then
        echo
        log_section "TRUSTED VENDOR PACKAGE DETAILS"
        local entry
        for entry in "${vendor_packages[@]}"; do
            IFS='|' read -r pkg origin <<< "$entry"
            installed="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo '-')"
            candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
            host="$origin"
            echo "--- $pkg"
            printf '  Installed: %s\n' "$installed"
            printf '  Candidate: %s\n' "${candidate:--}"
            printf '  Repository: %s\n' "$host"
            printf '  Classification: Trusted vendor\n'
            if [[ -n "$candidate" && "$candidate" != "(none)" && "$installed" != "-" ]]; then
                if dpkg --compare-versions "$candidate" gt "$installed"; then
                    echo "  Upgrade: YES"
                else
                    echo "  Upgrade: NO"
                fi
            else
                echo "  Upgrade: UNKNOWN"
            fi
            echo "  Source configuration:"
            grep -RhsE '^[[:space:]]*(deb|Types:|URIs:|Suites:|Components:|Signed-By:)' \
                /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null |
                grep -F "$host" | sed 's/^/    /' || true
            echo
        done
    fi

    if ((${#ppa_packages[@]})); then
        echo
        warn "PPA / Launchpad packages:"
        printf '  %s\n' "${ppa_packages[@]}"
        echo "Review whether each PPA is still required and maintained."
    fi

    if ((${#unknown_packages[@]})); then
        echo
        warn "UNKNOWN THIRD-PARTY PACKAGES:"
        printf '  %s\n' "${unknown_packages[@]}"
        echo "Do not automatically trust unknown repositories."
    fi

    if ((${#no_candidate_packages[@]})); then
        echo
        warn "PACKAGES WITH NO CURRENT APT CANDIDATE:"
        printf '  %s\n' "${no_candidate_packages[@]}"
        echo "These may be local, obsolete, or from disabled repositories."
    fi

    if ((unknown == 0 && ppa == 0 && none == 0)); then
        ok "No unknown package sources detected."
    fi
}

show_held_packages() {
    log_section "HELD APT PACKAGES"

    local held
    held="$(apt-mark showhold 2>/dev/null || true)"

    if [[ -n "$held" ]]; then
        warn "Held packages will not normally be upgraded:"
        printf '%s\n' "$held"
    else
        ok "No APT packages are held."
    fi
}

# -----------------------------
# SNAP
# -----------------------------

snap_maintain() {
    log_section "SNAP MAINTENANCE"

    if ! command -v snap >/dev/null 2>&1; then
        st_info "Snap not installed — skipping."
        return 0
    fi

    local refresh_list updates
    refresh_list="$(snap refresh --list 2>/dev/null || true)"
    updates="$(printf '%s\n' "$refresh_list" | awk 'NR > 1 && NF {count++} END {print count+0}')"

    if (( updates == 0 )); then
        st_green "Snap: no updates available."
        return 0
    fi

    st_info "Snap updates available: $updates"

    if "$DRY_RUN"; then
        st_info "DRY-RUN: snap refresh would update the listed snaps."
        printf '%s\n' "$refresh_list"
    else
        run_cmd "${SUDO[@]}" snap refresh
    fi
}


show_snap_sources() {
    log_section "SNAP SOURCES / CHANNELS"

    command -v snap >/dev/null 2>&1 || {
        check "snap not installed."
        return
    }

    snap list 2>/dev/null | awk '
        NR==1 {print "NAME\tVERSION\tREV\tTRACK\tPUBLISHER"; next}
        {print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $6}
    ' || true

    echo
    info "Snap refresh policy:"
    snap get system refresh.timer 2>/dev/null || true
}

# -----------------------------
# FLATPAK
# -----------------------------

flatpak_maintain() {
    log_section "FLATPAK"

    command -v flatpak >/dev/null 2>&1 || {
        check "Flatpak not installed — skipping."
        return
    }

    echo "Configured Flatpak remotes:"
    flatpak remotes --show-details 2>/dev/null || true

    echo
    info "Installed Flatpaks:"
    flatpak list --app --columns=application,version,installation,origin 2>/dev/null || true

    echo
    info "Updating Flatpak applications and runtimes:"
    run_cmd flatpak update ${ASSUME_YES:+-y}

    echo
    info "Removing unused Flatpak runtimes:"
    run_cmd flatpak uninstall --unused ${ASSUME_YES:+-y}
}

show_flatpak_sources() {
    log_section "FLATPAK SOURCES"

    command -v flatpak >/dev/null 2>&1 || {
        check "Flatpak not installed."
        return
    }

    flatpak remotes --show-details 2>/dev/null || check "No Flatpak remotes found."

    echo
    flatpak list --app --columns=application,version,branch,origin,installation 2>/dev/null || true
}

# -----------------------------
# OTHER PACKAGE ECOSYSTEMS
# -----------------------------

show_other_package_sources() {
    log_section "OTHER PACKAGE ECOSYSTEMS (INVENTORY ONLY)"

    local found=false

    if command -v pipx >/dev/null 2>&1; then
        found=true
        echo "--- pipx"
        pipx list 2>/dev/null || true
        info "pipx is inventory-only; upgrade individual environments deliberately."
    fi

    if command -v python3 >/dev/null 2>&1; then
        found=true
        echo "--- Python user packages"
        python3 -m pip list --user 2>/dev/null || true
        info "Python/pip packages are inventory-only."
    fi

    if command -v npm >/dev/null 2>&1; then
        found=true
        echo "--- npm global packages"
        npm list -g --depth=0 2>/dev/null || true
        info "npm globals are inventory-only."
    fi

    if command -v cargo >/dev/null 2>&1; then
        found=true
        echo "--- Cargo-installed binaries"
        cargo install --list 2>/dev/null || true
        info "Cargo packages are inventory-only."
    fi

    if command -v brew >/dev/null 2>&1; then
        found=true
        echo "--- Homebrew"
        brew list --versions 2>/dev/null || true
        info "Homebrew is inventory-only."
    fi

    if ! "$found"; then
        check "No additional package ecosystems detected."
    fi

    echo
    info "Reason: automatic cross-ecosystem upgrades can break virtual environments, development tools or user-installed applications."
}

# -----------------------------
# SOURCE REPORT
# -----------------------------

sources() {
    log_section "PACKAGE SOURCE INVENTORY"
    show_apt_sources
    show_installed_apt_origins
    show_held_packages
    show_snap_sources
    show_flatpak_sources
    show_other_package_sources

    log_section "LOCAL / MANUALLY INSTALLED DEBS"

    local local_debs=""
    if command -v apt-cache >/dev/null 2>&1; then
        # Show packages whose installed version has no repository candidate.
        # This catches many local/vendor installs without trying to reverse-engineer
        # the original .deb filename.
        info "Packages with no current APT candidate can be local/vendor/obsolete:"
        dpkg-query -W -f='${binary:Package}\n' 2>/dev/null |
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] || continue
                if [[ "$(apt_package_origin "$pkg")" == "NO-CURRENT-CANDIDATE" ]]; then
                    printf '%s\n' "$pkg"
                fi
            done
    fi

    [[ -n "$local_debs" ]] || true
}

# -----------------------------
# SECURITY / SYSTEM AUDIT
# -----------------------------

audit_ufw() {
    log_section "FIREWALL HEALTH"

    if ! command -v ufw >/dev/null 2>&1; then
        st_yellow "UFW: not installed."
        return 0
    fi

    local ufw_status ufw_defaults
    ufw_status="$(sudo ufw status 2>/dev/null | head -n1 || true)"

    if [[ "$ufw_status" != "Status: active" ]]; then
        st_yellow "UFW: installed but inactive."
        return 0
    fi

    st_green "UFW: active."

    ufw_defaults="$(sudo ufw status verbose 2>/dev/null |
        awk -F': ' '/Default:/{print $2}' || true)"

    if grep -q "deny (incoming)" <<< "$ufw_defaults"; then
        st_green "UFW default incoming policy: deny."
    else
        st_red "UFW default incoming policy is not deny."
    fi

    if grep -q "allow (outgoing)" <<< "$ufw_defaults"; then
        st_green "UFW default outgoing policy: allow."
    else
        st_yellow "UFW default outgoing policy is not allow."
    fi

    # Deliberately conservative: flag only a truly unrestricted inbound
    # ALLOW rule, not normal rules such as SSH restricted to a subnet.
    if sudo ufw status 2>/dev/null |
        grep -qE '(^|[[:space:]])ALLOW[[:space:]]+IN[[:space:]]+Anywhere([[:space:]]|$)'; then
        st_red "UFW: unrestricted incoming ALLOW rule detected."
    else
        st_green "UFW: no unrestricted incoming ALLOW rule detected."
    fi
}


audit_firewall() {
    audit_ufw
}


audit_ssh() {
    log_section "SSH"

    if ! systemctl list-unit-files ssh.service sshd.service 2>/dev/null |
        grep -Eq '^(ssh|sshd)\.service'; then
        check "No SSH service unit detected."
        return
    fi

    if systemctl is-active --quiet ssh 2>/dev/null ||
       systemctl is-active --quiet sshd 2>/dev/null; then
        warn "SSH service is running."

        if command -v sshd >/dev/null 2>&1; then
            local password_auth permit_root
            password_auth="$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2; exit}')"
            permit_root="$(sshd -T 2>/dev/null | awk '$1=="permitrootlogin"{print $2; exit}')"

            case "$password_auth" in
                yes) warn "Effective SSH PasswordAuthentication=yes." ;;
                no) ok "Effective SSH PasswordAuthentication=no." ;;
                *) check "Could not determine effective PasswordAuthentication." ;;
            esac

            case "$permit_root" in
                yes) warn "Effective SSH PermitRootLogin=yes." ;;
                prohibit-password|forced-commands-only|no)
                    ok "Effective SSH root login policy: $permit_root."
                    ;;
                *) check "Could not determine effective PermitRootLogin." ;;
            esac
        fi
    else
        ok "SSH service is not running."
    fi
}

audit_network_exposure() {
    log_section "NETWORK EXPOSURE"

    if ! command -v ss >/dev/null 2>&1; then
        st_yellow "ss command not available; network exposure analysis skipped."
        return 0
    fi

    local ufw_active=false ufw_rules="" line local_addr port proto service
    local exposure_count=0 blocked_count=0 allowed_count=0 loopback_count=0 multicast_count=0
    declare -A seen=()

    if command -v ufw >/dev/null 2>&1 && [[ "$(sudo ufw status 2>/dev/null | head -n1 || true)" == "Status: active" ]]; then
        ufw_active=true
        ufw_rules="$(sudo ufw status 2>/dev/null || true)"
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        proto="${line%% *}"
        [[ "$proto" == "tcp" || "$proto" == "udp" ]] || continue
        local_addr="$(awk '{print $5}' <<< "$line")"
        [[ -n "$local_addr" ]] || continue

        if [[ "$local_addr" =~ ^(127\.0\.0\.1|127\.0\.0\.54|127\.0\.0\.53|::1|\[::1\])(:|$) ]]; then
            ((loopback_count++)) || true
            continue
        fi
        if [[ "$local_addr" =~ ^(224\.0\.0\.251|ff02::fb|\[ff02::fb\])(:|$) ]]; then
            ((multicast_count++)) || true
            continue
        fi

        if [[ "$local_addr" =~ ^0\.0\.0\.0:([0-9]+)$ ]]; then
            port="${BASH_REMATCH[1]}"
        elif [[ "$local_addr" =~ ^\[::\]:([0-9]+)$ ]]; then
            port="${BASH_REMATCH[1]}"
        else
            continue
        fi

        # IPv4 + IPv6 wildcard sockets can represent the same service. Report once.
        [[ -n "${seen["$proto/$port"]+x}" ]] && continue
        seen["$proto/$port"]=1
        ((exposure_count++)) || true

        service="unknown service"
        if [[ "$port" == "41641" ]] && pgrep -x tailscaled >/dev/null 2>&1; then
            service="tailscaled.service"
        elif command -v lsof >/dev/null 2>&1; then
            service="$(
                sudo lsof -nP -i"$proto":"$port" -s"$([[ "$proto" == tcp ]] && echo LISTEN || echo UDP)" 2>/dev/null |
                    awk 'NR==2 {print $1}' |
                    head -n1
            )" || true
            if [[ -z "$service" ]]; then
                service="$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null |
                    awk 'tolower($0) ~ /legacy-printer|printer/ {print $1; exit}')"
            fi
            [[ -n "$service" ]] || service="unknown service"
        fi

        if [[ "$port" == "41641" && "$service" == "tailscaled.service" ]]; then
            st_green "UDP/$port — tailscaled.service (expected Tailscale endpoint)."
            continue
        fi

        if [[ "$ufw_active" == true ]]; then
            if grep -Eq "[[:space:]]${port}([[:space:]]|/|,|$).*ALLOW|[[:space:]]${port}/${proto}.*ALLOW|[[:space:]]${port}/(tcp|udp).*ALLOW" <<< "$ufw_rules"; then
                ((allowed_count++)) || true
                st_red "$proto/$port — $service; explicit UFW ALLOW exposes a wildcard listener. Review this rule."
            else
                ((blocked_count++)) || true
                st_yellow "$proto/$port — $service; wildcard listener is blocked by UFW. Review whether the service is needed."
            fi
        else
            st_red "$proto/$port — $service; wildcard listener and UFW is inactive."
        fi
    done < <(ss -H -tulpen 2>/dev/null || true)

    if (( exposure_count == 0 )); then
        st_green "No wildcard network listeners detected."
    else
        st_info "Exposure summary: wildcard=$exposure_count, UFW-blocked=$blocked_count, UFW-allowed=$allowed_count."
    fi
    if (( loopback_count > 0 )); then st_green "Loopback-only listeners: $loopback_count."; fi
    if (( multicast_count > 0 )); then st_green "Multicast listeners: $multicast_count (local scope)."; fi
}

audit_ports() {
    log_section "LISTENING PORTS"

    if command -v ss >/dev/null 2>&1; then
        ss -tulpen 2>/dev/null || true
    else
        check "ss command not available."
    fi
}

audit_users() {
    local human_count admin_count shell_count
    human_count="$(awk -F: '$3 >= 1000 && $1 != "nobody" {c++} END {print c+0}' /etc/passwd)"
    admin_count="$(getent group sudo 2>/dev/null | awk -F: '{n=split($4,a,","); print (n && $4 != "" ? n : 0)}')"
    shell_count="$(awk -F: '$7 ~ /(bash|zsh|fish|sh)$/ {c++} END {print c+0}' /etc/passwd)"
    st_green "Human accounts: $human_count."
    st_green "Sudo/admin members: $admin_count."
    st_info "Accounts with interactive shells: $shell_count."
}

audit_services() {
    log_section "FAILED SYSTEMD UNITS"

    local failed
    failed="$(systemctl --failed --no-legend --no-pager 2>/dev/null || true)"
    if [[ -n "$failed" ]]; then
        warn "Failed systemd units found:"
        printf '%s\n' "$failed"
    else
        ok "No failed systemd units."
    fi
}

audit_security_controls() {
    log_section "SECURITY CONTROLS"
    if [[ -e /sys/module/apparmor ]]; then
        st_green "AppArmor kernel module is loaded."
    else
        st_red "AppArmor kernel module is not loaded."
    fi
    if systemctl is-enabled --quiet apparmor 2>/dev/null && systemctl is-active --quiet apparmor 2>/dev/null; then
        st_green "AppArmor service is enabled and active."
    else
        st_yellow "AppArmor service is not both enabled and active."
    fi
}

audit_disk() {
    log_section "STORAGE"
    local root_usage boot_usage efi_usage
    root_usage="$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || true)"
    boot_usage="$(df /boot 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || true)"
    efi_usage="$(df /boot/efi 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || true)"

    if [[ "$root_usage" =~ ^[0-9]+$ ]]; then
        if (( root_usage >= 90 )); then st_red "Root filesystem usage is critical: ${root_usage}%."
        elif (( root_usage >= 80 )); then st_yellow "Root filesystem usage is high: ${root_usage}%."
        else st_green "Root filesystem: ${root_usage}% used."
        fi
    fi
    if [[ "$boot_usage" =~ ^[0-9]+$ ]]; then st_green "/boot: ${boot_usage}% used."; fi
    if [[ "$efi_usage" =~ ^[0-9]+$ ]]; then st_green "/boot/efi: ${efi_usage}% used."; fi
}

audit_package_health() {
    log_section "PACKAGE HEALTH"

    if dpkg --audit 2>/dev/null | grep .; then
        warn "dpkg reports package configuration/installation issues."
    else
        ok "dpkg reports no package audit issues."
    fi

    local broken
    broken="$(apt-get check 2>&1 || true)"
    if grep -qiE 'broken|unmet dependencies|dependency problems' <<< "$broken"; then
        warn "APT dependency check reported a problem:"
        printf '%s\n' "$broken"
    else
        ok "APT dependency check is clean."
    fi

    show_held_packages

    if [[ -f /var/run/reboot-required ]]; then
        warn "A reboot is required."
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            echo "Packages requesting reboot:"
            cat /var/run/reboot-required.pkgs
        fi
    else
        ok "No reboot currently required."
    fi
}

audit_auth_logs() {
    # Authentication is handled by the severity-aware audit_authentication().
    # Keep this legacy function as a no-op for compatibility.
    :
}


# -----------------------------
# SEVERITY-AWARE AUDIT CHECKS
# -----------------------------

audit_reboot_kernel() {
    log_section "REBOOT / KERNEL STATUS"

    if [[ -f /var/run/reboot-required || -f /run/reboot-required ]]; then
        st_red "Reboot required."
        if [[ -r /var/run/reboot-required.pkgs ]]; then
            st_info "Packages requesting reboot:"
            sed 's/^/  /' /var/run/reboot-required.pkgs
        fi
    else
        st_green "No reboot currently required."
    fi

    local running_kernel newest_kernel newest_version
    running_kernel="$(uname -r 2>/dev/null || true)"
    newest_kernel="$(
        dpkg-query -W -f='${Package}\n' 'linux-image*' 2>/dev/null |
        grep -E '^linux-image-[0-9]' |
        sort -V | tail -n1 || true
    )"

    if [[ -n "$running_kernel" && -n "$newest_kernel" ]]; then
        newest_version="${newest_kernel#linux-image-}"
        if [[ "$running_kernel" == "$newest_version"* ]]; then
            st_green "Running kernel matches the newest installed kernel."
        else
            st_yellow "A newer installed kernel may not be running."
            st_info "Running kernel: $running_kernel"
            st_info "Newest installed kernel package: $newest_kernel"
        fi
    fi
}

audit_secure_boot() {
    log_section "SECURE BOOT"

    if ! command -v mokutil >/dev/null 2>&1; then
        st_info "mokutil not installed; Secure Boot state cannot be queried."
        return 0
    fi

    local sb
    sb="$(mokutil --sb-state 2>/dev/null || true)"

    if grep -qi "SecureBoot enabled" <<< "$sb"; then
        st_green "Secure Boot: enabled."
    elif grep -qi "SecureBoot disabled" <<< "$sb"; then
        st_yellow "Secure Boot: disabled."
    else
        st_info "Secure Boot state could not be determined."
    fi
}

audit_authentication() {
    log_section "AUTHENTICATION / LOGIN SECURITY"
    local count ssh_count sudo_count other_count

    count="$(journalctl --since "24 hours ago" --no-pager -q 2>/dev/null |
        grep -Eic 'authentication failure|failed password|authentication failed|pam_unix.*failure' || true)"
    ssh_count="$(journalctl --since "24 hours ago" --no-pager -q 2>/dev/null |
        grep -Eic 'sshd.*(failed password|authentication failure|invalid user)' || true)"
    sudo_count="$(journalctl --since "24 hours ago" --no-pager -q 2>/dev/null |
        grep -Eic 'sudo:.*authentication failure|sudo:.*incorrect password' || true)"

    if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
        st_yellow "Authentication failures in the last 24h: $count."
        if (( ssh_count > 0 )); then
            st_info "SSH-related authentication failures: $ssh_count."
        fi
        if (( sudo_count > 0 )); then
            st_info "Sudo authentication failures: $sudo_count."
        fi
        other_count=$(( count - ssh_count - sudo_count ))
        (( other_count < 0 )) && other_count=0
        if (( other_count > 0 )); then
            st_info "Other/local authentication failures: $other_count."
        fi
    else
        st_green "No authentication failures detected in the last 24h."
    fi
}


audit_package_source_summary() {
    local pkg origin class
    local ubuntu=0 trusted=0 ppa=0 unknown=0 none=0
    local -a manual_packages=()

    mapfile -t manual_packages < <(apt-mark showmanual 2>/dev/null | sed '/^$/d' | sort -u)
    for pkg in "${manual_packages[@]}"; do
        origin="$(apt_package_origin "$pkg")"
        class="$(classify_origin "$origin")"
        case "$class" in
            "Ubuntu official") ((ubuntu++)) || true ;;
            "Trusted vendor") ((trusted++)) || true ;;
            "PPA / Launchpad") ((ppa++)) || true ;;
            "Unknown third-party") ((unknown++)) || true ;;
            "No current candidate") ((none++)) || true ;;
        esac
    done

    log_section "PACKAGE SOURCES"
    st_info "Ubuntu official: $ubuntu | Trusted vendors: $trusted | PPA: $ppa | Unknown: $unknown | No candidate: $none"
    if (( unknown > 0 || ppa > 0 || none > 0 )); then
        st_red "Package source review required."
    else
        st_green "No unknown package sources detected."
    fi
}

audit() {
    ST_GREEN_COUNT=0
    ST_YELLOW_COUNT=0
    ST_RED_COUNT=0

    log_section "SYSTEM AUDIT"
    check_platform

    audit_firewall
    audit_network_exposure
    audit_reboot_kernel
    audit_secure_boot
    audit_authentication
    audit_ssh
    audit_users
    audit_services
    audit_security_controls
    audit_disk
    audit_package_health
    audit_kernel_security
    audit_package_source_summary
    show_flatpak_sources

    st_summary
}

# -----------------------------
# DEEP SCAN
# -----------------------------

deep_scan() {
    log_section "DEEP SECURITY SCAN"

    local missing=false

    for tool in rkhunter chkrootkit debsums; do
        if command -v "$tool" >/dev/null 2>&1; then
            ok "$tool available."
        else
            warn "$tool not installed."
            missing=true
        fi
    done

    if "$missing"; then
        echo
        check "Some deep-scan tools are missing."
        echo
        echo "Available from Ubuntu APT:"
        echo "  sudo apt install rkhunter chkrootkit debsums"
        echo
        if "$DRY_RUN"; then
            info "Dry-run: no security tools will be installed."
        elif [[ "$ASSUME_YES" == true ]]; then
            info "--yes supplied: installing missing deep-scan tools."
            missing_packages=()
            command -v rkhunter >/dev/null 2>&1 || missing_packages+=(rkhunter)
            command -v chkrootkit >/dev/null 2>&1 || missing_packages+=(chkrootkit)
            command -v debsums >/dev/null 2>&1 || missing_packages+=(debsums)

            if ((${#missing_packages[@]})); then
                apt_update
                run_cmd "${SUDO[@]}" apt-get install -y "${missing_packages[@]}"
            fi
        else
            read -r -p "Install the missing deep-scan tools now? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                missing_packages=()
                command -v rkhunter >/dev/null 2>&1 || missing_packages+=(rkhunter)
                command -v chkrootkit >/dev/null 2>&1 || missing_packages+=(chkrootkit)
                command -v debsums >/dev/null 2>&1 || missing_packages+=(debsums)

                if ((${#missing_packages[@]})); then
                    apt_update
                    run_cmd "${SUDO[@]}" apt-get install -y "${missing_packages[@]}"
                fi
            else
                info "Skipping installation; deep scan will run only with tools already installed."
            fi
        fi
    fi

    if command -v rkhunter >/dev/null 2>&1; then
        log_section "RKHUNTER"
        if "$DRY_RUN"; then
            run_cmd "${SUDO[@]}" rkhunter --update
            run_cmd "${SUDO[@]}" rkhunter --check --skip-keypress
        else
            "${SUDO[@]}" rkhunter --update || warn "rkhunter database update failed."
            set +e
            local raw warnings
            raw="$("${SUDO[@]}" rkhunter --check --skip-keypress 2>/dev/null)"
            local rc=$?
            set -e
            warnings="$(printf '%s\n' "$raw" | grep '\[ Warning \]' || true)"

            if [[ -n "$warnings" ]]; then
                warn "rkhunter reported warnings:"
                printf '%s\n' "$warnings"
            else
                ok "rkhunter reported no filtered warnings."
            fi

            info "rkhunter exit code: $rc"
        fi
    fi

    if command -v chkrootkit >/dev/null 2>&1; then
        log_section "CHKROOTKIT"
        if "$DRY_RUN"; then
            run_cmd "${SUDO[@]}" chkrootkit
        else
            set +e
            local chk
            chk="$("${SUDO[@]}" chkrootkit 2>/dev/null)"
            local rc=$?
            set -e

            # Do not aggressively suppress findings. Known benign results can
            # be environment-specific, so show suspicious/INFECTED/WARNING lines.
            local findings
            findings="$(printf '%s\n' "$chk" |
                grep -Ei 'INFECTED|WARNING|suspicious|PACKET SNIFFER' || true)"

            if [[ -n "$findings" ]]; then
                warn "chkrootkit produced findings requiring review:"
                printf '%s\n' "$findings"
            else
                ok "chkrootkit produced no filtered findings."
            fi

            info "chkrootkit exit code: $rc"
        fi
    fi

    if command -v debsums >/dev/null 2>&1; then
        log_section "DEBSUMS FILE INTEGRITY"
        if "$DRY_RUN"; then
            run_cmd "${SUDO[@]}" debsums -s
        else
            local result
            result="$("${SUDO[@]}" debsums -s 2>/dev/null || true)"
            if [[ -n "$result" ]]; then
                warn "debsums reported modified/missing package files:"
                printf '%s\n' "$result"
            else
                ok "debsums found no silent integrity discrepancies."
            fi
        fi
    fi
}

# -----------------------------
# KERNEL / BOOT SECURITY
# -----------------------------

audit_kernel_security() {
    log_section "KERNEL / BOOT SECURITY"
    local running newest nvidia
    running="$(uname -r)"
    newest="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n1)"
    nvidia="$(modinfo -F version nvidia 2>/dev/null || true)"
    st_info "Running kernel: $running"
    if [[ -n "$newest" && "$newest" == "$running" ]]; then
        st_green "Running kernel is the newest installed kernel."
    elif [[ -n "$newest" ]]; then
        st_yellow "Newer installed kernel exists: $newest (running: $running). Reboot recommended after maintenance."
    else
        st_yellow "Could not determine newest installed kernel."
    fi
    if [[ -n "$nvidia" ]]; then st_info "NVIDIA kernel module: $nvidia"; fi
}

maintenance_kernel_summary() {
    log_section "KERNEL / BOOT STATUS"
    audit_kernel_security
}

# -----------------------------
# KERNEL / BOOT SECURITY
# -----------------------------

audit_kernel_boot() {
    log_section "KERNEL / BOOT SECURITY"

    echo "Running kernel: $(uname -r)"

    echo
    echo "Installed kernels:"
    dpkg-query -W -f='${binary:Package}\n' 'linux-image*' 2>/dev/null |
        grep -E '^linux-image-[0-9]' | sort -V || true

    echo
    if [[ -f /var/run/reboot-required ]]; then
        warn "Reboot is required."
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            echo "Packages requesting reboot:"
            sed 's/^/  /' /var/run/reboot-required.pkgs
        fi
    else
        ok "No reboot currently required."
    fi

    echo
    if command -v mokutil >/dev/null 2>&1; then
        local sb
        sb="$(mokutil --sb-state 2>/dev/null || true)"
        if grep -qi "SecureBoot enabled" <<< "$sb"; then
            ok "Secure Boot: enabled."
        elif grep -qi "SecureBoot disabled" <<< "$sb"; then
            warn "Secure Boot: disabled."
        else
            check "Secure Boot state: ${sb:-unknown}"
        fi
    else
        check "mokutil not installed; Secure Boot state not checked."
        echo "  Optional: sudo apt install mokutil"
    fi

    echo
    if command -v modinfo >/dev/null 2>&1; then
        local nvidia
        nvidia="$(modinfo nvidia 2>/dev/null | awk '$1=="version:" {print $2; exit}' || true)"
        if [[ -n "$nvidia" ]]; then
            info "NVIDIA kernel module: $nvidia"
        else
            info "NVIDIA kernel module not detected."
        fi
    fi
}


# -----------------------------
# APT TRANSACTION PREVIEW
# -----------------------------

apt_transaction_preview() {
    log_section "APT TRANSACTION PREVIEW"

    apt_available || {
        st_info "APT/dpkg not available — skipping."
        return
    }

    if ! "$DRY_RUN"; then
        st_info "Transaction preview is only used in dry-run mode."
        return
    fi

    # IMPORTANT:
    # Dry-run deliberately does not run `apt-get update`, because that changes
    # the local APT package indexes. Therefore the simulation below is based on
    # the currently cached metadata and must not be presented as a fresh
    # repository-state calculation.
    local simulated
    simulated="$(apt-get -s upgrade 2>&1 || true)"

    echo
    st_info "APT metadata was NOT refreshed in dry-run mode."
    st_info "The simulation below uses the currently cached APT metadata."

    if grep -qE '^The following packages will be upgraded:' <<< "$simulated"; then
        st_yellow "Simulated APT upgrade transaction:"
        printf '%s\n' "$simulated" |
            sed -n '/^The following packages will be upgraded:/,/^The following packages will be REMOVED:/p' |
            sed 's/^/  /'

        echo
        printf '%s\n' "$simulated" |
            grep -E '^( [0-9]+ upgraded,|[0-9]+ upgraded,|Need to get|After this operation)' |
            sed 's/^/  /' || true

    elif grep -qE '^[[:space:]]*0 upgraded, 0 newly installed, 0 to remove' <<< "$simulated"; then
        # This does NOT mean that the repositories have no updates.
        # It only means the current cached metadata produces no transaction.
        if apt list --upgradable 2>/dev/null | tail -n +2 | grep -q '/'; then
            st_yellow "Cached APT state reports upgradable packages, but the current simulation produces no transaction."
            st_info "This can happen when APT metadata is stale or inconsistent."
            st_info "Run the real maintenance once you are ready; it will refresh APT metadata first."
        else
            st_green "Cached APT state and simulated transaction both show no package changes."
        fi
    else
        st_yellow "APT simulation returned an unexpected result."
        printf '%s\n' "$simulated" | tail -n 20
    fi
}

# -----------------------------
# LOCAL / MANUALLY INSTALLED DEBS
# -----------------------------

show_local_deb_candidates() {
    log_section "LOCAL / MANUALLY INSTALLED DEBS"

    apt_available || {
        st_info "APT/dpkg not available — skipping."
        return
    }

    local -a packages=()
    mapfile -t packages < <(
        dpkg-query -W -f='${binary:Package}\n' 2>/dev/null |
            sort -u
    )

    local pkg origin class count=0
    for pkg in "${packages[@]}"; do
        origin="$(apt_package_origin "$pkg")"
        class="$(classify_origin "$origin")"

        if [[ "$class" == "No current candidate" ]]; then
            ((count++)) || true
            printf '  %-38s %s\n' "$pkg" "No current APT candidate"
        fi
    done

    if (( count == 0 )); then
        st_green "No installed DEBs without a current APT candidate."
    else
        st_red "$count installed package(s) have no current APT candidate."
        st_info "These may be manually installed, obsolete, or from a disabled repository."
        st_info "They will NOT be automatically upgraded by this toolkit."
    fi
}


# -----------------------------
# SOURCE-AWARE UPDATE REPORT
# -----------------------------

show_pending_apt_updates_by_origin() {
    log_section "PENDING APT UPDATES BY SOURCE"

    apt_available || {
        st_info "APT/dpkg not available — skipping."
        return
    }

    local -a upgrades=()
    mapfile -t upgrades < <(
        apt list --upgradable 2>/dev/null |
            awk 'NR > 1 && $0 ~ /\[upgradable from:/ {sub(/\/[^ ]+/, "", $1); print $1}' |
            sort -u
    )

    if ((${#upgrades[@]} == 0)); then
        st_green "No pending APT updates."
        return
    fi

    local ubuntu=0 vendor=0 ppa=0 unknown=0 none=0
    local pkg origin class installed candidate
    printf '%-38s %-22s %-18s %-18s\n' "PACKAGE" "SOURCE" "INSTALLED" "CANDIDATE"
    printf '%-38s %-22s %-18s %-18s\n' "-------" "------" "---------" "---------"

    for pkg in "${upgrades[@]}"; do
        origin="$(apt_package_origin "$pkg")"
        class="$(classify_origin "$origin")"
        installed="$(apt_installed_version "$pkg")"
        candidate="$(apt_candidate_version "$pkg")"
        printf '%-38s %-22s %-18s %-18s\n' \
            "$pkg" "$class" "$installed" "${candidate:--}"

        case "$class" in
            "Ubuntu official") ubuntu=$((ubuntu + 1)) || true ;;
            "Trusted vendor")  vendor=$((vendor + 1)) || true ;;
            "PPA / Launchpad") ppa=$((ppa + 1)) || true ;;
            "Unknown third-party") unknown=$((unknown + 1)) || true ;;
            "No current candidate") ((none++)) || true ;;
        esac
    done

    echo
    printf '  Ubuntu official:      %d\n' "$ubuntu"
    printf '  Trusted vendor:       %d\n' "$vendor"
    printf '  PPA / Launchpad:      %d\n' "$ppa"
    printf '  Unknown third-party:  %d\n' "$unknown"
    printf '  No current candidate: %d\n' "$none"

    if (( unknown > 0 || none > 0 )); then
        st_yellow "Review the non-standard pending update sources above."
    else
        st_green "All pending APT updates have a known source classification."
    fi
}

post_maintenance_health_check() {
    log_section "POST-MAINTENANCE HEALTH CHECK"

    if dpkg --audit 2>/dev/null | grep . >/dev/null; then
        st_red "dpkg reports package configuration/installation issues."
        dpkg --audit 2>/dev/null || true
    else
        st_green "dpkg package state is consistent."
    fi

    local apt_check_output
    apt_check_output="$("${SUDO[@]}" apt-get check 2>&1 || true)"
    if grep -qiE 'unmet dependencies|broken packages|dependency problems|E:' <<< "$apt_check_output"; then
        st_red "APT dependency check failed."
        printf '%s\n' "$apt_check_output"
    else
        st_green "APT dependency check is clean."
    fi

    local held
    held="$(apt-mark showhold 2>/dev/null || true)"
    if [[ -n "$held" ]]; then
        st_yellow "Held APT packages detected; they will not normally be upgraded."
        printf '%s\n' "$held"
    else
        st_green "No APT packages are held."
    fi

    if command -v systemctl >/dev/null 2>&1; then
        local failed
        failed="$(systemctl --failed --no-legend --no-pager 2>/dev/null || true)"
        if [[ -z "$failed" ]]; then
            st_green "No failed systemd units."
        else
            st_red "Failed systemd units detected."
            printf '%s\n' "$failed"
        fi
    fi

    if [[ -f /var/run/reboot-required || -f /run/reboot-required ]]; then
        st_red "Reboot required."
        if [[ -r /var/run/reboot-required.pkgs ]]; then
            st_info "Packages requesting reboot:"
            sed 's/^/  /' /var/run/reboot-required.pkgs
        fi
    else
        st_green "No reboot currently required."
    fi

    # UFW is read-only here; it never changes firewall state.
    audit_ufw

    # Keep the detailed APT source table in the run log, but do not print it
    # during normal --maintain output.
    if [[ -n "$LOG_FILE" ]]; then
        local pending_apt_log saved_green saved_yellow saved_red
        pending_apt_log="$(mktemp)"
        saved_green="$ST_GREEN_COUNT"
        saved_yellow="$ST_YELLOW_COUNT"
        saved_red="$ST_RED_COUNT"
        show_pending_apt_updates_by_origin > "$pending_apt_log"
        ST_GREEN_COUNT="$saved_green"
        ST_YELLOW_COUNT="$saved_yellow"
        ST_RED_COUNT="$saved_red"
        cat "$pending_apt_log" >> "$LOG_FILE"
        rm -f "$pending_apt_log"
    else
        show_pending_apt_updates_by_origin >/dev/null
    fi
}

# -----------------------------
# MAINTENANCE
# -----------------------------

maintain() {
    log_section "SYSTEM MAINTENANCE"
    check_platform

    if "$DRY_RUN"; then
        st_info "DRY-RUN: no package indexes, packages, logs or caches will be modified."
    fi

    # -------------------------
    # PRE-MAINTENANCE SUMMARY
    # -------------------------
    # Prechecks/inventory are intentionally dry-run-only.
    if "$DRY_RUN"; then
        log_section "PRE-MAINTENANCE SUMMARY"

        apt_available || st_info "APT/dpkg not available."

        local apt_updates=0
        local snap_updates=0
        local flatpak_updates=0

        if apt_available; then
            apt_updates="$(apt list --upgradable 2>/dev/null | awk 'NR > 1 && /\// {count++} END {print count+0}')"
            st_info "APT metadata was not refreshed (dry-run)."
            show_pending_apt_updates_by_origin
            show_held_packages
            show_local_deb_candidates
            package_source_summary
        fi

        if command -v snap >/dev/null 2>&1; then
            snap_updates="$(snap refresh --list 2>/dev/null | awk 'NR > 1 && NF {count++} END {print count+0}')"
            st_info "Snap updates available: $snap_updates"
        fi

        if command -v flatpak >/dev/null 2>&1; then
            flatpak_updates="$(flatpak remote-ls --updates 2>/dev/null | awk 'NF {count++} END {print count+0}')"
            st_info "Flatpak updates available: $flatpak_updates"
        else
            st_info "Flatpak not installed."
        fi
    fi

    # -------------------------
    # MAINTENANCE
    # -------------------------
    log_section "PACKAGE MAINTENANCE"

    apt_upgrade
    snap_maintain
    flatpak_maintain

    # -------------------------
    # SAFE CLEANUP
    # -------------------------
    log_section "SYSTEM CLEANUP"

    if "$DRY_RUN"; then
        st_info "DRY-RUN: journal/cache cleanup would be evaluated here."
        st_info "No cleanup changes were made."
    else
        run_cmd "${SUDO[@]}" journalctl --vacuum-time=14d

        if [[ -d "$HOME/.cache/thumbnails" ]]; then
            find "$HOME/.cache/thumbnails" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
            st_green "Thumbnail cache cleaned."
        else
            st_info "No thumbnail cache found."
        fi
    fi

    # -------------------------
    # POST-MAINTENANCE HEALTH
    # -------------------------
    ST_GREEN_COUNT=0
    ST_YELLOW_COUNT=0
    ST_RED_COUNT=0

    post_maintenance_health_check

    # Concise final update state — detailed inventories belong to the log.
    if apt_available; then
        local phased_deferred=0
        phased_deferred="$(apt-get -s upgrade 2>/dev/null |
            awk '
                /^The following upgrades have been deferred due to phasing:/ {
                    in_deferred=1
                    next
                }
                in_deferred && NF == 0 { exit }
                in_deferred { count += NF }
                END { print count+0 }
            ')"

        if (( phased_deferred > 0 )); then
            st_yellow "APT: $phased_deferred package(s) deferred by Ubuntu phased updates."
        else
            st_green "APT: no remaining upgradable packages."
        fi
    fi

    if command -v snap >/dev/null 2>&1; then
        if snap refresh --list >/dev/null 2>&1; then
            local snap_remaining
            snap_remaining="$(snap refresh --list 2>/dev/null | awk 'NR > 1 && NF {count++} END {print count+0}')"
            if (( snap_remaining == 0 )); then
                st_green "Snap: no remaining refreshable packages."
            else
                st_yellow "Snap: $snap_remaining refreshable package(s) remain."
            fi
        fi
    fi

    echo
    log_section "MAINTENANCE HEALTH SUMMARY"

    if "$DRY_RUN"; then
        st_info "DRY-RUN complete: no maintenance changes were made."
    else
        st_green "Maintenance operations completed."
    fi

    st_summary
}

# -----------------------------
# CONCISE PACKAGE SOURCE SUMMARY
# -----------------------------

package_source_summary() {
    if ! apt_available; then
        st_info "Package source summary unavailable: APT/dpkg not present."
        return 0
    fi

    local ubuntu=0 vendor=0 ppa=0 unknown=0 nocandidate=0
    local pkg origin class

    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue

        origin="$(apt_package_origin "$pkg")"
        class="$(classify_origin "$origin")"

        case "$class" in
            "Ubuntu official")      ubuntu=$((ubuntu + 1)) ;;
            "Trusted vendor")       vendor=$((vendor + 1)) ;;
            "PPA / Launchpad")      ppa=$((ppa + 1)) ;;
            "No current candidate") nocandidate=$((nocandidate + 1)) ;;
            *)                      unknown=$((unknown + 1)) ;;
        esac
    done < <(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null)

    echo
    st_info "Package source summary:"
    st_info "  Ubuntu official : $ubuntu"
    st_info "  Trusted vendors : $vendor"
    st_info "  PPA / Launchpad : $ppa"
    st_info "  Unknown         : $unknown"
    st_info "  No candidate    : $nocandidate"

    if (( unknown > 0 || nocandidate > 0 )); then
        st_red "Package source review required."
    elif (( ppa > 0 )); then
        st_yellow "PPA packages detected; review trust and maintenance status."
    else
        st_green "Package sources look healthy."
    fi
}


# -----------------------------
# INTERACTIVE MENU
# -----------------------------

interactive_menu() {
    while true; do
        cat <<EOF

==============================
 System Toolkit ${VERSION}
 Ubuntu 26.04 LTS
==============================
1) Maintain + update packages
2) Audit system/security
3) Package-source inventory
4) Deep security scan
5) Maintain + deep scan
6) Exit

EOF

        read -r -p "Select [1-6]: " choice

        case "$choice" in
            1) maintain; return ;;
            2) audit; return ;;
            3) sources; return ;;
            4) deep_scan; return ;;
            5) maintain; deep_scan; return ;;
            6) exit 0 ;;
            *) st_yellow "Invalid choice." ;;
        esac
    done
}

# -----------------------------
# MAIN
# -----------------------------

main() {
    parse_args "$@"
    need_root
    check_platform
    start_logging

    if [[ "$DRY_RUN" == true && "$MODE" == "--sources" ]]; then
        st_info "--dry-run has no effect on --sources because this mode is read-only."
    elif [[ "$DRY_RUN" == true && "$MODE" == "--audit" ]]; then
        st_info "--dry-run has no effect on --audit because this mode is read-only."
    fi

    # Exactly ONE primary execution path.
    # --maintain --deep-scan is intentionally supported as a secondary action.
    case "$MODE" in
        --maintain)
            maintain
            if "$DEEP_AFTER_MAINTAIN"; then
                deep_scan
            fi
            ;;
        --audit)
            audit
            ;;
        --sources)
            sources
            ;;
        --deep-scan)
            deep_scan
            ;;
        "")
            interactive_menu
            ;;
        *)
            die "Invalid mode: $MODE"
            ;;
    esac

    echo
    st_green "System Toolkit completed."
    if [[ -n "$LOG_FILE" ]]; then
        st_info "Detailed log saved to:"
        printf '       %s\n' "$LOG_FILE"
    fi
}

# Internal function integrity check: prevents confusing "command not found"
# failures if a function is accidentally omitted during future edits.
for _fn in audit_ufw audit_firewall audit_network_exposure audit_reboot_kernel audit_secure_boot audit_authentication audit_ssh audit_users audit_services audit_security_controls audit_disk audit_package_health audit_kernel_security audit_package_source_summary; do
    if ! declare -F "$_fn" >/dev/null 2>&1; then
        printf '[ERROR] Internal function missing: %s\n' "$_fn" >&2
        exit 127
    fi
done
unset _fn

main "$@"
