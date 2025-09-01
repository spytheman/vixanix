.PHONY: clean all vixanix wasm

all: vixanix wasm

clean:
	rm -rf vixanix vixanix.js vixanix.wasm

vixanix: vixanix.v wasm_embeds.v
	v -prod .

wasm: vixanix.v wasm_embeds.v
	v -prod -os wasm32_emscripten -o vixanix.js .
