# 用法: make | make wave | make clean
RTL := rtl/attention_ip.v
TB  := tb/tb_attention_smoke.v

.PHONY: all sim wave lint clean

all: sim

build:
	mkdir -p build

build/tb_attention_smoke.vvp: $(TB) $(RTL) | build
	iverilog -g2005 -Wall -o $@ $^

sim: build/tb_attention_smoke.vvp
	vvp -n $<

wave: sim
	gtkwave build/out.vcd &

lint:
	verilator --lint-only -Wall --top-module attention_ip $(RTL)

clean:
	rm -rf build
