set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_dir() + '/talos'
domain := 'kidibox.net'
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`

[private]
default:
    just -l talos

[doc('Apply Talos config to a node')]
apply-node node *args:
    just log info "Applying Talos machineconfig" "node" "{{ node }}";
    just talos render-config "{{ node }}" | talosctl -n "{{ node }}" apply-config -f /dev/stdin {{ args }}

apply-cluster:
    #!/usr/bin/env bash
    for node in $(talosctl get members -o json | jq -rs '.[].node')
    do
        just talos apply-node "$node"
    done

[doc('Render Talos config for a node')]
render-config node:
    nodename="{{ node }}"; \
    nodename="${nodename%%.*}"; \
    export IS_CONTROLLER="$(just talos machine-controller "{{ node }}")"; \
    talosctl machineconfig patch <(just template "{{ talos_dir }}/machineconfig.yaml.j2") -p @<(just template "{{ talos_dir }}/nodes/${nodename}.yaml.j2")

[doc('Generate schematic ID from Talos schematic')]
gen-schematic-id:
    curl -sX POST --data-binary "@{{ talos_dir }}/schematic.yaml" "https://factory.talos.dev/schematics" | jq -r '.id'

[private]
machine-controller node:
    nodename="{{ node }}"; \
    nodename="${nodename%%.*}"; \
    just template "{{ talos_dir }}/nodes/${nodename}.yaml.j2" | yq -e 'select(.machine) | (.machine.type == "controlplane") // ""'

[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
    talosctl -n "{{ controller }}" upgrade-k8s --to {{ version }}

[doc('Upgrade Talos version on a node')]
upgrade-node node *args:
    talosctl -n "{{ node }}" upgrade -i "$(just talos machine-image)" -m powercycle --timeout=10m {{ args }}

[private]
machine-image:
    just template "{{ talos_dir }}/machineconfig.yaml.j2" | yq -re 'select(.machine) | .machine.install.image'
