# kx-backtest

A local kdb+ backtesting harness for b2c2 cash-vs-derivative strategy simulations. It lets you replay strategy logic against historical production inputs entirely on your own machine, then query the simulated output alongside the seeded history.

It does two things:

1. **Seed** — pulls read-only market and strategy data (underlier mids, volatility, book risk, carry cost, available balances, strategy decisions, …) from a production kdb instance into a local, date-partitioned HDB — or into flat CSV files. Pull specifications live in `backtest/pulls.q`.
2. **Capture** — runs a long-lived single-process q HDB that a Java strategy simulation streams its results into (PnL, signals, order instructions, …), persisting each simulated day to disk with crash-safe write-ahead logging.

## Repository layout

- **`backtest/`** — the HDB, the seed / CSV-dump scripts, the streaming write API, and the shell wrappers that run them. All runtime params live in `backtest/qenv.conf`.

## Prerequisites

Everything here shells out to the `q` (kdb+) binary, so you need a local kdb+ install with `q` on your `PATH`. Bash 4+ and `unzip` are also assumed (both ship with macOS/Linux).

### Install kdb+

1. **Get the binary.** Grab kdb+ Personal Edition (free, non-commercial) from <https://kx.com/kdb-personal-edition-download/>, or use b2c2's commercial licence bundle if you have one. Pick the build for your OS — the zip contains a per-arch folder: `m64` (macOS), `l64` (Linux), `w64` (Windows).

2. **Unzip to `QHOME`.** Convention is `~/q`:

   ```bash
   unzip <downloaded>.zip -d ~/q
   ```

3. **Install the licence.** Personal Edition emails you a `kc.lic`; drop it in `QHOME`. Internal users: use the company `k4.lic`/`kc.lic` instead.

   ```bash
   mv ~/Downloads/kc.lic ~/q/
   ```

4. **Set the environment** — add to `~/.zshrc` (or `~/.bashrc`). Use the arch folder that matches your OS:

   ```bash
   export QHOME="$HOME/q"
   export PATH="$QHOME/m64:$PATH"   # m64=macOS, l64=Linux, w64=Windows
   ```

   > Apple Silicon: recent Personal Edition builds are native ARM. Older builds are x86 and need Rosetta (`softwareupdate --install-rosetta`).

5. **(Optional) nicer REPL.** kdb+ has no line editing on its own; wrap it with `rlwrap`:

   ```bash
   brew install rlwrap          # macOS;  apt-get install rlwrap on Debian/Ubuntu
   alias q='rlwrap -r q'
   ```

### Verify

Open a new shell and start q — you should get the version banner and a `q)` prompt:

```bash
$ q
KDB+ 4.1 ...
q)til 5
0 1 2 3 4
q)\\             / exit
```

If you see `'k4.lic` (licence error) the licence file isn't in `QHOME`; if `q: command not found`, `PATH` isn't picking up the arch folder.

## Getting started

1. Install kdb+ (above).
2. Follow the workflow in **[`backtest/README.md`](backtest/README.md)** — configure `qenv.conf`, seed prod data, start the HDB, stream a simulation, and query results.

## Documentation

- **[`backtest/README.md`](backtest/README.md)** — the full backtest HDB workflow, streaming write API, and operational caveats.
