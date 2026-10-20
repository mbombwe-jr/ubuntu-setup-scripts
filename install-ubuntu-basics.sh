#!/usr/bin/env bash
#
# Install Caddy, Docker (engine + compose) and GitHub CLI on Ubuntu.
#
# Usage:
#   sudo ./install-ubuntu-basics.sh              # install everything
#   sudo ./install-ubuntu-basics.sh caddy        # install a subset
#   sudo ./install-ubuntu-basics.sh docker gh
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
err()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || err "run as root: sudo $0 $*"
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || err "/etc/os-release not found"
  . /etc/os-release
  [[ "${ID}" == "ubuntu" ]] || err "this script targets Ubuntu (found: ${ID:-unknown})"
}

APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-300}"
APT_LOCK_FILES=(
  /var/lib/dpkg/lock
  /var/lib/dpkg/lock-frontend
  /var/lib/apt/lists/lock
  /var/cache/apt/archives/lock
)

apt_lock_pids() {
  local lock fd target
  for lock in "${APT_LOCK_FILES[@]}"; do
    [[ -e "${lock}" ]] || continue
    if command -v fuser >/dev/null 2>&1; then
      fuser "${lock}" 2>/dev/null || true
      continue
    fi
    if command -v lsof >/dev/null 2>&1; then
      lsof -t "${lock}" 2>/dev/null || true
      continue
    fi
    for fd in /proc/[0-9]*/fd/*; do
      target="$(readlink "${fd}" 2>/dev/null)" || continue
      [[ "${target}" == "${lock}" ]] && printf '%s\n' "${fd}"
    done
  done
  return 0
}

describe_lock_holders() {
  local pids cmd
  pids="$(apt_lock_pids | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  [[ -n "${pids}" ]] || { echo "unknown"; return 0; }
  cmd="$(ps -o pid=,args= -p ${pids} 2>/dev/null | head -3 || true)"
  [[ -n "${cmd}" ]] && echo "${cmd}" || echo "pids: ${pids}"
  return 0
}

wait_for_apt_lock() {
  local waited=0
  while :; do
    [[ -z "$(apt_lock_pids)" ]] && return 0
    if (( waited >= APT_LOCK_TIMEOUT )); then
      err "apt/dpkg lock still held after ${APT_LOCK_TIMEOUT}s.
    Holder: $(describe_lock_holders)
    Fix: stop the holder (e.g. 'systemctl stop unattended-upgrades' or 'systemctl stop apt-daily.service'),
         then re-run. Raise the limit with APT_LOCK_TIMEOUT=600."
    fi
    info "apt/dpkg lock busy, waiting ${waited}s/${APT_LOCK_TIMEOUT}s [$(describe_lock_holders)]"
    sleep 5
    waited=$((waited + 5))
  done
}

apt_update() {
  local attempt=0 out
  while (( attempt < 3 )); do
    attempt=$((attempt + 1))
    wait_for_apt_lock
    out="$(mktemp)"
    if apt-get -o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 update >"${out}" 2>&1; then
      rm -f "${out}"
      return 0
    fi
    if grep -qi "could not get lock" "${out}"; then
      info "apt-get update hit a lock, retrying in 10s..."
      rm -f "${out}"
      sleep 10
      continue
    fi
    printf '\n\033[1;31mapt-get update failed:\033[0m\n' >&2
    tail -20 "${out}" >&2
    rm -f "${out}"
    err "apt-get update failed (not a lock problem - check network/repos above)"
  done
  err "apt-get update failed after 3 attempts"
}

apt_install() {
  wait_for_apt_lock
  apt-get -o DPkg::Lock::Timeout=300 -y "$@"
}

install_prereqs() {
  log "Installing base packages"
  apt_update
  apt_install --no-install-recommends \
    ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common psmisc
}

install_caddy() {
  log "Installing Caddy"
  if command -v caddy >/dev/null 2>&1; then
    info "caddy already installed: $(caddy version 2>/dev/null || true)"
    return
  fi
  install_prereqs
  install -m 0755 -d /etc/apt/keyrings
  curl -1fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  curl -1fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
    -o /etc/apt/sources.list.d/caddy-stable.list
  apt_update
  apt_install caddy
  systemctl enable --now caddy
  info "caddy: $(caddy version 2>/dev/null || echo unknown)"
}

install_docker() {
  log "Installing Docker Engine + Compose plugin"
  if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
    info "docker already installed: $(docker --version)"
  else
    install_prereqs
    install -m 0755 -d /etc/apt/keyrings
    curl -1fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod 0644 /etc/apt/keyrings/docker.gpg
    local codename
    codename="$(lsb_release -cs)"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt_update
    apt_install \
      docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
  fi
  systemctl enable --now docker
  info "docker: $(docker --version 2>/dev/null || echo unknown)"
  info "compose: $(docker compose version 2>/dev/null || echo unknown)"
  add_user_to_docker "${SUDO_USER:-${USER:-root}}"
}

add_user_to_docker() {
  local user="$1"
  [[ -n "${user}" && "${user}" != "root" ]] || return 0
  id -u "${user}" >/dev/null 2>&1 || { info "user ${user} not found, skipping group add"; return 0; }
  getent group docker >/dev/null 2>&1 || groupadd docker
  usermod -aG docker "${user}"
  info "added ${user} to the docker group (re-login to apply)"
}

install_gh() {
  log "Installing GitHub CLI (gh)"
  if command -v gh >/dev/null 2>&1; then
    info "gh already installed: $(gh --version 2>/dev/null | head -1)"
    return
  fi
  install_prereqs
  install -m 0755 -d /etc/apt/keyrings
  curl -1fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor --yes -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt_update
  apt_install gh
  info "gh: $(gh --version 2>/dev/null | head -1)"
}

main() {
  require_root "$@"
  require_ubuntu

  local targets=("$@")
  if [[ ${#targets[@]} -eq 0 ]]; then
    targets=(caddy docker gh)
  fi

  local target
  for target in "${targets[@]}"; do
    case "${target}" in
      caddy) install_caddy ;;
      docker) install_docker ;;
      gh|github-cli) install_gh ;;
      *) err "unknown target: ${target} (valid: caddy, docker, gh)" ;;
    esac
  done

  log "Done"
  info "next: 'gh auth login' to authenticate GitHub CLI"
}

main "$@"
