# Generates playbooks/bql-analysis and playbooks/factset-analysis (playbook.yml + commands.yml) from one spec.
# Usage: python3 script/worksheet_packs.py playbooks   (needs PyYAML). Edit here, regenerate, then reinstall the packs.
import os, sys, yaml
class NoAlias(yaml.SafeDumper):
    def ignore_aliases(self, data): return True
root = sys.argv[1]
# ---------- command catalogs: same semantic keys, provider syntax ----------
# (key, category, label, bql_field or None, factset_code or None, kind)
#   kind: period (fiscal period params), point (current), est (consensus, forward periods)
FUND = [
 ("revenue","Income statement","Revenue","sales_rev_turn","FF_SALES"),
 ("gross_profit","Income statement","Gross profit","gross_profit","FF_GROSS_INC"),
 ("ebitda","Income statement","EBITDA","ebitda","FF_EBITDA_OPER"),
 ("operating_income","Income statement","Operating income (EBIT)","is_oper_inc","FF_EBIT_OPER"),
 ("net_income","Income statement","Net income","net_income","FF_NET_INC"),
 ("eps_diluted","Income statement","Diluted EPS","is_diluted_eps","FF_EPS_DIL"),
 ("interest_expense","Income statement","Interest expense","is_int_expense","FF_INT_EXP_DEBT"),
 ("rnd","Income statement","R&D expense","is_rd_expend","FF_RD_EXP"),
 ("sga","Income statement","SG&A expense","is_sga_expense","FF_SGA"),
 ("total_assets","Balance sheet","Total assets","bs_tot_asset","FF_ASSETS"),
 ("total_liabilities","Balance sheet","Total liabilities","bs_tot_liab2","FF_LIABS"),
 ("total_equity","Balance sheet","Total equity","total_equity","FF_COM_EQ"),
 ("total_debt","Balance sheet","Total debt","short_and_long_term_debt","FF_DEBT"),
 ("cash","Balance sheet","Cash and equivalents","bs_cash_near_cash_item","FF_CASH_ST"),
 ("net_debt","Balance sheet","Net debt","net_debt","FF_NET_DEBT"),
 ("current_assets","Balance sheet","Current assets","bs_cur_asset_report","FF_ASSETS_CURR"),
 ("current_liabilities","Balance sheet","Current liabilities","bs_cur_liab","FF_LIABS_CURR"),
 ("inventory","Balance sheet","Inventory","bs_inventories","FF_INVEN"),
 ("receivables","Balance sheet","Receivables","bs_acct_note_rcv","FF_RECEIV_NET"),
 ("operating_cash_flow","Cash flow","Cash from operations","cf_cash_from_oper","FF_OPER_CF"),
 ("capex","Cash flow","Capital expenditure","capital_expend","FF_CAPEX"),
 ("free_cash_flow","Cash flow","Free cash flow","cf_free_cash_flow","FF_FREE_CF"),
 ("dividends_per_share","Cash flow","Dividends per share","eqy_dps","FF_DPS"),
 ("pe_ratio","Ratios","P/E","pe_ratio","FF_PE"),
 ("price_to_book","Ratios","Price / book","px_to_book_ratio","FF_PBK"),
 ("price_to_sales","Ratios","Price / sales","px_to_sales_ratio","FF_PSALES"),
 ("ev_ebitda","Ratios","EV / EBITDA","ev_to_ebitda","FF_ENTRPR_VAL_EBITDA_OPER"),
 ("roe","Ratios","Return on equity","return_com_eqy","FF_ROE"),
 ("roa","Ratios","Return on assets","return_on_asset","FF_ROA"),
 ("gross_margin","Ratios","Gross margin","gross_margin","FF_GROSS_MGN"),
 ("operating_margin","Ratios","Operating margin","oper_margin","FF_OPER_MGN"),
 ("net_margin","Ratios","Net margin","prof_margin","FF_NET_MGN"),
 ("debt_to_equity","Ratios","Debt / equity","tot_debt_to_tot_eqy","FF_DEBT_EQ"),
 ("current_ratio","Ratios","Current ratio","cur_ratio","FF_CURR_RATIO"),
]
POINT = [
 ("price","Market","Last price","px_last","P_PRICE(0)"),
 ("market_cap","Market","Market capitalization","cur_mkt_cap","FF_MKT_VAL(ANN,0)"),
 ("enterprise_value","Market","Enterprise value","curr_entp_val","FF_ENTRPR_VAL(ANN,0)"),
 ("shares_out","Market","Shares outstanding","eqy_sh_out","FF_COM_SHS_OUT(ANN,0)"),
 ("volume","Market","Volume","px_volume","P_VOLUME(0)"),
 ("dividend_yield","Market","Dividend yield (12m)","eqy_dvd_yld_12m","FF_DIV_YLD(ANN,0)"),
 ("beta","Market","Beta","eqy_beta","P_BETA_PR(0)"),
 ("high_52w","Market","52-week high","high_52week","P_PRICE_HIGH_52W(0)"),
 ("low_52w","Market","52-week low","low_52week","P_PRICE_LOW_52W(0)"),
]
EST = [
 ("revenue_est","Estimates","Revenue, consensus","sales_rev_turn","SALES"),
 ("ebitda_est","Estimates","EBITDA, consensus","ebitda","EBITDA"),
 ("eps_est","Estimates","EPS, consensus","is_eps","EPS"),
 ("fcf_est","Estimates","Free cash flow, consensus","cf_free_cash_flow","FCF"),
 ("net_income_est","Estimates","Net income, consensus","net_income","NET"),
]
ESG = [
 ("esg_score","ESG","ESG score","esg_disclosure_score"),
 ("environmental_score","ESG","Environmental score","environ_disclosure_score"),
 ("social_score","ESG","Social score","social_disclosure_score"),
 ("governance_score","ESG","Governance score","govnce_disclosure_score"),
]
def bql_cmds():
    out = {}
    for k, cat, label, f, _ in FUND:
        out[k] = {"name": label, "category": cat, "syntax": f'=BQL({{security}},"{f}(fpt={{fpt}}, fpo={{fpo}})")',
                  "defaults": {"fpt": "A", "fpo": 0}, "description": f"{label} for the fiscal period (fpt: A annual, Q quarterly; fpo: 0 latest, -1 prior, ...)."}
    for k, cat, label, f, _ in POINT:
        out[k] = {"name": label, "category": cat, "syntax": f'=BQL({{security}},"{f}")', "description": f"{label}, latest."}
    for k, cat, label, f, _ in EST:
        out[k] = {"name": label, "category": cat, "syntax": f'=BQL({{security}},"{f}(fpt={{fpt}}, fpo={{fpo}}, ae=E)")',
                  "defaults": {"fpt": "A", "fpo": 1}, "description": f"{label} for a forward fiscal period (fpo 1 = next)."}
    for k, cat, label, f in ESG:
        out[k] = {"name": label, "category": cat, "syntax": f'=BQL({{security}},"{f}")', "description": f"Bloomberg {label.lower()} (disclosure-based)."}
    out["macro_value"] = {"name": "Macro series, latest", "category": "Macro", "syntax": '=BQL({security},"px_last")', "description": "Latest value of an economic index ticker (for example GDP CQOQ Index)."}
    out["macro_value_ago"] = {"name": "Macro series, value a period ago", "category": "Macro", "syntax": '=BQL({security},"px_last(dates={ago})")', "defaults": {"ago": "-1Y"}, "description": "Value of the series at a past date (dates=-1Y)."}
    out["index_members"] = {"name": "Index members", "category": "Universe", "syntax": '=BQL.Query("get(name) for(members(\'{index}\'))")', "defaults": {"index": "SPX Index"}, "description": "Lists an index's members (spills down)."}
    out["price_history"] = {"name": "Price history", "category": "Market", "syntax": '=BQL({security},"px_last(dates=range({start},0D))")', "defaults": {"start": "-1Y"}, "description": "Daily closing prices over a range (spills down)."}
    out["total_return_1y"] = {"name": "Total return, 1 year", "category": "Market", "syntax": '=BQL({security},"total_return(calc_interval=1Y)")', "description": "One-year total return."}
    return out
