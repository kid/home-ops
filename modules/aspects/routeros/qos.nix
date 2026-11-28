# Queues on a RouterOS device: CAKE on the bridge (download) and the WAN
# interface (upload), from the device's routerosInputs.qos (see
# modules/fleet/routeros/rb5009.nix).
{ lib, ... }:
let
  # Shared by both directions' CAKE queue types.
  cake = {
    kind = "cake";
    cake_nat = true;
    cake_diffserv = "diffserv4";
    cake_flowmode = "triple-isolate";
    cake_rtt_scheme = "regional";
    cake_overhead = 18;
    cake_mpu = 88;
  };
in
{
  den.aspects.routeros.qos.tofu =
    { routerosDevice, ... }:
    let
      inherit (routerosDevice.aspect.routerosInputs.qos) inputs;
    in
    {
      resource.routeros_queue_type = {
        qos_cake_rx = cake // {
          name = "cake-rx";
        };
        qos_cake_tx = cake // {
          name = "cake-tx";
          cake_ack_filter = "filter";
        };
      };

      resource.routeros_queue_tree = {
        qos_rx = {
          name = "default-rx";
          parent = inputs.bridge_name;
          max_limit = inputs.limit_rx;
          queue = "\${routeros_queue_type.qos_cake_rx.name}";
          packet_mark = [ "no-mark" ];
        };
        qos_tx = {
          name = "default-tx";
          parent = inputs.wan_interface;
          max_limit = inputs.limit_tx;
          queue = "\${routeros_queue_type.qos_cake_tx.name}";
          packet_mark = [ "no-mark" ];
        };
      };

      # From the catalog's ros-qos module, which the stack called until
      # these were ported. Drop once applied.
      moved =
        {
          "routeros_queue_type.cake_rx" = "routeros_queue_type.qos_cake_rx";
          "routeros_queue_type.cake_tx" = "routeros_queue_type.qos_cake_tx";
          "routeros_queue_tree.rx" = "routeros_queue_tree.qos_rx";
          "routeros_queue_tree.tx" = "routeros_queue_tree.qos_tx";
        }
        |> lib.mapAttrsToList (
          from: to: {
            from = "module.qos.${from}";
            inherit to;
          }
        );
    };
}
