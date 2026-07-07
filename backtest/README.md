# Backtest HDB

One-process q HDB that holds prod-seeded read data and accepts streaming result writes from a Java simulation. All params live in `qenv.conf`.

## 0. Prerequisites

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

## 1. Configure

Edit `qenv.conf`:

```bash
export PROD_HOST="prod-kdb.host"
export PROD_PORT="5000"
export START_DATE="2026.05.01"
export END_DATE="2026.05.20"
export HDB_PATH="$HOME/data/kdb/hdb"
export KDB_PORT="5042"
```

## 2. Seed prod data

Run once per date range. Idempotent — skips partitions already on disk.

```bash
./run-seed.sh
```

Tables pulled are listed in `pulls.q` (default: `mainQuote`, `lmfxTrade`). To add a table, append its name to `.bt.pulls.tables`.

## 3. Start the HDB

Long-lived. Loads the seeded HDB, replays any unflushed write-ahead logs, opens `KDB_PORT` for Java.

```bash
./run-hdb.sh
```

## 4. Run a simulation (from Java)

```java
c conn = new c("localhost", 5042);

// Declare the simulated date — survives a crash via persisted simDate file
conn.k(new Object[]{".bt.setSimDate", new c.Date(/* sim date */)});

// Stream events. rows = c.Flip matching schemas.q
for (...) {
    conn.k(new Object[]{".bt.upd", "btPnl", rows});
}

// End of simulated day — persist + clear live + truncate log
conn.k(new Object[]{".bt.flush", "btPnl", new c.Date(/* sim date */)});
```

If the q process crashes mid-day, restart it: `.bt.live.btPnl` is rebuilt from the write-ahead log at `<HDB_PATH>.live/btPnl`, and `.bt.cfg.simDate` is restored. Each logged message is tagged with the active sim date, and on replay messages tagged on-or-before the persisted `.bt.lastFlushed[tbl]` marker are dropped — so a crash *between* `.Q.dpft` and log truncation will not double-write or cross-contaminate the next day. Java continues where it left off.

## 5. Check results

Connect a q client to the same port:

```bash
q -p 0
q) h:hopen `::5042
q) h "tables[]"                                          / all tables
q) h "key `.bt.live"                                     / streaming tables
q) h "count .bt.live.btPnl"                              / live rows today
q) h ".bt.viewLive `btPnl"                               / live snapshot
q) h "select from btPnl where date=2026.05.20"           / historical, one date
q) h (`.bt.view; `btPnl; 2026.05.01; 2026.05.20)         / union live + history
q) h "select count i, sum pnl by date from btPnl"        / aggregate across dates
```

From Java, the same expressions go through `conn.k(...)`.

## Files

- `qenv.conf` — single source of params; sourced by both shell scripts
- `pulls.q` — list of tables to seed + optional per-table query overrides
- `schemas.q` — in-memory streaming tables under `.bt.live.*`
- `seed.q` — pulls prod data via IPC, writes local date partitions
- `hdb.q` — long-lived HDB + streaming write API + write-ahead log
- `run-seed.sh`, `run-hdb.sh` — wrappers that source `qenv.conf`

## Caveats

- **Log writes are not fsync'd by default.** A clean q-level crash replays correctly; a power loss or kernel panic can lose the log tail. Pass `-sync 1` to `hdb.q` to call `system "sync"` after every `.bt.upd` (slower, but durable).
- **Flush is not transactional across `.Q.dpft` → `lastFlushed` → log truncate.** The window between `.Q.dpft` and the `lastFlushed` marker save is small but non-zero: if q dies in that window, on restart the log replays into live and the next flush would double-write that day. Recover: `rm -rf $HDB_PATH/<date>/<tbl>` and rerun. The window between `lastFlushed` and log truncate is safe — stale messages are dropped on replay.
- **`.bt.upd` requires `setSimDate` first.** It signals `SimDateNotSetException` if simDate is null. This is so logged messages can be tagged with their date for crash recovery.
- **Live data has no `date` column** until `.bt.view` stamps it with `.bt.cfg.simDate`. Set `simDate` before streaming or live rows won't appear in unioned views.
- **Single-threaded.** Heavy historical queries block streaming writes on the same port. If that hurts, start a second read-only q against the same `HDB_PATH` on a different port.
