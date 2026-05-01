# Piraeus 3-Replica Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `linstor-zfs-ssd` request three replicas for new volumes and convert the currently provisioned `linstor-zfs-ssd` PVC-backed LINSTOR resources from the current 2-replica-plus-tiebreaker/diskless layout to three diskful replicas.

**Architecture:** Keep the desired default declarative in Git by updating the `linstor-zfs-ssd` storage class manifest on the feature branch. Apply the live cluster rollout separately through the LINSTOR controller and the existing `storageclass` object, because already-provisioned resources will not be retroactively changed by the manifest alone.

**Tech Stack:** Flux, Dagger, Kubernetes, Piraeus/LINSTOR, Talos, YAML

---

### File Map

**Files:**
- Modify: `kubernetes/apps/storage-system/piraeus-operator/app/storageclass-linstor-zfs-ssd.yaml`
- Modify: `AGENTS.md`
- Reference: `docs/superpowers/specs/2026-05-01-piraeus-3-replica-design.md`
- Reference: `dagger/flux-local/main.go`

### Task 1: Update The Declarative Default To 3 Replicas

**Files:**
- Modify: `kubernetes/apps/storage-system/piraeus-operator/app/storageclass-linstor-zfs-ssd.yaml`
- Modify: `AGENTS.md`

- [ ] **Step 1: Capture the current branch-side and live baseline**

Run from the feature worktree root:

```bash
grep -n 'placementCount' kubernetes/apps/storage-system/piraeus-operator/app/storageclass-linstor-zfs-ssd.yaml
```

Expected: one line showing `linstor.csi.linbit.com/placementCount: "2"`.

Run from the main repo root at `/home/kid/Code/kid/ops/home-ops` so `.envrc` resolves the real `kubeconfig`:

```bash
direnv exec . kubectl get storageclass linstor-zfs-ssd -o jsonpath='{.parameters.linstor\.csi\.linbit\.com/placementCount}{"\n"}'
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource-group list'
```

Expected: both commands still show `2` for `linstor-zfs-ssd`.

- [ ] **Step 2: Update the storage class manifest in Git**

Set the file contents to:

```yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: linstor-zfs-ssd
provisioner: linstor.csi.linbit.com
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  linstor.csi.linbit.com/storagePool: ssd
  linstor.csi.linbit.com/placementCount: "3"
  linstor.csi.linbit.com/resourceGroup: linstor-zfs-ssd
```

- [ ] **Step 3: Bring `AGENTS.md` in the branch up to date with the Dagger verification path**

Ensure the verification bullet reads exactly:

```md
- For cluster manifest changes, run the Flux-local checks through Dagger as exposed by `dagger.json` and implemented in `dagger/flux-local/main.go`. Use `direnv exec . dagger call flux-local test` to run the repo's cluster test suite and `direnv exec . dagger call flux-local test-build` to run the repo's cluster build suite. For single-cluster or targeted rendering, use `direnv exec . dagger call flux-local build --path clusters/<cluster> --kind all`.
```

- [ ] **Step 4: Verify the branch files now contain the intended values**

Run:

```bash
grep -n 'placementCount' kubernetes/apps/storage-system/piraeus-operator/app/storageclass-linstor-zfs-ssd.yaml
grep -n 'dagger call flux-local' AGENTS.md
```

Expected: the storage class shows `"3"`, and `AGENTS.md` points to `direnv exec . dagger call flux-local ...`.

- [ ] **Step 5: Do not commit unless the user explicitly asks for a commit**

Run only if the user later asks for a commit:

```bash
git add kubernetes/apps/storage-system/piraeus-operator/app/storageclass-linstor-zfs-ssd.yaml AGENTS.md
git commit -m "fix(linstor): default linstor-zfs-ssd to three replicas"
```

### Task 2: Verify The Branch Change With Dagger-Backed Flux Checks

