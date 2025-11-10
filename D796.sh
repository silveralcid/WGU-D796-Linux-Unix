#!/usr/bin/env bash
# system_master.sh
# Combined master script integrating all user, network, and maintenance scripts.
# Usage examples:
#   sudo ./system_master.sh create_user <username>
#   sudo ./system_master.sh delete_user <username>
#   ./system_master.sh check_google
#   ./system_master.sh archive_compare
#   ./system_master.sh assess_cleanup
#   ./system_master.sh demo_create
#   ./system_master.sh demo_delete

set -euo pipefail

#-------------------------------------------------------
# Section 1: User Management
#-------------------------------------------------------

create_user() {
  if [[ $# -lt 1 ]]; then
    echo "Error: Missing username argument." >&2
    echo "Usage: sudo $0 create_user <username>" >&2
    exit 1
  fi

  if [[ $EUID -ne 0 ]]; then
    echo "Error: Must be run as root." >&2
    exit 1
  fi

  USERNAME="$1"
  GROUP="dev_group"

  if ! getent group "$GROUP" >/dev/null 2>&1; then
    groupadd "$GROUP"
    echo "Created group: $GROUP"
  else
    echo "Group already exists: $GROUP"
  fi

  if id -u "$USERNAME" >/dev/null 2>&1; then
    echo "Error: User '$USERNAME' already exists." >&2
    exit 1
  fi

  useradd -m -g "$GROUP" -s /bin/bash "$USERNAME"
  PASSWORD="$(tr -dc 'A-Za-z0-9!@#$%_-+' </dev/urandom | head -c 16)"
  echo "${USERNAME}:${PASSWORD}" | chpasswd
  chage -d 0 "$USERNAME"

  echo "User '$USERNAME' created and added to group '$GROUP'."
  echo "Initial password (share securely): ${PASSWORD}"
  echo
  echo "===== /etc/passwd ====="
  cat /etc/passwd
  echo "======================="
}

delete_user() {
  if [[ $# -lt 1 ]]; then
    echo "Error: Missing username argument." >&2
    echo "Usage: sudo $0 delete_user <username>" >&2
    exit 1
  fi

  if [[ $EUID -ne 0 ]]; then
    echo "Error: Must be run as root." >&2
    exit 1
  fi

  USERNAME="$1"

  if ! id -u "$USERNAME" >/dev/null 2>&1; then
    echo "Error: User '$USERNAME' does not exist." >&2
    exit 1
  fi

  read -rp "Are you sure you want to delete '$USERNAME' and their home directory? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi

  userdel -r "$USERNAME"
  echo "User '$USERNAME' and home directory deleted."
  echo
  echo "===== /etc/passwd ====="
  cat /etc/passwd
  echo "======================="
}

#-------------------------------------------------------
# Section 2: Network & DNS Checks
#-------------------------------------------------------

check_google() {
  if ping -c 1 -W 2 -q "google.com" >/dev/null 2>&1; then
    echo "Network is up."
  else
    echo "Network to google.com is down or unreachable."
  fi
}

check_google_dns_ip() {
  TARGET_IP="8.8.8.8"
  if ping -c 1 -W 2 -q "$TARGET_IP" >/dev/null 2>&1; then
    echo "Connectivity to $TARGET_IP is OK."
  else
    echo "Cannot reach $TARGET_IP."
  fi
}

check_example_dns() {
  DOMAIN="example.com"
  LOOKUP_OUT="$(nslookup "$DOMAIN" 2>/dev/null || true)"
  IPS="$(printf "%s" "$LOOKUP_OUT" | awk '/^Address: /{print $2}' | tail -n +2 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"

  if [[ -n "${IPS:-}" ]]; then
    echo "DNS resolution for $DOMAIN succeeded:"
    echo "$IPS"
  else
    echo "DNS resolution for $DOMAIN failed."
  fi
}

#-------------------------------------------------------
# Section 3: System Maintenance
#-------------------------------------------------------

assess_cleanup() {
  initial_free=$(df --output=avail / | tail -n 1)

  cleanDir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
      rm -rf "${dir:?}/"* "${dir:?}"/.[!.]* "${dir:?}"/..?* 2>/dev/null || true
      echo "Cleaned: $dir"
    else
      echo "Directory not found: $dir"
    fi
  }

  dirs_to_clean=("/var/log" "$HOME/.cache")

  for dir in "${dirs_to_clean[@]}"; do
    cleanDir "$dir"
  done

  final_free=$(df --output=avail / | tail -n 1)
  freed=$((final_free - initial_free))
  if ((freed > 0)); then
    echo "Disk space freed: $freed KB"
  else
    echo "No significant disk space was freed."
  fi
}

archive_compare() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: run as root (use sudo)." >&2
    exit 1
  fi

  fileSize() {
    local f="${1:-}"
    [[ -f "$f" ]] || { echo "File not found: $f" >&2; return 2; }
    stat -c '%s' -- "$f"
  }

  timestamp="$(date +%Y%m%d-%H%M%S)"
  outdir="$PWD"
  base_gz="$outdir/etc-$timestamp.tar.gz"
  base_bz2="$outdir/etc-$timestamp.tar.bz2"

  tar -C / -czpf "$base_gz" etc
  tar -C / -cjpf "$base_bz2" etc

  size_gz="$(fileSize "$base_gz")"
  size_bz2="$(fileSize "$base_bz2")"

  hr() { numfmt --to=iec --suffix=B "$1" || echo "$1 B"; }

  diff_abs=$(( size_gz - size_bz2 ))
  (( diff_abs < 0 )) && diff_abs=$(( -diff_abs ))

  echo "Created:"
  echo "  GZIP : $base_gz ($(hr "$size_gz"))"
  echo "  BZIP2: $base_bz2 ($(hr "$size_bz2"))"

  if (( size_gz < size_bz2 )); then
    echo "Result: gzip archive is smaller by $(hr "$diff_abs")."
  elif (( size_bz2 < size_gz )); then
    echo "Result: bzip2 archive is smaller by $(hr "$diff_abs")."
  else
    echo "Result: both archives are identical in size."
  fi
}

#-------------------------------------------------------
# Section 4: Demos
#-------------------------------------------------------

demo_create_user() {
  bash ./demo_create_user.sh
}

demo_delete_user() {
  bash ./demo_delete_user.sh
}

#-------------------------------------------------------
# Command Dispatcher
#-------------------------------------------------------

case "${1:-}" in
  create_user) shift; create_user "$@" ;;
  delete_user) shift; delete_user "$@" ;;
  check_google) check_google ;;
  check_google_dns_ip) check_google_dns_ip ;;
  check_example_dns) check_example_dns ;;
  assess_cleanup) assess_cleanup ;;
  archive_compare) archive_compare ;;
  demo_create) demo_create_user ;;
  demo_delete) demo_delete_user ;;
  *)
    echo "Usage: sudo $0 <command> [args]"
    echo
    echo "Available commands:"
    echo "  create_user <username>     Create a user and add to dev_group"
    echo "  delete_user <username>     Delete a user and home directory"
    echo "  check_google               Ping google.com"
    echo "  check_google_dns_ip        Ping Google DNS (8.8.8.8)"
    echo "  check_example_dns          Resolve example.com"
    echo "  assess_cleanup             Clean logs and caches"
    echo "  archive_compare            Compare gzip vs bzip2 archive sizes"
    echo "  demo_create                Run user creation demo"
    echo "  demo_delete                Run user deletion demo"
    ;;
esac
