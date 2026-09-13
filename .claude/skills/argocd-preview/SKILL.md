---
name: argocd-preview
description: Point the prd cluster's ArgoCD at a PR branch to live-test a change to one app, then let it auto-revert. Use when the user asks to "preview this PR/branch on the cluster", "point ArgoCD at this branch", "test this app change live", or similar.
---

This repo's `prd` cluster has one ArgoCD `Application` per app aspect,
each committed with `spec.source.targetRevision: main` and
`syncPolicy.automated.selfHeal: true` (see
`manifests/prd/apps/Application-*.yaml`). A root `apps` Application (same
policy) owns all of those child `Application` objects.

Several apps are cluster-singletons (`openebs`, `cilium`, `coredns`,
`cert-manager`, `argocd`, `sops-operator`) — never deploy a second copy
of one to preview a change. The mechanism below never creates a second
copy of anything: it makes the existing, single `Application` sync from
a branch instead of `main` for a short window, then fall back on its own.

## Procedure

1. If not already logged in this session, run `argocd login --core`. It
   uses the existing `KUBECONFIG` context — no server exposure or extra
   credentials needed.
2. Confirm which app (matches a name under `manifests/prd/apps/`) and
   which branch or PR to preview, if the user did not already say.
3. Run `argocd app diff <app> --revision <branch>` and show the user the
   diff before doing anything live. Confirm it matches the expected
   change.
4. Run `argocd app sync <app> --revision <branch>` to apply it to the
   live cluster.
5. Tell the user this is temporary by design: the committed
   `targetRevision` is still `main`, so ArgoCD's selfHeal reverts the app
   back to `main` on its own on the next reconcile cycle (default ~3
   min). No manual revert step is needed.

## Holding a preview open longer

If the user wants the preview to survive past one reconcile cycle, pause
auto-sync on **both** the target app and the root `apps` Application:

```
argocd app set <app> --sync-policy none
argocd app set apps --sync-policy none
```

Pausing only the target app is not enough — the root `apps` Application
owns the child `Application` object as a managed resource, and its own
selfHeal would revert the child's `syncPolicy` field back to `automated`,
which then immediately reverts the branch preview back to `main`.

When the user is done, restore both:

```
argocd app set <app> --sync-policy automated
argocd app set apps --sync-policy automated
```

Confirm with `argocd app get <app>` that it lands back on `main`.

## Guardrail

Never run this procedure against `openebs`, `cilium`, `coredns`,
`cert-manager`, `argocd`, or `sops-operator` without the user explicitly
confirming first. A bad live sync on one of these has a much larger blast
radius than on a namespaced app like `external-dns`.