**Files:**
- Reference: `dagger.json`
- Reference: `dagger/flux-local/main.go`

- [ ] **Step 1: Run the repo-wide Flux-local test suite through Dagger**

Run from the feature worktree root:

```bash
direnv allow
direnv exec . dagger call flux-local test
```

Expected: Dagger completes successfully and returns passing output for the configured cluster suite.

- [ ] **Step 2: Run the repo-wide Flux-local build suite through Dagger**

Run:

```bash
direnv exec . dagger call flux-local test-build
```

Expected: Dagger completes successfully and returns passing build output for the configured cluster suite.

- [ ] **Step 3: Render the dev cluster explicitly to catch targeted manifest issues**

Run:

```bash
direnv exec . dagger call flux-local build --path clusters/dev --kind all export --path /tmp/piraeus-3-replica-dev.yaml
```

Expected: `/tmp/piraeus-3-replica-dev.yaml` is written successfully and the command exits `0`.

- [ ] **Step 4: Confirm the rendered output includes the updated storage class**

Run:

```bash
rg -n 'linstor.csi.linbit.com/placementCount: "3"' /tmp/piraeus-3-replica-dev.yaml
```

Expected: at least one match for the `linstor-zfs-ssd` storage class.

### Task 3: Recreate The Live StorageClass And Update The Live LINSTOR Default Before Touching Existing Resources

**Files:**
- No file changes; live cluster operations only

- [ ] **Step 1: Delete the live Kubernetes `StorageClass` before recreating it with the new placement count**

Run from the main repo root at `/home/kid/Code/kid/ops/home-ops`:

```bash
direnv exec . kubectl delete storageclass linstor-zfs-ssd
```

Expected: Kubernetes reports the storage class was deleted. Existing bound PVs remain intact because they reference the provisioned volumes, not the deleted class object.

- [ ] **Step 2: Recreate the live `StorageClass` with placement count 3**

Run:

```bash
cat <<'EOF' | direnv exec . kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: linstor-zfs-ssd
  labels:
    kustomize.toolkit.fluxcd.io/name: piraeus-operator
    kustomize.toolkit.fluxcd.io/namespace: storage-system
provisioner: linstor.csi.linbit.com
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  linstor.csi.linbit.com/storagePool: ssd
  linstor.csi.linbit.com/placementCount: "3"
  linstor.csi.linbit.com/resourceGroup: linstor-zfs-ssd
EOF
```

Expected: Kubernetes reports the storage class was created or configured.

- [ ] **Step 3: Raise the live LINSTOR resource-group default from 2 to 3**

Run:

```bash
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource-group modify linstor-zfs-ssd --place-count 3'
```

Expected: the command exits `0`.

- [ ] **Step 4: Verify the live defaults now both say 3**

Run:

```bash
direnv exec . kubectl get storageclass linstor-zfs-ssd -o jsonpath='{.parameters.linstor\.csi\.linbit\.com/placementCount}{"\n"}'
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource-group list'
```

Expected: the storage class prints `3`, and the `linstor-zfs-ssd` resource group shows `PlaceCount: 3`.

### Task 4: Convert Existing `linstor-zfs-ssd` Resources To Three Diskful Replicas

**Files:**
- No file changes; live cluster operations only

- [ ] **Step 1: Record the current affected PVCs and LINSTOR resources**

Run:

```bash
direnv exec . kubectl get pvc -A -o wide | rg 'linstor-zfs-ssd'
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource list'
```

Expected: six bound PVCs on `linstor-zfs-ssd`, with several third placements still shown as `TieBreaker` or `Diskless`.

- [ ] **Step 2: Ask LINSTOR to auto-place three replicas for each current PVC-backed resource**

Run:

