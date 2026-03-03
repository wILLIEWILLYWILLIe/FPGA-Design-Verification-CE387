# 📻 ECE 387 期末專案：立體聲 FM 接收器 (FPGA)

本專案的目標是在 FPGA 上實現一個完整的 DSP 流水線，將 USRP 採集的 I/Q 數據轉換為左右聲道音訊輸出。  
C 語言參考實作位於 `FM Radio/src/`，需將其轉換為定點數 SystemVerilog。

---

## 1. 系統參數

| 參數 | 值 | 說明 |
|------|----|------|
| `QUAD_RATE` | 256 kHz | USRP 輸出採樣率 |
| `AUDIO_RATE` | 32 kHz | 音訊輸出採樣率 |
| `AUDIO_DECIM` | 8 | 降採樣因子 |
| `BITS / QUANT_VAL` | 10 / 1024 | Q10 定點量化精度 |
| `FM_DEMOD_GAIN` | ≈ 742 (Q10) | `QUAD_RATE / (2π × 55000)` |
| `TAU` | 75 μs | FM de-emphasis 時間常數 |
| `MAX_TAPS` | 32 | 最大 FIR tap 數 |

---

## 2. 完整處理流水線

```
usrp.dat (interleaved I/Q bytes, little-endian 16-bit)
    ↓ read_IQ()             → unpack + QUANTIZE (×1024 → Q10)
    ↓ fir_cmplx_n()         → 20-tap 複數 LPF (Channel Filter, 截止 80 kHz)，decimation=1
    ↓ demodulate_n()        → FM 解調：IQ[n] × conj(IQ[n-1])，qarctan() 取角度

        ┌──────────────────────────────────────────────────────┐
        │               三路並行處理                           │
        ├─────────────────┬────────────────┬───────────────────┤
        │   L+R 路徑      │  Pilot 路徑    │   L-R 路徑        │
        │ fir_n(AUDIO_LPR)│fir_n(BP_PILOT) │ fir_n(BP_LMR)    │
        │ 32-tap LPF      │ 32-tap BPF     │ 32-tap BPF        │
        │ 截止 15 kHz     │ 提取 19 kHz   │ 23~53 kHz         │
        │ decimation=8    │ decimation=1   │ decimation=1      │
        │                 │ × 自身 (平方)  │        ↑          │
        │                 │ → 38 kHz + DC  │        │multiply  │
        │                 │ fir_n(HP)      │        │          │
        │                 │ 移除 DC        │←───────┘          │
        │                 │ → 純 38 kHz   │                   │
        │                 └────────────────┘                   │
        │                   multiply_n()                        │
        │                   L-R 解調回基頻                     │
        │                 fir_n(AUDIO_LMR)                     │
        │                 32-tap LPF, decimation=8             │
        └──────────────────────────────────────────────────────┘
    ↓
    add_n()        → L = (L+R) + (L-R)
    sub_n()        → R = (L+R) - (L-R)
    deemphasis × 2 → 1st-order IIR (L, R 各一路)
    gain_n() × 2   → 音量控制
    ↓
    audio_tx()     → 32 kHz 立體聲輸出
```

---

## 3. 關鍵模組分析

### A. Channel Filter (`fir_cmplx_n`)
- 20-tap，`CHANNEL_COEFFS_IMAG` **全為 0**
- 等效於兩路**獨立的實數 FIR**，共用同一組係數
- FPGA 實作：一個實數 FIR 模組，實例化兩次（I 路 + Q 路）

### B. FM 解調器 (`demodulate` + `qarctan`)
```c
r = prev_r × cur_r + prev_i × cur_i   // Re(conj(prev) × cur)
i = prev_r × cur_i - prev_i × cur_r   // Im(conj(prev) × cur)
out = gain × qarctan(i, r)
```

> ⚠️ **重要：`qarctan` 用的是分段有理逼近，不是 CORDIC！**

```c
// x >= 0:
r = (x - |y|) / (x + |y|)
angle = π/4 - (π/4) × r

// x < 0:
r = (x + |y|) / (|y| - x)
angle = 3π/4 - (π/4) × r
```
只需要：加減、乘、一次除法、符號判斷 → FPGA 直接實作

### C. 通用 FIR (`fir_n`)
- 移位暫存器（shift register）＋ MAC
- 支援 decimation：每 D 個輸入輸出 1 個
- 被 6 條濾波路徑共用，是**最核心的模組**

### D. Pilot 38 kHz 載波生成
```
BP_PILOT (19 kHz) → multiply(自身 → 平方) → HP filter (移除 DC) → 38 kHz 載波
```
再與 BP_LMR 相乘完成 L-R 下變頻

### E. De-emphasis IIR (`iir`)
- 1st-order IIR：`y[n] = 0.174×x[n] + 0.174×x[n-1] - 0.652×y[n-1]`（Q10）
- IIR_X_COEFFS = `[178, 178]`（Q10）
- IIR_Y_COEFFS = `[0, -668]`（Q10）

---

## 4. FIR 濾波器係數總覽

