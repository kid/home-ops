# Home Assistant → `prd` k3s migration

## Goal
Move Home Assistant off its Proxmox VM into the `prd` k3s cluster (home-ops repo). Moving the VM to Incus was considered and is not preferred. Before the move, an Olimex ESP32-POE(-ISO) running ESPHome replaces the HAOS-SBFspot add-on and its Bluetooth dongle.

Current VM: HAOS 18.1 (`ova`), HA Core 2026.8.2, `10.0.10.101`, MAC `52:54:00:93:9b:8f`, Servers VLAN 10.

## Priority: keep long-term energy data
The Energy dashboard reads from the recorder's long-term statistics in `/config/home-assistant_v2.db` (SQLite, 269 MB, WAL). HA keeps them indefinitely; full state history is purged after 10 days.

| Statistic | Since | Source |
|---|---|---|
| `sensor.sma_energy_daily` (solar) | 2023-06-01 | SBFspot via MQTT, unique_id `2130215525_EToday`, kWh, `total_increasing`, resets to 0 overnight; sum 13951.384 kWh at 2026-11-07 08:00 UTC |
| `sensor.socket_kitchen_fridge_energy` | 2023-08-08 | Zigbee2MQTT |
| `sensor.socket_entryway_washing_machine_energy` | 2023-08-08 | Zigbee2MQTT |
| `sensor.socket_arnaud_office_desk_energy` | 2023-08-08 | Zigbee2MQTT |
| `sensor.socket_arnaud_office_cockpit_energy` | 2023-08-08 | Zigbee2MQTT |
| `sensor.socket_kitchen_dishwasher_energy` | 2023-08-09 | Zigbee2MQTT (no data since 2025-08-30: plug dead or unpaired) |
| `sensor.socket_living_room_charger_energy` | 2023-08-12 | Zigbee2MQTT |
| `sensor.socket_cecile_office_desk_energy` | 2023-08-12 | Zigbee2MQTT |
| `sensor.socket_cinema_tv_stand_energy` | 2023-08-12 | Zigbee2MQTT |
| `sensor.socket_entryway_rack_energy` | 2023-08-12 | Zigbee2MQTT |
| `sensor.socket_rack_pve0_energy` | 2023-12-29 | Zigbee2MQTT |
| `sensor.socket_rack_pve1_energy` | 2023-12-29 | Zigbee2MQTT |

`statistics_meta` has 167 entities, with statistics starting 2023-05-28.

Continuity depends on three things:
1. **Database file.** Copy `home-assistant_v2.db` intact into the HA PVC. Take a `sqlite3 .backup` just before cutover and keep it outside the cluster.
2. **Zigbee plugs.** Their unique_ids come from IEEE addresses. Moving Z2M's `database.db` intact keeps them; only the broker in HA's MQTT config entry changes.
3. **Solar.** The ESP32's `energy_production_day` sensor must land on `sensor.sma_energy_daily` (procedure below).

## Decisions
- **Kubernetes over an Incus VM.** No add-on needs HAOS, and the repo already has this pattern from the pve1 CTs → kopiur-backed Deployments (`modules/kubernetes/media/*`). The move also lets the broad rb5009 rule go. Availability is unchanged: the k3s VMs also run on node1.
- **Recorder stays on SQLite.** No Postgres or TimescaleDB:
  - HA docs recommend SQLite, and migrating between database engines is unsupported, so switching would lose the energy statistics.
  - The recorder can't use TimescaleDB, and LTSS (the TimescaleDB bridge) is unmaintained.
  - The repo has no Postgres operator.
- **Drop InfluxDB after archiving it.**
  - Database `homeassistant`, retention `autogen` (infinite), 1941 series from 2023-06-01, recording every entity.
  - Nothing reads it, and it has no energy data older than HA's statistics.
  - Fallback if raw long-term history is ever wanted: a dedicated VictoriaMetrics `VMSingle` with long retention, plus a `vmctl influx` import (numeric data only). The cluster's existing VMSingle has `retentionPeriod = "30d"` (`modules/kubernetes/victoria-metrics/default.nix:273`).
- **Drop MariaDB after `mysqldump SBFspot`.**
  - The `homeassistant` database is empty; the recorder uses SQLite.
  - The `SBFspot` database (~36 MB) is written only by SBFspot; HA doesn't read it:

    | Table | Rows | Contents |
    |---|---|---|
    | `SpotData` | 185k | |
    | `DayData` | 170k | 5-min, 2023-06-01 → now |
    | `MonthData` | 1233 | daily totals |
    | `EventData` | 1410 | |

  - The dump keeps the 5-minute history and inverter events.
