CXX     := g++
CXXFLAGS := -O2 -Wall -Wno-narrowing -I src

SRC_DIR  := src
TEST_DIR := test

# Source files
SRC_COMMON := $(SRC_DIR)/fm_radio.cpp
SRC_AUDIO  := $(SRC_DIR)/audio.cpp
SRC_MAIN   := $(SRC_DIR)/main.cpp
SRC_GOLDEN := $(SRC_DIR)/main_golden.cpp

# Targets
TARGET        := fm_radio
TARGET_GOLDEN := fm_golden

INPUT_DAT := $(TEST_DIR)/usrp.dat

# -------------------------------------------------------
.PHONY: all golden clean run

all: $(TARGET) $(TARGET_GOLDEN)

# Original fm_radio binary (plays audio to /dev/dsp)
$(TARGET): $(SRC_COMMON) $(SRC_AUDIO) $(SRC_MAIN)
	$(CXX) $(CXXFLAGS) $^ -o $@
	@echo "Built: $(TARGET)"

# Golden reference generator (no audio dependency)
$(TARGET_GOLDEN): $(SRC_COMMON) $(SRC_GOLDEN)
	$(CXX) $(CXXFLAGS) $^ -o $@
	@echo "Built: $(TARGET_GOLDEN)"

# Run golden generator → dumps all signals into test/
golden: $(TARGET_GOLDEN)
	@echo "=== Running golden reference generator ==="
	./$(TARGET_GOLDEN) $(INPUT_DAT) $(TEST_DIR)
	@echo ""
	@echo "=== Files generated in $(TEST_DIR)/ ==="
	@ls -lh $(TEST_DIR)/*.txt 2>/dev/null || echo "  (none)"

# Run original fm_radio (requires /dev/dsp)
run: $(TARGET)
	./$(TARGET) $(INPUT_DAT)

clean:
	rm -f $(TARGET) $(TARGET_GOLDEN)
	@echo "Cleaned binaries."

clean-golden:
	rm -f $(TEST_DIR)/*.txt
	@echo "Cleaned golden reference files."
