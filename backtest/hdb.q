// Backtest HDB process
// kx-backtest @ b2c2

// DOCUMENTATION:
// Long-lived q process that mounts the local HDB tree (seeded by seed.q) and
// listens for IPC connections from Java.
//
// Streaming write path (crash-safe):
//   .bt.setSimDate[dt]     - declare which sim date subsequent .bt.upd belongs to
//                            (required before .bt.upd; persisted across crashes)
//   .bt.upd[tbl; rows]     - schema-check rows, write-ahead-log tagged with
//                            simDate, then append to .bt.live.<tbl>
//   .bt.flush[tbl; dt]     - persist .bt.live.<tbl> as a date partition, write
//                            lastFlushed marker, truncate log, reload HDB
//
// Batch alternative (no log):
//   .bt.writeResult[tbl;dt;rows]
//
// Reads:
//   .bt.viewLive[tbl]                  - current in-memory snapshot
//   .bt.view[tbl; startDt; endDt]      - unions on-disk partitions with live
//                                        (live rows tagged with .bt.cfg.simDate)
//
// Crash safety: each .bt.upd appends a serialized message to a kdb log file
// at <hdb>.live/<tbl>. Messages are tagged with the active simDate. On
// startup the log is replayed via -11!, rebuilding .bt.live.<tbl> exactly
// as before the crash, EXCEPT messages tagged with a date <= the persisted
// .bt.lastFlushed[tbl] marker are dropped (they were already persisted by a
// flush that died before truncating the log). .bt.flush truncates the log.
//
// Durability caveat: log writes are not fsync'd. A clean q-level crash is
// recoverable; a power loss / kernel panic can lose the tail. Pass
// -sync 1 to call `system "sync"` after every .bt.upd (slower).
//
// Usage:
//   q hdb.q -hdb <path> -port <port>


\l schemas.q


.bt.hdb.cfg.path:`;
.bt.hdb.cfg.port:0;
.bt.hdb.cfg.logPath:`;
.bt.hdb.cfg.sync:0b;

.bt.cfg.simDate:0Nd;
.bt.log.handles:(`symbol$())!`int$();
.bt.lastFlushed:(`symbol$())!`date$();


.bt.hdb.parseArgs:{[]
    args:.Q.opt .z.x;
    .bt.hdb.cfg.path:hsym `$first args`hdb;
    .bt.hdb.cfg.port:"J"$first args`port;
    .bt.hdb.cfg.logPath:hsym `$1_string[.bt.hdb.cfg.path],".live";
    .bt.hdb.cfg.sync:`sync in key args;

    if[(""~first args`hdb) or null .bt.hdb.cfg.port;
        -2 "Missing arg. Need -hdb -port";
        exit 1;
    ];
    if[not type key .bt.hdb.cfg.path;
        -2 "HDB path does not exist: ",string .bt.hdb.cfg.path;
        exit 1;
    ];
 };


// `\l` walks the HDB directory and parses every entry as a partition. macOS
// Finder/Spotlight dropping `.DS_Store` files in there will crash the load
// with 'parse `:.../.DS_Store. Scrub them before each load.
.bt.hdb.loadHdb:{[]
    system "find ",1_string[.bt.hdb.cfg.path]," -name .DS_Store -delete";
    system "l ",1_ string .bt.hdb.cfg.path;
 };


.bt.hdb.init:{[]
    .bt.hdb.parseArgs[];
    .bt.hdb.loadHdb[];
    .bt.log.ensureDir[];
    .bt.log.restoreSimDate[];
    .bt.log.loadLastFlushed[];
    .bt.log.replayAll[];
    system "p ",string .bt.hdb.cfg.port;
    -1 "HDB ",string[.bt.hdb.cfg.path]," ready on port ",string .bt.hdb.cfg.port;
    -1 "Streaming tables: ",", " sv string key `.bt.live;
    -1 "Sim date: ",string .bt.cfg.simDate;
    -1 "Last flushed: ",.Q.s1 .bt.lastFlushed;
 };


// --- Write-ahead log ---------------------------------------------------------

.bt.log.ensureDir:{[]
    system "mkdir -p ",1_ string .bt.hdb.cfg.logPath;
 };

.bt.log.path:{[tbl]
    ` sv .bt.hdb.cfg.logPath,tbl
 };

