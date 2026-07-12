# nv-monitor — containerized (docker)

Run [nv-monitor](https://github.com/wentbackward/nv-monitor) as a headless Prometheus/OpenMetrics exporter in a container. Designed for the **DGX Spark** (Grace ARM + GB10 GPU) and any Linux system with an NVIDIA GPU.

**Architecture notes:**

- Designed for **DGX Spark** (arm64 / aarch64).
- The Docker image **cross-compiles nv-monitor from source** with two small patches that are specific to running inside a container:
  1. **Device dedup for disk metrics** — Inside a container, the NVIDIA container-toolkit bind-mounts individual driver files (`.so`, `.conf`, `.bin`) into `/proc/mounts` as separate `ext4` entries, all pointing to the same block device. On a DGX Spark this adds ~47 spurious mountpoints. The dedup collapses them into one entry per unique device.
  2. **Mountpoint label cleanup** — After dedup, remaining file-path mountpoints are relabeled to `"/"` for clean Prometheus output.

  These patches are container-only artifacts. Running nv-monitor directly on the host (as the original author intended) avoids them entirely.
- `libncursesw6` is the only runtime library dependency beyond glibc — the binary links against it even in headless mode.
- NVIDIA's `libnvidia-ml.so.1` is loaded dynamically at runtime and must be provided by the host via `nvidia-container-toolkit`. GPU metrics work when present; CPU/memory metrics work without it.
- The container runs in **headless mode** (`-n`) by default, exposing Prometheus metrics. No TUI rendering.

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/engine/install/) with [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- An NVIDIA GPU (or DGX Spark) on the host
- nvidia runtime is configured
```bash
docker info | grep -i runtime
# if not
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Build the image

```bash
docker build -t taoofshawn/nv-monitor:latest .
```

### Run

```bash
docker run -d --name nv-monitor \
  --restart unless-stopped \
  -p 9101:9101 \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  --runtime nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  taoofshawn/nv-monitor:latest
```

Verify it's working:

```bash
curl -s localhost:9101/metrics | head -20
```

You should see metrics like `nv_cpu_usage_percent`, `nv_memory_used_bytes`, `nv_gpu_utilization_percent`, etc.

## Docker Compose

A `docker-compose.yml` is included for easier deployment:

```bash
# Start
docker compose up -d

# View logs
docker compose logs -f
```

The compose file also includes a commented-out Prometheus sidecar service — uncomment it for a self-contained monitoring stack on each node.

## Prometheus Scrape Configuration

Add a job to your Prometheus `scrape_configs`:

```yaml
scrape_configs:
  - job_name: 'nv-monitor'
    scrape_interval: 5s
    scrape_timeout: 3s
    honor_labels: true
    static_configs:
      - targets: ['<node-hostname-or-ip>:9101']
        labels:
          cluster: 'dgx-spark-cluster'
```

### Cluster-wide scrape

If you have a central Prometheus (or use federated Prometheus), list all nodes:

```yaml
scrape_configs:
  - job_name: 'nv-monitor'
    scrape_interval: 5s
    honor_labels: true
    static_configs:
      - targets:
          - 'dgx-spark-01:9101'
          - 'dgx-spark-02:9101'
          - 'dgx-spark-03:9101'
          - 'dgx-spark-04:9101'
        labels:
          cluster: 'dgx-spark-cluster'
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NVIDIA_VISIBLE_DEVICES` | `all` | Which GPUs to expose to the container. Set to a comma-separated list (e.g. `0,1`) to limit. |
| `NVIDIA_DRIVER_CAPABILITIES` | `utility` | Required for NVML access. |

## Customizing at Runtime

Override the default command to change the port or add flags:

```bash
docker run -d --name nv-monitor \
  -p 9102:9102 \
  ... \
  taoofshawn/nv-monitor:latest \
  -n -p 9102
```

Or use a custom entrypoint wrapper to set locale or other environment:

```bash
docker run -d ... -e LC_ALL=C taoofshawn/nv-monitor:latest
```

> **Note:** The binary already calls `setlocale(LC_NUMERIC, "C")` in code, so locale issues with Prometheus decimal formatting are handled regardless of environment.

## Port Reference

| Port | Purpose | Configurable |
|------|---------|-------------|
| 9101 | Prometheus `/metrics` endpoint | Yes (`-p PORT`) |

## Available Metrics

See the full metric table in the [project README](https://github.com/wentbackward/nv-monitor#prometheus-metrics). All metrics described there are available via the containerized exporter.
