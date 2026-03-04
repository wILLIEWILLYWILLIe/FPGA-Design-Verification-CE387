# HW8 Neural Network — SystemVerilog 實現筆記

## 作業概述

實現一個 **hardware-pipelined, streaming Deep Neural Network (DNN)**，用於 MNIST 手寫數字辨識（0–9）。

---

## C 參考程式分析 (`neural_net.c`)

### 網路架構

```
Input (784) → Layer 0 (10 neurons) → ReLU → Layer 1 (10 neurons) → ReLU → Softmax/Argmax → 預測數字
```

| 參數 | 值 |
|------|-----|
| 輸入維度 | 784（28×28 MNIST 像素） |
| Layer 0 | 784 inputs → 10 outputs（7840 weights + 10 biases） |
| Layer 1 | 10 inputs → 10 outputs（100 weights + 10 biases） |
| 輸出 | 10 class scores → argmax → 預測數字 |
| 測試真實標籤 | **7** |

### 定點量化方式（Q14）

```c
#define BITS            14
#define QUANT_VAL       (1 << BITS)       // 16384
#define DEQUANTIZE_I(i) (int)((int)(i) / (int)QUANT_VAL)  // 向零截斷整數除法
```

### Neuron 計算流程

```c
void neuron(int *inputs, int *weights, int bias, int input_size, int *output) {
    int acc = bias;
    for (int i = 0; i < input_size; i++) {
        acc += DEQUANTIZE_I(inputs[i] * weights[i]);  // 每次 MAC 後反量化
    }
    *output = acc >> BITS;  // 最終輸出再反量化一次
}
```

**關鍵觀察：**
1. **每次乘法後立即反量化**：`acc += DEQUANTIZE_I(inputs[i] * weights[i])`
2. **反量化 = 整數除法（向零截斷）**：不是算術右移（向負無窮取整）
3. **最終輸出用 `>> BITS`**（算術右移），注意這裡與中間的 `/` 不同
4. **Bias 直接加入累加器**，不需要額外處理
5. Layer 之間有 **ReLU** 激活：`output = max(0, input)`

### 資料檔案

| 檔案 | 內容 | 格式 |
|------|------|------|
| `x_test.txt` | 784 筆輸入像素 | 8 位 hex（32-bit signed int） |
| `y_test.txt` | 真實標籤 | 十進位（值 = 7） |
| `layer_0_weights_biases.txt` | 7840 weights + 10 biases = 7850 行 | 8 位 hex |
| `layer_1_weights_biases.txt` | 100 weights + 10 biases = 110 行 | 8 位 hex |

### 反量化注意事項（與 HW7 相同問題）

C 的 `/` 是**向零截斷**，SystemVerilog 的 `>>>` 是**向負無窮取整**。對負數結果會有差異：
- C: `-3 / 16384 = 0`
- SV: `-3 >>> 14 = -1`

需要使用與 HW7 `complex_mult.sv` 相同的優化技巧：
```
adjusted = (product < 0) ? (product + (QUANT_VAL - 1)) : product;
result   = adjusted >>> BITS;
```

---

## 需要建立的 SystemVerilog 模組

### 目錄結構

