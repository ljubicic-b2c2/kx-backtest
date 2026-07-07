// Backtest seed pull specifications
// kx-backtest @ b2c2

// DOCUMENTATION:
// Declares which tables seed.q pulls from prod each date.
//
// To add a new table:
//   1. Append the table name to .bt.pulls.tables
//   2. (Optional) Add a query override in .bt.pulls.override if the default
//      "select from <tbl> where date=DT" needs filtering or projection.

// Tables to pull. Real prod names live in b2c2-kdb/kdb-app/tick/schemas/*.q
.bt.pulls.tables:`availableBalance`carryCost`liveOwn`riskBookNetRisk`underlierMid`volatility`cashDerivativeDecision;

// Per-table query overrides. Function takes a date, returns the IPC query string.
.bt.pulls.override:(`symbol$())!();

.bt.pulls.override[`availableBalance]:{[dt]
    "`timestamp`exchange xasc .qt.dr.getRawData `table`dateList`symList`exchange`inclCols!(`availableBalance;.qt.util.dt.getDateList[",string[dt],";",string[dt],";0b];`BTC`ETH`XRP`SOL;.qt.strategy.impl.cortex.cfg.cashExchanges;`timestamp`sym`exchange`quantity)"
 };

.bt.pulls.override[`carryCost]:{[dt]
    "`timestamp xasc raze {[d;s] update sym:s from .qt.strategy.impl.cashVsDeriv.i.getCarryCost[d;s;()]}[",string[dt],";] each `BTC`ETH`SOL`XRP"
 };

.bt.pulls.override[`liveOwn]:{[dt]
    "`timestamp xasc delete date from .qt.dr.trade.getTrades`product`subproduct`dateList`symLike`filters`extraCols!(`spot;`otc;",string[dt],";`BTC`ETH`XRP`SOL;enlist(=;`book;enlist `);`book)"
 };

.bt.pulls.override[`riskBookNetRisk]:{[dt]
    "`timestamp xasc select timestamp, sym, usd_risk, local_risk from .qt.feature.getFeature[`risk;`dateList`symList!(",string[dt],";`BTC`ETH`XRP`SOL)]"
 };

.bt.pulls.override[`underlierMid]:{[dt]
    "`timestamp xasc delete date from .qt.feature.getFeature[`underlierMid] `dateList`symList`source`inclCols!(",string[dt],";`BTCUSD`ETHUSD`SOLUSD`XRPUSD;`ReginaMqp;`date`timestamp`sym`mid`vanilla_mid`bid`ask`pre_vim`shift`dispersion`alpha`source`trigger`trigger_timestamp`host`serialisation_version`channel)"
 };

.bt.pulls.override[`volatility]:{[dt]
    "`timestamp xasc select timestamp, sym, volatility from .qt.submodel.impl.volatility.i.getProdDefault[",string[dt],";`BTCUSD`ETHUSD`SOLUSD`XRPUSD]"
 };

.bt.pulls.override[`cashDerivativeDecision]:{[dt]
    "`timestamp xasc select timestamp, sym, name, expected_tenor, hedgingInstruments from raze {[d;s] .qt.strategy.getStrategyOutput[`cashVsDeriv;d;s;();()]}[",string[dt],";] each `BTC`ETH`SOL`XRP"
 };


