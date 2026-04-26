# Paper Outline

1. introduction
2. background
3. experimental design
4. results and discussion
5. conclusion


#ideas to mention:

-the goal is to test whether N4sid is a valid modeling technique compared to Machine Learning and Physics based equations of motion.
-it was proven that the modeling technique works for the regime that i tested (a boat accelerating and doing a circle). There are areas of opportunities to improve the model, but given the theil and pearson results and the limitations of the experimental design we can conclude that the technique works. 
- 3 limitations of the experimental design: 1. the pool is only 4 x 5 meter and the boat is 0.8 meters. for comparison, lovo ayala et al [reference 1], use a pool 25 m by 30 m for a 2 meter long boat. Thus, i was only able to excite the dynamics in a contrained regime and the model is too specific. 
2. the sensors produce a noisy speed that hinders the precision of the modeling. better sensors include higher sampling rate sensors and accelerometers or imu.
3. camera field of view, the camera had to be in diagonal perpective, which hinders visualization of the marker at certain intances. so placing camera higher would have reduced nan recordings and increase workable region of the boat. 

-mention why regime a and regime b. regime a is an acceleration from 0m/s, regime b start of the turning. two different tasks of a manuever. so they are dynamically different and worth analysing separately, because a single theil or pearson for the whole manuever whole hide the fact that the model is good, but hindered do to noise speed calculation of the circle part.
-mention model parameters. 
-mention stuff from theil analysis and pearson analysis (theil: most of the times (regime A for speed, regime A and B for yaw) the shape of the predicted model is good but not good enough; in regime B of speed the error comes mostly from U^C which is because the data was noisy. ) (pearson: most of the time the shape of the prediction is really good, except the regime B of the speed)


#write Paper sections:

---

# Vision-Based System Identification of a Small Surface Vehicle: A Regime-Conditioned Validation of N4SID Against Pearson and Theil Diagnostics

## Abstract
Subspace state-space identification is an attractive middle ground between first-principles hydrodynamic modeling and purely data-driven machine learning, but its validity for small, agile surface vehicles operating in confined water is rarely tested with regime-conditioned diagnostics. This work fits a discrete-time, second-order N4SID model that maps propeller-thrust and rudder-angle commands to forward speed and yaw of a 0.8 m radio-controlled boat, using only an overhead-camera ArUco tracker as the kinematic sensor. Eighteen trials spanning three propeller commands and two rudder commands were segmented into a straight-line acceleration regime (A) and a steady-circle regime (B). Pearson correlation and Theil inequality decomposition were computed per regime and reported with 95% confidence intervals on linear trends. The model achieves regime-A speed and yaw correlations of 0.99 and 0.89 and a regime-B yaw correlation of 0.97; regime-B speed is dominated by covariance error, attributable to differentiated-position speed noise rather than structural model error.

**Keywords:** system identification, N4SID, Theil decomposition, Pearson correlation, ArUco tracking, small surface vehicle.

## 1. Introduction
Modeling the planar dynamics of a small surface vehicle is a prerequisite for closed-loop control, trajectory planning, and pedagogical demonstrations of marine robotics, yet the appropriate level of model fidelity for short, confined experiments is not obvious. Three families of approaches dominate: physics-based equations of motion derived from Fossen-style maneuvering models, data-driven machine-learning regressors, and linear subspace system identification. The first requires hydrodynamic coefficients that are difficult to obtain on small custom hulls; the second requires data volumes that are impractical in a single laboratory session. Subspace identification, and specifically the N4SID algorithm, sits between these extremes by fitting a low-order linear state-space model directly from input–output data without requiring a parametric drag or added-mass model.

The central question of this study is whether an N4SID-fit model is a valid modeling technique for a small autonomous boat when judged against the diagnostics that practitioners actually care about: does the predicted output track the *shape* of the measurement, and where does the residual error come from? Validity is established here not by a single fit-percentage but by stratifying the evaluation across two dynamically distinct phases of a single maneuver: a straight-line acceleration from rest (Regime A) and the steady-state portion of a turn (Regime B). A single global metric averaged across both regimes would conflate two physically separate failure modes.

