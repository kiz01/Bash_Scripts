#!/usr/bin/env bash

# -----------------------------
# HELP
# -----------------------------
show_help() {
    cat << 'EOF'

System Toolkit — Maintenance & Security Helper

USAGE:
  ./system_toolkit.sh --maintain
  ./system_toolkit.sh --audit
  ./system_toolkit.sh --deep-scan
  ./system_toolkit.sh --maintain --deep-scan
  ./system_toolkit.sh --maintain --dry-run
  ./system_toolkit.sh            # interactive menu

MODES:

  --maintain
    - Updates system packages (APT, Snap, Flatpak)
    - Cleans unused packages and cache
    - Performs basic health checks (disk usage, login attempts)
    - Safe to run weekly

  --audit
    - Checks system configuration
    - Firewall, SSH, users, open ports, package health
    - Read-only (no changes made)
    - Run monthly

  --deep-scan
    - Runs rkhunter (filtered output)
    - Runs chkrootkit (filtered output)
    - Verifies package integrity using debsums
    - Slow, use occasionally or after updates

FLAGS:

  --dry-run
    - Shows what would be executed without making changes

NOTES:

  - Script is non-invasive (no auto-hardening or installs)
  - Security tools are filtered to reduce noise
  - Warnings ≠ compromise — review context before acting
  - Designed for personal Linux systems

EOF
}

# -----------------------------
# Parse arguments
# -----------------------------
for arg in "$@"; do
    case "$arg" in
        --maintain|--audit|--deep-scan)
            if [ -z "$MODE1" ]; then
                MODE1="$arg"
            else
                MODE2="$arg"
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# -----------------------------
# STRICT MODE
# -----------------------------
set -e

MODE1=""
MODE2=""
DRY_RUN=false

# -----------------------------
# Helpers
# -----------------------------
log_section() {
    echo ""
    echo "=== $1 ==="
}

ok()    { echo "[OK] $1"; }
warn()  { echo "[WARN] $1"; }
check() { echo "[CHECK] $1"; }

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $*"
    else
        eval "$@"
    fi
}

# Detect sudo
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# -----------------------------
# MAINTENANCE
# -----------------------------
maintain() {

    log_section "SYSTEM UPDATE"

    if [ "$DRY_RUN" = true ]; then
        run_cmd "$SUDO apt update"
        run_cmd "$SUDO apt -s upgrade"
        run_cmd "$SUDO apt -s full-upgrade"
        run_cmd "$SUDO apt -s autoremove"
    else
        run_cmd "$SUDO apt update"
        run_cmd "$SUDO apt upgrade -y"
        run_cmd "$SUDO apt full-upgrade -y"
        run_cmd "$SUDO apt autoremove -y"
        run_cmd "$SUDO apt autoclean -y"
        run_cmd "$SUDO dpkg -l | awk '/^rc/ { print \$2 }' | xargs -r $SUDO dpkg --purge"
    fi
    
# ---------------- SNAP ----------------
log_section "SNAP"

if dpkg -l | grep -q "^ii  snapd"; then
    ok "snapd detected — managing snap packages"

    if command -v snap >/dev/null 2>&1; then

        # Show installed snaps
        snaps=$(snap list | awk 'NR>1 {print $1}')
        if [ -z "$snaps" ]; then
            check "No snap packages installed"
        else
            echo "Installed snaps:"
            snap list
        fi

        if [ "$DRY_RUN" = true ]; then
            echo ""
            echo "[DRY-RUN] Checking for available snap updates..."
            run_cmd "$SUDO snap refresh --list"
        else
            echo ""
            echo "Updating snap packages..."
            run_cmd "$SUDO snap refresh"

            echo ""
            echo "Setting snap retention policy (keep last 2 revisions)..."
            run_cmd "$SUDO snap set system refresh.retain=2"
        fi

    else
        warn "snap command not found even though snapd is installed"
    fi
else
    check "snapd not installed — skipping"
fi

# ---------------- FLATPAK ----------------

    if command -v flatpak >/dev/null 2>&1; then
        log_section "FLATPAK"
        if [ "$DRY_RUN" = true ]; then
            run_cmd "flatpak update --assumeno"
            run_cmd "flatpak uninstall --unused --assumeno"
        else
            run_cmd "flatpak update -y"
            run_cmd "flatpak uninstall --unused -y"
        fi
    fi

    if [ "$DRY_RUN" = false ]; then
        log_section "SYSTEM CLEANUP"
        run_cmd "$SUDO journalctl --vacuum-time=7d"
        run_cmd "rm -rf ~/.cache/thumbnails/*"
    fi

    log_section "QUICK HEALTH CHECK"

    usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$usage" -gt 80 ]; then
        warn "Disk usage is above 80% ($usage%)"
    else
        ok "Disk usage is healthy ($usage%)"
    fi

    fails=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
    check "Failed login attempts (total log): $fails"
}

