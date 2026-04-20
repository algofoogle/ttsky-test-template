#include <verilated.h>
#include "Vsynth.h"

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    // Verilated::traceEverOn(true);
    // Defaults
    double sim_seconds = 2.0;
    std::string out_path = "dac_output.bin";

    if (argc >= 2) {
        sim_seconds = std::atof(argv[1]);
    }
    if (argc >= 3) {
        out_path = argv[2];
    }

    const uint64_t clk_hz = 25175000ULL;
    const uint64_t sample_div = 500ULL;
    const uint64_t total_clocks =
        static_cast<uint64_t>(sim_seconds * static_cast<double>(clk_hz));

    Vsynth top;

    std::cout << total_clocks << " total clocks to simulate\n";

    std::ofstream ofs(out_path, std::ios::binary);
    if (!ofs) {
        std::cerr << "ERROR: Could not open output file: " << out_path << "\n";
        return 1;
    }
    // Reset for a few cycles
    top.clk = 0;
    top.reset = 1;
    for (int i = 0; i < 8; ++i) {
        top.clk = 0;
        top.eval();
        top.clk = 1;
        top.eval();
    }
    top.reset = 0;

    for (uint64_t i = 0; i < total_clocks; ++i) {
        // Rising edge
        top.clk = 0;
        top.eval();

        top.clk = 1;
        top.eval();

        if (i % 500 == 0) {
            // Time to write a raw sample.
            ofs.put(static_cast<uint8_t>(top.sample));
        }
    }

    ofs.close();

    std::cerr << "Done.\n";
    return 0;
}