The apparatus is deliberately minimal: a tank, a radio-controlled boat instrumented only with an ArUco fiducial marker on its deck, and an overhead camera that recovers the boat pose `(x, y, ψ)` in a calibrated world frame. Inputs are the propeller-thrust and rudder-angle PWM commands sent to an on-board ESP32. The full eighteen-trial data set is used to fit a second-order state-space model and to evaluate it through Pearson correlation `r`, the bias / variance / covariance Theil decomposition `U^B`, `U^V`, `U^C`, and the slopes of these metrics versus operating command, each reported with 95% confidence intervals.

The remainder of the paper is organized as follows. Section 2 reviews the kinematic conventions, the N4SID estimator, and the Pearson and Theil metrics used for validation. Section 3 describes the apparatus, calibration, experimental matrix, and data-processing pipeline. Section 4 reports the identified model, presents the regime-conditioned diagnostics, and discusses the dominant error mechanisms. Section 5 concludes with the conditions under which the linear model is and is not adequate, and identifies three concrete limitations of the experimental design that should guide future work.

## 2. Background
### 2.1 Kinematic conventions
A right-handed body-fixed frame is attached to the boat with the *x*-axis pointing to starboard, the *y*-axis pointing forward through the bow, and the *z*-axis pointing up out of the deck. The world frame is aligned with the pool surface so that the marker pose recovered from the camera is expressed as `(x(t), y(t), ψ(t))`, where `ψ` is the heading measured about the world *z*-axis. Forward speed is the magnitude of the planar velocity, `v(t) = sqrt(x_dot^2 + y_dot^2)`, and yaw is unwrapped before fitting to remove the `±π` discontinuity.

### 2.2 N4SID subspace identification
The model fit to the data is a discrete-time innovations state-space form:

```
x_{k+1} = A x_k + B u_k + K e_k
y_k     = C x_k + D u_k + e_k
```

with input vector `u = [u_prop_percent, u_rudder_deg]^T` and output vector `y = [v, ψ_unwrapped]^T`. The state dimension is fixed at `n_x = 2`, chosen as the smallest order that captures the dominant surge and yaw time constants without overfitting the short transients available in a 4 × 5 m tank. The estimator is the N4SID subspace algorithm with simulation-focused fitting, which selects the matrices that minimize one-step-ahead innovations error while penalizing open-loop simulation drift. Multiple identification trials are merged into a single multi-experiment dataset so that one model is challenged against every validation trial.

### 2.3 Pearson correlation
For each (trial, regime, output) triple, paired samples `{(y_k, ŷ_k)}` are formed from the measured signal `y` and the simulated signal `ŷ`, and Pearson’s linear correlation is computed:

```
r = sum_k (y_k - y_bar)(ŷ_k - ŷ_bar) / sqrt( sum_k (y_k - y_bar)^2 · sum_k (ŷ_k - ŷ_bar)^2 ).
```

A high `r` indicates that the predicted signal *co-varies* with the measurement — that the *shape* of the trajectory is reproduced — but it does not by itself imply that the bias or amplitude is correct. This is precisely why Pearson is reported jointly with the Theil decomposition.

### 2.4 Theil MSE decomposition
With mean squared error `MSE = (1/N) sum_k (y_k − ŷ_k)^2`, Theil’s identity

```
MSE = (y_bar − ŷ_bar)^2 + (s_y − s_ŷ)^2 + 2 s_y s_ŷ (1 − r)
```

partitions the error into a bias term, a variance-amplitude term, and a covariance term. Normalizing each term by the MSE yields the Theil proportions

```
U^B = (y_bar − ŷ_bar)^2 / MSE,
U^V = (s_y − s_ŷ)^2 / MSE,
U^C = 2 s_y s_ŷ (1 − r) / MSE,
```

with `U^B + U^V + U^C = 1`. A bias-dominated error (large `U^B`) indicates an offset or calibration mismatch; a variance-dominated error (large `U^V`) indicates a gain or amplitude mismatch; a covariance-dominated error (large `U^C`) indicates timing, phase, or unmodeled dynamics — or, in practice, output noise that the model cannot and should not chase.

