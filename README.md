# ubuntu-setup-scripts

One-command installer for a fresh Ubuntu server: **Caddy**, **Docker Engine + Compose** and **GitHub CLI (`gh`)**.

No cloning, no setup. Run a single command on any new Ubuntu machine.

## Quick start

Install everything (Caddy + Docker + gh):

```bash
curl -fsSL "https://raw.githubusercontent.com/mbombwe-jr/ubuntu-setup-scripts/main/install-ubuntu-basics.sh?v=$(date +%s)" | sudo bash
```

The `?v=$(date +%s)` only busts the `raw.githubusercontent.com` cache (5 min) so you always get the
latest version of the script. It can be dropped:

```bash
curl -fsSL https://raw.githubusercontent.com/mbombwe-jr/ubuntu-setup-scripts/main/install-ubuntu-basics.sh | sudo bash
```

Install only some of them — pass the names after `--`:

```bash
curl -fsSL "https://raw.githubusercontent.com/mbombwe-jr/ubuntu-setup-scripts/main/install-ubuntu-basics.sh?v=$(date +%s)" | sudo bash -s -- docker gh
```

Valid targets: `caddy`, `docker`, `gh` (`github-cli` also works).

Re-running the script is safe: `apt-get install` is a no-op for packages that are already at the
latest version.

## What it installs

| Tool | Repository | Notes |
| --- | --- | --- |
| Caddy | `dl.cloudsmith.io/public/caddy/stable` | key pinned via `signed-by` in `/etc/apt/sources.list.d/caddy-stable.list`; service enabled and started |
| Docker Engine + Compose | `download.docker.com/linux/ubuntu` | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`; your user is added to the `docker` group |
| GitHub CLI | `cli.github.com/packages` | key pinned via `signed-by`; run `gh auth login` afterwards |

The script also installs the base packages `ca-certificates`, `curl`, `gnupg`, `lsb-release` and
`psmisc`.

## Requirements

- Ubuntu (the script exits with an error on other distributions)
- `root` — the one-liners use `sudo bash`, which is enough
- Outbound HTTPS to `dl.cloudsmith.io`, `download.docker.com` and `cli.github.com`

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `APT_LOCK_TIMEOUT` | `300` | seconds to wait for the apt/dpkg lock before giving up |

```bash
curl -fsSL "https://raw.githubusercontent.com/mbombwe-jr/ubuntu-setup-scripts/main/install-ubuntu-basics.sh?v=$(date +%s)" | sudo APT_LOCK_TIMEOUT=600 bash
```

## After installing

```bash
gh auth login                 # authenticate the GitHub CLI
docker run hello-world        # verify Docker
docker compose version        # verify the Compose plugin
caddy version                 # verify Caddy
newgrp docker                 # pick up the docker group without logging out
```

## Local use

```bash
git clone https://github.com/mbombwe-jr/ubuntu-setup-scripts.git
cd ubuntu-setup-scripts
chmod +x install-ubuntu-basics.sh
sudo ./install-ubuntu-basics.sh            # everything
sudo ./install-ubuntu-basics.sh caddy      # a single tool
sudo ./install-ubuntu-basics.sh docker gh  # a subset
```

## Troubleshooting

**`APT lock timeout after 300s`** — another apt process (usually `unattended-upgrades`, `apt-daily`
or a running `apt-get upgrade`) holds the lock. Free it and re-run:

```bash
systemctl stop unattended-upgrades
systemctl stop apt-daily.service apt-daily-upgrade.service
ps aux | grep -E 'apt|dpkg' | grep -v grep
```

**`E: Invalid operation ...`** — you are running an old cached copy of the script. Re-run with the
cache-busting URL shown above.

**APT signature errors (`NO_PUBKEY`, `EXPKEYSIG`, "not signed")** — the script automatically
temporarily disables only the Caddy source, updates the Ubuntu indexes with it excluded, then
restores the source. If the error persists, the keyring in `/etc/apt/keyrings` needs refreshing:
delete the Caddy source and keyring and re-run the script.

**Any other apt failure** is printed in full (the real apt output is shown, not hidden behind a
retry loop), so a broken repository or a network problem shows the actual error.
