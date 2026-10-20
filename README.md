# ubuntu-setup-scripts

One-command installer for a fresh Ubuntu server: **Caddy**, **Docker** (engine + Compose) and **GitHub CLI (`gh`)**.

No cloning, no setup. Run the single command below on any new Ubuntu machine.

## Quick start

Install everything (Caddy + Docker + gh):

```bash
curl -fsSL https://raw.githubusercontent.com/mbombwe-jr/ubuntu-setup-scripts/main/install-ubuntu-basics.sh | sudo bash
```

Install only some of them — pass the names after `--`:

```bash
curl -fsSL https://raw.githubusercontent.com/mbombwe-jr/ubuntu-setup-scripts/main/install-ubuntu-basics.sh | sudo bash -s -- docker gh
```

Valid targets: `caddy`, `docker`, `gh`.

## What it installs

| Tool | Source | Notes |
| --- | --- | --- |
| Caddy | CloudSmith apt repo | service enabled and started automatically |
| Docker Engine | `download.docker.com` apt repo | `docker-ce`, `docker-ce-cli`, `containerd.io`, `buildx` and `compose` plugins; your user is added to the `docker` group |
| GitHub CLI | `cli.github.com` apt repo | run `gh auth login` afterwards |

Every step is idempotent: already-installed tools are detected and skipped, so the script is safe to re-run.

## Requirements

- Ubuntu (the script exits with an error on other distributions)
- `root` (the script uses `sudo bash`, which is enough)

## After installing

```bash
gh auth login                 # authenticate the GitHub CLI
docker run hello-world        # verify Docker
caddy version                 # verify Caddy
newgrp docker                 # apply the docker group without re-logging in
```

## Local use

```bash
git clone https://github.com/mbombwe-jr/ubuntu-setup-scripts.git
cd ubuntu-setup-scripts
chmod +x install-ubuntu-basics.sh
sudo ./install-ubuntu-basics.sh            # everything
sudo ./install-ubuntu-basics.sh caddy      # single tool
```