| 模組 | Tap 數 | 類型 | 作用 |
|------|--------|------|------|
| `CHANNEL_COEFFS` | 20 | Complex LPF | 截止 80 kHz，Channel Filter |
| `AUDIO_LPR_COEFFS` | 32 | LPF | 截止 15 kHz，L+R 音訊 |
| `AUDIO_LMR_COEFFS` | 32 | LPF | 截止 15 kHz，L-R 音訊（同上） |
| `BP_PILOT_COEFFS` | 32 | BPF | 19 kHz Pilot Tone |
| `BP_LMR_COEFFS` | 32 | BPF | 23~53 kHz，L-R 載波 |
| `HP_COEFFS` | 32 | HPF | 移除 Pilot 平方後的 DC |

> `AUDIO_LPR_COEFFS` 與 `AUDIO_LMR_COEFFS` **係數完全相同**，可共用同一個模組

---

## 5. 實作計劃與優先順序

### Phase 1：核心基礎模組（先驗證定點數正確性）
- [x] **`fir.sv`** — 通用參數化實數 FIR（tap 數、係數、decimation 可配置）✅
- [x] **`fir_pkg.sv`** — 所有 FIR/IIR 係數 package ✅
- [ ] **`fir_cmplx.sv`** — 複數 FIR（Channel Filter 虛部係數=0，可用兩個 `fir.sv` 代替）
- [x] **`qarctan.sv`** — 分段有理逼近 arctan（package function）✅

### Phase 2：FM 解調路徑（先跑出單聲道輸出）
- [x] **`demodulate.sv`** — conj multiply + `qarctan_f` + gain ✅
- [x] **`fir.sv` (decimation=8)** — L+R LPF ✅（同一 fir.sv 不同參數）
- [ ] **`fm_channel.sv`** — Channel Filter + FM Demod 串聯
- [ ] **`mono_path.sv`** — 全 mono 路徑串接

### Phase 3：立體聲分離
- [x] **`multiply.sv`** — 定點乘法 `DEQUANTIZE(x*y)` ✅
- [x] **`add_sub.sv`** — 加法/減法 (left_raw/right_raw) ✅
- [ ] **`pilot_gen.sv`** — BP_PILOT → 平方 → HP → 38 kHz 載波
- [ ] **`stereo_path.sv`** — BP_LMR → × 38 kHz → AUDIO_LMR + decimation=8

### Phase 4：後處理與整合
- [x] **`deemphasis.sv`** — 1st-order IIR de-emphasis ✅
- [x] **`gain.sv`** — 音量控制 ✅
- [ ] **`fm_radio_top.sv`** — 全系統整合

### Phase 5：驗證
- [x] C 模擬輸出作為 golden reference（`make golden` → `test/*.txt`）✅
- [x] `fir.sv` (Channel, 20-tap, decim=1)：**PASS 262144/262144** ✅
- [x] `fir.sv` (L+R LPF, 32-tap, decim=8)：**PASS 32768/32768** ✅
- [x] `fir.sv` (BP Pilot, 32-tap, decim=1)：**PASS 262144/262144** ✅
- [x] `fir.sv` (BP L-R, 32-tap, decim=1)：**PASS 262144/262144** ✅
- [x] `fir.sv` (HP, 32-tap, decim=1)：**PASS 262144/262144** ✅
- [x] `fir.sv` (L-R LPF, 32-tap, decim=8)：**PASS 32768/32768** ✅
- [x] `demodulate.sv`：**PASS 262144/262144** ✅
- [x] `multiply.sv` (Pilot squaring)：**PASS 262144/262144** ✅
- [x] `multiply.sv` (L-R demod)：**PASS 262144/262144** ✅
- [x] `deemphasis.sv` (Left)：**PASS 32768/32768** ✅
- [x] `gain.sv` (Left)：**PASS 32768/32768** ✅
- [x] `add_sub.sv` (ADD left_raw, SUB right_raw)：**PASS 32768/32768** ✅
- [x] 全流程串接驗證（`fm_radio_top.sv`）：**PASS 32768/32768** ✅
- [ ] UVM 環境（如時間允許）

---

## 6. 模組驗證對照表

