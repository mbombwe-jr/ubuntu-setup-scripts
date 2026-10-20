#!/usr/bin/env bash
#
# Install Caddy, Docker Engine + Compose, and GitHub CLI on Ubuntu.
#
# Usage:
#   sudo ./install-ubuntu-basics.sh
#   sudo ./install-ubuntu-basics.sh caddy
#   sudo ./install-ubuntu-basics.sh docker gh
#
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

APT_LOCK_TIMEOUT="${APT_LOCK_TIMEOUT:-300}"

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
err()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "$EUID" -eq 0 ]] || err "Run as root: sudo $0 $*"
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || err "/etc/os-release not found"
  . /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || err "Ubuntu required; found ${ID:-unknown}"
}

wait_for_apt() {
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend \
      /var/lib/dpkg/lock \
      /var/lib/apt/lists/lock \
      /var/cache/apt/archives/lock >/dev/null 2>&1; do
    (( waited < APT_LOCK_TIMEOUT )) ||
      err "APT lock timeout after ${APT_LOCK_TIMEOUT}s. Check running apt/dpkg processes."
    info "Waiting for APT lock (${waited}s)..."
    sleep 5
    waited=$((waited + 5))
  done
}

apt_update() {
  local output
  output="$(mktemp)"

  wait_for_apt
  if apt-get \
      -o DPkg::Lock::Timeout=300 \
      -o Acquire::Retries=3 update >"$output" 2>&1; then
    cat "$output"
    rm -f "$output"
    return 0
  fi

  # If the existing Caddy source is broken, temporarily exclude only
  # that source while updating Ubuntu's package indexes.
  if grep -Eqi \
      'NO_PUBKEY|not signed|signature verification failed|EXPKEYSIG' "$output"; then
    info "APT signature error detected; checking the Caddy repository."

    local source backup
    source=""
    backup=""

    for candidate in \
      /etc/apt/sources.list.d/caddy-stable.list \
      /etc/apt/sources.list.d/caddy-stable.sources; do
      if [[ -f "$candidate" ]]; then
        source="$candidate"
        break
      fi
    done

    if [[ -n "$source" ]]; then
      backup="${source}.install-backup"
      [[ ! -e "$backup" ]] || {
        cat "$output" >&2
        rm -f "$output"
        err "Backup already exists: $backup. Inspect it before proceeding."
      }

      mv "$source" "$backup"
      if apt-get \
          -o DPkg::Lock::Timeout=300 \
          -o Acquire::Retries=3 update; then
        mv "$backup" "$source"
        rm -f "$output"
        return 0
      else
        mv "$backup" "$source"
        rm -f "$output"
        err "APT update failed even with Caddy temporarily excluded."
      fi
    fi
  fi

  cat "$output" >&2
  rm -f "$output"
  err "apt-get update failed. Check the repository configuration and network."
}

apt_install() {
  wait_for_apt
  apt-get -o DPkg::Lock::Timeout=300 -y install "$@"
}

install_prereqs() {
  log "Installing base packages"
  apt_update
  apt_install --no-install-recommends \
    ca-certificates curl gnupg lsb-release psmisc
}

install_caddy() {
  log "Installing Caddy"

  install_prereqs
  install -d -m 0755 /usr/share/keyrings

  curl -1fsSL \
    https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
    -o /tmp/caddy-stable.gpg

  gpg --batch --yes --dearmor \
    -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    /tmp/caddy-stable.gpg

  rm -f /tmp/caddy-stable.gpg
  chmod 0644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  # Explicitly bind the repository to its official signing key.
  cat > /etc/apt/sources.list.d/caddy-stable.list <<'EOF'
deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
EOF

  apt_update
  apt_install caddy
  systemctl enable --now caddy

  info "Caddy: $(caddy version)"
}

add_user_to_docker() {
  local user="${1:-}"
  [[ -n "$user" && "$user" != root ]] || return 0

  id "$user" >/dev/null 2>&1 || {
    info "User $user not found; skipping Docker group."
    return 0
  }

  getent group docker >/dev/null 2>&1 || groupadd docker
  usermod -aG docker "$user"
  info "Added $user to docker group; log out and back in to apply."
}

install_docker() {
  log "Installing Docker Engine and Compose"

  install_prereqs
  install -d -m 0755 /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc

  . /etc/os-release
  local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  [[ -n "$codename" ]] || err "Cannot determine Ubuntu codename."

  printf '%s\n' \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt_update
  apt_install docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
  info "Docker: $(docker --version)"
  info "Compose: $(docker compose version)"

  add_user_to_docker "${SUDO_USER:-}"
}

install_gh() {
  log "Installing GitHub CLI"

  install_prereqs
  install -d -m 0755 /etc/apt/keyrings

  curl -1fsSL \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg

  printf '%s\n' \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list

  apt_update
  apt_install gh
  info "GitHub CLI: $(gh --version | head -n 1)"
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
    case "$target" in
      caddy) install_caddy ;;
      docker) install_docker ;;
      gh|github-cli) install_gh ;;
      *) err "Unknown target: $target (valid: caddy, docker, gh)" ;;
    esac
  done

  log "Done"
  info "Run 'gh auth login' to authenticate GitHub CLI."
}

main "$@"