```bash
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc '
linstor resource-definition auto-place pvc-4a148806-9953-49c9-a1ac-fe9c84489ea7 --place-count 3 --storage-pool ssd &&
linstor resource-definition auto-place pvc-3349566b-5f00-4dc2-8335-21ba5e2188da --place-count 3 --storage-pool ssd &&
linstor resource-definition auto-place pvc-85840be1-81dd-42d2-9d41-5524404016df --place-count 3 --storage-pool ssd &&
linstor resource-definition auto-place pvc-bb6f398c-f0e9-46f1-bc16-760cbf48d7fa --place-count 3 --storage-pool ssd &&
linstor resource-definition auto-place pvc-d127a9c0-51e8-4585-a96a-14e08175d0d6 --place-count 3 --storage-pool ssd &&
linstor resource-definition auto-place pvc-4e3af43e-e5b3-43b7-9d27-4610cb2b3694 --place-count 3 --storage-pool ssd
'
```

Expected: each command exits `0` and schedules or confirms a third full placement.

- [ ] **Step 3: Re-check resource state after auto-placement**

Run:

```bash
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource list'
```

Expected: each of the six resources shows three placements. Ideally all three are `UpToDate`; if any third placement is still `TieBreaker` or `Diskless`, continue to the next step.

- [ ] **Step 4: Promote any remaining non-diskful third placements to diskful replicas**

Run only for resources that still show `TieBreaker` or `Diskless` after Step 3:

```bash
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc '
linstor resource toggle-disk talos1 pvc-4a148806-9953-49c9-a1ac-fe9c84489ea7 --default-storage-pool || true
linstor resource toggle-disk talos1 pvc-3349566b-5f00-4dc2-8335-21ba5e2188da --default-storage-pool || true
linstor resource toggle-disk talos2 pvc-85840be1-81dd-42d2-9d41-5524404016df --default-storage-pool || true
linstor resource toggle-disk talos1 pvc-bb6f398c-f0e9-46f1-bc16-760cbf48d7fa --default-storage-pool || true
linstor resource toggle-disk talos2 pvc-d127a9c0-51e8-4585-a96a-14e08175d0d6 --default-storage-pool || true
linstor resource toggle-disk talos2 pvc-4e3af43e-e5b3-43b7-9d27-4610cb2b3694 --default-storage-pool || true
'
```

Expected: any still-diskless or tiebreaker third placements are converted into diskful replicas. Commands that are no longer needed may return a no-op or an error, which is why this step uses `|| true` and must be followed by verification.

- [ ] **Step 5: Wait for replication to settle**

Run:

```bash
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource-definition list && linstor resource list'
```

Expected: all six PVC-backed resources remain `ok`, and each has three healthy placements with no lingering `TieBreaker` or `Diskless` state.

### Task 5: Final Verification And Operator Notes

**Files:**
- No file changes; verification and reporting only

- [ ] **Step 1: Verify the affected PVC inventory still matches expectations**

Run:

```bash
direnv exec . kubectl get pvc -A -o wide | rg 'linstor-zfs-ssd'
direnv exec . kubectl get pv -o wide | rg 'linstor-zfs-ssd'
```

Expected: the same six PVCs remain bound and their PVs are still attached to `linstor-zfs-ssd`.

- [ ] **Step 2: Verify the live LINSTOR layout is healthy**

Run:

```bash
direnv exec . kubectl -n storage-system exec deploy/linstor-controller -- sh -lc 'linstor resource list'
```

Expected: no affected resource is left degraded, diskless, or tiebreaker-only.

- [ ] **Step 3: Verify the branch still contains the desired declarative value**

Run from the feature worktree root:

```bash
grep -n 'placementCount' kubernetes/apps/storage-system/piraeus-operator/app/storageclass-linstor-zfs-ssd.yaml
git status --short
```

Expected: the manifest still shows `"3"`, and `git status` only shows the intended branch changes.

- [ ] **Step 4: Do not push, open a PR, or commit unless the user explicitly asks**

If the user asks for any of those next steps later, use the repo’s normal git and GitHub workflow from the feature worktree.