| SV 模組 | 輸入 txt | 輸出 golden txt | 說明 |
|---------|----------|----------------|------|
| `fir.sv`（Channel I） | `in_I.txt` | `ch_I.txt` | 20-tap LPF |
| `fir.sv`（Channel Q） | `in_Q.txt` | `ch_Q.txt` | 20-tap LPF |
| `demodulate.sv` | `ch_I.txt`, `ch_Q.txt` | `demod.txt` | FM 解調 |
| `fir.sv`（L+R LPF, ×8） | `demod.txt` | `audio_lpr.txt` | 32-tap, decim=8 |
| `fir.sv`（BP Pilot） | `demod.txt` | `bp_pilot.txt` | 32-tap BPF |
| `fir.sv`（BP L-R） | `demod.txt` | `bp_lmr.txt` | 32-tap BPF |
| `multiply.sv`（平方） | `bp_pilot.txt` × 自身 | `pilot_sq.txt` | 自身相乘 |
| `fir.sv`（HP filter） | `pilot_sq.txt` | `pilot_38k.txt` | 32-tap HPF |
| `multiply.sv`（解調） | `pilot_38k.txt`, `bp_lmr.txt` | `lmr_bb.txt` | L-R 下變頻 |
| `fir.sv`（L-R LPF, ×8） | `lmr_bb.txt` | `audio_lmr.txt` | 32-tap, decim=8 |
| `add_sub.sv` | `audio_lpr.txt`, `audio_lmr.txt` | `left_raw.txt`, `right_raw.txt` | 加減法 |
| `deemphasis.sv`（L/R） | `left/right_raw.txt` | `left/right_deemph.txt` | IIR |
| `gain.sv`（L/R） | `left/right_deemph.txt` | `out_left/right.txt` | 音量控制 |

---

## 7. Debug 紀錄

### A. fir.sv 驗證過程（Xcelium xrun）

| 問題 | 原因 | 修正 |
|------|------|------|
| `$readmemd` not found | Xcelium 不支援 `$readmemd`（非標準） | 改用 `$fscanf` 逐行讀十進位 |
| `always_ff` multiple drivers | `errors`/`checked`/`out_idx` 同時被 `initial` 和 `always_ff` 寫入 | TB 改用 `always @(posedge clk)` |
| `ref` illegal in static task | Xcelium 不允許 static task 使用 `ref` 參數 | 移除 task，改用 inline `$fscanf` |
| `integer i` multiple drivers | `i` 被 `always_comb` 和 `always_ff` 共用 | 各 block 用 `int j`/`int k` local 變數 |
| 262107 mismatches（off-by-one） | `x_reg <= x_in` 是非阻塞，MAC 讀到舊值 | 加 `x_new` 組合邏輯，先算 shift 結果再 MAC |
| 2 mismatches（overflow） | SV 乘法因 64-bit `acc` 被自動提升，不像 C 的 32-bit overflow | 用 `logic signed [31:0] prod` 強制 32-bit，並改為每項單獨 DEQUANTIZE |
| **PASS 262144/262144** | — | 全部修正後 bit-true 通過 |

### B. demodulate.sv 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| 261933 mismatches（大量輸出為 0） | `qarctan` 作為獨立 module，跨模組 `always_comb` evaluation order 問題 | 改為 package function `qarctan_f`，inline 呼叫 |
| 255437 mismatches（系統性 ~2% 偏低） | `FM_DEMOD_GAIN` 常數錯誤：742 → 正確值 758 | 重新計算 `(int)(256000/(2π×55000)×1024)=758` |
| **PASS 262144/262144** | — | 全部修正後 bit-true 通過 |

### C. fir.sv decimation=8 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| 32768 mismatches（全部輸出 `x`） | TB 用 `.*` 自動連接，但本地變數叫 `dut_coeffs`，DUT port 叫 `coeffs`，名字不匹配導致未連接 | 將 TB 中 `dut_coeffs` 改名為 `coeffs` |
| 32747 mismatches（數值錯亂） | `fir.sv` 的 decimation 邏輯每個 clock 移位 DECIM，但每個 clock 只收 1 個樣本 | 改為每個 clock shift 1 位，每 DECIM 個 clock 才算 MAC，移除 `x_new` 組合邏輯 |
| **PASS 32768/32768** | — | 同時 regression 通過：fir (decim=1) PASS 262144/262144 |

### D. multiply.sv 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| **一次通過** | 邏輯簡單，僅 `DEQUANTIZE(x*y)` | 無需修正 |
| **PASS 262144/262144** | — | Pilot 平方驗證通過 |

### E. deemphasis.sv 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| 14123 mismatches（系統性 ±1） | `IIR_Y_COEFFS[1]` 常數錯誤：寫成 -668，實際用 C 程式計算為 -666 | 用 gcc 執行直接算出正確係數：`QUANTIZE_F((0.21140067-1)/(0.21140067+1))=-666` |
| 14123 mismatches（类型報警 + 郾同答案） | 換成 `logic signed` 後仍相同 | 策却是係數錯誤，不是類型問題 |
| **PASS 32768/32768** | — | 係數額正後 + two-process 改寫 |

### F. gain.sv 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| **一次通過** | 邏輯簡單 | 無需修正 |
| **PASS 32768/32768** | — | 音量控制驗證通過 |

### G. add_sub_tb.sv 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| `ref` argument illegal | Xcelium 不支援 static task 使用 `ref` 參數（同 fir_tb 的舊 bug）| 移除 task，改為兩段 inline 迴圈分別跑 ADD 和 SUB |
| **PASS 32768/32768 (ADD + SUB)** | — | bit-true 通過 |

### H. 其餘中間路徑 TB（fir_bppilot/bplmr/hp/lmr, mult_lmr）