### 2.5 Trend fits and uncertainty
For each combination of (output, regime, rudder), the dependence of `r`, `U^B`, `U^V`, and `U^C` on propeller command is summarized by a linear regression `y = m x + b`, with parameter uncertainty reported at the 95 % confidence level as `m = m_0 ± u_m` and `b = b_0 ± u_b`. A slope is interpreted as statistically meaningful only if its 95 % confidence interval excludes zero; sample count `n`, coefficient of determination `R^2`, and root-mean-square error are reported alongside every fit.

## 3. Experimental Design
### 3.1 System architecture
The apparatus has three coupled components: a calibrated overhead-camera vision system that recovers boat pose in a fixed world frame, an on-board ESP32 controller that receives commands wirelessly and drives the electronic speed controller and the rudder servo, and a laptop-side runtime loop that simultaneously detects the marker, sends actuator commands, and logs the synchronized time series. The schematic of the apparatus and the body-fixed frame convention are shown in Figure 1, and a photograph of the actual rig is shown in Figure 2.

> **Fig. 1.** Schematic of the experimental setup. A laptop drives an overhead camera that observes the boat through a deck-mounted ArUco fiducial marker; the boat carries an on-board computer that receives propeller-thrust and rudder-angle PWM commands wirelessly. The dashed curve illustrates a representative trajectory in the world frame. The inset Cartesian frame defines the body-fixed convention used throughout: *z* up, *y* forward through the bow, *x* to starboard.

> **Fig. 2.** Photograph of the experimental rig. The 4 × 5 m water tank holds the 0.8 m radio-controlled boat, on which the on-board computer and the ArUco marker are visible on the deck. An iPhone mounted at the back of the tank serves as the overhead camera and is tethered to the laptop in the background.

### 3.2 Vision-based pose measurement
A printed `DICT_6X6_250` ArUco marker is mounted rigidly on the boat parallel to the water surface and approximately above the center of mass; a constant *z*-offset is applied analytically to refer the recovered pose to the center of mass. Additional fixed markers around the tank define the pool-plane coordinate frame. The camera observes the scene from an oblique angle. Marker detection at each frame yields the pose `(x(t), y(t), ψ(t))` in the world frame.

### 3.3 Camera calibration
Camera intrinsics are estimated from chessboard images captured at the experimental resolution and held fixed during extrinsic calibration, which uses the known positions of the reference markers on the pool plane. Reprojection RMSE is **2.56 px** for intrinsics and **8.46 px** for extrinsics. The extrinsic residual does not decrease with additional frames, indicating a stable solution dominated by systematic effects: residual lens distortion, oblique-angle corner localization bias, and slight non-coplanarity of the reference markers. The propagated planar position uncertainty is approximately 3 mm, which is small relative to the meter-scale trajectories observed in the tank.

### 3.4 Actuation and communication
Propeller thrust and rudder angle are commanded as PWM microsecond values. The laptop transmits commands over Wi-Fi to the on-board ESP32, which generates the corresponding ESC and servo signals. Commands are mapped from PWM into physically interpretable channels before identification:

```
u_prop_percent  = (u_prop_PWM   − 1500) / 500 · 100,    u_prop_percent ∈ [0, 100]
u_rudder_deg    = (u_rudder_PWM − 1500) / 500 · 40,     u_rudder_deg   ∈ [−40, 40]
```

so that the input vector presented to N4SID is `u(t) = [u_prop_percent(t), u_rudder_deg(t)]^T`.

### 3.5 Data acquisition
A single runtime loop performs marker detection, command updates, and logging, producing the synchronized record `[t, u_prop, u_rudder, x, y, ψ]`. The nominal sampling rate is 60 Hz and the observed rate is approximately 40 Hz once frame processing overhead is included; all subsequent analysis uses the timestamp-derived sample interval rather than the nominal rate.

