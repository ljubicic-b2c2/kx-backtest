// Backtest streaming result table schemas
// kx-backtest @ b2c2

// DOCUMENTATION:
// In-memory accumulator tables. Java streams events into these via .bt.upd
// and .bt.flush persists them to date partitions on disk at end-of-simulated-day.
//
// Live tables live under .bt.live so they don't shadow the partitioned tables
// of the same name once HDB is loaded.
//
// Conventions for new tables (enforced by .Q.dpft in .bt.flush):
//   - Must include a `sym` column - .Q.dpft applies `p# on it
//   - Must NOT include a `date` column - .Q.dpft adds it implicitly
//   - First column conventionally `time` (timestamp `p) for ordering
//   - Types use kdb char codes: P=timestamp, S=symbol, F=float, J=long, etc.
//
// Adding a new streaming table: append one line below.

/.bt.live.btPnl:                   flip `time`sym`pnl`bps`scenario!"PSFFS"$\:();
/.bt.live.btSignal:                flip `time`sym`signal`confidence`scenario!"PSFFS"$\:();
// hedgingInstruments holds a sym LIST per row. Declared via seed-and-clear (0#) so
// the column's meta type is `S (nested sym list) rather than ` ` (generic). The
// regina KdbOutputSink sends String[] per row, which serialises as a sym list, and
// .bt.i.schemaCheck requires an exact column-type match.
.bt.live.cashDerivativeDecision:  0#([] timestamp:enlist 0Np; sym:enlist `; name:enlist `; expected_tenor:enlist 0Nn; hedgingInstruments:enlist enlist `);
.bt.live.cortexPassive:           0#([] timestamp:enlist 0Np; sym:enlist `; name:enlist `; riskVal:enlist 0n; alphaVal:enlist 0n; deltaQ:enlist 0n; hedgingInstruments:enlist enlist `; hedgingVenues:enlist enlist `; hedgingMaxSize:enlist enlist 0n; details:enlist enlist `);
// cortex order instructions (SOR-bound). One row per instruction. instrument2 == instrument
// unless the strategy hedges cash AND perp. Written by regina's CortexOrderInstructionKxWriterSource.
.bt.live.cortexOrderInstruction:  0#([] timestamp:enlist 0Np; sym:enlist `; instrument:enlist `; instrument2:enlist `; side:enlist `; quantity:enlist 0n; limitPrice:enlist 0n; ttlMillis:enlist 0Nj; instruction:enlist `; orderType:enlist `; cortexOrderId:enlist 0Nj; traceId:enlist `);


