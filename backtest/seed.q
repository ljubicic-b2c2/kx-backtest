// Backtest HDB seeder
// kx-backtest @ b2c2

// DOCUMENTATION:
// Connects to a prod kdb instance over IPC and copies one date-partition at a
// time into a local HDB tree using .Q.dpft. Symbols are re-enumerated locally
// by .Q.dpft against the HDB's sym file - no need to copy prod's sym file.
//
// Usage:
//   q seed.q -prodhost <h> -prodport <p> -hdb <path> -start <yyyy.mm.dd> -end <yyyy.mm.dd>
//
// Re-runs are idempotent: partitions already present on disk are skipped.

\l pulls.q


.bt.seed.cfg.host:"";
.bt.seed.cfg.port:0;
.bt.seed.cfg.hdbPath:`;
.bt.seed.cfg.startDate:0Nd;
.bt.seed.cfg.endDate:0Nd;


.bt.seed.parseArgs:{[]
    args:.Q.opt .z.x;
    .bt.seed.cfg.host:first args`prodhost;
    .bt.seed.cfg.port:"J"$first args`prodport;
    .bt.seed.cfg.hdbPath:hsym `$first args`hdb;
    .bt.seed.cfg.startDate:"D"$first args`start;
    .bt.seed.cfg.endDate:"D"$first args`end;

    if[any (""~/:(.bt.seed.cfg.host; first args`hdb)) , null (.bt.seed.cfg.port; .bt.seed.cfg.startDate; .bt.seed.cfg.endDate);
        -2 "Missing arg. Need -prodhost -prodport -hdb -start -end";
        exit 1;
    ];
    if[.bt.seed.cfg.startDate > .bt.seed.cfg.endDate;
        -2 "Start date (",string[.bt.seed.cfg.startDate],") is after end date (",string[.bt.seed.cfg.endDate],")";
        exit 1;
    ];
 };


// Build the IPC query for one (table, date), honouring overrides if any.
.bt.seed.query:{[tbl;dt]
    $[tbl in key .bt.pulls.override;
        .bt.pulls.override[tbl] dt;
    / else
        "select from ",string[tbl]," where date=",string dt
    ]
 };


// Pull one (table, date) over IPC and persist as a date partition locally.
.bt.seed.pullAndSave:{[handle;tbl;dt]
    partPath:.Q.par[.bt.seed.cfg.hdbPath; dt; tbl];
    if[0 < count key partPath;
        -1 "  skip ",string[tbl]," ",string[dt]," (already on disk)";
        :();
    ];

    q:.bt.seed.query[tbl;dt];
    -1 "  pull ",string[tbl]," ",string dt;

    data:handle q;
    if[0 = count data;
        -1 "    empty, nothing to write";
        :();
    ];

    / .Q.dpft requires the table as a global named `tbl. Set, write, then unset.
    tbl set data;
    .Q.dpft[.bt.seed.cfg.hdbPath; dt; `sym; tbl];
    ![`.; (); 0b; enlist tbl];
    .Q.gc[];
 };


.bt.seed.run:{[]
    .bt.seed.parseArgs[];

    handle:hopen `$":",.bt.seed.cfg.host,":",string .bt.seed.cfg.port;
    -1 "Connected to ",.bt.seed.cfg.host,":",string .bt.seed.cfg.port;

    dates:.bt.seed.cfg.startDate + til 1 + .bt.seed.cfg.endDate - .bt.seed.cfg.startDate;
    -1 "Seeding ",string[count dates]," date(s) x ",string[count .bt.pulls.tables]," table(s) into ",string .bt.seed.cfg.hdbPath;

    {[h;dt]
        -1 "Date ",string dt;
        .bt.seed.pullAndSave[h;;dt] each .bt.pulls.tables;
     }[handle;] each dates;

    hclose handle;
    -1 "Seed complete";
    exit 0;
 };


.bt.seed.run[];