```
HW8/
├── neural_net/           # 提供的 C 參考與資料
│   ├── neural_net.c          # C 參考程式
│   ├── x_test.txt            # 784 筆輸入（hex）
│   ├── y_test.txt            # 真實標籤（7）
│   ├── layer_0_weights_biases.txt
│   ├── layer_1_weights_biases.txt
│   └── split_weights.py      # Weight 切分工具
├── imp/
│   ├── sv/               # RTL + Testbench（全部 Two-Process 風格）
│   │   ├── nn_pkg.sv         # Package（參數 + dequantize 函式）
│   │   ├── neuron.sv         # 單一 Neuron（MAC + dequantize）
│   │   ├── argmax.sv         # Argmax（找最大值 index）
│   │   ├── nn_top.sv         # 頂層（FIFO → L0 → L1 → Argmax）
│   │   ├── fifo.sv           # FIFO（從 HW7 複製）
│   │   └── nn_tb.sv          # Direct Testbench（含 cycle 計數）
│   ├── sim/              # 模擬
│   │   ├── Makefile          # Xcelium: make sim / make sim_gui
│   │   └── nn_sim.do         # ModelSim .do 腳本
│   ├── source/           # Per-neuron weight/bias 檔案（由 split_weights.py 產生）
│   │   ├── layer0_neuron{0-9}_weights.txt
│   │   ├── layer1_neuron{0-9}_weights.txt
│   │   ├── layer0_biases.txt
│   │   └── layer1_biases.txt
│   ├── syn/              # Synplify 合成
│   │   └── nn_top.prj        # Cyclone IV-E EP4CE115
│   └── uvm/              # UVM 驗證環境（後續建立）
```

---

## 各模組詳細設計

### 1. `nn_pkg.sv` — 參數 Package

```
- BITS = 14                     // Q14 量化位數
- QUANT_VAL = 1 << BITS         // 16384
- DATA_WIDTH = 32               // 資料寬度
- NUM_INPUTS = 784              // 輸入像素數
- NUM_OUTPUTS = 10              // 輸出類別數
- NUM_LAYERS = 2                // 層數
- LAYER_0_IN = 784, LAYER_0_OUT = 10
- LAYER_1_IN = 10,  LAYER_1_OUT = 10
- FIFO_DEPTH = 16               // FIFO 深度
- DEBUG = 0/1                    // 除錯模式
```

### 2. `neuron.sv` — 單一 Neuron

**介面：**
```
輸入：clk, reset, valid_in, input_data, start
輸出：valid_out, output_data, done
```

**功能：**
- 接收串流輸入（每 cycle 一個 input）
- 從 ROM 讀取對應的 weight
- MAC 運算：`acc += dequantize(input * weight)`
- 收到所有 input 後輸出 `acc >> BITS`
- Weight 和 bias 存在內部 ROM（用 `initial $readmemh` 載入或硬編碼）

**設計考量：**
- **串流架構**：每 cycle 接收一個 input，做一次 MAC
- 需要一個 counter 追蹤已處理的 input 數量
- 乘法結果為 64-bit（32×32），反量化後截回 32-bit
- 最終輸出再 `>>> BITS`

### 3. `layer.sv` — Dense Layer

**介面：**
```
輸入：clk, reset, valid_in, input_data, start
輸出：valid_out, output_data[NUM_OUTPUTS-1:0], done
```

**功能：**
- 實例化 `NUM_OUTPUTS` 個 neuron（例如 10 個）
- 所有 neuron **同時接收相同的 input**（broadcast）
- 每個 neuron 使用不同的 weight set
- 當所有 neuron 完成後，對所有輸出做 ReLU：`out = (out > 0) ? out : 0`
- done 信號表示該層所有輸出已就緒

**設計考量：**
- Layer 0：784 cycles 計算（一次 inference）
- Layer 1：10 cycles 計算
- 層間用暫存器或 FIFO 緩衝
- ReLU 為純組合邏輯（或加一級 pipeline）

### 4. `argmax.sv` — Argmax 模組

**介面：**
```
輸入：clk, reset, valid_in, scores[NUM_OUTPUTS-1:0]
輸出：valid_out, predicted_class[3:0], max_score
```

**功能：**
- 接收 10 個 class scores
- 找出最大值及其 index
- 輸出 predicted_class（0–9）

### 5. `nn_top.sv` — 頂層模組

**介面：**
```
輸入：clk, reset, wr_en, din[DATA_WIDTH-1:0]
輸出：rd_en, dout[3:0], inference_done, predicted_class[3:0]
       in_full, out_empty
```

**架構：**
```
Input FIFO → Layer 0 (784→10, ReLU) → Layer 1 (10→10, ReLU) → Argmax → Output
```

