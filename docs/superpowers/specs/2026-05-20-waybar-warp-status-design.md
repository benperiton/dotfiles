# Waybar Cloudflare WARP status + toggle

## Problem

Cloudflare WARP was installed via an older `cloudflare-warp` RPM that omits the
tray/GUI helper, so there is no system indicator for whether WARP is up. The
waybar `custom/vpn` module on the bottom bar already exists and its on-click
handler (`warp-toggle.sh`) already toggles WARP, but the status script
(`vpn-status.sh`) only inspects NetworkManager-managed VPN and WireGuard
connections. WARP runs as its own `warp-svc` daemon outside NetworkManager, so
the bar currently shows the grey "LAN ... / public IP" disconnected state even
when WARP is connected.

## Goals

- See at a glance whether WARP is connected.
- One click on the existing module toggles WARP on/off.
- Visible feedback during the transition (toggle isn't instant).
- Preserve the existing nmcli VPN behaviour for machines/cases without WARP.
- Stay within the existing single `custom/vpn` module (no new modules).

## Non-goals

- Replacing the polling model with an event-driven (dbus) module.
- Surfacing WARP Zero Trust posture, team policies, or warp-cli registration
  flows in the bar.
- Showing WARP and an nmcli VPN side-by-side. If both are active, WARP wins
  (it's the egress that matters for daily use).


## Design

### Detection order in `vpn-status.sh`

The script gains a WARP probe ahead of the existing nmcli check:

1. **WARP probe.** If `warp-cli` is on `PATH`, capture one `warp-cli status`
   call and map the first line:
   - `Connected` -> WARP-connected branch.
   - `Connecting`, `Disconnecting`, `Unable to Connect` -> transitional
     branch.
   - `Disconnected`, `Disabled`, or anything else -> fall through to step 2.
2. **nmcli VPN/WireGuard probe.** Unchanged. Renders when WARP is absent or
   off and an nmcli VPN/wireguard connection is `activated`.
3. **LAN fallback.** Unchanged. Plain "LAN ... / public IP" disconnected
   state.

On machines without `warp-cli` installed, the script's behaviour is byte
identical to today.

### Output per state

The output is a JSON object with `text`, `class`, and `tooltip`, matching the
existing module contract (`return-type: json`).

| State                | Icon              | `text`                                       | `class`        |
|----------------------|-------------------|----------------------------------------------|----------------|
| WARP connected       | `` (fa-lock)     | `WARP <100.96.x.x> / <public IP>`            | `connected`    |
| WARP transitional    | `` (fa-lock)     | `WARP Connecting…` (or `Disconnecting…` / `Unreachable`) | `connecting`   |
| nmcli VPN connected  | `` (fa-lock)     | `VPN (<name>) <iface IP> / <public IP>`      | `connected`    |
| No VPN               | `` (fa-unlock)   | `LAN <lan IP> / <public IP>`                 | `disconnected` |

Icon code points are the existing `LOCK_OPEN` / `LOCK_SHUT` constants in the
script (U+F09C, U+F023).

The WARP IP is read from `ip -4 addr show dev CloudflareWARP`. That interface
only exists when WARP is up, so its presence doubles as a sanity check on the
`warp-cli status` parse. If `warp-cli status` reports `Connected` but the
interface is missing (a state the daemon has been seen to hit briefly during
init), we treat it as transitional rather than connected.

### Tooltip (WARP branch)

Multiline:

```
WARP: Connected (split tunnel)
WARP IP: 100.96.0.4
Public IP: <public>  ← egress via local ISP (split tunnel)
Network: healthy
```

- The `(split tunnel)` / `(full tunnel)` tag comes from
  `warp-cli settings 2>/dev/null` matching the `Split Tunnel mode` line. If
  parsing fails, the tag is omitted (we don't guess).
- The egress hint changes accordingly: in full-tunnel mode the line reads
  `Public IP: <public>  ← egress via WARP`.
- `Network: <state>` is the second line of the already-captured
  `warp-cli status` output. If absent, the line is omitted.

For the transitional state the tooltip simplifies to:

```
WARP: <Connecting|Disconnecting|Unable to Connect>
```

The nmcli-VPN and LAN branches keep their current tooltips unchanged.

### CSS

One new rule alongside `.connected` / `.disconnected` in `style.css`:

```css
#custom-vpn.connecting {
    color: #fe8019;   /* gruvbox orange, matches existing #mode highlight */
}
```

### Click behaviour

`warp-toggle.sh` already toggles WARP when present and falls back to
`nm-connection-editor` when not. It gains one trailing line so the bar
repaints immediately after a click rather than waiting for the next 5s tick:

```sh
pkill -RTMIN+8 waybar 2>/dev/null || true
```

The waybar `custom/vpn` module gains `"signal": 8` so it reacts to that
signal.

### Polling

`interval: 5` stays. `warp-cli status` is local IPC and returns in tens of
milliseconds. The public-IP curl keeps its `--max-time 3` so a flapping link
cannot stall the bar.

### Robustness

- Each external command is called once per refresh and its exit code is
  checked. A non-zero exit from `warp-cli status` is treated as "warp-cli not
  usable" and the script falls through to the nmcli branch.
- Curl failure for the public IP yields `unknown` (existing behaviour).
- The script never returns non-JSON, even on partial failure, so waybar
  cannot enter the "module errored" state.

## Files touched

All edits go to the chezmoi source, per the dotfiles workflow:

- `private_dot_config/waybar/executable_vpn-status.sh`: main rewrite,
  expected to stay under 60 lines.
- `private_dot_config/waybar/executable_warp-toggle.sh`: append the
  `pkill -RTMIN+8 waybar` line.
- `private_dot_config/waybar/config.jsonc`: add `"signal": 8` to the
  `custom/vpn` module.
- `private_dot_config/waybar/style.css`: add the `.connecting` rule.

Commit and push to `benperiton/dotfiles` main. We do not run
`chezmoi apply` (requires 1Password); the live `~/.config/waybar/*` will be
updated either manually for testing on this machine or on the next
`chezmoi apply`.

## Testing (manual)

1. `warp-cli connect` → bar transitions through orange "WARP Connecting…" and
   settles on yellow "WARP 100.96.x.x / <public IP>". Tooltip says
   "(split tunnel)" and "Network: healthy".
2. `warp-cli disconnect` → orange "WARP Disconnecting…" for ~1s, then grey
   "LAN ... / public IP".
3. Run waybar with `warp-cli` removed from `PATH` (e.g.
   `PATH=/usr/local/bin waybar`) → behaviour is identical to today
   (nmcli/LAN branches only).
4. Block 1.1.1.1 with a firewall rule (or pull WiFi) while connecting → bar
   shows orange "WARP Unreachable" without the script erroring, and curl's
   `--max-time 3` ensures the bar doesn't freeze.
5. Click the module → bar repaints within ~100ms via SIGRTMIN+8, not after
   the next 5s tick.

Each test is a sub-minute manual check. No automated harness for ~60 lines
of shell.

## Risks and mitigations

- **`warp-cli status` output format changes between WARP versions.** Mitigated
  by matching on substrings (`Connected`, `Connecting`, etc.) rather than
  exact lines, and by treating any unparseable output as fall-through.
- **Split-tunnel egress confuses users into thinking WARP is broken.** The
  tooltip explicitly labels the egress path so it's clear that a local
  public IP under WARP-on is expected in split-tunnel mode.
- **`CloudflareWARP` iface name changes.** Currently stable across the
  versions installed; the iface check is a sanity guard, not the primary
  signal, so a name change degrades to "trust warp-cli status" rather than
  breaking.