# -----------------------------
# AUDIT
# -----------------------------
audit() {

    log_section "FIREWALL"
    if command -v ufw >/dev/null 2>&1; then
        status=$(sudo ufw status | head -n1)
        if echo "$status" | grep -q "active"; then
            ok "UFW is enabled"
        else
            warn "UFW is NOT enabled"
        fi
    else
        check "UFW not installed"
    fi

    log_section "SSH CONFIG"
    if systemctl is-active --quiet ssh; then
        warn "SSH service is running"

        if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
            warn "SSH password authentication ENABLED"
        else
            ok "SSH password authentication disabled or not set"
        fi
    else
        ok "SSH service not running"
    fi

    log_section "OPEN PORTS"
    ss -tulnp | grep LISTEN || check "No listening ports found"

    log_section "USERS"
    users=$(awk -F: '$3 >= 1000 {print $1}' /etc/passwd)
    echo "Users: $users"

    log_section "SUDO USERS"
    getent group sudo | cut -d: -f4

    log_section "PACKAGE HEALTH"
    if dpkg --audit | grep .; then
        warn "Broken packages detected"
    else
        ok "No broken packages"
    fi
}

# -----------------------------
# DEEP SCAN
# -----------------------------
deep_scan() {

log_section "ROOTKIT SCAN"

missing_tools=false

# Check rkhunter
if command -v rkhunter >/dev/null 2>&1; then
    ok "rkhunter available"
else
    warn "rkhunter not installed"
    missing_tools=true
fi

# Check chkrootkit
if command -v chkrootkit >/dev/null 2>&1; then
    ok "chkrootkit available"
else
    warn "chkrootkit not installed"
    missing_tools=true
fi

# If missing, guide and skip
if [ "$missing_tools" = true ]; then
    echo ""
    check "To enable rootkit scanning, install:"
    echo "sudo apt install rkhunter chkrootkit"
    echo ""
    check "Skipping rootkit scan"
    return
fi

# Run scans
echo ""
echo "Updating rkhunter database..."

if ! $SUDO rkhunter --update; then
    warn "rkhunter update failed — continuing with scan"
fi

# RKHUNTER SCAN ----------------------------------------

echo ""
log_section "RKHUNTER SCAN (final)"

set +e

raw_output=$($SUDO rkhunter --check --skip-keypress 2>/dev/null)

# Extract ONLY actual warnings
warnings=$(echo "$raw_output" | grep "\[ Warning \]")

# Extract suspect count (important signal)
suspect_summary=$(echo "$raw_output" | grep "Suspect files")

set -e

# Final output
if [ -z "$warnings" ]; then
    ok "rkhunter: no relevant warnings"
else
    echo "$warnings"
    echo ""
    echo "$suspect_summary"
    warn "rkhunter reported warnings"
fi

# CHKROOTKIT SCAN --------------------------------------

echo ""
log_section "CHKROOTKIT SCAN"

# Disable exit-on-error temporarily
set +e

raw_output=$($SUDO chkrootkit 2>/dev/null)

# Extract suspicious file section
suspicious_files=$(echo "$raw_output" | awk '
/WARNING: The following suspicious files/ {flag=1; next}
/^$/ {if(flag) exit}
flag
')

# Filter known safe patterns
suspicious_files=$(echo "$suspicious_files" | grep -vE \
"virtualbox|\.build-id|rubygems|libreoffice|\.java|nvidia|\.module-common\.o")

# Extract real sniffers
sniffer=$(echo "$raw_output" | grep "PACKET SNIFFER" | \
    grep -vE "NetworkManager|wpa_supplicant")

# Re-enable strict mode
set -e

# Final output
if [ -z "$suspicious_files" ] && [ -z "$sniffer" ]; then
    ok "chkrootkit: no relevant findings"
else
    [ -n "$suspicious_files" ] && echo "$suspicious_files"
    [ -n "$sniffer" ] && echo "$sniffer"
    warn "chkrootkit reported relevant findings"
fi

# ---------------- FILE INTEGRITY ----------------
    log_section "FILE INTEGRITY"

if command -v debsums >/dev/null 2>&1; then

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would run debsums integrity check (requires root)"
    else
        echo "Running debsums (this may take time)..."

        result=$($SUDO debsums -s 2>/dev/null)

        if [ -z "$result" ]; then
            ok "No integrity issues detected"
        else
            warn "Modified files detected:"
            echo "$result"
        fi
    fi

else
    check "debsums not installed"
fi
}

# -----------------------------
# MENU
# -----------------------------
interactive_menu() {

    echo ""
    echo "Tip: You can run with flags like:"
    echo "$0 --maintain"
    echo "$0 --audit"
    echo "$0 --deep-scan"
    echo "$0 --maintain --deep-scan"
    echo "$0 --maintain --dry-run"
    echo ""

    echo "=============================="
    echo " System Toolkit Menu"
    echo "=============================="
    echo "1) Maintain"
    echo "2) Audit"
    echo "3) Deep Scan"
    echo "4) Maintain + Deep Scan"
    echo "5) Exit"
    echo ""

    read -p "Select an option [1-5]: " choice

    case "$choice" in
        1) maintain ;;
        2) audit ;;
        3) deep_scan ;;
        4) maintain; deep_scan ;;
        5) exit 0 ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
}

# -----------------------------
# EXECUTION
# -----------------------------
if [ -z "$MODE1" ]; then
    interactive_menu
else
    case "$MODE1" in
        --maintain) maintain ;;
        --audit) audit ;;
        --deep-scan) deep_scan ;;
    esac

    if [ -n "$MODE2" ]; then
        case "$MODE2" in
            --maintain) maintain ;;
            --audit) audit ;;
            --deep-scan) deep_scan ;;
        esac
    fi
fi

echo ""
echo "✅ Done."