### 3.6 Experimental procedure and matrix
Every trial follows the same fixed sequence: the boat is initialized at rest with neutral inputs (1500 µs on both channels); a step in propeller command is applied to one of {1625, 1650, 1675} µs; forward motion is allowed to develop until the boat reaches an approximately steady speed; a step in rudder command to one of {1775, 2000} µs (equivalent to 22° and 40°) is then applied and the boat completes a turn. The full experimental matrix is therefore 3 propeller levels × 2 rudder levels × 3 repetitions = **18 trials**, summarized in Figure 3. Each trial is treated as an independent realization under fixed inputs.

> **Fig. 3.** Experimental matrix. All 18 trials are organized by propeller-thrust PWM (1625 / 1650 / 1675 µs, equivalent to 25 / 30 / 35 % of full thrust) and by rudder-angle PWM (1775 / 2000 µs, equivalent to 22° / 40° of rudder deflection), with three repetitions per (propeller, rudder) cell.

### 3.7 Data processing
Position time series are smoothed with a Savitzky–Golay filter (with a fallback for short records) and differentiated to obtain `(x_dot, y_dot)`, from which the speed magnitude is computed and zero-phase low-pass filtered to suppress differentiation noise. Yaw is unwrapped to a continuous signal for identification and re-wrapped only for visualization. Rows containing non-finite values are removed; trials with insufficient sample count or known boundary-contact events are excluded. Inputs and outputs are time-aligned on the recorded timestamps. Figure 4 shows the propeller- and rudder-command time histories of a representative trial, with Regime A and Regime B shaded in red and blue respectively. Figure 5 shows the corresponding planar trajectory and yaw with the same regime coloring.

> **Fig. 4.** Inputs of a representative trial. Propeller-thrust and rudder-angle PWM commands are plotted versus time. The red background marks Regime A (straight-line acceleration from rest); the blue background marks Regime B, which begins at the rudder step where the boat starts to turn.

> **Fig. 5.** Outputs of the same representative trial. (Top) Planar trajectory `(x, y)` in the world frame, with red circles indicating samples that fall in Regime A and blue circles indicating samples in Regime B. (Bottom) Yaw `ψ(t)` versus time, color-coded with the same convention.

### 3.8 Regime segmentation
Each trial is partitioned into two contiguous phases. **Regime A** spans from `t = 0` to just before the detected onset of turning and represents the boat accelerating from rest along an approximately straight path. **Regime B** spans from the end of Regime A to the end of the trial and corresponds to the steady-state circular maneuver. Regimes A and B are dynamically distinct tasks — a longitudinal acceleration and a coupled yaw–surge limit cycle — so a single Pearson or Theil score over the full trial would mask the fact that the model captures one regime well while struggling with another. An earlier sample-wise gated turning mask was discarded because it produced fragmented Regime B segments that were difficult to interpret; the contiguous-block definition is used throughout.

### 3.9 Model identification and validation
A second-order N4SID model is identified on a manually curated subset of trials spanning both rudder levels and all three propeller levels; the remaining trials form the validation set. For every validation trial the same preprocessing pipeline is applied, the model output `ŷ(t)` is simulated from the measured input `u(t)`, and Pearson `r`, the Theil triplet, and the residual diagnostics are computed per regime. Strict preprocessing parity between identification and validation is enforced so that no construction-mismatch artifacts contaminate the evaluation.

## 4. Results and Discussion
### 4.1 Identified model
A discrete-time, second-order state-space model with two inputs (`u_prop_percent`, `u_rudder_deg`) and two outputs (`speed`, `yaw_unwrapped`) was fit by N4SID with simulation-focused weighting on the merged identification dataset. The fitted eigenvalues are real and inside the unit circle, corresponding to a dominant surge time constant on the order of one second and a yaw integrator-like mode consistent with rudder-driven heading change. Figure 6 overlays the measured and predicted speed and yaw for a representative trial; Figure 7 reports the Pearson `r` and Theil triplet for that single trial as a per-regime table.

> **Fig. 6.** Real (solid) versus N4SID-predicted (dashed) outputs for the representative trial of Figs. 4–5. (Top) Speed `v(t)`. (Bottom) Yaw `ψ(t)`. Regime A and Regime B are indicated by the red and blue background shading, respectively.

> **Fig. 7.** Per-regime validation metrics for the same representative trial. The table reports Pearson correlation `r` and the Theil triplet `[U^B, U^V, U^C]` separately for each (output, regime) pair: speed × A, speed × B, yaw × A, and yaw × B.

