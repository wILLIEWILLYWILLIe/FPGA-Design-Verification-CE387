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
- [ ] **`fir.sv`** — 通用參數化實數 FIR（tap 數、係數、decimation 可配置）
- [ ] **`fir_cmplx.sv`** — 複數 FIR（實例化兩個 `fir.sv`）
- [ ] **`qarctan.sv`** — 分段有理逼近的 arctan（或查表）

### Phase 2：FM 解調路徑（先跑出單聲道輸出）
- [ ] **`demodulate.sv`** — 4 個乘法 + `qarctan` + gain
- [ ] **`fm_channel.sv`** — Channel Filter + FM Demod 串聯
- [ ] **`mono_path.sv`** — L+R FIR + decimation=8 → 32 kHz 單聲道

### Phase 3：立體聲分離
- [ ] **`pilot_gen.sv`** — BP_PILOT → 平方 → HP → 38 kHz 載波
- [ ] **`stereo_path.sv`** — BP_LMR → × 38 kHz → AUDIO_LMR + decimation=8

### Phase 4：後處理與整合
- [ ] **`deemphasis.sv`** — 1st-order IIR，左右各一路
- [ ] **`fft_top.sv`** — 全系統整合 + FIFO 緩衝

### Phase 5：驗證
- [ ] C 模擬輸出作為 golden reference（各模組逐一驗證）
- [ ] ModelSim 定點數 vs C 參考輸出比較
- [ ] UVM 環境（如時間允許）

---

## 6. FPGA 實作注意事項

| 考量 | 說明 |
|------|------|
| **量化格式** | 全程 Q10（`× 1024`），乘法後需 `DEQUANTIZE`（`>> 10`）|
| **乘法位寬** | `int × int` = 32×32 → 64 bit，要確保截斷策略一致 |
| **除法** | `qarctan` 中有一次整數除法，可用 DSP 或查表替代 |
| **Pitch Squaring** | `multiply_n(bp_pilot, bp_pilot)` 就是自身相乘，非常簡單 |
| **FIFO 同步** | 三路並行路徑最終採樣率不同（256 kHz vs 32 kHz），需 FIFO 對齊 |
| **sin_lut** | `fm_radio.h` 裡有 1024-entry sin LUT，但 C code 中**並未實際使用** |

---

## 7. Source Files 說明 (`src/`)

| 檔案 | 說明 |
|------|------|
| `fm_radio.h` | 所有常數定義（`QUANT_VAL`, `AUDIO_RATE`, `FM_DEMOD_GAIN` 等）、所有 FIR/IIR 濾波器係數陣列（hex 格式，Q10 定點）、`sin_lut` 查表（1024 entry，但 C code 未使用） |
| `fm_radio.cpp` | 完整 FM Radio DSP 流水線實作。`fm_radio_stereo()` 是主入口，依序呼叫 Channel Filter → FM Demod → 三路並行濾波 → 立體聲重建 → De-emphasis → 音量控制 |
| `audio.cpp` | Linux OSS 音效裝置驅動（`/dev/dsp`）。`audio_init()` 開啟裝置並設定 32 kHz stereo 16-bit，`audio_tx()` 將 `int[]` 轉為 `short[]` 後寫入裝置。**FPGA 不需要這個檔案** |
| `main.cpp` | 程式主入口：開啟 `test/usrp.dat`，進入 `while(!feof)` 迴圈，每次讀取 `SAMPLES×4` bytes（262144×4 = 1 MB）→ 呼叫 `fm_radio_stereo()` → `audio_tx()` 即時播放。是**串流批次處理**模型，每批 ~4 秒音訊 |
| `main_golden.cpp` | 自製的 golden reference 產生器（取代 `main.cpp`）。只處理第一批資料，但把所有中間訊號都 dump 成 `test/*.txt`，供 FPGA bit-true 驗證用 |

---

## 8. Golden Reference 檔案說明 (`test/`)

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

> **FPGA 驗證方式：** 每個 SV 模組的 testbench 讀取對應的輸入檔，比對輸出是否與輸出檔完全一致（bit-true）。
> 例如驗證 `fir.sv`（Channel Filter）：輸入 `in_I.txt` → 比對 `ch_I.txt`。