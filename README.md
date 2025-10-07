# libremesh-virtual-mesh

Virtual LibreMesh testbed using for repeatable CI :
- QEMU
- mac80211_hwsim linux module
- [vwifi](https://github.com/Raizo62/vwifi)

This project aims at providing an easy, lightweight, repeatable and quick to setup testbed for LibreMesh.

## Setup

Clone this repository in your OpenWRT build directory :
```bash
git clone --recurse-submodules https://github.com/VGDSpehar/libremesh-virtual-mesh.git
```
### Compiling LibreMesh with vwifi :

For this testbed to work, you'll need :

1. x86-64 target  (follow these [instructions](https://libremesh.org/development.html#compiling_libremesh_from_source_code))
2. Adding the [vwifi-client package](https://github.com/javierbrk/vwifi_cli_package) to your OpenWRT build feeds :

```bash
echo 'src-git https://github.com/javierbrk/vwifi_cli_package' >> feeds.conf
./scripts/feeds update -a
./scrips/feeds install -a
```

Running `make menuconfig` you should now be able to select vwifi for your build configuration.
Select it, make sure your target is x86-64 then compile your LibreMesh firmware
```bash
make -j$(nproc+1)
```
### Vwifi-server

Follow the instructions from the [repository](https://github.com/Raizo62/vwifi) in order to have vwifi-server.

## Running the virtual mesh

From your OpenWRT build directory

```bash
./libremesh-virtual-mesh/start-mesh.sh
```

then a tmux window should open with 5 different panes. From top left to bottom :
0. vwifi-server : this is the server that will relay the wifi frames across each virtual machines
1. LiMe-000001 listening on port *2201*
2. LiMe-000002 listening on port *2202*
3. LiMe-000003 listening on port *2203*
5. A standard shell that will help you setup/monitor the mesh

## Monitoring and testing

It is possible to add another VM in order to test/monitor the mesh.

Simply open a new pane, and launch `./libremesh-virtual-mesh/launch-monitoring-vm.sh`
Then set the VM with :
`setup-vm.sh 2204`

In this monitoring VM (or in any other VM) you should be able to observe the mesh topology of the setup :

`shared-state-async get wifi_links_info`


You'll see that each VM is connected to the others on their wlan0-mesh interface, forming a mesh.