### 4.2 Regime-conditioned Pearson correlation
Aggregating across all validation trials and weighting by sample count, the regime-level Pearson correlations are

```
r(speed, A) = 0.988,    r(speed, B) = −0.182,
r(yaw,   A) = 0.885,    r(yaw,   B) = 0.974.
```

Three of the four cells indicate that the predicted shape closely tracks the measured shape: speed in Regime A and yaw in both regimes are reproduced with high linear correlation. The single anomaly is speed in Regime B, where `r` is small and slightly negative — the predicted speed during the steady circle does not co-vary with the measured speed. As discussed below, this is the signature of measurement noise on the differentiated-position speed during a sustained yaw, not of a missing dynamic mode.

The full per-trial breakdown of these aggregate numbers is shown in Figures 8 and 9, which plot Pearson `r` for the speed and yaw channels as a function of propeller-thrust command, with one marker per validation trial separated by regime and rudder setting. Per-rudder linear regressions `r = m·x + b` are overlaid with shaded 95 % confidence bands. Statistically meaningful slopes (95 % CI excludes zero) appear in two cases: a **negative** slope for speed in Regime A at 22° rudder (Fig. 8) and a **positive** slope for yaw in Regime B at 40° rudder (Fig. 9). The remaining regressions have confidence intervals that cross zero and are reported as non-significant.

> **Fig. 8.** Aggregate Pearson correlation `r` for the **speed** channel across all 18 validation trials, plotted as a function of propeller-thrust command (% of full thrust). One marker per trial, with four series corresponding to the (regime, rudder) combinations: Regime A / Rudder 22° (red circles), Regime B / Rudder 22° (blue triangles), Regime A / Rudder 40° (red squares), Regime B / Rudder 40° (blue diamonds). Per-series linear fits are overlaid with shaded 95 % confidence bands on slope and intercept. Regime-A points cluster near `r ≈ 1`; Regime-B points are distributed near and below zero.

> **Fig. 9.** Aggregate Pearson correlation `r` for the **yaw** channel, in the same per-trial scatter format as Fig. 8. The vertical axis is zoomed to the high-correlation range observed for yaw. Three of the four series (both rudders in Regime B and Rudder 22° in Regime A) cluster tightly near `r ≈ 0.95–1.0`; Rudder 40° in Regime A is the most dispersed series.

### 4.3 Theil decomposition by regime
The mean Theil proportions across all validation trials are

```
[U^B, U^V, U^C](speed, A) = [0.724, 0.189, 0.087],
[U^B, U^V, U^C](speed, B) = [0.174, 0.077, 0.749],
[U^B, U^V, U^C](yaw,   A) = [0.991, 0.009, 0.000],
[U^B, U^V, U^C](yaw,   B) = [0.693, 0.284, 0.023].
```

Three of the four regime/output combinations are bias-dominated — speed-A, yaw-A, and yaw-B. Recalling that a bias-dominated error has a small covariance term `U^C`, this means that the *shape* of the predicted trajectory is correct in those cases and the residual MSE is concentrated in a constant offset or a slow gain mismatch that could be removed by a simple calibration or by an integral term in a downstream controller. Yaw in Regime A is the clearest example, with `U^B ≈ 0.99` and a near-zero `U^C`: the model reproduces the heading dynamics during straight-line acceleration almost perfectly up to a constant offset.

The exception is speed in Regime B, where `U^C ≈ 0.75` — the residual MSE is dominated by covariance/timing error. This is consistent with the small Pearson `r` in the same cell. The mechanism is, however, *not* a structurally missing dynamic mode but rather measurement noise: the boat speed is computed by numerical differentiation of camera-tracked position, and during the steady circle the true speed is nearly constant while the noise on the differentiated position is amplified by lateral acceleration. A nearly-constant predicted speed cannot, by construction, correlate with high-frequency noise, and the Theil identity assigns the resulting MSE almost entirely to `U^C`.

