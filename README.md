# Warehouse SLA Risk Analytics & Automated Alerting System

An end-to-end supply-chain analytics project that predicts SLA-breach risk for dark-store (quick-commerce) warehouse orders, explains *why* an order is risky, turns that into a zone-level slotting recommendation, and closes the loop with an automated Python + n8n alerting pipeline.

**Domain:** Quick-commerce / dark-store fulfillment (Blinkit/Zepto/Swiggy-style warehouse operations)
**Positioning:** Business Analytics & Supply Chain first, ML as a supporting decision-support layer — not an ML-engineering showcase.

---

## 1. Business Problem

A dark store is a mini-warehouse that exists only to pick, pack, and hand off quick-commerce orders within a tight delivery SLA (often 10–15 minutes end-to-end). Orders miss that window because of picker overload, items scattered across distant zones/bins, shift transitions, or zone congestion — and most warehouses only discover a breach *after* it happens.

This project builds a system that:
1. Flags an order's SLA-breach risk **the moment it's created**, not after the fact.
2. Explains *why* an order is risky, in operational language a warehouse manager can act on.
3. Identifies which warehouse zones actually *cause* delays (vs. zones that merely see high traffic), to drive a slotting/prioritization recommendation.
4. Automatically monitors incoming risk data and alerts operations when high-risk volume crosses a business-defined threshold — without a human running any of it manually.

## 2. Project Objective

The system answers two operational questions:

> "Which orders, right now, are likely to breach their SLA — and why?"
> "Does the current order portfolio contain enough high-risk orders to require an operational alert?"

---

## 3. End-to-End Pipeline

```
 RAW WAREHOUSE DATA (Kaggle — Swiggy dark-store hackathon export)
        │  1.05M picklist-level rows
        ▼
 PHASE 1 — DATA CLEANING & UNDERSTANDING          (Pandas)
        │  column audit, type fixes, dedup → order×zone table
        ▼
 PHASE 2 — SQL BUSINESS ANALYSIS                  (PostgreSQL)
        │  zone workload, bottleneck vs. causation-rate analysis
        ▼
 PHASE 3 — SLA-LABEL SIMULATION                   (Python, discrete-event)
        │  reconstructs pick-completion time from documented shift/travel params
        ▼
 PHASE 4 — FEATURE ENGINEERING                    (Pandas)
        │  order-level feature table, leakage/redundancy checks
        ▼
 PHASE 5 — SLA-RISK CLASSIFICATION                (Scikit-learn)
        │  Logistic Regression vs. Random Forest, business-metric selection
        ▼
 PHASE 6 — MODEL EXPLAINABILITY                   (SHAP)
        │  global + per-order "why is this risky" explanations
        ▼
 PHASE 7 — ZONE / SLOTTING RECOMMENDATION          (Python)
        │  causation-rate ranking → which zones to fix first
        ▼
 PHASE 8 — POWER BI DASHBOARD                      (3 pages)
        │  Executive Overview · Zone Performance · Order Risk
        ▼
 PHASE 9 — AUTOMATED ALERTING WORKFLOW             (n8n + Python + Gmail)
        │  Google Drive → Python risk KPIs → business rule → Sheets log → Gmail alert
        ▼
 OPERATIONAL DECISION
```

---

## 4. Dataset

| | |
|---|---|
| **Source** | Swiggy warehouse-level picklist dataset (Kaggle, Dec 2025 hackathon export) |
| **Raw size** | ~1.05M rows, `picklist_creation_data_for_hackathon_with_order_date.csv` |
| **Grain** | Picklist / SKU line level — `order_id, sku, zone, bin_rank, store_id (POD), dimensions, weight, order_qty, pod_priority` |
| **Documented operating params** | Bin-to-bin travel: 30s · Pickup time: 5s/unit · Shift windows (e.g., Night1: 45 pickers, 8PM–5AM) |
| **Cleaned intermediate table** | `zone_workload_clean.csv` — 51,203 rows × 17 columns (order × zone grain) |
| **Order-level analytical table** | ~1,925 unique orders (feeds the classifier and the dashboard) |

**Why this dataset:** it's a genuinely fresh, first-mover dataset with no prior public GitHub work on it at the time of building — unlike the heavily recycled hotel-cancellation / generic-warehouse-EDA datasets common in portfolio projects.

## 5. Data Pipeline in Detail

### Phase 1 — Cleaning & Structuring
Standardized column names and types, removed exact duplicates, validated row/shape at every transformation step, and reshaped the raw picklist-level export into an order×zone workload table suitable for both SQL and simulation work.

