# Handoff: making `terragrunt-stacks` support `den.quirks`/`pipe.collect`

**Status: resolved.** `modules/terragrunt/collect.nix`'s `instantiate` now routes through a real
`lib.evalModules` pass (per stack-module, freeform-typed, `specialArgs = { inherit device
firewall; }`), so quirks/`pipe.collect` do work against `"terragrunt-stacks"` now — see
`modules/network/aspects/ros-firewall.nix`'s `{ device, firewall ? [ ], ... }:` for a real
consumer, and `modules/network/aspects/network-internet-access.nix` / `modules/clusters/prd.nix`
for producers. This answers this doc's own open question 3 ("does this repo actually need this
at all") with a concrete yes: network-level "internet access" + cluster-level router-access
firewall rules needed exactly this "many decoupled producers, one consumer" shape. The rest of
this document is kept as-is below as the historical investigation record — it's still accurate
about *why* the naive approach failed and what the fix required; see `AGENTS.md`'s "Network /
Terragrunt" section for the current condensed summary, including two non-obvious gotchas hit
while implementing the fix (an anonymous companion module in `modules`, and `pipe.collectAll`
predicates needing to name their target entity kind).

## Context: why this file exists

While improving `modules/network/` (den user-registry work, dropping the private `tf`
namespace, deduping cross-device data), we hit a real duplication bug: `modules/devices/
rb5009.nix` hardcoded crs320's own Management-VLAN address and MAC address in two places (a
DHCP static lease entry, a firewall rule), while `modules/devices/crs320.nix` independently
declared the same address for itself. The natural, "den-idiomatic" fix — and the one
initially preferred, since it mirrors a pattern the user pointed at approvingly in a sibling
repo (`nix-config`'s `modules/den/policies/pipes.nix`) — was a `den.quirks` + `pipe.collect`:
each device emits its own address/MAC as quirk data, and any device that needs a sibling's
data collects it, instead of hardcoding.

That was implemented, tested empirically against a live `nix eval`, and **it does not work**
with this repo's current `"terragrunt-stacks"` collection mechanism. We fell back to a
direct schema field instead (`den.devices.crs320.managementHostNum`/`.managementMac`, read
directly via `config.den.devices.crs320.*` from `rb5009.nix`) for the address-dedup fix
itself — that part is done, committed, and out of scope for this document. This document is
specifically about *the thing that didn't work*, for whoever wants to make it work later.

## The problem, precisely

`modules/terragrunt/collect.nix` registers `"terragrunt-stacks"` directly on `den.classes`
(a home-ops-invented class — RouterOS/Terraform data, not a NixOS-native output) and collects
it per-device via:

```nix
den.policies.device-to-terragrunt =
  { device, ... }:
  [
    (den.lib.policy.instantiate {
      name = "${device.name}-terragrunt";
      class = "terragrunt-stacks";
      instantiate =
        { modules, ... }:
        lib.listToAttrs (
          map (
            m:
            let
              content = builtins.head m.imports;
            in
            lib.nameValuePair content.stack (removeAttrs content [ "stack" ])
          ) modules
        );
      intoAttr = [ "terragruntStacks" device.name ];
    })
  ];
```

The `instantiate` function's job is to turn the walked, wrapped `modules` list into the final
plain attrset (`{ base = {...}; capsman = {...}; ... }`). It does this by assuming
`builtins.head m.imports` is already fully-resolved plain data (`{ stack; moduleSource;
inputs; ... }`) for every item in `modules`.

**That assumption breaks the moment any of the aspects contributing to this class (e.g.
`modules/network/aspects/ros-base.nix`'s `"terragrunt-stacks"` content function) requests a
`den.quirks` value as a real named function parameter** — e.g.:

```nix
"terragrunt-stacks" = { device, someQuirk ? [ ], ... }: { ... };
```

When a content function's formal parameter pattern names a quirk, den's pipeline defers that
aspect's content into a wrapped, not-yet-evaluated module object (has `__functor`/
`__functionArgs`, not the plain attrset shape `instantiate` expects). Normally, that
deferred wrapper gets resolved by a *later* `lib.evalModules` pass — this is how den's
built-in classes (`nixos`, `homeManager`) actually work: they get fed into a real
`evalModules` call somewhere downstream, which is what finally supplies `_module.args` (the
quirk values) and calls each module function with the correct merged arguments.

**Our custom `instantiate` function never performs that `evalModules` pass.** It just does
`builtins.head m.imports` directly on the raw wrapped-or-not module list. So the moment a
quirk is requested, `content.stack` (etc.) doesn't exist yet — the whole thing crashes with
`error: attribute 'stack' missing`, because `content` is actually a curried function still
waiting for its quirk args, not the resolved attrset.

## How this was confirmed (not just theorized)

1. Declared a real quirk (`den.quirks.deviceMgmtAddr`), had `rb5009`/`crs320`'s own
   `den.aspects.<name>` emit it (`{ device, ... }: { hostNum = ...; mac = ...; };`), added a
   `pipe.collect` policy on `den.schema.device.includes` (mirroring the existing, so-far-
   unconsumed `k3s-nodes` quirk in `modules/den/aspects/services/k3s.nix` +
   `modules/den/policies/pipes.nix`).
2. First test: requested the quirk via an `@`-binding + string-select
   (`ctx@{ device, ... }: ... ctx."device-mgmt-addr" or [ ] ...`) — quirk name was hyphenated.
   Result: `ctx` only ever contained `{ device }`. Nothing else arrived at all.
3. Hypothesis: den's quirk-injection relies on `builtins.functionArgs`-style introspection of
   the content function's *own declared parameter names* to decide what to inject (matching
   the quirks-and-pipes docs' own phrasing: "When an aspect requires a quirk argument
   (`{ firewall, ... }:`), the pipeline defers its inclusion"). A hyphenated name can't be
   written as a real formal parameter (`{ device, "x-y", ... }:` is a Nix syntax error,
   confirmed via `nix-instantiate --eval`), so a hyphenated quirk name may never be
   requestable via the standard mechanism at all — the `@`-binding-only version never
   "asks" for it in the way den's introspection checks for.
4. Renamed the quirk to camelCase (`deviceMgmtAddr`) and requested it as a real named
   parameter: `{ device, deviceMgmtAddr ? [ ], ... }:`. This changed the failure mode —
   confirming the hypothesis, the quirk request *was* now recognized — but the whole
   evaluation crashed instead of returning the quirk's data:
   ```
   error: attribute 'stack' missing
     at modules/terragrunt/collect.nix:44:33
   ```
5. Instrumented `collect.nix`'s `instantiate` temporarily to inspect `modules` directly.
   Found: for the one aspect requesting the quirk (`ros-base.nix`), `builtins.head m.imports`
   was a value with `builtins.attrNames` = `["__functionArgs", "__functor"]` — i.e. a
   function-like wrapper object, not resolved data. Every *other* aspect (capsman/dns/
   firewall/qos, none of which request any quirk) correctly showed
   `["dependsOn","inputs","moduleRef","moduleSource","moduleVersion","stack"]` — fully
   resolved plain data, as `instantiate` expects.
6. Read den's actual pinned source (`nix/lib/aspects/fx/wrap-classes.nix`,
   `wrapCollectedClasses`/`processEntry`/`wrapClassModule`) — confirmed this wrapping is a
   real, designed pipeline stage meant to be finalized by a downstream `evalModules`-style
   consumer, which `collect.nix`'s `instantiate` is not.