**控制邏輯：**
1. 從 input FIFO 讀取 784 筆資料，串流送入 Layer 0
2. Layer 0 完成後，將 10 筆輸出串流送入 Layer 1
3. Layer 1 完成後，將 10 筆輸出送入 Argmax
4. Argmax 輸出最終預測類別

### 6. `nn_tb.sv` — Direct Testbench

**功能：**
1. 用 `$readmemh` 讀取 `x_test.txt` 到 input array
2. 逐筆寫入 input FIFO
3. 等待 inference_done
4. 比較 `predicted_class` 與 `y_test.txt` 中的真實標籤
5. 印出 PASS/FAIL

---

## Weight/Bias 載入策略

### 方案：使用 `$readmemh` 從檔案載入到 ROM

每個 neuron 的 weight 從預先切分的檔案載入：
- Layer 0, Neuron j: weights[j*784 : (j+1)*784-1] 從 `layer_0_weights_biases.txt` 前 7840 行
- Layer 0, Bias j: 第 7840+j 行

**或者**：在 testbench 中用 `$readmemh` 載入整個檔案到大 array，neuron 在初始化時從 array 中取對應 slice。

**建議做法**：寫一個前處理腳本（或手動），將 weight 檔案切分為每個 neuron 獨立的檔案，方便 neuron 模組內部 `$readmemh` 載入。

---

## 反量化實現

與 HW7 相同的向零截斷邏輯：

```systemverilog
function automatic signed [DATA_WIDTH-1:0] dequantize;
    input signed [2*DATA_WIDTH-1:0] product;
    logic signed [2*DATA_WIDTH-1:0] adjusted;
    adjusted = (product < 0) ? (product + QUANT_VAL - 1) : product;
    dequantize = adjusted >>> BITS;
endfunction
```

---

## Coding Style

所有 RTL 模組使用 **Two-Process FSM** 風格：
- **Process 1** (`always_comb`)：計算 `_next` 信號（組合邏輯）
- **Process 2** (`always_ff`)：將 `_next` 寫入暫存器
- Output 用 `assign` 從暫存器驅動

所有 `$readmemh` 檔案路徑集中在模組頂部用 `localparam` 定義，方便管理。

---

## 模擬方式

### Xcelium（主要）
```bash
source /vol/ece303/genus_tutorial/cadence.env
cd imp/sim && make sim      # batch
cd imp/sim && make sim_gui  # 波形 GUI
```

### ModelSim（備用）
```bash
cd imp/sim && do nn_sim.do
```

---

## Direct Testbench 驗證結果

```
============================================
RESULTS
============================================
Predicted Class  : 7
True Label       : 7
Max Score        : 1 (0x00000001)
--------------------------------------------
DUT FSM Cycles   : 805  (pipelined MAC: +2 cycles)
  Layer 0 (MAC)  : ~786 cycles (784 MACs + 2 pipeline flush)
  Layer 1 (MAC)  : ~12 cycles (10 MACs + 2 pipeline flush)
Total Sim Cycles : 814 (from reset release)

*** TEST PASSED ***
============================================
```

