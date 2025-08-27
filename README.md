# libremesh-virtual-mesh

Virtual LibreMesh testbed using for repeatable CI :
- QEMU
- mac80211_hwsim module
- [vwifi](https://github.com/Raizo62/vwifi)

This project aims at providing an easy, lightweight, repeatable and quick to setup testbed for LibreMesh.

## Setup

Clone this repository in your OpenWRT build directory :

`git clone git@github.com:VGDSpehar/libremesh-virtual-mesh.git`

Once cloned, you need to build [vwifi](https://github.com/Raizo62/vwifi) :
- For your machine following the project [README.md](https://github.com/Raizo62/vwifi/blob/master/README.md) : you specifically need the vwifi-server binary, that you'll add to your path
- For OpenWRT following this [wiki](https://github.com/Raizo62/vwifi/wiki/Install-on-OpenWRT-X86_64) : in this case, you only need the vwifi-client binary

## Running the virtual mesh

In you OpenWRT build directory, run : 

> ./libremesh-virtual-mesh/start-mesh.sh

then a tmux window should open with 5 different panes. From top left to bottom : 
0. vwifi-server : this is the server that will relay the wifi frames across each virtual machines
1. LiMe-000001 listening on port *2201*
2. LiMe-000002 listening on port *2202*
3. LiMe-000003 listening on port *2203*
5. A standard shell that will help you setup/monitor the mesh

Once each VM has booted, you need to set each one of the VM like this : 

> ./libremesh-virtual-mesh/setup-vm.sh <ssh-port>

This will : 
- upload the vwifi-client to the VM
- setup the mac80211_hwsim module and the mac address of the Wi-Fi interfaces
- set up vwifi-client to run as a service at boot
- reboot the VM

Once rebooted, each VM should automatically connect to the vwifi-server, and see each other. 

## Monitoring and testing

It is possible to add another VM in order to test/monitor the mesh. 
Simply open a new pane, and launch `./libremesh-virtual-mesh/launch-monitoring-vm.sh`
Then set the VM like before, this time is using port *2204*

In this monitoring VM (or in any other VM) you should be able to observe the star topology of the setup : 

> shared-state-async get wifi_links_info

You'll see that each VM is connected to the other on their wlan0-mesh interface.