- **Solar:** use `energy_production_day` (kWh, `total_increasing`, daily reset). It matches the existing sensor. Not `total_energy_production`: switching to a lifetime counter would add the inverter's whole lifetime total as a one-off spike.
- **Egress via Cilium egress gateway.** `kubeProxyReplacement=true` and `bpf.masquerade=true` are already on (`modules/kubernetes/cilium/default.nix`).
  - HA and Z2M leave from one fixed K3s VLAN IP.
  - rb5009's Servers rule "Allow access to all vlans" (`modules/routerosDevices/rb5009.nix:234-241`) is replaced by a `firewall` quirk rule for that IP toward IotLocal (50), Trusted (100) and Guest (101).
  - HA's CiliumNetworkPolicy allows those CIDRs plus `world`.
- **Not in scope:** no HomeKit, no Matter/Thread.

## Add-ons
| Add-on | Slug | Fate |
|---|---|---|
| Mosquitto | `core_mosquitto` | k8s Deployment |
| Zigbee2MQTT 2.14.3-1 | `45df7312_zigbee2mqtt` | k8s Deployment |
| HAOS-SBFspot | `a51a23d8_haos-sbfspot` | replaced by the ESP32 |
| MariaDB | `core_mariadb` | drop after `mysqldump SBFspot` |
| InfluxDB 1.x | `a0d7b954_influxdb` | drop after archiving (HA backup including the add-on) |
| Studio Code Server | `a0d7b954_vscode` | drop |
| Terminal & SSH | `core_ssh` | drop |
| Get HACS | `cb646a50_get` | drop (already stopped) |

## HA configuration findings
- **HACS custom components:**
  - `hacs` 2.0.5.
  - `dreame_vacuum` v2.0.0b23. Requires pillow, numpy, requests, pycryptodome, python-miio, mini-racer, paho-mqtt.
  - `roborock_custom_map` 0.1.6.
  - `mammotion` 0.1.109: no config entry, delete it.
- **Frontend cards** in `/config/www/community`: dreame-vacuum-map-card, lovelace-xiaomi-vacuum-map-card, vacuum-card. `/config/www/garmin/menu.json` also exists. All of these stay in the HA PVC.
- **Config entry targets** (all outbound from HA):
  - ESPHome: UZG-01 at `10.0.50.40`, plus two Everything Presence Lite sensors on Trusted (`10.0.100.x`).
  - Overkiz `10.0.50.30:8443`.
  - HEOS `10.0.101.206` (Guest VLAN).
  - Modbus charger `10.0.100.177:502`.
  - denonavr, webostv, androidtv_remote, and reolink (×2).
  - plex at `10.0.30.100` via a plex.direct URL (possibly stale).
  - Cloud: roborock, dreame, surepetcare, forecast_solar, met, Google TTS, 11 `mobile_app` registrations.
- **URLs:** `internal_url` and `external_url` are null. The `http:` block in `configuration.yaml` is commented out, yet `https://ha.kidibox.net` serves through the tunnel.
- **Bluetooth:** adapters are the TP-Link UB500 (`E8:48:B8:C8:20:00`, the SBFspot dongle) and the UZG-01 BLE proxy. No entities use Bluetooth.
- **`influxdb`:** the YAML is commented out, but a config entry remains (source `import`, host `a0d7b954-influxdb:8086`, api v1). Delete it at cutover.
- **`switch` wake_on_lan `pve`:** targets `10.0.10.10`, MAC `d0:50:99:fe:51:b5` = node1. `shell_command.turn_off_pve` SSHes to `homeassistant@pve.servers.home.kidibox.net` (`/config/ssh_keys/id_rsa_homeassistant`) and runs `sudo shutdown -h now`. HA will run on node1, so delete both or move WoL to rb5009 `/tool wol`.
- **Unchanged:** the Modbus `car_charger`, the template sensors (`home_energy`, `car_charger_sanitized`, `chargepoint_status`) and `input_number.electric_meter_reading`.
- **Z2M:**
  - `mqtt.server: mqtt://core-mosquitto:1883`, user `addons`.
  - `serial.port: tcp://10.0.50.40:6638`, `adapter: zstack`, frontend port 8099.
  - Data in `/config/zigbee2mqtt` (189 MB: `database.db`, `coordinator_backup.json`, `state.json`).
