# oc-netlab

`netlab` is a Wireshark-like network debugger for the OpenComputers OpenOS environment. It captures `modem_message` traffic, shows a live scrolling view, records to JSONL capture files, and replays traffic with original timing.

```
netlab [live] (p pause, f filter, s save, e export, r replay, q quit)
  12.53 <- remote-1 lp=123  rp=-     len=12 d=3 hello world
  12.89 -> remote-2 lp=-    rp=321   len=4  pong
rate: 4.2 msg/s  avg size: 8.5 bytes  total: 31  errors: 0
```

## Install

### Quick install (recommended)

Copy the repository to an OpenOS computer and run:

```
cd installer
install.lua
```

This copies files into `/bin/netlab`, `/lib/netlab`, and `/etc/netlab` and creates `/home/netlab/captures`.

### Manual install

Copy the contents of `openos/` into `/` on the OpenOS machine.

## Quick start

* Live sniffer:
  ```
  netlab
  ```
* Replay a capture at 2x speed:
  ```
  netlab replay /home/netlab/captures/capture-123.jsonl --speed 2
  ```
* Send a quick message:
  ```
  netlab send --to <addr> --port 123 --data "hello"
  ```
* Ping/pong RTT test:
  ```
  netlab ping --to <addr> --port 123
  netlab ping --listen --port 123
  ```

Capture files default to `/home/netlab/captures/`. Example JSONL capture files are in `examples/captures/`.

## Features

* Live `modem_message` sniffer with filters (port, remote address, payload substring/regex, direction).
* Structured JSONL capture with schema versioning.
* Ring buffer to avoid memory blowups and periodic flush to disk.
* Replay mode with timing control and optional dry-run.
* Outbound capture by wrapping `modem.send`/`modem.broadcast`.
* CLI helpers: `send` and `ping`.

## Troubleshooting

* **No modem found**: Attach a modem component and try again.
* **No events showing**: Ensure the modem has the desired ports open. OpenComputers only emits `modem_message` for open ports.
* **Capture files not created**: Verify `/home/netlab/captures` exists and you have write permissions.

## Developer notes

* OpenComputers dispatches `modem_message` events only for open ports; `netlab` does not open all ports automatically.
* Replay mode uses a local dispatcher that emits virtual `modem_message` events so the TUI path remains identical.
* The JSON encoder/decoder in `netlab.utils` is intentionally small and only supports the types emitted by `netlab`.

## License

MIT. See [LICENSE](LICENSE).
