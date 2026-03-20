# Scripts

## dbc (devbox-connect)

Connects to the devbox via mosh+tmux. Handles WoL if the box is asleep.

### Remote WoL over VPN

WoL broadcasts don't cross subnets, so when connecting over WireGuard (192.168.90.0/24)
the script sends WoL to a relay address (192.168.10.254) instead of the LAN broadcast.

This works via a static ARP entry on the MikroTik router that maps that IP to the
broadcast MAC, so the router re-broadcasts the magic packet on the LAN.

#### MikroTik config required

```routeros
/ip arp add address=192.168.10.254 mac-address=FF:FF:FF:FF:FF:FF interface=bridge
/ip firewall filter add chain=forward src-address=192.168.90.0/24 dst-address=192.168.10.254 protocol=udp dst-port=9 action=accept
```

The firewall rule must be above any drop/reject rules in the forward chain.