| 問題 | 原因 | 修正 |
|------|------|------|
| **全部一次通過** | `fir.sv` 通用模組配係數即可，`multiply.sv` 邏輯已驗證 | 無需修正 |
| **PASS: 全數 262144/262144 或 32768/32768** | — | Pipeline 所有中間路徑 bit-true 驗證完成 |

### I. fm_radio_top.sv (全系統整合) 驗證過程

| 問題 | 原因 | 修正 |
|------|------|------|
| **左右聲道出現對稱誤差 (Left 少 16，Right 多 16)** | L-R 路徑的時間沒對齊。`pilot_38k` 在解調前經過了 `multiply(sq)` 和 `fir(hp)` 浪費了 **2 cycles**，直接拿來跟剛做完 BP 的 `bp_lmr` 相乘會導致時間錯位。因為錯位，`audio_lmr` 算錯，導致加減法後產生 `±LMR_error` 變成對稱誤差 | 在 `bp_lmr` 送入 L-R 解調乘法器前，手動加上 **2-cycle register delay (`bp_lmr_d2`)**，讓兩邊訊號時間完全對齊。 |
| **PASS 32768/32768 (Left & Right)** | — | 全 pipeline 端到端 (End-to-End) bit-true 驗證通過 ✅ |

---

## 8. 目前 SV 檔案列表 (`imp/sv/`)

| 檔案 | 類型 | 驗證狀態 | 說明 |
|------|------|----------|------|
| `fir_pkg.sv` | Package | — | 所有係數、常數定義 |
| `qarctan.sv` | Package | — | `qarctan_f()` inline function |
| `fm_radio_top.sv` | Module | **PASS** | 全系統頂層模組（含 4-cycle LPR delay 及 2-cycle BPLMR delay） |
| `fir.sv` | Module | **PASS** ×6 | 通用 FIR，所有 tap 數、decimation 均可配置 |
| `demodulate.sv` | Module | **PASS** | FM 解調器（conjugate multiply + qarctan + gain） |
| `multiply.sv` | Module | **PASS** | 定點乘法，用於 Pilot 平方和 L-R 解調 |
| `deemphasis.sv` | Module | **PASS** | 1st-order IIR de-emphasis（左/右各一等 |
| `gain.sv` | Module | **PASS** | 音量控制 `DEQUANTIZE(x*gain) << 4` |
| `add_sub.sv` | Module | **PASS** | 加法（left_raw）+ 減法（right_raw） |
| `fir_tb.sv` | TB | ✔ PASS | Channel Filter I 路（in_I → ch_I） |
| `fir_lpr_tb.sv` | TB | ✔ PASS | L+R LPF decim=8（demod → audio_lpr） |
| `fir_bppilot_tb.sv` | TB | ✔ PASS | BP Pilot decim=1（demod → bp_pilot） |
| `fir_bplmr_tb.sv` | TB | ✔ PASS | BP L-R decim=1（demod → bp_lmr） |
| `fir_hp_tb.sv` | TB | ✔ PASS | HP decim=1（pilot_sq → pilot_38k） |
| `fir_lmr_tb.sv` | TB | ✔ PASS | L-R LPF decim=8（lmr_bb → audio_lmr） |
| `demod_tb.sv` | TB | ✔ PASS | FM 解調器（ch_I/Q → demod） |
| `multiply_tb.sv` | TB | ✔ PASS | Pilot 平方（bp_pilot × bp_pilot → pilot_sq） |
| `multiply_lmr_tb.sv` | TB | ✔ PASS | L-R 解調（pilot_38k × bp_lmr → lmr_bb） |
| `deemphasis_tb.sv` | TB | ✔ PASS | IIR de-emphasis Left（left_raw → left_deemph） |
| `gain_tb.sv` | TB | ✔ PASS | 音量控制 Left（left_deemph → out_left） |
| `add_sub_tb.sv` | TB | ✔ PASS | lpr±lmr → left_raw，right_raw |
| `fm_radio_top_tb.sv`| TB | ✔ PASS | 端到端全系統（in_I/Q → left/right_out） |

## 9. Makefile 使用方式 (`imp/sim/`)

```bash
make fir          # Channel Filter (20-tap, decim=1)     in_I → ch_I
make fir_lpr      # L+R LPF (32-tap, decim=8)           demod → audio_lpr
make fir_bppilot  # BP Pilot BPF (32-tap, decim=1)      demod → bp_pilot
make fir_bplmr    # BP L-R BPF (32-tap, decim=1)        demod → bp_lmr
make fir_hp       # HP filter (32-tap, decim=1)         pilot_sq → pilot_38k
make fir_lmr      # L-R LPF (32-tap, decim=8)           lmr_bb → audio_lmr
make demod        # FM 解調器                            ch_I/Q → demod
make mult         # Pilot 平方                             bp_pilot² → pilot_sq
make mult_lmr     # L-R 解調乘法                        pilot_38k×bp_lmr → lmr_bb
make deemph       # IIR de-emphasis (Left)               left_raw → left_deemph
make gain_test    # 音量控制 (Left)                      left_deemph → out_left
make add_sub_test # 加減法                                 lpr±lmr → left/right_raw
make top          # 全系統 Top-level                       in_I/Q → out_left/right
# 以上 13 個 testbench 全部 PASS
make all          # 跑全部系統單元測試與 top
make clean        # 清除 xcelium 檔案
```