### Phase 2 — SQL Business Analysis (PostgreSQL)
Loaded the cleaned table into PostgreSQL and ran a progressive SQL analysis:
- **Aggregation & filtering:** zone workload totals, SKU diversity per zone, priority-tier workload distribution, outlier detection on `sku_lines`.
- **Joins:** normalized into `orders`, `order_zone_workload`, and `zone_master` tables; validated referential integrity (orphaned zones, unmatched records).
- **Window functions:** `RANK()`/`DENSE_RANK()` to rank zones by workload and complexity tier, `SUM()`/`AVG() OVER (PARTITION BY ...)` to compare each order's zone-level load against zone/order baselines, `LAG()`/`LEAD()` for day-over-day workload trends.
- **CTEs:** identified zones with above-average workload and orders in the top workload percentile.
- **Key finding:** separated **exposure rate** (how often a zone appears in a high-risk order) from **causation rate** (how often a zone is actually the reason an order became high-risk). The highest-traffic zone (305 bottleneck occurrences) had only a **2.3% causation rate**, while a lower-traffic zone (`FMCG_FOOD1`) had a **31% causation rate** — meaning raw congestion frequency is a misleading signal for where to intervene.

### Phase 3 — SLA-Label Simulation
The raw dataset had no picker ID, shift assignment, pick-start/pick-end timestamps, or SLA cutoff — those were narrative details on the Kaggle page, not actual columns. Rather than fabricate a label, a **discrete-event simulation** was built using the dataset's documented operational parameters (30s bin-to-bin travel, 5s/unit pickup time, shift capacity/windows) to generate realistic pick-completion timestamps and compare them against SLA cutoffs, producing an honest, disclosed **proxy risk label** rather than an observed one.

### Phase 4 — Feature Engineering
Final order-level feature set (post leakage/redundancy review — two columns were dropped for being mathematically redundant with existing features):

`priority_num`, `total_volume_cm3`, `number_of_zones`, `total_weight_kg`, `total_qty`, `unique_skus`, `sku_lines`, `total_base_work_seconds`, `unique_bins`

### Phase 5 — SLA-Risk Classification
Stratified 80/20 train-test split, preprocessing fit on training data only, features scaled, class imbalance handled with `class_weight='balanced'`. Two models trained and compared **on the business objective, not raw accuracy**:

| Metric | Logistic Regression | Random Forest |
|---|---|---|
| Accuracy | 90% | 93% |
| High-risk Precision | 51% | 77% |
| High-risk Recall | **95%** | 49% |
| High-risk F1 | 0.66 | 0.60 |
| ROC-AUC | **0.979** | 0.937 |
| High-risk orders missed (of 41 in test set) | **2** | 21 |

**Decision:** Logistic Regression selected as the primary screening model. Missing a genuinely high-risk order is operationally more expensive than raising extra false alerts, so recall was weighted over precision — Random Forest's higher headline accuracy was explicitly rejected as the wrong optimization target for this use case.

### Phase 6 — Explainability (SHAP)
Used `shap.LinearExplainer` on the selected Logistic Regression model to produce both global and per-order explanations.

| Feature | Mean \|SHAP\| |
|---|---|
| `priority_num` | 3.34 |
| `total_volume_cm3` | 1.24 |
| `number_of_zones` | 0.36 |
| `total_weight_kg` | 0.35 |
| `total_qty` | 0.31 |
| `unique_skus` | 0.25 |
| `sku_lines` | 0.11 |
| `total_base_work_seconds` | 0.08 |
| `unique_bins` | 0.06 |

This lets the system say *"this order is risky primarily because of its priority tier and shipment volume"* instead of returning an unexplained risk score. **Caveat documented honestly:** because the underlying simulation processes orders in priority order, `priority_num`'s dominance partly reflects a rule built into the simulation rather than a fully independent, real-world discovery — this is called out directly rather than overstated.

### Phase 7 — Zone / Slotting Recommendation
Combined causation rate, workload, and sample size (not a single blind metric) into a zone-priority recommendation, with automated threshold buckets manually reviewed and overridden where they obscured meaningfully different zone profiles — documented as an explicit analyst judgment call.

### Phase 8 — Power BI Dashboard
Three-page dashboard built from four exported analytical CSVs (`order_completion`, `zone_recommendation`, `simulation_df`, `shap_summary`):

- **Page 1 — Executive Operations Overview:** total orders, high-risk %, average completion time, daily completion trend, workload vs. capacity.
- **Page 2 — Zone Performance:** zone workload Pareto, bottleneck frequency vs. high-risk causation rate, drill-down zone table.
- **Page 3 — Order Risk:** SHAP driver chart, risk by priority/volume/weight bucket, predicted-risk distribution, top high-risk orders, live ROC-AUC KPI.