| 指標 | 數值 |
|------|------|
| DUT FSM Cycles | 805（pipeline +2） |
| Layer 0 MAC | 786 cycles |
| Layer 1 MAC | 12 cycles |
| FSM Overhead | ~7 cycles (prefetch + start + wait + argmax + done) |
| Total Sim Cycles | 814 (含 FIFO 寫入） |
| @100MHz Inference | 8.05 µs |

---

## Synplify 合成結果（Cyclone IV-E EP4CE115）

> Synplify O-2018 不支援 `localparam string` 陣列。解法：展開 generate loop 為 20 個 explicit instance。

### 優化歷程

| Rev | F_max | Slack | Logic Levels | 改動 |
|-----|-------|-------|---------|------|
| 0（baseline） | 46.9 MHz | -3.199 ns | 83 | 原始：MAC 全組合邏輯 |
| 1 | 57.6 MHz | -2.605 ns | 74 | 2-stage pipeline MAC |
| 2 | 63.1 MHz | -2.378 ns | 50 | + iterative argmax |
| 3 | 64.5 MHz | -2.326 ns | 50 | + register FIFO output（nn_top） |
| **4** | **87.3 MHz** | **-1.718 ns** | **49** | **+ register weight ROM（3-stage pipeline）** |

**總提升：46.9 → 87.3 MHz（+86%）**

### DUT Cycle 分析（816 cycles）

| 階段 | State | Cycles | 說明 |
|------|-------|--------|------|
| FIFO 預取 | S_IDLE + S_FIFO_PREFETCH | 2 | rd_en → BRAM latency → fifo_dout_reg |
| Layer 0 啟動 | S_START_L0 | 1 | l0_start pulse + pre-fetch rd_en |
| Layer 0 MAC | S_RUN_L0 | 784 | 784 inputs × 1 cycle/input |
| L0 Pipeline flush | S_WAIT_L0 | 3 | Stage 0→1→2 + done_pending → valid_out |
| Layer 1 啟動 | S_START_L1 | 1 | l1_start pulse |
| Layer 1 MAC | S_RUN_L1 | 10 | 10 inputs × 1 cycle/input |
| L1 Pipeline flush | S_WAIT_L1 | 3 | 同上 |
| Argmax | S_ARGMAX + S_DONE | 11 | start(1) + 9 comparisons + output(1) |
| **總計** | | **~816** | 含 FSM 轉換 overhead |

> 原始設計（無 pipeline）：803 cycles。Pipeline 代價：+13 cycles（1.6%），換取 86% 頻率提升。

### Rev 4 Throughput

| 指標 | @87.3MHz (F_max) | @50MHz (conservative) |
|------|---------|---------| 
| Clock Period | 11.46 ns | 20 ns |
| Inference Time | 816 × 11.46ns = **9.35 µs** | 816 × 20ns = **16.32 µs** |
| Throughput | **107.0K inf/s** | **61.3K inf/s** |

### 已實施優化（共 4 項）

#### 1. 3-Stage Pipeline MAC（neuron.sv）

| Stage | 內容 | 隔離的延遲 |
|-------|------|------------|
| **Stage 0** | `weight_reg <= weights[cnt]`, `data_reg <= data_in` | Weight ROM BRAM (~4.1ns) |
| **Stage 1** | `product_reg <= data_reg * weight_reg` | DSP multiply + partial product carry chains |
| **Stage 2** | `acc <= acc + dequantize(product_reg)` | Dequantize + accumulate carry chain |

#### 2. Iterative Argmax（argmax.sv）
每 cycle 比較 1 個 score（原本 10-way 32-bit parallel → 74 LUT levels）

#### 3. Register FIFO Output（nn_top.sv）
`fifo_dout_reg` 隔離 FIFO BRAM 的 4.15ns clock-to-output delay

#### 4. Register Weight ROM Output（neuron.sv Stage 0）
`weight_reg` 隔離 weight ROM BRAM 的 4.11ns clock-to-output delay

### 當前瓶頸（Rev 4）

**Critical path = 純 32×32 乘法（49 級 LUT，11.46ns）：**

```
data_reg[0] (register, 0.85ns)
  → DSP 18×18 partial multiply (4.3ns)
  → carry chain 1: partial product combination (18 levels, 2.5ns)
  → carry chain 2: upper partial product add (28 levels, 4.5ns)
  → final mux (1.1ns)
  → product_reg[63]
```

**注意：** 起點已從 BRAM 變為一般 register（0.85ns vs 4.1ns），確認 BRAM 隔離成功。
剩餘延遲 ~11ns 是 32×32 乘法在 Cyclone IV 上的**架構硬限制**（需 4 個 18×18 DSP + LUT carry chains）。

### 進一步優化可能性

| 優化 | 預期效果 | 可行性 |
|------|---------|--------|
| 縮窄到 18-bit | ~140MHz+（fit 單一 DSP, 無 carry chain） | 需改量化方案，驗證 MNIST 精度 |
| Synplify retiming | 讓工具自動平衡 pipeline | 加 `set_option -retiming 1` |
| 更深 pipeline | 拆乘法 carry chain 為兩級 | 複雜度高，收益有限 |

---

## 建立順序（SV Sim 優先）

### Phase 1：RTL + Simulation ✅ 完成
- [x] `nn_pkg.sv` — Package（參數 + dequantize）
- [x] `neuron.sv` — Neuron（Two-Process, bias port, weight ROM）
- [x] `argmax.sv` — Argmax（Two-Process）
- [x] `nn_top.sv` — Top（Two-Process FSM, localparam 檔案路徑）
- [x] `fifo.sv` — 從 HW7 複製
- [x] `nn_tb.sv` — Direct TB（DUT cycle counter）
- [x] `Makefile` — Xcelium (`make sim`)
- [x] `nn_sim.do` — ModelSim 備用
- [x] `nn_top.prj` — Synplify PRJ（Cyclone IV-E）

### Phase 2：驗證 ✅ 完成
- [x] C 程式確認預測 class=7
- [x] TEST PASSED — Predicted=7, True=7, 816 DUT FSM cycles（3-stage pipeline）

### Phase 3：合成 ✅ 完成
- [x] 執行 Synplify 合成
- [x] 分析時序 / 面積 / DSP 使用
- [x] 時序優化（46.9 → 87.3 MHz，+86%）

### Phase 4：UVM ✅ 完成
- [x] UVM 驗證環境（12 files）
- [x] Functional coverage（prediction class coverage）
- [x] ModelSim .do files（nn_uvm_sim.do + nn_uvm_wave.do）

---

## UVM 驗證環境

### 架構

```
my_uvm_test
 └─ my_uvm_env
     ├─ my_uvm_agent
     │   ├─ uvm_sequencer ← my_uvm_sequence (讀 x_test.txt)
     │   ├─ my_uvm_driver (寫 784 pixels 進 FIFO)
     │   └─ my_uvm_monitor (偵測 inference_done + 量測 latency)
     └─ my_uvm_scoreboard (比較 predicted vs y_test.txt + coverage)
```

### 檔案列表（`imp/uvm/`）

| 檔案 | 功能 |
|------|------|
| `nn_if.sv` | Interface：wr_en, din, in_full, inference_done, predicted_class, max_score |
| `my_uvm_globals.sv` | Global params + 檔案路徑 |
| `my_uvm_transaction.sv` | Transaction：pixel_data[784] |
| `my_uvm_sequence.sv` | 從 x_test.txt 讀 784 hex values |
| `my_uvm_driver.sv` | 寫入 FIFO（active-high reset, backpressure 支援） |
| `my_uvm_monitor.sv` | 偵測 inference_done、量測 cycle latency |
| `my_uvm_scoreboard.sv` | 比較 predicted class vs y_test.txt、prediction covergroup |
| `my_uvm_agent.sv` | Agent：sequencer + driver + monitor |
| `my_uvm_env.sv` | Env：agent + scoreboard |
| `my_uvm_test.sv` | Test：啟動 sequence、等待推論完成 |
| `my_uvm_pkg.sv` | Package：`timescale 1ns/10ps` + include all |
| `my_uvm_tb.sv` | TB top：clock、reset、DUT instantiation |

### ModelSim .do files（`imp/sim/`）

- `nn_uvm_sim.do` — 編譯 RTL + UVM、自動偵測 GUI/batch mode
- `nn_uvm_wave.do` — Waveform groups：TOP, VIF, FSM, FIFO, L0, L0_N0_PIPE, L0_RESULT, L1, ARGMAX

### 執行方式

```bash
# ModelSim GUI
vsim -do nn_uvm_sim.do

# ModelSim batch
vsim -c -do nn_uvm_sim.do

# Xcelium
xrun -sv -access +rwc -timescale 1ns/1ps -64bit -uvm +incdir+../uvm \
  ../sv/nn_pkg.sv ../sv/fifo.sv ../sv/neuron.sv ../sv/argmax.sv ../sv/nn_top.sv \
  ../uvm/my_uvm_pkg.sv ../uvm/nn_if.sv ../uvm/my_uvm_tb.sv +UVM_TESTNAME=my_uvm_test
```

### Functional Coverage

- **Prediction class coverage（0–9）：** 10 bins for predicted and expected class
- **Correctness coverage：** pass/fail bins
- **Cross coverage：** predicted × expected

### UVM ModelSim 結果

```
[SCB] TEST PASSED! Predicted: 7, Expected: 7, Score: 1
[SCB] ALL 1 TESTS PASSED!
[SCB] Prediction Coverage: 17.8%
[SCB] Layer Activations Coverage: 100.0%

--- PERFORMANCE SUMMARY ---
First Write Cycle:    6
Inference Done Cycle: 824
Total Latency:        818 cycles
@100MHz Inference:    8.18 us
```

---

## 作業要求 vs 實作對照（hw8.pdf）

### ✅ 已完成

| 要求 | 狀態 | 說明 |
|------|------|------|
| 從 input FIFO 讀取 hex 資料 | ✅ | `fifo.sv` + `nn_top` FSM |
| 2 層 Dense Layer | ✅ | Layer 0 (784→10) + Layer 1 (10→10) |
| 輸出信號分類數字 0–9 | ✅ | `predicted_class[3:0]` |
| 參數化 Neuron 模組 | ✅ | `neuron.sv`（INPUT_SIZE, WEIGHT_FILE） |
| **Parameterized Layer module** | ✅ | **`layer.sv` 封裝 N 個 neurons + bias ROM + ReLU** |
| Argmax 模組 | ✅ | `argmax.sv`（NUM_CLASSES） |
| Fixed-point quantization | ✅ | Q14 format, dequantize function |
| Data width 參數化 | ✅ | `nn_pkg::DATA_WIDTH = 32` |
| NN size 參數化 | ✅ | `LAYER0_IN/OUT`, `LAYER1_IN/OUT` in `nn_pkg` |
| **FIFO depth: 16** | ✅ | **`FIFO_BUFFER_SIZE` 設為 16（UVM driver backpressure 支援）** |
| UVM 產生 input sequences | ✅ | `my_uvm_sequence` 讀 `x_test.txt` |
| UVM drive inputs + capture output | ✅ | driver → FIFO (`din`, `wr_en`), monitor → `inference_done` |
| 比較 software reference | ✅ | scoreboard vs `y_test.txt` |
| **Functional coverage per layer** | ✅ | **Scoreboard 中 `cg_layer_activations` (L0/L1 輸出 0 或大於 0)，達 100%** |
| **Feed inputs continuously** | ✅ | **`my_uvm_driver.sv` 利用 `for` 迴圈無縫連續寫入 784 筆資料，僅受 `in_full` backpressure 暫停（`while (vif.in_full) @(posedge vif.clock);`），符合 Streaming 架構** |
| 量測 throughput / latency | ✅ | monitor 報告：818 cycles, 8.18µs |
| sim.do script | ✅ | `nn_sim.do`, `nn_uvm_sim.do`, `nn_uvm_wave.do` |
| Synplify 合成 + 分析 | ✅ | 87.3MHz, DSP/LUT/BRAM 分析 |
| Worst path timing analysis | ✅ | Critical path 49 LUT levels, 11.46ns |

### ⚠️ 需注意

*(目前所有 hw8.pdf 作業要求皆已達成)*


