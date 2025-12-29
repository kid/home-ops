resource "routeros_queue_type" "cake_rx" {
  name = "cake-rx"
  kind = "cake"

  cake_nat        = true
  cake_diffserv   = "diffserv4"
  cake_flowmode   = "triple-isolate"
  cake_rtt_scheme = "regional"
  cake_overhead   = 18
  cake_mpu        = 88
}

resource "routeros_queue_type" "cake_tx" {
  name = "cake-tx"
  kind = "cake"

  cake_nat        = true
  cake_diffserv   = "diffserv4"
  cake_flowmode   = "triple-isolate"
  cake_rtt_scheme = "regional"
  cake_ack_filter = "filter"
  cake_overhead   = 18
  cake_mpu        = 88
}

resource "routeros_queue_tree" "rx" {
  name        = "default-rx"
  parent      = var.bridge_name
  max_limit   = var.limit_rx
  queue       = routeros_queue_type.cake_rx.name
  packet_mark = ["no-mark"]
}

resource "routeros_queue_tree" "tx" {
  name        = "default-tx"
  parent      = var.wan_interface
  max_limit   = var.limit_tx
  queue       = routeros_queue_type.cake_tx.name
  packet_mark = ["no-mark"]
}
