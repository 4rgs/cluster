# cluster

A distributed AI node cluster: a CLI orchestrator (`clusterctl`) plus
sample web UI integration. Routes user asks to the right AI node based
on keyword scoring, tracks every ask, and persists data to a local store.

> **License**: MIT — see [LICENSE](LICENSE).
> **Author**: Álvaro González (see [LICENSE](LICENSE))

## What's in the box

- **`bin/clusterctl`** — Python 3.11+ orchestrator CLI. Reads the TOML
  config, pings nodes, routes asks, executes them, optionally stores
  results in Hindsight.
- **`bin/hindsight_client.py`** — minimal client for Hindsight memory
  server (auto-remember every ask, surface memory stats in health).
- **`cluster.toml`** — node configuration (TOML).
- **`PLAN.md`** — development plan / roadmap (free-form notes).
- **`install.sh`** — full install for a fresh Debian/Ubuntu box.
- **`uninstall.sh`** — full uninstall.
- **`check.sh`** — diagnostic check (systemd, port, health, DB).
- **`configure.sh`** — interactive wizard to create `cluster.toml`.

## Install

The full install requires `cluster-web` to be available in parallel:

```sh
sudo \
  INSTALL_DIR=/opt/cluster-web \
  CLUSTER_DIR=/opt/cluster \
  SERVICE_USER=clusteruser \
  ./install.sh
```

After install, run the configuration wizard to set up your first nodes:

```sh
sudo CLUSTER_DIR=/opt/cluster /opt/cluster/configure.sh
```

The wizard walks you through adding one or more nodes, writes
`cluster.toml`, and asks `clusterctl` to verify connectivity.

## Quick check

```sh
sudo ./check.sh
```

Verifies: systemd unit is active, port is listening, `/api/health`
returns 200, `clusterctl` is executable, SQLite DB is readable,
`cluster.toml` is parseable.

## CLI usage

`clusterctl` is a thin wrapper around the `cluster.toml` config:

```sh
clusterctl health                                # JSON of all enabled nodes
clusterctl route "explain async"                # see routing decision
clusterctl ask "implement fibonacci in python"   # run an ask
clusterctl nodes list                            # list all nodes
clusterctl nodes add <name> --host X --model Y --role Z
clusterctl nodes remove <name>
clusterctl nodes enable <name>
clusterctl nodes disable <name>
```

## Config file format

```toml
[meta]
name = "my-cluster"

[routing]
code_keywords = [ "code", "function", "script", ... ]
chat_keywords = [ "explain", "why", "how", ... ]
general_penalty = [ "hello", "thanks", "ok", ... ]

[feedback]
mode_default = "synthesis"

[[node]]
name = "chat-node"
role = "chat_reflection"
host = "node-host-or-ip"
port = 11434
protocol = "ollama"           # ollama | lmstudio | openai | hermes | custom
model = "gemma4:12b-mlx"
timeout_s = 120
enabled = true

[[node]]
name = "code-node"
role = "code_tools"
host = "node-host-or-ip"
port = 1234
protocol = "lmstudio"
model = "your-code-model"
timeout_s = 180
enabled = true
```

Every field is documented inline in the wizard's output.

## Routing algorithm

Each ask is scored against three keyword lists:
- **`code_keywords`** — code/programming intent
- **`chat_keywords`** — Q&A/explanation intent
- **`general_penalty`** — pure chitchat ("hola", "thanks", etc.)

Whichever category has the highest score wins. If no keyword matches,
the ask goes to a `general` role node. If no `general` node exists, the
first enabled node is used as fallback. The `clusterctl route` subcommand
prints the decision without sending the ask — useful for debugging.

## Add a node with auth

```sh
clusterctl nodes add my-cloud-node \
  --host api.openai.com --port 443 \
  --protocol openai --model gpt-4 \
  --role general \
  --token sk-...  # Bearer auth for protected nodes
```

The token is stored verbatim in `cluster.toml` but is masked in API
responses (`***<last4>`). On a 401, the cluster surfaces a clear error.

## Hindsight memory

`clusterctl ask` auto-remembers every successful ask to a Hindsight
memory server (if reachable). Memory stats are visible in the web UI
mesh under the `hindsight` node.

To enable, set `HINDSIGHT_BASE=http://your-hindsight-server:8765` in
the systemd service environment. Bank defaults to `cluster`
(overridable with `HINDSIGHT_BANK`).

## License

MIT — see [LICENSE](LICENSE).
