// Backtest CSV dumper
// kx-backtest @ b2c2

// DOCUMENTATION:
// Connects to a prod kdb instance over IPC and writes one CSV per (table, date)
// using the same pull specifications as seed.q (.bt.pulls.tables / .bt.pulls.override).
//
// Usage:
//   q dump-csv.q -prodhost <h> -prodport <p> -csv <path> -start <yyyy.mm.dd> -end <yyyy.mm.dd>
//
// Output: <csv>/<tableName>.<yyyy.mm.dd>.csv
// Re-runs are idempotent: files already present on disk are skipped.

\l pulls.q


.bt.dump.cfg.host:"";
.bt.dump.cfg.port:0;
.bt.dump.cfg.csvPath:`;
.bt.dump.cfg.startDate:0Nd;
.bt.dump.cfg.endDate:0Nd;


.bt.dump.parseArgs:{[]
    args:.Q.opt .z.x;
    .bt.dump.cfg.host:first args`prodhost;
    .bt.dump.cfg.port:"J"$first args`prodport;
    .bt.dump.cfg.csvPath:hsym `$first args`csv;
    .bt.dump.cfg.startDate:"D"$first args`start;
    .bt.dump.cfg.endDate:"D"$first args`end;

    if[any (""~/:(.bt.dump.cfg.host; first args`csv)) , null (.bt.dump.cfg.port; .bt.dump.cfg.startDate; .bt.dump.cfg.endDate);
        -2 "Missing arg. Need -prodhost -prodport -csv -start -end";
        exit 1;
    ];
    if[.bt.dump.cfg.startDate > .bt.dump.cfg.endDate;
        -2 "Start date (",string[.bt.dump.cfg.startDate],") is after end date (",string[.bt.dump.cfg.endDate],")";
        exit 1;
    ];
 };


// Build the IPC query for one (table, date), honouring overrides if any.
.bt.dump.query:{[tbl;dt]
    $[tbl in key .bt.pulls.override;
        .bt.pulls.override[tbl] dt;
    / else
        "select from ",string[tbl]," where date=",string dt
    ]
 };


// Target CSV path for one (table, date).
.bt.dump.filePath:{[tbl;dt]
    ` sv .bt.dump.cfg.csvPath, `$ string[tbl],".",string[dt],".csv"
 };


// CSV writer can't serialise general-list / nested columns. Stringify any
// column whose type is 0h (mixed) so 0: succeeds.
.bt.dump.csvFriendly:{[t]
    d:flip t;
    flip (key d)!{$[0h=type x; .Q.s1 each x; x]} each value d
 };


// Force a consistent column order in CSV output: timestamp first, sym second,
// remaining columns keep their original order. Missing columns are skipped.
.bt.dump.reorder:{[t]
    (`timestamp`sym inter cols t) xcols t
 };


// Pull one (table, date) over IPC and write as a CSV file.
.bt.dump.pullAndSave:{[handle;tbl;dt]
    fp:.bt.dump.filePath[tbl;dt];
    if[not null @[hcount;fp;0N];
        -1 "  skip ",string[tbl]," ",string[dt]," (already on disk)";
        :();
    ];

    q:.bt.dump.query[tbl;dt];
    -1 "  pull ",string[tbl]," ",string dt;

    data:handle q;
    if[0 = count data;
        -1 "    empty, nothing to write";
        :();
    ];

    fp 0: "," 0: .bt.dump.csvFriendly .bt.dump.reorder data;
    .Q.gc[];
 };


.bt.dump.run:{[]
    .bt.dump.parseArgs[];

    / Ensure target dir exists.
    system "mkdir -p ",1_ string .bt.dump.cfg.csvPath;

    handle:hopen `$":",.bt.dump.cfg.host,":",string .bt.dump.cfg.port;
    -1 "Connected to ",.bt.dump.cfg.host,":",string .bt.dump.cfg.port;

    dates:.bt.dump.cfg.startDate + til 1 + .bt.dump.cfg.endDate - .bt.dump.cfg.startDate;
    -1 "Dumping ",string[count dates]," date(s) x ",string[count .bt.pulls.tables]," table(s) into ",string .bt.dump.cfg.csvPath;

    {[h;dt]
        -1 "Date ",string dt;
        .bt.dump.pullAndSave[h;;dt] each .bt.pulls.tables;
     }[handle;] each dates;

    hclose handle;
    -1 "Dump complete";
    exit 0;
 };


.bt.dump.run[];
