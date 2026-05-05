# libremesh-virtual-mesh

Virtual LibreMesh testbed for repeatable local and CI-style mesh testing with:

- QEMU
- tmux
- [vwifi](https://github.com/Raizo62/vwifi)

This project stays shell-based. The current refactor adds a proper CLI, runtime state, and modular Bash libraries without changing the basic workflow of launching `vwifi-server`, booting multiple LibreMesh VMs, and reaching them over forwarded SSH ports.

## Dependencies

Install these commands on the Linux host that will run the testbed:

- `qemu-system-x86_64`
- `qemu-img`
- `tmux`
- `ssh`
- `ip`
- `gzip`
- `vwifi-server`

`vwifi-server` comes from the upstream vwifi project:

- https://github.com/Raizo62/vwifi

## LibreMesh / OpenWrt Build Setup

Clone this repository inside your OpenWrt build directory:

```bash
git clone --recurse-submodules https://github.com/VGDSpehar/libremesh-virtual-mesh.git
```

Build a LibreMesh/OpenWrt `x86_64` image. Follow the LibreMesh development instructions and add the `vwifi-client` package feed:

```bash
echo 'src-git vwifi https://github.com/javierbrk/vwifi_cli_package' >> feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a
```

Then enable the `vwifi` package in `make menuconfig`, keep the target on `x86_64`, and build:

```bash
make -j$(( $(nproc) + 1 ))
```

By default the CLI looks for the image at:

```text
../bin/targets/x86/64/openwrt-x86-64-generic-ext4-combined.img.gz
```

relative to this repository, which matches the common layout where the repository is cloned into the OpenWrt build tree.

## CLI Usage

The new entrypoint is:

```bash
./bin/lvm help
```

Main commands:

```bash
./bin/lvm start
./bin/lvm stop
./bin/lvm status
./bin/lvm clean
./bin/lvm help
```

Compatibility wrappers are still available:

```bash
./start-mesh.sh
./setup-vm.sh 2201
./launch-monitoring-vm.sh
```

## Starting The Mesh

From anywhere on the filesystem:

```bash
/path/to/libremesh-virtual-mesh/bin/lvm start
```

What `start` does:

- validates configuration
- checks required host dependencies
- prepares runtime directories in `/tmp/libremesh-virtual-mesh`
- decompresses the OpenWrt image and creates per-node QCOW2 overlays
- starts `vwifi-server`
- launches the requested number of LibreMesh VMs
- configures each node over SSH
- opens or reuses a tmux session for log monitoring

By default this starts:

- `node-1` on SSH port `2201`
- `node-2` on SSH port `2202`
- `node-3` on SSH port `2203`

## Status, Stop, And Clean

Show the current state:

```bash
./bin/lvm status
```

Stop the VMs and `vwifi-server` started by this project:

```bash
./bin/lvm stop
```

Remove this project's runtime state only:

```bash
./bin/lvm clean
```

`clean` only removes the runtime directory. It does not touch your OpenWrt build artifacts.

## Configuration

The CLI works without a config file. Defaults live in `config/default.conf`.

Optional overrides can be supplied with:

- environment variables
- `config/local.conf`

Useful environment variables:

- `LVM_NODE_COUNT`
- `LVM_BASE_SSH_PORT`
- `LVM_OPENWRT_BUILD_DIR`
- `LVM_IMAGE_PATH`
- `LVM_RUNTIME_DIR`
- `LVM_TMUX_SESSION`
- `LVM_VM_MEMORY`
- `LVM_VM_CPUS`

Examples:

```bash
LVM_NODE_COUNT=5 ./bin/lvm start
LVM_BASE_SSH_PORT=2301 ./bin/lvm start
LVM_OPENWRT_BUILD_DIR=/path/to/openwrt ./bin/lvm start
LVM_RUNTIME_DIR=/tmp/lvm-test ./bin/lvm start
```

To create a local project config:

```bash
cp config/local.conf.example config/local.conf
```

## Runtime Layout

Runtime files are stored under:

```text
/tmp/libremesh-virtual-mesh
```

Important paths:

- `logs/node-1.log`
- `logs/node-2.log`
- `logs/node-3.log`
- `logs/vwifi-server.log`
- `logs/monitor.log`
- `pids/`
- `disks/`
- `state/`

## SSH Access

After `start`, connect to a node with:

```bash
ssh root@127.0.0.1 -p 2201
```

Adjust the port for the node you want.

## Monitoring VM

The monitoring VM helper is still available:

```bash
./bin/lvm start-monitor
```

This launches a separate monitoring VM with:

- SSH forwarded on `2204` by default
- HTTP forwarded on `8004` by default

To configure it once SSH is reachable:

```bash
./bin/lvm setup-vm 2204
```

Inside a node or monitoring VM you can inspect the mesh, for example:

```bash
shared-state-async get wifi_links_info
```

## Development

Optional helper targets:

```bash
make lint
make start
make stop
make status
make clean
```
