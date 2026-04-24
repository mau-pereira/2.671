# N4SID Camera Boat Context (Working Notes)

This file is a reusable context brief for Cursor chats. It summarizes the current data pipeline, identification setup, error metrics, and interpretation logic used in:

- `data_folder/April22_data_processing/plot_n4sid_real_vs_pred_all_rawdata.m`

It is not final manuscript text; it is reference material for drafting.

---

## 1) Dataset and Trial Handling

- Source data are CSV experiments containing:
  - `timestamp`
  - `u_propeller_pwm`
  - `u_rudder_pwm`
  - `x`, `y`, `yaw`
- Rows with non-finite values are filtered out.
- A minimum sample threshold is enforced per file.
- Invalid trials (boat touching border) were separated from the main analysis folder.
- Validation loops over experiment CSVs in the main folder (excluding non-experiment aggregate files like `n4sid.csv`).

---

## 2) Input/Output Signal Construction

### Inputs

PWM commands are converted to physically meaningful channels:

\[
u_1 = u_{\text{prop,\%}} = \frac{u_{\text{prop,pwm}}-1500}{500}\cdot 100,\quad u_1\in[0,100]
\]

\[
u_2 = u_{\text{rudder,deg}} = \frac{u_{\text{rudder,pwm}}-1500}{500}\cdot 40,\quad u_2\in[-40,40]
\]

### Outputs

- Speed is derived from position:
  1. Smooth \(x(t), y(t)\) (Savitzky-Golay; moving-average fallback for short segments),
  2. Differentiate to obtain \(\dot{x}, \dot{y}\),
  3. Compute \(v(t)=\sqrt{\dot{x}^2+\dot{y}^2}\),
  4. Low-pass filter speed with zero-phase Butterworth filtering.

- Yaw used for identification is **unwrapped**:

\[
\psi_{\text{id}}(t)=\mathrm{unwrap}(\psi(t))
\]

So identification output vector is:

\[
y=[v,\ \psi_{\text{id}}]^\top
\]

---

## 3) Identification Modes

The workflow supports three modes:

1. Use all experiment CSV files in folder for identification.
2. Use one explicit identification CSV.
3. Use a hand-picked list of identification CSV files (merged in specified order).

---

## 4) N4SID Estimation

Discrete-time state-space model estimated using N4SID (`Focus='simulation'`):

\[
x_{k+1}=Ax_k+Bu_k+Ke_k,\qquad y_k=Cx_k+Du_k+e_k
\]

- Current model order (`nx`) is configurable (often 2).
- Multi-file identification uses merged multi-experiment `iddata`.

---

## 5) Validation Procedure

For each validation file:

1. Build processed \(u(t)\), \(y(t)\) using the same preprocessing.
2. Simulate \(\hat{y}(t)\) from the identified model.
3. Plot real vs predicted speed and yaw.
4. Plot time-series error percentages.
5. Compute scalar diagnostics (correlation, normalized error, Theil decomposition).

---

## 6) Yaw Display vs Yaw for ID

- Identification uses unwrapped yaw.
- Visualization uses wrapped yaw (sawtooth view):

\[
\psi_{\text{wrap}}=\mathrm{atan2}(\sin\psi,\cos\psi)
\]

This keeps identification numerically well-behaved while showing heading cycles intuitively.

---

## 7) Error Metrics in Use

### 7.1 Pearson Correlation

\[
r=\mathrm{corr}(y,\hat{y})
\]

Used as a "shape similarity" indicator.

### 7.2 Normalized RMSE-style metric

Reported with selectable normalization:

- `RMSE/std(y)` (default),
- or `RMSE/range(y)`.

### 7.3 Compare-style fit percentage

Based on identification toolbox goodness-of-fit:

\[
\mathrm{Fit}_{\%}=100\cdot(1-\mathrm{NRMSE}_{\text{gof}})
\]

### 7.4 Theil MSE Proportions

Error decomposition into:

- \(U^B\): bias contribution,
- \(U^V\): variance contribution,
- \(U^C\): covariance/shape-timing contribution,

with \(U^B+U^V+U^C\approx 1\).

---

## 8) Percent Error Curves

### Speed percent error

\[
e_v^\%(t)=100\cdot\frac{|\hat{v}(t)-v(t)|}{\max(|v(t)|,\epsilon_v)}
\]

where \(\epsilon_v\) is a small floor to avoid division instability near zero speed.

### Yaw percent error (fixed angular scale)

Compute wrapped angular error:

\[
e_\psi(t)=\mathrm{atan2}\!\left(\sin(\hat{\psi}_{\text{wrap}}-\psi_{\text{wrap}}),\ \cos(\hat{\psi}_{\text{wrap}}-\psi_{\text{wrap}})\right)
\]

Then normalize by fixed scale:

\[
e_\psi^\%(t)=100\cdot\frac{|e_\psi(t)|}{\pi}
\]

This avoids blow-ups around \(\psi\approx 0\).

---

## 9) Figure Layout and Reporting

Per validation file, the script produces a 4-panel figure:

1. Speed real vs predicted,
2. Speed absolute percent estimation error,
3. Yaw real vs predicted (wrapped view),
4. Yaw absolute percent estimation error.

Legend includes:

- Real and Predicted traces,
- \(r\),
- \(U^B\), \(U^V\), \(U^C\).

Console logs include per-file summary of \(r\) and \(U^B/U^V/U^C\) for speed and yaw.

---

## 10) Current Interpretation Snapshot

- Yaw typically shows high shape agreement in many runs, with residual error often attributable to bias/variance components rather than strong shape mismatch.
- Speed quality is more variable run-to-run and can exhibit larger covariance/shape-related error components.
- This supports using both global fit and decomposition diagnostics to separate calibration issues from structural/dynamic mismatch.

These are working observations and should be re-evaluated whenever identification file selection or preprocessing choices change.