---

## 8. FPGA 實作注意事項

| 考量 | 說明 |
|------|------|
| **量化格式** | 全程 Q10（`× 1024`），乘法後需 `DEQUANTIZE`（`>> 10`）|
| **乘法位寬** | `int × int` = 32×32 → 64 bit，要確保截斷策略一致 |
| **除法** | `qarctan` 中有一次整數除法，可用 DSP 或查表替代 |
| **Pitch Squaring** | `multiply_n(bp_pilot, bp_pilot)` 就是自身相乘，非常簡單 |
| **FIFO 同步** | 三路並行路徑最終採樣率不同（256 kHz vs 32 kHz），需 FIFO 對齊 |
| **sin_lut** | `fm_radio.h` 裡有 1024-entry sin LUT，但 C code 中**並未實際使用** |

---

## 9. Source Files 說明 (`src/`)

| 檔案 | 說明 |
|------|------|
| `fm_radio.h` | 所有常數定義（`QUANT_VAL`, `AUDIO_RATE`, `FM_DEMOD_GAIN` 等）、所有 FIR/IIR 濾波器係數陣列（hex 格式，Q10 定點）、`sin_lut` 查表（1024 entry，但 C code 未使用） |
| `fm_radio.cpp` | 完整 FM Radio DSP 流水線實作。`fm_radio_stereo()` 是主入口，依序呼叫 Channel Filter → FM Demod → 三路並行濾波 → 立體聲重建 → De-emphasis → 音量控制 |
| `audio.cpp` | Linux OSS 音效裝置驅動（`/dev/dsp`）。`audio_init()` 開啟裝置並設定 32 kHz stereo 16-bit，`audio_tx()` 將 `int[]` 轉為 `short[]` 後寫入裝置。**FPGA 不需要這個檔案** |
| `main.cpp` | 程式主入口：開啟 `test/usrp.dat`，進入 `while(!feof)` 迴圈，每次讀取 `SAMPLES×4` bytes（262144×4 = 1 MB）→ 呼叫 `fm_radio_stereo()` → `audio_tx()` 即時播放。是**串流批次處理**模型，每批 ~4 秒音訊 |
| `main_golden.cpp` | 自製的 golden reference 產生器（取代 `main.cpp`）。只處理第一批資料，但把所有中間訊號都 dump 成 `test/*.txt`，供 FPGA bit-true 驗證用 |

---

## 10. Golden Reference 檔案說明 (`test/`)

執行 `make golden` 後，`test/` 資料夾會產生以下 18 個檔案，每個檔案每行一個十進位整數（Q10 格式）。

| 檔案 | 樣本數 | 對應 C 函數 | 說明 |
|------|--------|------------|------|
| `usrp.dat` | — | — | 輸入原始數據（binary，I/Q interleaved bytes） |
| `in_I.txt` | 262144 | `read_IQ()` | I/Q 解包 + QUANTIZE 後的 **I 通道** (Q10) |
| `in_Q.txt` | 262144 | `read_IQ()` | I/Q 解包 + QUANTIZE 後的 **Q 通道** (Q10) |
| `ch_I.txt` | 262144 | `fir_cmplx_n()` | Channel Filter (20-tap LPF, 截止 80 kHz) 後的 **I** |
| `ch_Q.txt` | 262144 | `fir_cmplx_n()` | Channel Filter 後的 **Q** |
| `demod.txt` | 262144 | `demodulate_n()` | FM 解調後的瞬時頻率訊號，後續三路並行的共同輸入 |
| `audio_lpr.txt` | 32768 | `fir_n(AUDIO_LPR)` | L+R 路徑：32-tap LPF (15 kHz) + decimation×8 → **32 kHz Mono** |
| `bp_pilot.txt` | 262144 | `fir_n(BP_PILOT)` | Pilot 路徑：32-tap BPF 提取 **19 kHz** 導航音 |
| `pilot_sq.txt` | 262144 | `multiply_n()` | Pilot 自身平方 → **38 kHz + DC** |
| `pilot_38k.txt` | 262144 | `fir_n(HP)` | HP filter 移除 DC 後的純 **38 kHz 載波** |
| `bp_lmr.txt` | 262144 | `fir_n(BP_LMR)` | L-R 路徑：32-tap BPF 提取 **23~53 kHz** 訊號 |
| `lmr_bb.txt` | 262144 | `multiply_n()` | `pilot_38k × bp_lmr`：L-R 解調回**基頻** |
| `audio_lmr.txt` | 32768 | `fir_n(AUDIO_LMR)` | L-R 路徑：32-tap LPF (15 kHz) + decimation×8 → **32 kHz** |
| `left_raw.txt` | 32768 | `add_n()` | `audio_lpr + audio_lmr` = 2L（未 de-emphasis） |
| `right_raw.txt` | 32768 | `sub_n()` | `audio_lpr - audio_lmr` = 2R（未 de-emphasis） |
| `left_deemph.txt` | 32768 | `deemphasis_n()` | 左聲道 de-emphasis IIR 後 |
| `right_deemph.txt` | 32768 | `deemphasis_n()` | 右聲道 de-emphasis IIR 後 |
| `out_left.txt` | 32768 | `gain_n()` | **最終左聲道輸出**（音量控制後，16-bit 範圍） |
| `out_right.txt` | 32768 | `gain_n()` | **最終右聲道輸出**（音量控制後，16-bit 範圍） |