### Phase 9 — Automated Alerting Workflow (n8n)
Closes the loop from analysis to action:

```
Google Drive (dashboard_order_risk.csv)
        │
        ▼
n8n — Download File → Extract From CSV     (1,924 order records)
        │
        ▼
Python — Risk Aggregation
   ├─ total_orders, high_risk_orders
   ├─ high_risk_rate
   └─ avg_predicted_risk_probability
        │
        ▼
n8n IF Node — Business Rule: high_risk_orders > 2
        │
    ┌───┴───┐
  TRUE     FALSE → no action
    │
    ▼
Google Sheets (alert log / audit trail)
    │
    ▼
Gmail (automated risk notification)
```

**Test run result:**

| Metric | Result |
|---|---|
| Total Orders | 1,924 |
| High-Risk Orders | 207 |
| High-Risk Rate | 10.76% |
| Avg. Predicted Risk Probability | 21.89% |
| Alert Rule | `high_risk_orders > 2` |
| Rule Result | TRUE |
| Google Sheets Logging | Successful |
| Gmail Alert | Successfully received |

The business rule is deliberately kept separate from the Python analytics layer, so the alert threshold can be changed without touching the analysis code.

---

## 6. Tech Stack

| Layer | Tools |
|---|---|
| Data cleaning & feature engineering | Python, Pandas |
| Database & business analysis | SQL (PostgreSQL) — CTEs, window functions, joins |
| Modeling | Scikit-learn (Logistic Regression, Random Forest) |
| Explainability | SHAP |
| Visualization | Power BI |
| Workflow automation | n8n, Gmail, Google Sheets, Google Drive |
| Environment | Google Colab / Jupyter |

---

## 7. Skills Demonstrated

**Data Analytics** — SQL window functions & CTEs, KPI design, zone bottleneck vs. causation analysis, business-metric-driven model selection.
**Applied ML** — class-imbalance handling, stratified evaluation, model comparison against a business objective rather than accuracy alone.
**Explainable AI** — SHAP-based global and local explanations translated into operational language.
**Workflow Automation** — multi-system orchestration (n8n), conditional business logic, automated logging and notification.
**Documentation & Judgment** — explicit assumptions, simulated-vs-observed data disclosure, and manually-reviewed thresholds rather than blind automation.

---

## 8. Assumptions & Limitations

- The dataset has no true SLA-breach labels; `high_risk` is derived from a documented, disclosed discrete-event simulation, not observed outcomes.
- `priority_num`'s dominance in SHAP is partly attributable to the simulation's own processing order, not proven as an independent real-world driver — flagged rather than oversold.
- The `high_risk_orders > 2` alert threshold is an illustrative business rule, not a statistically optimized value.
- The pipeline runs against a static historical export; it is not connected to a live order stream.
- Alert deduplication is not implemented — a repeated TRUE condition on successive runs would currently re-alert.
- Zone-threshold buckets for the slotting recommendation were manually adjusted in places where automated cutoffs obscured real differences between zones.

## 9. Future Improvements *(not yet implemented)*

- Replace manual workflow execution with a scheduled/event-driven trigger.
- Add data-quality validation before risk aggregation.
- Add alert deduplication / alert-only-on-change logic.
- Store historical risk summaries for trend monitoring.
- Make the alert threshold configurable rather than hard-coded.
- Add severity tiers (Low/Medium/High/Critical) instead of a single boolean rule.

---

## 10. Project Structure

```
warehouse-sla-risk-analytics/
│
├── data/
│   ├── raw/                          # original Kaggle export
│   └── processed/                    # zone_workload_clean.csv, dashboard CSVs
│
├── sql/
│   └── zone_analysis_queries.sql     # aggregation, joins, window functions, CTEs
│
├── notebooks/
│   ├── 01_cleaning_feature_engineering.ipynb
│   ├── 02_sla_simulation.ipynb
│   ├── 03_model_training_shap.ipynb
│   └── 04_zone_slotting_recommendation.ipynb
│
├── n8n/
│   └── order_risk_automation.json
│
├── dashboard/
│   ├── warehouse_dashboard.pbix
│   └── screenshots/
│
├── README.md
└── requirements.txt
```

---

## 11. Key Takeaway

This project doesn't stop at a dashboard or a model score. It follows the full chain:

```
DATA → INSIGHT → PREDICTION → EXPLANATION → DECISION → AUTOMATED ACTION
```

Every step — including the model choice, the SHAP caveat, and the alert threshold — was picked and documented for a specific operational reason, not to maximize a leaderboard metric.