def fds_cmds():
    out = {}
    for k, cat, label, _, c in FUND:
        out[k] = {"name": label, "category": cat, "syntax": f'=FDS({{security}},"{c}({{period}},{{fpo}})")', "defaults": {"period": "ANN", "fpo": 0},
                  "description": f"{label} (period: ANN annual, QTR quarterly; fpo: 0 latest, -1 prior, ...)."}
    for k, cat, label, _, c in POINT:
        out[k] = {"name": label, "category": cat, "syntax": f'=FDS({{security}},"{c}")', "description": f"{label}, latest."}
    for k, cat, label, _, item in EST:
        out[k] = {"name": label, "category": cat, "syntax": f'=FDS({{security}},"FE_ESTIMATE({item},MEAN,ANN_ROLL,+{{fpo}},0)")', "defaults": {"fpo": 1},
                  "description": f"{label} for a forward fiscal year (+1 = next)."}
    for k, cat, label, _ in ESG:
        out[k] = {"name": label, "category": cat, "syntax": '=FDS({security},"{esg_code}")', "defaults": {"esg_code": ""},
                  "description": f"FactSet {label.lower()}: set the code for your ESG data subscription."}
    out["macro_value"] = {"name": "Economic series, latest", "category": "Macro", "syntax": '=FDS({security},"{econ_code}")', "defaults": {"econ_code": ""},
                          "description": "Latest value of an economic series: set your FactSet economics code."}
    out["macro_value_ago"] = {"name": "Economic series, value a period ago", "category": "Macro", "syntax": '=FDS({security},"{econ_code_ago}")', "defaults": {"econ_code_ago": ""},
                              "description": "Value of the series a period ago: set your FactSet economics code."}
    out["price_history"] = {"name": "Price history", "category": "Market", "syntax": '=FDS({security},"P_PRICE({start},0,D)")', "defaults": {"start": "-1AY"}, "description": "Daily prices over a range (spills down)."}
    out["total_return_1y"] = {"name": "Total return, 1 year", "category": "Market", "syntax": '=FDS({security},"P_TOTAL_RETURNC(-1AY,0)")', "description": "One-year total return."}
    return out