> 例如驗證 `fir.sv`（Channel Filter）：輸入 `in_I.txt` → 比對 `ch_I.txt`。

---

## 11. C Reference (`fm_radio.cpp`) 完整性與對應檢核

為了確保 FPGA 實作完全覆蓋 C 程式的要求，以下為 `fm_radio_stereo()` 中的所有運算步驟與 SV 模組的嚴格對應檢查：

| C 程式運算 (fm_radio_stereo) | C 函數呼叫 | SV 模組對應 | 檢核結果 |
|-----------------------------|------------|-------------|----------|
| **1. Channel Filter (80kHz)** | `fir_cmplx_n` (decim=1) | `fir.sv` (2 次實例化 I/Q) | ✅ **PASS** (bit-true) |
| **2. FM Demodulation** | `demodulate_n` | `demodulate.sv` | ✅ **PASS** (含 `qarctan_f` 行為完全一致) |
| **3. L+R Path (LPF 15kHz)** | `fir_n` (decim=8) | `fir.sv` (`lpr_coeffs`, decim=8) | ✅ **PASS** |
| **4. Pilot BPF (19kHz)** | `fir_n` (decim=1) | `fir.sv` (`pilot_coeffs`) | ✅ **PASS** |
| **5. Pilot Squaring (38kHz)** | `multiply_n` | `multiply.sv` (自身相乘) | ✅ **PASS** |
| **6. Pilot HPF** | `fir_n` (decim=1) | `fir.sv` (`hp_coeffs`) | ✅ **PASS** |
| **7. L-R BPF (23-53kHz)** | `fir_n` (decim=1) | `fir.sv` (`bplmr_coeffs`) | ✅ **PASS** |
| **8. L-R Demodulation** | `multiply_n` | `multiply.sv` (L-R BPF × Pilot HPF) | ✅ **PASS** (加 2-cycle delay 解決時間對齊) |
| **9. L-R Path (LPF 15kHz)** | `fir_n` (decim=8) | `fir.sv` (`lmr_coeffs`, decim=8) | ✅ **PASS** |
| **10. Stereo Mix (Add/Sub)** | `add_n`, `sub_n` | `add_sub.sv` | ✅ **PASS** (加 4-cycle delay 解決 LPR/LMR 對齊) |
| **11. De-emphasis** | `deemphasis_n` | `deemphasis.sv` (IIR) | ✅ **PASS** (修正 `IIR_Y_COEFFS[1]` 為 -666) |
| **12. Volume Control (Gain)** | `gain_n` | `gain.sv` | ✅ **PASS** |

**完整性結論：**
1. 所有 C 迴圈處理均轉換為 **Stream 流水線並行處理**。
2. 所有資料位寬均**嚴格維持 C 的 32-bit int 範圍與溢位行為**。
3. 所有 `DEQUANTIZE` (1024 除法) 與 Q10 格式轉換皆在硬體中完美重現。
4. **Top Level End-to-End 比對：0 Errors (32768/32768 samples for both Left and Right)。**

---

## 12. 合成優化紀錄 (Synplify)

### 修正 1：`deemphasis.sv` — 消除硬體除法器（Quick Fix）

**問題：** `deemphasis.sv` 的組合邏輯中使用 `/ (1 << BITS)`，Synplify 將其推論為 **6 個 `sdiv` 硬體除法器**（L/R 各 3 個）。這導致 RTL 優化階段耗時 **2 分 53 秒**，且佔用大量面積。

**修正：** 將 3 處 `/ (1 << BITS)` 替換為 `fir_pkg::div1024_f()`：
```diff
- c_y1 = (prod0 / (1 << BITS)) + (prod1 / (1 << BITS));
+ c_y1 = fir_pkg::div1024_f(prod0) + fir_pkg::div1024_f(prod1);

- c_y2 = prod0 / (1 << BITS);
+ c_y2 = fir_pkg::div1024_f(prod0);
```

**原理：** `div1024_f` 使用條件式算術右移 (`>>>10`)，純粹是 wiring + 小 mux，不需要除法器硬體。它正確處理 C 語言的截斷至零語義（負數加 1023 再右移）。

---

### 修正 2：`demodulate.sv` — 拆分 Stage 2 除法器管線（Main Fix）

**問題：** 原 Stage 2 在一個組合邏輯塊中同時完成 `abs_y` 計算、乘法 `(x ± abs_y) × 1024`、和除法 `/ (x + abs_y)`。這是 **critical path**：600 logic levels、-15.3ns slack。

