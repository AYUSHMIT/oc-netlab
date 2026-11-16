# oc-netlab

A terminal network debugger for **OpenComputers running OpenOS in Minecraft**. Inspect modem messages, filter a live event view, save JSONL captures, and replay a trace at a chosen speed.

The project combines a small capture library with an interactive Lua CLI. Its useful engineering pieces are event-driven collection, a bounded display buffer, buffered file writes, reversible modem instrumentation, and a replay dispatcher.

## Try a trace without Minecraft

From a local checkout, using **Lua 5.2 or 5.3**:

```sh
git clone https://github.com/AYUSHMIT/oc-netlab.git
cd oc-netlab
lua tests/run.lua
lua examples/replay.lua examples/captures/sample.jsonl 2
```

The last command replays the included two-message fixture at 2× speed and prints:

```text
1.20 inbound  remote-1 port=123 hello
2.10 outbound remote-2 port=321 pong
```

This offline demo reads stored records; it needs no modem and sends no traffic. The fixture is an example, not a performance benchmark.

## Install in OpenOS

Copy this repository onto an OpenOS computer with a screen, GPU, keyboard, modem, and writable filesystem. From the repository root:

```sh
cd installer
install.lua
cd ..
netlab help
netlab replay examples/captures/sample.jsonl --speed 2 --dry-run
```

The installer copies `openos/` into the filesystem root, including `/bin/netlab`, `/lib/netlab/`, and `/etc/netlab/config.lua`. It also creates `/home/netlab/captures/`. Reinstalling replaces the installed files, including the config.

For live capture, open the ports your application uses before starting:

```sh
netlab
```

The inspector does not open every modem port. When multiple modems are present, it prompts for one.

### Live controls

| Key | Action |
| --- | --- |
| `p` | Pause/resume automatic display refresh; collection continues |
| `f` | Filter by port, remote address, direction, or payload preview |
| `s` | Start/stop a new JSONL recording |
| `e` | Export the current ring buffer |
| `r` | Open a saved trace for replay |
| `c` | Clear the display buffer and statistics |
| `q` | Flush pending records, stop capture, and exit |

Payload filters inspect the preview of the first payload value. Pattern filters use **Lua patterns**, not regular expressions. Display filtering does not remove records from a recording or export.

### Send and ping

Use the full receiver modem address in place of `RECEIVER_MODEM_ADDRESS`:

```sh
netlab send --to RECEIVER_MODEM_ADDRESS --port 123 --data "hello"
netlab ping --to RECEIVER_MODEM_ADDRESS --port 123 --timeout 5
```

For ping, run the responder on the other computer first:

```sh
netlab ping --listen --port 123
```

The responder opens port 123. A separate application receiving `send` traffic must open its own port.

## Capture and replay

A capture contains one schema-versioned JSON header followed by one event per line. Records include direction, timestamps, modem addresses, port, distance when available, payload values, an estimated payload length, and a printable preview.

- **Recording** appends new events and periodically flushes pending writes.
- **Export** snapshots all records currently retained in the ring.
- **Dry-run replay** preserves stored record metadata, including direction and timestamps.
- **Dispatched replay** feeds reconstructed `modem_message` events into a private dispatcher. Capture then records them as inbound events with replay-time timestamps.

Neither replay mode transmits through the real modem. Use `--dry-run` when inspecting the original trace:

```sh
netlab replay /home/netlab/captures/capture-123.jsonl --speed 2 --dry-run
```

Replace the filename with an existing capture and use a positive speed factor. Replay loads the entire file into memory, so keep traces within the computer's memory budget.

### Configuration

Edit `/etc/netlab/config.lua`:

| Setting | Default | Purpose |
| --- | --- | --- |
| `capture_dir` | `/home/netlab/captures` | Recordings and exports |
| `ring_size` | `512` | Maximum records retained for display/export |
| `sample_rate` | `1` | Keep all records; a fraction below 1 enables random sampling |
| `flush_interval` | `2` | Seconds between recording flushes |
| `preview_len` | `64` | Payload preview budget |
| `stats_window` | `5` | Seconds used for the message-rate window |
| `ui_refresh` | `0.1` | Event-loop polling interval in seconds |

## Code map

| Component | Responsibility |
| --- | --- |
| [CLI](openos/bin/netlab.lua) | Terminal view, controls, modem selection, send/ping |
| [Capture](openos/lib/netlab/capture.lua) | Event collection, outbound wrappers, JSONL writes |
| [Replay](openos/lib/netlab/replay.lua) | Trace loading, timing, private event dispatch |
| [Ring](openos/lib/netlab/ring.lua) | Bounded oldest-first event history |
| [Filters](openos/lib/netlab/filters.lua) | Port/address/direction and preview matching |
| [Schema](openos/lib/netlab/schema.lua) / [utilities](openos/lib/netlab/utils.lua) | Record versioning, JSON, timing, previews |
| [Tests](tests/) | Six test files covering core behavior and regression cases |

## Validation and limits

The six test files and offline demo pass under Lua 5.2 and 5.3. Regression coverage includes launcher argument forwarding, modem argument/return preservation, final-record flushing, replay timing, and nonblocking timer registration. These host-side checks use mocked OpenOS interfaces; they do not replace an in-game installation/TUI test.

Capture visibility is limited to modem events delivered to this computer on open ports. Outbound instrumentation covers calls through the wrapped modem proxy, not every program or device on the network. Payload length is an estimate, not a wire-byte measurement. The JSON codec targets simple capture payloads; it is not a general-purpose JSON implementation.

If the live view is empty, check the selected modem and receiving port. If saving fails, check the capture directory and available space. Use a positive replay speed and a capture produced by netlab.

[MIT license](LICENSE).