7. Checked `nixopslab`'s own equivalent (`modules/terranix/collect.nix`, the thing this
   repo's `collect.nix` is explicitly modeled on) — it uses the identical `instantiate =
   { modules, ... }: modules;` pattern (even simpler — doesn't even unwrap `m.imports`), and
   **none of nixopslab's own `terranix`-class content functions request any quirk value
   either**. So this exact combination (custom `instantiate`-collected class + quirk
   consumption) has no working precedent anywhere we could find — not in this repo, not in
   the repo this code was modeled on.

## What we did instead (already committed, not part of this handoff)

Abandoned quirks for the address-dedup fix specifically. Added two plain fields to the
device schema (`modules/den/schema/devices.nix`): `managementHostNum`, `managementMac`.
`crs320.nix` sets them once; `rb5009.nix` reads `config.den.devices.crs320.managementHostNum`/
`.managementMac` directly instead of the two hardcoded literals. Plain config read, no
`resolve.to`, no quirks — same reasoning as `den.users.registry`/`den.groups` elsewhere in
this repo (single producer, single consumer, no real "many decoupled siblings" problem to
solve).

## The actual fix, if someone wants to do this properly later

`instantiate`'s `{ modules, ... }: ...` function would need to route `modules` through a real
`lib.evalModules` call before extracting per-stack content, e.g. roughly:

```nix
instantiate =
  { modules, ... }:
  let
    evaluated = lib.evalModules {
      modules = map (m: { imports = [ m ]; }) modules; # or however den's own wrapper shape needs feeding in — verify
      # specialArgs: needs figuring out. Real classes get their quirk values
      # injected via _module.args by whatever machinery calls evalModules for
      # them (probably in nix/lib/aspects/fx/ somewhere near class-module.nix
      # or wrap-classes.nix's caller) — this needs tracing, not guessing.
    };
  in
  # then extract per-stack content from evaluated.config instead of
  # m.imports directly — but note: our "modules" aren't real NixOS-style
  # option/config declarations, they're flat data merged via plain `//`, so
  # this may also require each ros-*.nix content function to declare actual
  # `options.stack`/`options.inputs`/etc. instead of just returning a plain
  # attrset — i.e. this might not be a small change to collect.nix alone,
  # it could require reshaping every ros-*.nix file's content function too.