**修正：** 將 Stage 2 拆分為兩個管線階段：

| 階段 | 計算內容 | 說明 |
|------|----------|------|
| **Stage 2a（新）** | `abs_y`、`numer = (x ± abs_y) × QUANT_VAL`、`denom = (x + abs_y)` | 準備被除數和除數，註冊 `x_ge0` / `y_neg` 符號旗標 |
| **Stage 2b（原 Stage 2）** | `r = numer / denom` | 僅做除法，輸入為已註冊的 numer/denom |

Pipeline 從 3 stage（Stg1→Stg2→Stg3）變為 4 stage（Stg1→Stg2a→Stg2b→Stg3）。

**不需要調整 Top-level 對齊：** demod 輸出延遲增加 1 cycle，但因為 demod 同時餵給所有下游路徑（LPR、Pilot、BPLMR），相對時序不變，`LPR_DELAY = 4` 和 `bp_lmr_d2` 延遲均維持原值。

---

### 合成結果比較

| 指標 | Rev -1 (原始) | Rev 0 | Rev 4 | Rev 5 | Rev 6 | Rev 7 | Rev 8 | **Rev 9** |
|------|---------------|-------|-------|-------|-------|-------|-------|-----------|
| `sdiv` 數量 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| Logic Levels | 600+ | 49 | 28 | 26 | 51 | 40 | 18 | **18** |
| Critical Path 延遲 | ~101.5 ns | 15.1 ns | 13.6 ns | 13.0 ns | 12.7 ns | 12.6 ns | 11.3 ns | **11.1 ns** |
| 推論頻率 | 9.8 MHz | 66.3 MHz | 73.0 MHz | 76.7 MHz | 78.4 MHz | 79.0 MHz | 88.3 MHz | **89.6 MHz** |
| Critical Path | demod (巨型迴圈) | demod 2c | demod 3b | demod 1a | deemph | deemph in | demod 3c | **fir mult** |

> 補充說明：最一開始的 **Rev -1 (9.8 MHz)** 狀態，是因為 `demodulate.sv` 裡面的 32-bit 除法器 (Restoring Divider) 使用了一個巨大的 `for` 迴圈在「單一一個 Clock Cycle 組合邏輯」中暴力展開算完 32 iter，並且加上 `deemphasis` 裡面的 6 顆巨大硬體除法器 (`sdiv`) 導致了極慘的 Critical Path。\n> 我們透過將它改寫成 32 階的 Pipelined Divider，才一口氣把頻率從 **9.8 MHz 拉升到了 66.3 MHz**，之後才是後續把除法與乘法進一步切碎的 Pipeline 優化。

> 🎉 **從 9.8 MHz → 89.6 MHz，綜合提升 9× 倍！逼近 90 MHz！**

---

### 修正 7：`demodulate.sv` — 管線化 Stage 3b (Rev 7)

**問題（Rev 6）：** 13.6 ns。從 `stg3a_angle` 出來做負號反轉、乘上 `FM_DEMOD_GAIN` 到 `div1024_f` 結束。
**修正：** 將 Stage 3b 拆為 3b (負號反轉 + register) 和 3c (Gain 乘法 + 除法)。
**現象：** 頻率 73.0 → **76.7 MHz**。
**新瓶頸：** Waterbed Effect 再次出現！這次浮現的是 `demodulate.sv` 的源頭 Stage 1 (I/Q 交叉相乘)。

---

### 修正 8：`demodulate.sv` — 管線化 Stage 1 (Rev 8)

**問題（Rev 7）：** 13.0 ns (51 logic levels)。Stage 1 同時算了 4 個乘法與 2 個 `div1024_f`。
**修正：** 切成 Stage 1a (4次乘法) 和 Stage 1b (`div1024_f` + 加減法)。
**現象：** 頻率 76.7 → **78.4 MHz**。
*(受限於 `fm_radio_top.sv` 設定的更高的 Target Clock 101 MHz，Worst Slack 變大了，但不代表變爛，只是我們開始挑戰極限)。*

---

### 修正 9：`fm_radio_top.sv` — 新增 Stage 6.5 Pipeline Register (Rev 9)

**修正：** 
在 `add_sub` 輸出與 `deemphasis` 輸入之間，插入了 `left_raw_reg` 和 `right_raw_reg` (Stage 6.5)。
理論上這能切斷跨 module 組合邏輯。
**現象：** 頻率幾乎沒變 (維持 79.0 MHz，Worst Slack 仍然在 -2.85ns 左右)。
**原因：** 仔細看 Rev 9 的報告，雖然起點變成了 `left_raw_reg`，但長達 12.66 ns 的 delay 其實**全都在 `deemphasis.sv` 內部**！
`deemphasis.sv` 第一個 cycle 就做了 `prod0 = IIR_X_COEFFS[0] * x_in` 和 `prod1 = IIR_X_COEFFS[1] * x0_reg`，接著還把這兩個 42-bit 的乘積各自做了 `div1024_f` 並相加。
這意味著 `乘法 -> 算術右移 -> 24-bit加法` 全擠在同一個 cycle。