# ---------- blueprints (provider-neutral; command keys are shared) ----------
def blueprints(p):
    sec = {"bql": "AAPL US Equity", "factset": "AAPL-US"}[p]
    peers = {"bql": "AAPL US Equity\nMSFT US Equity\nGOOGL US Equity\nAMZN US Equity\nMETA US Equity",
             "factset": "AAPL-US\nMSFT-US\nGOOGL-US\nAMZN-US\nMETA-US"}[p]
    macro = {"bql": "GDP CQOQ Index\nCPI YOY Index\nUSURTOT Index\nFDTR Index\nUSGG10YR Index\nUSGG2YR Index", "factset": ""}[p]
    fp = {"bql": "fpo", "factset": "fpo"}[p]
    hist = [{"label": f"FY{n}" if n else "FY0", "params": {fp: n}} for n in (-4, -3, -2, -1, 0)]
    fwd = [{"label": f"FY+{n}", "params": {fp: n, "n": n}} for n in range(1, 6)]
    fin_rows = [("revenue","Revenue"),("gross_profit","Gross profit"),("ebitda","EBITDA"),("operating_income","Operating income"),
                ("net_income","Net income"),("eps_diluted","Diluted EPS"),("total_assets","Total assets"),("total_debt","Total debt"),
                ("cash","Cash and equivalents"),("total_equity","Total equity"),("operating_cash_flow","Cash from operations"),
                ("capex","Capital expenditure"),("free_cash_flow","Free cash flow")]
    P = p + "-"
    return {
      P+"financial-statements": {"kind": "table", "sheet": "Financials", "title": "Financial statements (5 years)", "row_header": "Millions",
        "inputs": [{"key": "security", "label": "Security", "default": sec}], "columns": hist,
        "rows": [{"key": k, "label": l, "command": k, "format": "0.00" if k == "eps_diluted" else "#,##0"} for k, l in fin_rows]},
      P+"financial-ratios": {"kind": "table", "sheet": "Ratios", "title": "Financial ratios", "source": P+"financial-statements",
        "columns": hist,
        "rows": [
          {"key": "revenue_growth", "label": "Revenue growth", "formula": '=IFERROR({src_row:revenue}/{src_prev:revenue}-1,"")', "format": "0.0%"},
          {"key": "gross_margin", "label": "Gross margin", "formula": '=IFERROR({src_row:gross_profit}/{src_row:revenue},"")', "format": "0.0%"},
          {"key": "ebitda_margin", "label": "EBITDA margin", "formula": '=IFERROR({src_row:ebitda}/{src_row:revenue},"")', "format": "0.0%"},
          {"key": "net_margin", "label": "Net margin", "formula": '=IFERROR({src_row:net_income}/{src_row:revenue},"")', "format": "0.0%"},
          {"key": "roe", "label": "Return on equity", "formula": '=IFERROR({src_row:net_income}/{src_row:total_equity},"")', "format": "0.0%"},
          {"key": "debt_to_equity", "label": "Debt / equity", "formula": '=IFERROR({src_row:total_debt}/{src_row:total_equity},"")', "format": "0.00x"},
          {"key": "net_debt_to_ebitda", "label": "Net debt / EBITDA", "formula": '=IFERROR(({src_row:total_debt}-{src_row:cash})/{src_row:ebitda},"")', "format": "0.00x"},
          {"key": "fcf_conversion", "label": "FCF conversion (FCF / net income)", "formula": '=IFERROR({src_row:free_cash_flow}/{src_row:net_income},"")', "format": "0.0%"}]},
      P+"chart-financial-trends": {"kind": "chart", "source": P+"financial-statements", "chart": "ColumnClustered", "title": "Revenue, EBITDA and net income",
        "series": ["revenue", "ebitda", "net_income"]},
      P+"macro-dashboard": {"kind": "grid", "sheet": "Macro", "title": "Macro dashboard", "stats": [],
        "inputs": [{"key": "series", "label": "Series", "type": "list", "default": macro}] +
                  ([] if p == "bql" else [{"key": "econ_code", "label": "FactSet code for the latest value", "default": ""},
                                          {"key": "econ_code_ago", "label": "FactSet code for the value a year ago", "default": ""}]),
        "columns": [{"key": "latest", "label": "Latest", "command": "macro_value", "format": "0.00"},
                    {"key": "year_ago", "label": "A year ago", "command": "macro_value_ago", "format": "0.00"}]},
      P+"chart-macro-indicators": {"kind": "chart", "source": P+"macro-dashboard", "chart": "ColumnClustered", "title": "Macro indicators: latest vs a year ago",
        "series": ["latest", "year_ago"]},
      P+"dcf-valuation": {"kind": "table", "sheet": "DCF", "title": "Discounted cash flow valuation", "row_header": "Millions",
        "inputs": [{"key": "security", "label": "Security", "default": sec},
                   {"key": "wacc", "label": "WACC", "default": 0.09, "format": "0.0%"},
                   {"key": "terminal_growth", "label": "Terminal growth", "default": 0.025, "format": "0.0%"}],
        "columns": fwd,
        "rows": [{"key": "revenue", "label": "Revenue (consensus)", "command": "revenue_est", "format": "#,##0"},
                 {"key": "ebitda", "label": "EBITDA (consensus)", "command": "ebitda_est", "format": "#,##0"},
                 {"key": "fcf", "label": "Free cash flow (consensus)", "command": "fcf_est", "format": "#,##0"},
                 {"key": "discount_factor", "label": "Discount factor", "formula": "=1/(1+{input:wacc})^{col:n}", "format": "0.000"},
                 {"key": "pv_fcf", "label": "PV of free cash flow", "formula": "={row:fcf}*{row:discount_factor}", "format": "#,##0"}],
        "summary": [{"key": "sum_pv", "label": "Sum of PV of FCF", "formula": "={row_sum:pv_fcf}", "format": "#,##0"},
                    {"key": "terminal_value", "label": "Terminal value", "formula": "={row_last:fcf}*(1+{input:terminal_growth})/({input:wacc}-{input:terminal_growth})", "format": "#,##0"},
                    {"key": "pv_terminal", "label": "PV of terminal value", "formula": "={cell:terminal_value}*{row_last:discount_factor}", "format": "#,##0"},
                    {"key": "enterprise_value", "label": "Enterprise value", "formula": "={cell:sum_pv}+{cell:pv_terminal}", "format": "#,##0", "bold": True},
                    {"key": "net_debt", "label": "Net debt", "command": "net_debt", "format": "#,##0"},
                    {"key": "equity_value", "label": "Equity value", "formula": "={cell:enterprise_value}-{cell:net_debt}", "format": "#,##0"},
                    {"key": "shares", "label": "Shares outstanding", "command": "shares_out", "format": "#,##0"},
                    {"key": "value_per_share", "label": "Value per share", "formula": "={cell:equity_value}/{cell:shares}", "format": "0.00", "bold": True},
                    {"key": "price", "label": "Current price", "command": "price", "format": "0.00"},
                    {"key": "upside", "label": "Upside / (downside)", "formula": "={cell:value_per_share}/{cell:price}-1", "format": "0.0%", "bold": True}]},
      P+"dcf-sensitivity": {"kind": "sensitivity", "sheet": "DCF sensitivity", "title": "Value per share: WACC x terminal growth", "source": P+"dcf-valuation",
        "row_param": {"label": "WACC", "values": [0.07, 0.08, 0.09, 0.10, 0.11], "format": "0.0%"},
        "col_param": {"label": "Terminal growth", "values": [0.015, 0.02, 0.025, 0.03, 0.035], "format": "0.0%"},
        "formula": "=(NPV({row},{src_row_range:fcf})+{src_row_last:fcf}*(1+{col})/({row}-{col})/(1+{row})^{src_count}-{src_cell:net_debt})/{src_cell:shares}",
        "format": "0.00"},
      P+"peer-comparables": {"kind": "grid", "sheet": "Comps", "title": "Peer comparables",
        "inputs": [{"key": "peers", "label": "Security", "type": "list", "default": peers}],
        "columns": [{"key": "price", "label": "Price", "command": "price", "format": "0.00"},
                    {"key": "market_cap", "label": "Market cap", "command": "market_cap", "format": "#,##0"},
                    {"key": "ev_ebitda", "label": "EV / EBITDA", "command": "ev_ebitda", "format": "0.0x"},
                    {"key": "pe_ratio", "label": "P / E", "command": "pe_ratio", "format": "0.0x"},
                    {"key": "price_to_book", "label": "P / B", "command": "price_to_book", "format": "0.0x"},
                    {"key": "price_to_sales", "label": "P / S", "command": "price_to_sales", "format": "0.0x"},
                    {"key": "roe", "label": "ROE", "command": "roe", "format": "0.0"},
                    {"key": "net_margin", "label": "Net margin", "command": "net_margin", "format": "0.0"}]},
      P+"chart-peer-multiples": {"kind": "chart", "source": P+"peer-comparables", "chart": "ColumnClustered", "title": "P/E and EV/EBITDA by peer",
        "series": ["pe_ratio", "ev_ebitda"]},
      P+"esg-scorecard": {"kind": "grid", "sheet": "ESG", "title": "ESG scorecard",
        "inputs": [{"key": "peers", "label": "Security", "type": "list", "default": peers}] +
                  ([] if p == "bql" else [{"key": "esg_code", "label": "FactSet ESG score code", "default": ""}]),
        "columns": [{"key": "esg_score", "label": "ESG", "command": "esg_score", "format": "0.0"}] +
                   ([{"key": "environmental_score", "label": "Environmental", "command": "environmental_score", "format": "0.0"},
                     {"key": "social_score", "label": "Social", "command": "social_score", "format": "0.0"},
                     {"key": "governance_score", "label": "Governance", "command": "governance_score", "format": "0.0"}] if p == "bql" else [])},
      P+"chart-esg-scores": {"kind": "chart", "source": P+"esg-scorecard", "chart": "BarClustered", "title": "ESG scores by company",
        "series": ["esg_score"] + (["environmental_score", "social_score", "governance_score"] if p == "bql" else [])},
    }