.bt.log.handle:{[tbl]
    h:.bt.log.handles tbl;
    if[not null h;
        :h;
    ];

    path:.bt.log.path tbl;
    if[not type key path;
        .[path; (); :; ()];
    ];

    h:hopen path;
    .bt.log.handles[tbl]:h;
    :h;
 };

.bt.log.close:{[tbl]
    h:.bt.log.handles tbl;
    if[not null h;
        hclose h;
        .bt.log.handles _: tbl;
    ];
 };

.bt.log.replayAll:{[]
    if[not 11h = type k:key .bt.hdb.cfg.logPath;
        :();
    ];

    tbls:`symbol$k except `simDate`lastFlushed;
    if[0 = count tbls;
        :();
    ];

    -1 "Replaying ",string[count tbls]," live log(s)";
    .bt.log.replay each tbls;
 };

.bt.log.replay:{[tbl]
    path:.bt.log.path tbl;
    n:@[{-11!x}; path; {[e] -2 "log replay failed: ",e; -1}];
    -1 $[n < 0;
        "  ",string[tbl],": replay FAILED";
        "  ",string[tbl],": replayed ",string[n]," messages"];
 };

.bt.log.simDatePath:{[]
    ` sv .bt.hdb.cfg.logPath,`simDate
 };

.bt.log.restoreSimDate:{[]
    path:.bt.log.simDatePath[];
    if[type key path;
        .bt.cfg.simDate:get path;
    ];
 };

.bt.log.clearSimDate:{[]
    @[hdel; .bt.log.simDatePath[]; (::)];
    .bt.cfg.simDate:0Nd;
 };

.bt.log.lastFlushedPath:{[]
    ` sv .bt.hdb.cfg.logPath,`lastFlushed
 };

.bt.log.loadLastFlushed:{[]
    path:.bt.log.lastFlushedPath[];
    if[type key path;
        .bt.lastFlushed:get path;
    ];
 };

.bt.log.saveLastFlushed:{[tbl;dt]
    .bt.lastFlushed[tbl]:dt;
    .bt.log.lastFlushedPath[] set .bt.lastFlushed;
 };


// --- Streaming write API -----------------------------------------------------

// Internal apply step. Also the function the log replay calls. Messages
// tagged with a date <= the persisted lastFlushed marker are dropped: they
// were already persisted by a flush that died before truncating the log.
.bt.i.applyUpd:{[tbl;dt;rows]
    lf:.bt.lastFlushed tbl;
    if[(not null lf) and dt <= lf;
        :();
    ];
    nm:` sv `.bt.live,tbl;
    nm upsert rows;
 };

// Verify incoming rows match the live table's column names and types. Run
// BEFORE logging so a malformed message can't poison the log.
//
// Generic columns (declared as () in schemas.q, meta type ' ') accept any
// incoming type — q has no way to express a "typed empty nested-list column",
// so a column intended to hold per-row lists (e.g. `S sym lists) must be
// declared generic and rely on this lenient match. Names must still match
// exactly, and all non-generic columns are still strictly type-checked.
.bt.i.schemaCheck:{[tbl;rows]
    nm:` sv `.bt.live,tbl;
    mL:0!meta value nm;
    mR:0!meta rows;
    if[not (mL`c) ~ mR`c;
        '"SchemaException: ",string[tbl]," column names differ: expects ",.Q.s1[mL`c],", got ",.Q.s1[mR`c];
    ];
    mismatched:where ((mL`t) <> mR`t) and not " " = mL`t;
    if[count mismatched;
        '"SchemaException: ",string[tbl]," expects (",.Q.s1[mL`c],";",.Q.s1[mL`t],"), got (",.Q.s1[mR`c],";",.Q.s1[mR`t],")";
    ];
 };

// Wrapper for clients that stream column-major data (e.g. regina's KdbOutputSink,
// which sends an Object[] of column arrays rather than a built-up table). Zips the
// columns with the live table's `cols` and flips to a table before delegating to
// .bt.upd, so the WAL + schemaCheck path stays identical.
//
// Also auto-manages simDate from the data:
//   - first call ever bootstraps simDate from the first row's `timestamp`
//   - subsequent calls whose rows are dated past simDate flush ALL live tables
//     for the old date and advance simDate
// The client is responsible for not straddling midnight within a single batch
// (regina's KdbOutputSink flushes its buffer before crossing UTC midnight).
.bt.updCols:{[tbl;data]
    t:flip cols[value ` sv `.bt.live,tbl]!data;
    rowDate:`date$first t`timestamp;

    if[null .bt.cfg.simDate;
        .bt.setSimDate[rowDate];
    ];

    if[rowDate > .bt.cfg.simDate;
        oldDate:.bt.cfg.simDate;
        {.bt.flush[x; oldDate]} each key `.bt.live;
        .bt.setSimDate[rowDate];
    ];

    .bt.upd[tbl; t]
 };

.bt.upd:{[tbl;rows]
    if[not tbl in key `.bt.live;
        '"UnknownLiveTableException: ",string tbl;
    ];
    if[null .bt.cfg.simDate;
        '"SimDateNotSetException: call .bt.setSimDate before .bt.upd";
    ];
    .bt.i.schemaCheck[tbl;rows];

    dt:.bt.cfg.simDate;
    h:.bt.log.handle tbl;
    h (`.bt.i.applyUpd; tbl; dt; rows);
    if[.bt.hdb.cfg.sync; system "sync"];
    .bt.i.applyUpd[tbl;dt;rows];
 };

.bt.flush:{[tbl;dt]
    if[not tbl in key `.bt.live;
        '"UnknownLiveTableException: ",string tbl;
    ];

    nm:` sv `.bt.live,tbl;
    rows:value nm;

    if[0 = count rows;
        -1 "Nothing to flush: ",string tbl;
        :`empty;
    ];

    tbl set rows;
    .Q.dpft[.bt.hdb.cfg.path; dt; `sym; tbl];
    ![`.; (); 0b; enlist tbl];

    .bt.log.saveLastFlushed[tbl;dt];
    .bt.log.close tbl;
    @[hdel; .bt.log.path tbl; (::)];

    nm set 0#rows;
    .bt.hdb.loadHdb[];
    .Q.gc[];

    -1 "Flushed ",string[count rows]," rows of ",string[tbl]," @ ",string dt;
    `ok
 };

.bt.setSimDate:{[dt]
    .bt.cfg.simDate:dt;
    .bt.log.simDatePath[] set dt;
    -1 "Sim date = ",string dt;
    `ok
 };


// --- Read API ----------------------------------------------------------------

.bt.viewLive:{[tbl]
    value ` sv `.bt.live,tbl
 };

// Unions on-disk partitions [startDt..endDt] with the in-memory accumulator
// (live rows are tagged with .bt.cfg.simDate as their `date column, but only
// if simDate falls inside the requested range).
.bt.view:{[tbl;startDt;endDt]
    hist:$[tbl in tables[];
        ?[tbl; enlist (within;`date;startDt,endDt); 0b; ()];
        ()
    ];

    if[(null .bt.cfg.simDate) or not .bt.cfg.simDate within (startDt;endDt);
        :hist;
    ];

    live:.bt.viewLive tbl;
    if[0 = count live;
        :hist;
    ];

    liveDated:update date:.bt.cfg.simDate from live;
    $[count hist;
        cols[hist] xcols hist,liveDated;
        liveDated
    ]
 };


// --- Batch write (no log) and HDB reload -------------------------------------

.bt.writeResult:{[tbl;dt;rows]
    if[0 = count rows;
        :`empty;
    ];

    tbl set rows;
    .Q.dpft[.bt.hdb.cfg.path; dt; `sym; tbl];
    ![`.; (); 0b; enlist tbl];
    .Q.gc[];

    -1 "Wrote ",string[count rows]," rows: ",string[tbl]," ",string dt;
    `ok
 };

.bt.reload:{[]
    .bt.hdb.loadHdb[];
    `ok
 };


.bt.hdb.init[];