- **SBFspot PVOutput:**
  - `PVoutput_SID=2130215525` (the inverter serial, not SBFspot's `serial:systemID` form) and a key are set.
  - The upload log shows only headers, so uploads are probably not happening (inference).
  - Check the PVOutput account if one exists. The ESP32 won't upload there.

## Repo context
- **Existing aspect** `modules/kubernetes/home-assistant/default.nix`. It only fronts the VM:
  - A selector-less Service plus an EndpointSlice from `config.den.devices.homeassistant.address`, port 8123, hostname `ha.kidibox.net`.
  - A public HTTPRoute (`home-ops.dev/public-dns=true`), a `firewall` quirk for K3s → HA, and `ciliumNetworkPolicies.cloudflare-tunnel-home-assistant` on `applications.cloudflare-tunnel-gateway`.
  - The tunnel proxy needs a Service port with a ws appProtocol.
  - Included in `modules/clusters/prd.nix` (~line 205).
- **Pattern to copy:** `modules/kubernetes/media/default.nix`: Deployment, kopiur-backed config PVC, Service + HTTPRoute, Cilium policy. `flux.dependsOn` includes `kopiur-config`, plus `external-secrets-config` when the app uses secrets.
- **Backups:** `cluster.methods.mkKopiurBackup { name; uid; storage; ignore; existingClaim?; }` (`modules/kubernetes/kopiur/default.nix`), StorageClass `miroir`. For HA: `uid = 65534`, `ignore = [ "/.venv" ... ]`.
- **OIDC:** `cluster.methods.mkOidcAuth` (`modules/kubernetes/kanidm/envoy-oidc.nix`) fronts apps with no login of their own (the Z2M frontend).
- **Device entry:** `den.devices.homeassistant` is in `modules/devices.nix:51-59` (Servers, hostNum 101).
- **VLANs:** Management 99, Servers 10, Storage 20, IotLocal 50, IotInternet 51, Trusted 100, Guest 101 (`modules/networks.nix`). K3s is VLAN 40 (`modules/clusters/prd.nix`).
- **Image:** `ghcr.io/home-operations/home-assistant`.
  - Runs as `nobody` (65534).
  - Installs custom-integration requirements into `/config/.venv` and rebuilds it on every image change, so the pod needs PyPI egress. HACS needs GitHub egress.
  - go2rtc is bundled. WebRTC live view needs port 8555 on a LoadBalancer IP; MSE/HLS work through the Gateway.

## ESP32 solar sensor
- Config in `esphome/sma-inverter.yaml` (and the UZG-01's in `esphome/uzg-01.yaml`). Secrets come from the 1Password items `ESPHome - sma-inverter` and `ESPHome - uzg-01` in vault `home-ops`: `cd esphome && op inject -i secrets.tpl.yaml -o secrets.yaml` (gitignored), then `nix run nixpkgs#esphome -- run sma-inverter.yaml`. The UZG-01 needs ESPHome 2026.10+ (`uart_tcp`); the flake's nixpkgs has 2026.9.1.
- Board: ESP32-D0WD-V3 rev 3.1, base MAC `68:fe:71:a7:bb:e4`. Inverter: SB 5000TL-21, firmware 02.55.03.R, Bluetooth `00:80:25:A5:F0:6B`.
- **The inverter takes one Bluetooth connection at a time** (observed 2026-11-07: SBFspot's 11:25 run waited at "Connecting (1/10)" until the ESP32 let go). The ESP32 holds its connection all day, so it and SBFspot cannot run side by side. Missed SBFspot polls lose no energy: EToday is the inverter's own counter.
- **Two upstream bugs at `bb0658df`, both fixed in the fork `kid/esphome_smabluetooth` (branch `fix/energy-records`, verified on the device):**
  - The record parser stops before the second 16-byte record of a reply ("Record at 57 exceeds pcktBufPos=76"), so EToday (and FEEDTM) were never read and `energy_production_day` stayed at 0.
  - Energy sensors publish 0 from boot until the first read. Home Assistant takes a drop to 0 as a `total_increasing` reset, so every daytime reboot would double-count that day's production.
- With the patch, the ESP32 read EToday 0.849 kWh at 11:20:39 while SBFspot reported 0.847 kWh at 11:20:25.
- The inverter clock runs ~12 min fast. The ESP32 corrects it (at most every 12 h) once SNTP has synced.

## Solar cutover procedure
Not yet verified. Test first on a throwaway HA container with a copy of the database.
1. Validate the ESP32 in short daytime windows with the SBFspot add-on stopped: its "Energy daily" must match SBFspot's last value.
2. At night, after the daily reset, stop SBFspot.
3. Delete the MQTT entity `sensor.sma_energy_daily` (`2130215525_EToday`).
4. Rename the ESP32's `energy_production_day` sensor to `sensor.sma_energy_daily`.
5. Check that the next hourly statistics row continues from ~13951.38 kWh rather than restarting at 0.

## Plan
### Step 0: on the current VM
- [x] Build the ESP32 solar sensor (`esphome/sma-inverter.yaml`); patch the component (above).
- [x] Publish the component patch and pin it: `kid/esphome_smabluetooth` branch `fix/energy-records` (`70404ff2`). Upstream PR still to open.
- [x] Place the ESP32 on IotLocal: rb5009 `ether6`, `den.devices.sma-inverter` = `10.0.50.41` (`sma-inverter.iot-local.home.kidibox.net`, rb5009 static DNS), Ethernet MAC `68:fe:71:a7:bb:e7` (confirmed). Flashed over the network on 2026-11-07; it set the inverter clock from SNTP.
- [x] Add it to HA (ESPHome integration, host `sma-inverter.iot-local.home.kidibox.net`).
- [x] Solar cutover, 2026-11-07 ~12:25 (rehearsed first on a throwaway HA 2026.8.2 with a DB copy): SBFspot MQTT device deleted, ESP32 `Energy daily` renamed to `sensor.sma_energy_daily`. The 12:25 short-term row continues the statistic: 13952.125 + (1.430 − 0.982) = 13952.573. The ESP32's pre-rename statistic `sensor.sma_inverter_energy_daily` (metadata 192) is orphaned; delete it under Developer tools → Statistics.
- [x] Remove the node1 wake-on-LAN `switch.pve` and `shell_command.turn_off_pve` from `configuration.yaml`; delete `shell_commands.yaml` and `/config/ssh_keys/` (its only user). Core config check passed; restarted 2026-11-07 12:51.
- [x] Delete the orphaned `switch.pve` entity (UI) and `custom_components/mammotion` (installed by hand, not tracked by HACS).
- [x] Archive the SBFspot database: `~/home-assistant-archive/sbfspot-2026-11-07.sql.gz` on the workstation (sha256 `86172ca7…4b64f7f`, row counts match the live tables: DayData 176834, MonthData 1253, SpotData 192372, EventData 1460). SBFspot and MariaDB are stopped with boot `manual`.
- [x] Archive InfluxDB: full backup `pre-k3s-migration-2026-11-07` (slug `828b4e1f`, 1.03 GB, unencrypted, all add-ons) copied to `~/home-assistant-archive/ha-full-pre-k3s-migration-2026-11-07.tar` (sha256 `89794970…46780758e`, matches the VM copy).
- [x] Uninstall SBFspot and MariaDB (2026-11-07).
- [x] Unplug the UB500 dongle and remove its USB passthrough from the VM on pve1.
- [x] Drop InfluxDB: `influxdb` config entry deleted, add-on uninstalled.

### Repo
- [x] Mosquitto (`modules/kubernetes/home-assistant/mosquitto.nix`, #648, #649): TLS-only on 8883 with a `cluster-ca` certificate, a daily SIGHUP reloader, generated passwords in `mosquitto-home-assistant` and `mosquitto-zigbee2mqtt`, no persistence. Live; an in-cluster pub/sub test passed.
- [x] Zigbee2MQTT (`modules/kubernetes/home-assistant/zigbee2mqtt.nix`, #650): kopiur PVC, `ZIGBEE2MQTT_CONFIG_*` overrides for MQTT (TLS), the serial port and the frontend, JSON console logs, egress to Mosquitto, `10.0.50.40:6638` and HTTPS (OTA), frontend at `zigbee2mqtt.kidibox.net` behind Kanidm (`admins`), rb5009 forward rule K3s → UZG-01:6638. Deployed with `replicas = 0` until the cutover.
- [x] Home Assistant (`modules/kubernetes/home-assistant/home-assistant.nix`): `ghcr.io/home-operations/home-assistant:2026.8.2` (the VM's version), uid 65534, read-only root filesystem, kopiur PVC (5Gi; `.venv`, `deps`, `.cache`, `backups`, `tts` and logs left out of the snapshots). Egress to Mosquitto, the device VLANs (IotLocal, IotInternet, Trusted, Guest; any port) and world 80/443; ingress from the tunnel proxy and the apps Gateway. One switch, `inCluster`: while `false` the Service, EndpointSlice, tunnel egress and firewall rule keep pointing at the VM and the Deployment stays at 0; `true` gives the Service its selector, drops the EndpointSlice and the VM's firewall rule, moves the tunnel's egress to the pod, adds the LAN route `home-assistant-internal` on the apps Gateway, and sets `replicas = 1`.
- [x] Cilium egress gateway: `egressGateway.enabled` (and `operator.rollOutPods`, so the operator restarts and registers the `CiliumEgressGatewayPolicy` CRD). Open-source Cilium has no gateway failover (cilium/cilium#18230), so every node gets its own HA egress IP and HA's traffic leaves from the node it runs on: `den.clusters.prd.egressGateways.home-assistant` = `k3s-prd-0` → `10.0.40.20`, `k3s-prd-1` → `10.0.40.21`, each added as a `/32` next to the node's DHCP lease (`modules/nixos/services/k3s/egress-gateway.nix`, which fails a node's build if it has no address). One `CiliumEgressGatewayPolicy` per node (HA's pods on that node → that node, its IP) for the four device VLANs; rb5009 forward rules from both IPs out to IotLocal, IotInternet, Trusted and Guest.
- [ ] Roll it out, in this order: merge (Flux enables the feature and applies the policies); apply the rb5009 firewall stack; `colmena apply --on @k3s` **from `main`** (it re-runs the k3s-bootstrap units on the server, which apply the manifests baked from the tree it builds); then re-apply the policies (`kubectl delete ciliumegressgatewaypolicy home-assistant-k3s-prd-0 home-assistant-k3s-prd-1` and `flux reconcile kustomization home-assistant`), because Cilium picks the egress IP when a policy is applied and ignores an address added afterwards. Check on each node with a throwaway pod labelled `app.kubernetes.io/name: home-assistant` in `home-assistant` that a device answers and rb5009 sees that node's IP.

### Cutover
- [ ] Take a full HA backup plus a `sqlite3 .backup` of `home-assistant_v2.db`, stored off-cluster.
- [ ] HA and Zigbee2MQTT move together: the VM's HA can't reach the in-cluster Mosquitto (ClusterIP), and the in-cluster HA can't reach the add-on's.
- [ ] Stop the Z2M add-on and set it to manual boot before the cluster Z2M starts: two Zigbee2MQTT instances must never drive the coordinator at once.
- [ ] Import `/config` (excluding `zigbee2mqtt/`, `deps/` and `.venv`) into the HA PVC, owned by uid 65534, and `zigbee2mqtt/` (`configuration.yaml`, `database.db`, `coordinator_backup.json`, `state.json`; not `log/`) into the Z2M PVC, owned by uid 1000.
- [ ] Before HA starts, add to its `configuration.yaml`: `http: { use_x_forwarded_for: true, trusted_proxies: [172.40.0.0/16] }` (the pod CIDR: the tunnel proxy and Envoy).
- [ ] Flip `inCluster = true` in `home-assistant.nix` and the Z2M Deployment's `replicas = 1`; merge; apply the rb5009 firewall stack.
- [ ] Repoint HA's MQTT config entry to `mosquitto.home-assistant.svc:8883`: user `home-assistant`, password from the `mosquitto-home-assistant` Secret, TLS with the `cluster-ca` CA uploaded as a custom certificate.
- [x] Plex integration repointed on the VM on 2026-11-07 by re-adding it through the Plex account (manual setup failed with "server not found"). It picked `https://plex.kidibox.net:443` (verify SSL on), which the in-cluster HA reaches through `netpol.gatewayEgress`. `sensor.plex_plex`, `update.plex_media_server_plex` and `button.scan_clients_plex` kept their IDs; the client media players come back when those clients next play.
- [ ] Update the companion apps' internal URL.
- Known limits in the cluster: no mDNS/SSDP discovery of new devices (existing entries use IPs or DNS names); go2rtc WebRTC needs UDP 8555 on a LoadBalancer IP (MSE/HLS work through the Gateway).
- [ ] After the cutover: remove the `inCluster = false` branches and `den.devices.homeassistant`, and rb5009's Servers "Allow access to all vlans" rule (`modules/routerosDevices/rb5009.nix`), which only existed for the VM.

## Notes
- Read-only commands on the VM:
  - `ssh root@10.0.10.101 'ha apps info <slug> --raw-json'`
  - `sqlite3 -readonly 'file:/config/home-assistant_v2.db?mode=ro' ...`
- The `sqlite` and `mariadb-client` apk packages were installed in the Terminal & SSH add-on. They disappear when the add-on restarts.