SKILLS = {  # suffix: (title, description, field, app steps, notes)
 "financial-statements": ("Build a five-year financial statements sheet", "Builds a worksheet of five fiscal years of income statement, balance sheet and cash flow lines for one security, as live {P} formulas. Use when starting a company's financial analysis.",
   "investment-analysis/financial-analysis", [["Enter the security"], ["Build the Financials sheet from the add-in"], ["Check the latest year against the filing"]],
   ["Figures are in the provider's reporting currency and units (usually millions); say so in the row header.", "Compare FY0 revenue and net income with the latest annual report before relying on the sheet."]),
 "financial-ratios": ("Compute financial ratios", "Builds a ratios worksheet (growth, margins, return on equity, leverage, cash conversion) from the financial statements sheet. Use after building the five-year financial statements.",
   "investment-analysis/financial-analysis", [["Build the Ratios sheet from the add-in"], ["Review margins and leverage trends"]],
   ["Ratios read the Financials sheet, so build that first and keep its layout.", "Blank cells mean a missing input year, not zero."]),
 "chart-financial-trends": ("Chart financial trends", "Charts revenue, EBITDA and net income across five years on the financial statements sheet. Use when the financial analysis needs a trend chart for a deck or memo.",
   "investment-analysis/charting", [["Add the trend chart from the add-in"], ["Format and copy the chart"]],
   ["Uses the Financials sheet; rebuild the chart after rebuilding that sheet."]),
 "macro-dashboard": ("Build a macro dashboard", "Builds a worksheet of economic indicators (growth, inflation, unemployment, policy rate, Treasury yields) with the latest value and the value a year ago. Use when starting a macro analysis.",
   "investment-analysis/macro-analysis", [["Choose the series"], ["Build the Macro sheet from the add-in"], ["Note the release date of each series"]],
   ["Economic series are released with a lag and get revised; note the as-of date.", "One series per row; replace the default list with the series your analysis needs."]),
 "chart-macro-indicators": ("Chart macro indicators", "Charts each macro indicator's latest value against a year ago. Use when the macro analysis needs a summary chart.",
   "investment-analysis/charting", [["Add the macro chart from the add-in"], ["Copy the chart into the memo or deck"]], ["Indicators have different units; chart like with like, or split the chart."]),
 "dcf-valuation": ("Build a DCF valuation", "Builds a five-year discounted cash flow worksheet from consensus free cash flow, with WACC and terminal growth inputs, a Gordon-growth terminal value, and value per share against the current price. Use for an intrinsic valuation of one security.",
   "investment-analysis/valuation/intrinsic-valuation", [["Enter the security, WACC and terminal growth"], ["Build the DCF sheet from the add-in"], ["Check units and the share count"]],
   ["Consensus free cash flow, net debt and shares must be in the same units (usually millions).", "Terminal growth must be below WACC; keep it near long-run nominal GDP growth.", "Replace consensus with your own forecast where you have one."]),
 "dcf-sensitivity": ("Sensitivity-test the DCF", "Builds a two-way sensitivity grid of value per share across WACC and terminal growth, reading the DCF sheet. Use after building the DCF valuation.",
   "investment-analysis/sensitivity-testing", [["Build the sensitivity grid from the add-in"], ["Highlight the base case"]],
   ["Reads the DCF sheet's free cash flow, net debt and share count; rebuild after changing the DCF."]),
 "peer-comparables": ("Build a peer comparables sheet", "Builds a relative valuation worksheet of price, market cap and multiples (EV/EBITDA, P/E, P/B, P/S) with ROE and net margin for a list of peers, plus the median and mean. Use for a relative valuation.",
   "investment-analysis/valuation/relative-valuation", [["List the peers"], ["Build the Comps sheet from the add-in"], ["Exclude outliers from the median"]],
   ["Peers should share business model, size and region; say why each is in.", "Negative earnings make P/E meaningless; leave it blank rather than zero."]),
 "chart-peer-multiples": ("Chart peer multiples", "Charts P/E and EV/EBITDA for each peer on the comparables sheet. Use when the relative valuation needs a chart.",
   "investment-analysis/charting", [["Add the multiples chart from the add-in"], ["Copy the chart into the memo or deck"]], ["Uses the Comps sheet."]),
 "esg-scorecard": ("Build an ESG scorecard", "Builds a worksheet of ESG scores for a company and its peers, with the median and mean. Use when an analysis needs an ESG comparison.",
   "investment-analysis/esg", [["List the companies"], ["Build the ESG sheet from the add-in"], ["Note the score provider and date"]],
   ["Scores from different providers aren't comparable; use one provider per sheet.", "Disclosure scores measure reporting, not performance."]),
 "chart-esg-scores": ("Chart ESG scores", "Charts the ESG scores of each company on the ESG scorecard. Use when the ESG comparison needs a chart.",
   "investment-analysis/charting", [["Add the ESG chart from the add-in"], ["Copy the chart into the memo or deck"]], ["Uses the ESG sheet."]),
}
ROUTES = {
 "financial-analysis": ("Financial analysis", ["financial-statements", "financial-ratios", "chart-financial-trends"]),
 "macro-analysis": ("Macro analysis", ["macro-dashboard", "chart-macro-indicators"]),
 "valuation-intrinsic": ("Valuation: intrinsic", ["dcf-valuation", "dcf-sensitivity"]),
 "valuation-relative": ("Valuation: relative", ["peer-comparables", "chart-peer-multiples"]),
 "esg": ("ESG", ["esg-scorecard", "chart-esg-scores"]),
}
FIELDS = [
 {"path": "investment-analysis", "name": "Investment analysis", "keywords": ["equity research", "analysis", "valuation", "investment"]},
 {"path": "investment-analysis/financial-analysis", "name": "Financial analysis", "keywords": ["financial statements", "ratios", "margin", "income statement"]},
 {"path": "investment-analysis/macro-analysis", "name": "Macro analysis", "keywords": ["macro", "gdp", "inflation", "rates", "economic"]},
 {"path": "investment-analysis/valuation", "name": "Valuation", "keywords": ["valuation", "fair value"]},
 {"path": "investment-analysis/valuation/intrinsic-valuation", "name": "Intrinsic valuation", "keywords": ["dcf", "discounted cash flow", "wacc"]},
 {"path": "investment-analysis/valuation/relative-valuation", "name": "Relative valuation", "keywords": ["comps", "multiples", "peers", "ev/ebitda"]},
 {"path": "investment-analysis/esg", "name": "ESG", "keywords": ["esg", "environmental", "social", "governance", "sustainability"]},
 {"path": "investment-analysis/charting", "name": "Charting", "keywords": ["chart", "graph"]},
 {"path": "investment-analysis/sensitivity-testing", "name": "Sensitivity testing", "keywords": ["sensitivity", "scenario", "what-if"]},
]
PROV = {"bql": ("Bloomberg BQL", "BQL"), "factset": ("FactSet", "FactSet")}
for p, (long, short) in PROV.items():
    d = os.path.join(root, f"{p}-analysis"); os.makedirs(d, exist_ok=True)
    bps = blueprints(p)
    routes = {}
    for rk, (rtitle, steps) in ROUTES.items():
        rs = []
        for suf in steps:
            title, desc, field, apps, notes = SKILLS[suf]
            # Charts and sensitivity grids belong to their route's field first (so the road isn't a "bridge"),
            # and to Charting / Sensitivity testing second (so filtering by task type still finds them).
            route_field = SKILLS[steps[0]][2]
            fields = [field] if field == route_field else [route_field, field]
            rs.append({"name": f"{p}-{suf}", "title": f"{title} ({short})", "description": desc.replace("{P}", short),
                       "fields": fields, "steps": [["excel", a[0]] for a in apps], "notes": notes, "worksheet": bps[f"{p}-{suf}"]})
        routes[rk] = {"title": rtitle, "steps": rs}
    pack = {"key": f"{p}-analysis", "version": 1, "kind": "pack", "provider": p, "title": f"{long} worksheets", "area": p, "stage": "local",
            "description": f"Skills that build Excel worksheets with {long} formulas for financial analysis, macro analysis, valuation (intrinsic and relative) and ESG, then chart and sensitivity-test them. The {short} command library holds every formula they use.",
            "disclaimer": f"Formulas use {long} syntax and field codes from the command library; a command marked unverified hasn't been checked against {short} documentation in your terminal yet. Check units and periods before relying on a sheet.",
            "fields": FIELDS, "routes": routes}
    with open(os.path.join(d, "playbook.yml"), "w") as f:
        f.write(f"# {long} worksheet skills, generated by script/worksheet_packs.py from one spec shared with the other provider (command keys are shared,\n# syntax comes from commands.yml). Routes: financial analysis, macro, intrinsic and relative valuation, ESG.\n")
        yaml.dump(pack, f, Dumper=NoAlias, sort_keys=False, width=140, allow_unicode=True)
    cmds = bql_cmds() if p == "bql" else fds_cmds()
    with open(os.path.join(d, "commands.yml"), "w") as f:
        f.write(f"# {long} command library: each formula with its syntax ({{param}} placeholders), defaults and category.\n# Starter catalog: every command installs as unverified until someone with {short} access checks it (console: Formulas).\n# Add the rest by editing this file or importing a CSV in the console.\n")
        yaml.dump({"provider": p, "commands": cmds}, f, Dumper=NoAlias, sort_keys=False, width=160, allow_unicode=True)
    print(p, len(cmds), "commands,", sum(len(r["steps"]) for r in routes.values()), "skills")