### 4.4 Trends with operating command
Figures 10 and 11 plot `U^B`, `U^V`, and `U^C` for speed and yaw, respectively, as a function of propeller command, separated by rudder level. Statistically significant slopes (95 % CI excludes zero) at the analyzed conditions include: yaw `U^B` positive in Regime A at 22° and negative in Regime B at 40°; yaw `U^V` negative in Regime A at 22° and positive in Regime B at 40°; speed `U^B` positive in both Regime A at 22° and Regime B at 40°; and speed `U^C` negative in Regime B at 40°. The remaining trends have confidence intervals that include zero and are reported as weak.

> **Fig. 10.** Theil components for the speed channel as a function of propeller-thrust command. The three side-by-side panels show (left) the bias term `U^B`, (center) the variance term `U^V`, and (right) the covariance term `U^C`. Markers are separated by regime (A / B) and rudder setting (22° / 40°). Linear fits `y = m x + b` are overlaid with shaded 95 % confidence bands on the slope and intercept.

> **Fig. 11.** Theil components for the yaw channel, in the same three-panel layout as Fig. 10 (`U^B`, `U^V`, `U^C` left-to-right). Markers are again separated by regime (A / B), and by both rudder setting and propeller-thrust level so that operating-command dependence can be read off each panel.

Figure 12 shows the regime/output mean Theil proportions as a stacked bar chart, summarizing the structural finding that bias dominates everywhere except speed in Regime B.

> **Fig. 12.** Mean Theil MSE proportion across all 18 trials, shown as a stacked-bar summary of `[U^B, U^V, U^C]` for each (output, regime) combination: (speed, A), (speed, B), (yaw, A), and (yaw, B). The bias term dominates three of the four cells; only speed in Regime B is dominated by the covariance term `U^C`.

### 4.5 Synthesis
The combined Pearson and Theil picture establishes that the N4SID modeling technique works for the regimes tested. In three of four regime/output cells the model reproduces the dynamic *shape* of the measurement and the remaining error is an offset that downstream control or calibration can absorb. The single weak cell — speed in Regime B — is explained by sensor noise on a differentiated position signal, not by a deficiency of the linear model. This is a meaningful answer to the modeling-choice question posed in Section 1: for a small surface vehicle accelerating from rest and entering a sustained circle, an N4SID-fit second-order state-space model is sufficient, and the additional complexity of physics-based hydrodynamic equations or machine-learning regressors is not justified by the present data.

Three limitations of the experimental design constrain the strength of this claim. First, the tank is only 4 × 5 m for a 0.8 m boat, whereas comparable studies such as Lovo Ayala et al. [Reference 1] use a 25 × 30 m basin for a 2 m boat. The dynamics excited here are therefore confined to a single operating envelope and the identified model is correspondingly specific. Second, the speed signal is obtained by differentiating the camera-tracked position at an effective 40 Hz, which produces noise that hinders the precision of the estimator; a higher-rate position sensor or an on-board accelerometer or IMU would substantially reduce the regime-B `U^C` term. Third, the camera observes the marker from an oblique angle and occasionally loses detection; a higher mounting position would increase the workable region of the tank and reduce the number of dropped frames.

## 5. Conclusion
A second-order discrete-time state-space model identified by N4SID from overhead-camera ArUco tracking is a valid and sufficient model of the small surface vehicle studied here, when validity is judged by regime-conditioned Pearson correlation and Theil error decomposition rather than by a single global fit percentage. Across the eighteen-trial matrix the model achieves a weighted Pearson correlation of 0.99 for speed in the straight-line acceleration regime and 0.89 and 0.97 for yaw in the acceleration and circle regimes respectively; the Theil decomposition shows that residual error in those three cells is bias-dominated and therefore correctable by calibration or a downstream integral controller. The single weak cell — speed correlation in the circle regime — is attributable to measurement noise on differentiated camera-tracked position rather than to missing dynamics. The combination of a regime-aware split with Theil decomposition gives diagnostic interpretability that a single fit percentage cannot, isolating *where* the model fails and *why*. Future work should expand the operating envelope by repeating the experiment in a larger basin, replace the differentiated-position speed with an on-board IMU, and elevate the camera to remove oblique-angle dropouts.

