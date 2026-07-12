# nv-monitor — Docker image for DGX Spark (arm64)
#
# Cross-compiles nv-monitor from source with a fix to deduplicate disk
# metrics by device. This collapses the ~47 NVIDIA container-toolkit file
# bind-mounts (all on /dev/nvme0n1p2) into a single disk metric entry,
# keeping the Prometheus buffer at its default 8192 bytes.
#
# Build:
#   podman build -t taoofshawn/nv-monitor:latest .
#   docker build -t taoofshawn/nv-monitor:latest .
#
# Run (headless Prometheus exporter):
#   podman run -d --name nv-monitor \
#     --restart unless-stopped \
#     -p 9101:9101 \
#     -v /proc:/host/proc:ro \
#     -v /sys:/host/sys:ro \
#     --runtime nvidia \
#     -e NVIDIA_VISIBLE_DEVICES=all \
#     taoofshawn/nv-monitor:latest

# ── Stage 1: Cross-compile nv-monitor for arm64 + extract arm64 libncursesw6 ──
FROM --platform=linux/amd64 debian:stable-slim AS builder

# Enable multiarch and install arm64 cross-compilation toolchain + ncurses dev
RUN dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        crossbuild-essential-arm64 \
        libncurses-dev:arm64 \
        make git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Clone source, apply dedup fix, and cross-compile for arm64.
# The dedup collapses duplicate disk metrics by device name — without it the
# ~47 NVIDIA file bind-mounts (all on /dev/nvme0n1p2) generate 141 metric
# lines that overflow the default 8192-byte Prometheus buffer.
RUN git clone https://github.com/wentbackward/nv-monitor /src && \
    cd /src && \
    sed -i '/snprintf(disks\[n_disks\]\.mount/i\                \/\* Skip duplicate devices (many NVIDIA bind-mounts share the same device) \*\/\n                { int _dup = 0; for (int _j = 0; _j < n_disks; _j++) if (strcmp(disks[_j].device, me->mnt_fsname) == 0) { _dup = 1; break; } if (_dup) continue; }' nv-monitor.c && \
    sed -i '/        if (n_disks > 0) {/i\        \/\* Clean up mountpoint labels: use "\/" for file bind-mounts \*\/\n        for (int _i = 0; _i < n_disks; _i++) {\n            struct stat _st;\n            if (stat(disks[_i].mount, &_st) == 0 && !S_ISDIR(_st.st_mode))\n                strcpy(disks[_i].mount, "\/");\n        }' nv-monitor.c && \
    make CC=aarch64-linux-gnu-gcc \
         CFLAGS="-O3 -flto -Wall -Wextra -std=gnu11" \
         LDFLAGS="-lncursesw -ldl -lpthread" && \
    cp nv-monitor /nv-monitor && \
    rm -rf /src

# Download and extract libncursesw6 for arm64 without running arm64 code.
# Use dpkg-deb to extract (available in base debian:stable-slim).
RUN DEB_URL=$(curl -fsSL "https://packages.debian.org/stable/arm64/libncursesw6/download" \
    | grep -oP 'href="\K[^"]*libncursesw6[^"]*_arm64\.deb' | head -1) && \
    curl -fsSL "$DEB_URL" -o /libncursesw6.deb && \
    mkdir /ncurses && \
    dpkg-deb --extract /libncursesw6.deb /ncurses

# ── Stage 2: arm64 root filesystem (just the base, no commands run) ──
FROM --platform=linux/arm64 docker.io/arm64v8/debian:stable-slim AS arm64-rootfs

# ── Stage 3: Final arm64 image from scratch ──────────────────────────
FROM --platform=linux/arm64 scratch

# Copy the entire arm64 rootfs first
COPY --from=arm64-rootfs / /

# Copy the ncurses library files extracted in stage 1
# They live under /usr/lib/aarch64-linux-gnu/ on arm64
COPY --from=builder /ncurses/usr /usr

# Copy the nv-monitor binary (cross-compiled with device-dedup fix)
COPY --from=builder /nv-monitor /usr/local/bin/nv-monitor

# nv-monitor gracefully handles missing NVIDIA drivers (NVML loaded dynamically).
# The binary will report CPU/memory metrics without GPU data if libnvidia-ml.so.1
# is not available (it will be provided by nvidia-container-toolkit at runtime).

EXPOSE 9101

# Headless Prometheus exporter mode by default.
# Override CMD to change port (e.g. CMD ["-n", "-p", "9102"]).
ENTRYPOINT ["/usr/local/bin/nv-monitor"]
CMD ["-n", "-p", "9101"]