---

### 修正 10：`deemphasis.sv` — 管線化 FIR 乘法器 (Rev 10)

**修正：** 
我不只把輸入 register 起來，我更把 `deemphasis.sv` 裡計算出來的 `prod0` 與 `prod1` 也加上了 pipeline register (`prod0_reg`, `prod1_reg`)。
這樣就把原本 12.66ns 的怪獸路徑切成了：
- Cycle 1: 兩個大乘法 (約 5~6 ns)
- Cycle 2: `div1024_f` 與加總 (約 5~6 ns)

**結果：** Logic levels 直接砍半 (40 → 18)，頻率從 79.0 MHz 飆升到 **88.3 MHz**！

---

### 目前 Critical Path 分析 (Rev 10, 88.3 MHz)

繞了一大圈，Critical Path 又回到了 `demodulate.sv` 裡面！

```
Starting point: u_demod.stg3b_angle_signed_reg[0] 
Ending point:   u_demod.demod_out_1[21] 
```

這條路徑有 18 logic levels / 11.3 ns。
這是 **Stage 3c** 的運算：`fir_pkg::div1024_f(FM_DEMOD_GAIN * stg3b_angle_signed_reg)`。
它做了一個大乘法 (與常數 `FM_DEMOD_GAIN` 81711 相乘)，然後立刻做算術右移 (`div1024_f`)。

---

### 修正 11：`demodulate.sv` — 管線化 Stage 3c (Rev 11)

**修正：** 
將 Stage 3c 的長路徑再切一刀，分成：
- **Stage 3c:** `stg3c_prod_calc = FM_DEMOD_GAIN * stg3b_angle_signed_reg;` (存在新的暫存器 `stg3c_prod_reg` 中)
- **Stage 3d:** `demod_out = fir_pkg::div1024_f(stg3c_prod_reg);`

這樣原本 11.3 ns 的常數乘法與算術右移就被切成了兩個 cycle。
**結果：** 的確解決了 Demodulator 的問題，整體頻率提升到 **89.6 MHz** (-2.409ns slack)。

---

### 目前 Critical Path 分析 (Rev 11, 89.6 MHz)

繞了一大圈，Critical Path 終於離開了 `demodulate.sv` 和 `deemphasis.sv`。現在的瓶頸是：

```
Starting point: u_fir_lpr.x_reg[8][0] 
Ending point:   u_fir_bppilot.prod_reg[9]_0[21] 
```

這條路徑有 18 logic levels / 11.1 ns。
這是 `fir.sv` 裡面的大乘法：`prod_comb[i] = coeffs[i] * x_reg[i];` 以及接續的一大串加法樹 (Adder Tree)。
因為前面一直切管線，我們把最長的路徑都壓平了，現在凸顯出來的都是這種「巨大乘法陣列」。

---

### 後續可優化方向：啟用 DSP block 推論 (Rev 12 準備)

到了 89.6 MHz，我們發現到處都是「大乘法陣列」的延遲。
 Cyclone IV 有硬體 DSP block (18x18 或 9x9 multipliers)，專門算這個最快。
如果能在包含乘法的訊號變數或 module 加上 `(* syn_multstyle = "DSP" *)`，強迫編譯器使用 DSP block，就能一口氣收割所有零散的乘法延遲。這不只能解決 `fir.sv` 的問題，對 `demodulate.sv` 或 `deemphasis.sv` 有剩下的小乘法也有幫助。我將在所有會產生巨大乘法的變數宣告上使用這個 PRAGMA。

---

### 總結：所有修正檔案列表

| 檔案 | 修正內容 |
|------|------|
| `deemphasis.sv` | Rev 1: `/ (1<<BITS)` 改 `div1024_f()` (省下近 3 分鐘編譯時間) |
| `demodulate.sv` | Rev 2: 32-stage pipelined restoring divider |
| `demodulate.sv` | Rev 3: Stage 3 拆為 3a, 3b |
| `fir.sv`        | Rev 4: 2-stage pipelined MAC (DSP乘法 → register → Adder Tree) |
| `fm_radio_top.sv` | Rev 4: 對齊各 channel FIR 增加的 1 cycle latency |
| `deemphasis.sv` | Rev 5: FIR / IIR 管線打斷 |
| `demodulate.sv` | Rev 6: Stage 2c divider-output register |
| `demodulate.sv` | Rev 7: Stage 3 分成 3b (正負反轉) 和 3c (乘 Gain) |
| `demodulate.sv` | Rev 8: Stage 1 切斷 (1a 交叉相乘 / 1b 移位加減) |
| `fm_radio_top.sv` | Rev 9: 在 add_sub 和 deemphasis 中間加上 pipeline register |
| `deemphasis.sv` | Rev 10: 管線化 FIR 乘法器 (`prod0`, `prod1` 加上暫存器) |
| `demodulate.sv` | Rev 11: Stage 3 分成 3c (乘 Gain) 和 3d (除 1024) |