```

Open questions to resolve before implementing, not answered by this investigation:

1. **Where exactly does den inject quirk values into `_module.args` for a real class
   evaluation?** We found the wrapping side (`wrap-classes.nix`) but not the call site that
   actually runs `evalModules` for `nixos`/`homeManager` classes with the right
   `specialArgs`. Trace that first — it's the thing to replicate, not guess at.
2. **Do the `ros-*.nix` content functions need to become real NixOS-style modules (with
   `options.*` declarations) to work under `evalModules`, or can they stay plain
   attribute-returning functions?** If the former, this is a much bigger rewrite than "fix
   `collect.nix`" — it touches all five `ros-*.nix` files' shape, not just the collection
   glue.
3. **Does this repo actually need this at all right now?** At the time of writing, there is
   exactly one already-declared-but-unconsumed quirk in this repo (`k3s-nodes`, for a future
   Cilium BGP config — see `modules/den/aspects/services/k3s.nix` +
   `modules/den/policies/pipes.nix`), and it's declared on the **host** entity kind (a
   NixOS-native class, `nixos`), not the device/terragrunt-stacks side — so even `k3s-nodes`
   doesn't exercise this specific gap. Confirm there's an actual, current need for a device
   (RouterOS) aspect to consume a quirk before investing in this — it's entirely possible the
   direct-schema-field pattern (`managementHostNum`/`managementMac`, or similar) is just the
   right tool for every case that comes up in a 2-3 device fleet, and this rework is never
   actually worth doing.

## Where to look

- `modules/terragrunt/collect.nix` — the `instantiate` function, unchanged from before this
  investigation (no TODO comment was left in the code; this file is the TODO).
- `modules/network/aspects/ros-base.nix` — the actual would-be quirk consumer, if this is
  ever revisited (it's where `routeros_users`/`routeros_groups` are already merged from
  `den.users.registry`/`den.groups` via plain reads — a real quirk consumer would sit right
  alongside that).
- `AGENTS.md`'s "Network / Terragrunt" section has a one-paragraph summary of this same
  finding, for anyone who hasn't found this file yet.
- den's pinned source, if still cached locally at time of reading this: was accessible via
  `nix flake archive` → `/nix/store/<hash>-source` during this investigation, specifically
  `nix/lib/aspects/fx/wrap-classes.nix`, `nix/lib/policy-effects.nix` (the `instantiate`
  effect constructor itself), and `nix/lib/aspects/fx/key-classification.nix`. Re-fetch fresh
  if this store path has been garbage-collected.
