#!/usr/bin/env python3
"""
Split layer weight/bias files into per-neuron weight files and bias header.
Usage: python3 split_weights.py
Run from the neural_net/ directory.
"""
import os

def split_layer(layer_file, input_size, output_size, layer_idx, out_dir):
    """Read weights and biases, split into per-neuron files."""
    with open(layer_file, 'r') as f:
        lines = [l.strip() for l in f if l.strip()]
    
    expected = input_size * output_size + output_size
    assert len(lines) == expected, f"Expected {expected} lines, got {len(lines)}"
    
    # Weights: first input_size*output_size lines
    # Layout: neuron j uses weights[j*input_size : (j+1)*input_size]
    weights = lines[:input_size * output_size]
    biases  = lines[input_size * output_size:]
    
    os.makedirs(out_dir, exist_ok=True)
    
    for j in range(output_size):
        w_file = os.path.join(out_dir, f"layer{layer_idx}_neuron{j}_weights.txt")
        with open(w_file, 'w') as f:
            for i in range(input_size):
                f.write(weights[j * input_size + i] + '\n')
        print(f"  Written {w_file} ({input_size} weights)")
    
    # Write biases
    b_file = os.path.join(out_dir, f"layer{layer_idx}_biases.txt")
    with open(b_file, 'w') as f:
        for b in biases:
            f.write(b + '\n')
    print(f"  Written {b_file} ({output_size} biases)")
    
    # Print bias values for hardcoding in SV
    print(f"  Layer {layer_idx} biases (for SV):")
    for j, b in enumerate(biases):
        val = int(b, 16)
        if val >= 0x80000000:
            val -= 0x100000000
        print(f"    Neuron {j}: 32'h{b} ({val})")

if __name__ == '__main__':
    src_dir = '.'
    out_dir = '../imp/source'
    
    print("Splitting Layer 0 (784 inputs x 10 outputs):")
    split_layer(os.path.join(src_dir, 'layer_0_weights_biases.txt'),
                784, 10, 0, out_dir)
    
    print("\nSplitting Layer 1 (10 inputs x 10 outputs):")
    split_layer(os.path.join(src_dir, 'layer_1_weights_biases.txt'),
                10, 10, 1, out_dir)
    
    print("\nDone!")
