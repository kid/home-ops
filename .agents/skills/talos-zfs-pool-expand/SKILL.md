---
name: talos-zfs-pool-expand
description: Expand a ZFS pool on Talos after the underlying VM disk has been enlarged. Use when a Talos node disk or volume was grown, ZFS or LINSTOR still shows the old capacity, or a Piraeus/LINSTOR ZFS backing disk needs to consume new space.
---

# Talos ZFS Pool Expansion

Use this skill when a Talos node's backing disk has been expanded and the ZFS pool still reports the old size.

This repo's common case is:
- Talos control-plane nodes
- a larger backing disk visible as `/dev/vdb`
- a ZFS member partition on `/dev/vdb1`
- pool name `piraeus-ssd`
- LINSTOR/Piraeus reporting capacity from that pool

## Safety rules

- Prefer one node at a time.
- Verify the node remains part of a healthy control-plane quorum before rebooting it.
- Prefer `kubectl cordon <node>` + `talosctl reboot` over `talosctl reboot --drain` on this cluster; draining can hang on sticky workloads.
- Do not assume the device path or pool name; verify them first.
- Clean up any temporary debug pods you create.

## Repo/environment rules

- Enter through `direnv exec .` so repo-local `talosconfig` and `kubeconfig` are used.
- Use `talosctl --talosconfig talosconfig ...` and `kubectl --kubeconfig kubeconfig ...` explicitly.

## Workflow

### 1. Verify the disk sees the new size

Check Talos-discovered block devices first:

```bash
direnv exec . bash -lc 'talosctl --talosconfig talosconfig -n <node-ip> get discoveredvolumes vdb -o yaml'
```

Look for:
- `spec.size` / `pretty_size` increased on `vdb`
- `vdb1` still at the old size

You can also verify inside the satellite pod when available:

```bash
direnv exec . bash -lc 'kubectl --kubeconfig kubeconfig -n storage-system exec <linstor-satellite-pod> -c linstor-satellite -- lsblk /dev/vdb -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL'
```

### 2. Resize the GPT partition to fill the disk

If the satellite container lacks partitioning tools, create a temporary privileged pod in `storage-system` on the target node with `/dev` mounted from the host.

A minimal pattern is:
- namespace: `storage-system`
- `nodeSelector: kubernetes.io/hostname: <node>`
- `securityContext.privileged: true`
- hostPath mount of `/dev`
- install `parted` / `gdisk` if needed

Then run:

```bash
parted -s -f /dev/vdb resizepart 1 100%
partprobe /dev/vdb || true
lsblk /dev/vdb -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL
```

Expected result:
- `/dev/vdb1` grows to the full disk size

### 3. Check ZFS on the node

From the LINSTOR satellite pod on that node:

```bash
kubectl --kubeconfig kubeconfig -n storage-system exec <linstor-satellite-pod> -c linstor-satellite -- sh -lc 'zpool list piraeus-ssd; zpool get size,expandsize,autoexpand piraeus-ssd'
```

Interpretation:
- If `size` already increased, continue to LINSTOR verification.
- If `expandsize` shows extra capacity, ZFS sees room but has not expanded yet.
- Ensure `autoexpand=on`.

### 4. If ZFS does not expand immediately, reboot the node

Use this repo's safer operational pattern:

```bash
direnv exec . bash -lc 'kubectl --kubeconfig kubeconfig cordon <node>'
direnv exec . bash -lc 'talosctl --talosconfig talosconfig -n <node-ip> reboot --wait --timeout 15m'
```

Wait for:
- node `Ready`
- Cilium healthy on that node
- `linstor-satellite` back to `2/2 Running`

Then:

```bash
direnv exec . bash -lc 'kubectl --kubeconfig kubeconfig uncordon <node>'
```

After reboot, re-check:

```bash
kubectl --kubeconfig kubeconfig -n storage-system exec <linstor-satellite-pod> -c linstor-satellite -- sh -lc 'lsblk /dev/vdb -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL; zpool list piraeus-ssd; zpool get size,expandsize,autoexpand piraeus-ssd'
```

### 5. If ZFS still reports old size, nudge it

Try toggling `autoexpand`:

```bash
kubectl --kubeconfig kubeconfig -n storage-system exec <linstor-satellite-pod> -c linstor-satellite -- sh -lc 'zpool set autoexpand=off piraeus-ssd && zpool set autoexpand=on piraeus-ssd && zpool get size,expandsize,autoexpand piraeus-ssd'
```

In this repo, that was enough to force the pool to expand on one node after reboot.

### 6. Refresh LINSTOR/Piraeus capacity

Even after ZFS expands, LINSTOR may still show the old capacity.

Refresh the node in LINSTOR:

```bash
direnv exec . bash -lc 'kubectl --kubeconfig kubeconfig -n storage-system exec deploy/linstor-controller -- linstor node reconnect <node>'
```

Then verify:

```bash
direnv exec . bash -lc 'kubectl --kubeconfig kubeconfig -n storage-system exec deploy/linstor-controller -- linstor storage-pool list'
```

## Verification checklist

Confirm all of the following:

1. Node is `Ready`
2. `lsblk` shows `/dev/vdb1` at the new size
3. `zpool list piraeus-ssd` shows the new pool size
4. `zpool get size,expandsize piraeus-ssd` shows no remaining expansion gap
5. `linstor storage-pool list` shows updated capacity for the node
6. Temporary debug pods are deleted

## Known cluster-specific lessons

- `talosctl reboot --drain` can fail or stall on this cluster; prefer manual `cordon` + reboot.
- ZFS `autoexpand=on` may not apply the new size immediately after partition growth.
- A reboot may be required for ZFS to re-read the member geometry cleanly.
- LINSTOR capacity can lag after ZFS expansion; `linstor node reconnect <node>` fixes reporting.

## Report back to the user with

- which node(s) were changed
- old and new disk / pool sizes
- whether a reboot was needed
- whether LINSTOR required reconnect
- final `linstor storage-pool list` result for the affected nodes
