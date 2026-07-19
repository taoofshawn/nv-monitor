# nv-monitor — DGX Spark native deployment

Deploy [nv-monitor](https://github.com/wentbackward/nv-monitor) as a native systemd service on DGX Spark nodes — no container runtime required. Includes an Ansible playbook and a Grafana dashboard.

## Quick start

```bash
./setup.sh --ask-become-pass
```

This will:
1. Create a Python virtual environment with Ansible
2. Download the latest `nv-monitor-linux-arm64` binary from GitHub releases
3. Install it to `/usr/local/bin` on each Spark
4. Install and enable a systemd unit (auto-start on boot)
5. Verify the `/metrics` endpoint is responding

## Prerequisites

- SSH access to the Spark nodes as `sdrew` (or update `inventory/hosts.yml`)
- Passwordless or password-based `sudo` (`--ask-become-pass` prompts for it)
- Python 3 + `python3-venv` on the control machine

  ```bash
  sudo apt-get install -y python3-venv
  ```

## Inventory

Edit `inventory/hosts.yml` to add or remove nodes:

```yaml
all:
  hosts:
    spark-0f0b:
      ansible_host: spark-0f0b.shawndo.intra
      ansible_user: sdrew
    spark-6d14:
      ansible_host: spark-6d14.shawndo.intra
      ansible_user: sdrew
```

## Service details

- **Binary:** `/usr/local/bin/nv-monitor`
- **Port:** 9101 (Prometheus `/metrics` endpoint)
- **Systemd unit:** `/etc/systemd/system/nv-monitor.service`
- **Flags:** `-n -p 9101` (headless mode, Prometheus exporter)
- **Restart:** `always`
- **Data directory:** `/var/lib/nv-monitor`

The binary downloads the latest precompiled release for `linux/arm64` from the [upstream repository](https://github.com/wentbackward/nv-monitor/releases). No compilation needed.

## Prometheus scrape config

Add to your Prometheus `scrape_configs`:

```yaml
scrape_configs:
  - job_name: 'nv-monitor'
    scrape_interval: 5s
    scrape_timeout: 3s
    honor_labels: true
    static_configs:
      - targets:
          - 'spark-0f0b.shawndo.intra:9101'
          - 'spark-6d14.shawndo.intra:9101'
        labels:
          cluster: 'dgx-spark-cluster'
```

## Grafana dashboard

The repository includes `nv-monitor-grafana.json` — a complete Grafana dashboard with 18 panels covering CPU, memory, GPU, disk, and RDMA metrics. Import it via the Grafana UI or API.

## Files

```
├── setup.sh                  # Venv → Ansible → deploy
├── requirements.txt          # Python/Ansible deps
├── playbook.yml              # Ansible entry point
├── inventory/
│   └── hosts.yml             # Spark node inventory
├── roles/
│   └── nv-monitor/
│       ├── tasks/main.yml    # Download, install, enable
│       ├── files/nv-monitor.service  # systemd unit
│       └── handlers/main.yml
└── nv-monitor-grafana.json   # Grafana dashboard
```
