// sim_frame.cpp - "virtual monitor" for Verilator.
//
// Clocks the whole design (game_top) and watches ONLY the VGA pins, exactly
// like a real monitor would:
//   - finds the hsync / vsync pulses and measures their period and width
//   - takes the visible window at the standard offset after each sync pulse
//   - checks that everything outside the window is black
//   - checks that every 32x32 tile is a single colour (catches pipeline
//     misalignment: if colour and sync were off by N clocks, tile edges
//     would land at x%32 == N and tiles would not be uniform)
//   - writes one full frame to a PPM image
//
// Usage: sim_frame out.ppm [grid]     (pass "grid" if drawcon GRID=1)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vsim_top.h"
#include "verilated.h"

static int errors = 0;
#define CHECK(cond, ...)                                            \
  do {                                                              \
    if (!(cond)) {                                                  \
      if (++errors <= 10) { std::printf("ERROR: " __VA_ARGS__); std::printf("\n"); } \
    }                                                               \
  } while (0)

int main(int argc, char** argv) {
  const char* out = argc > 1 ? argv[1] : "frame.ppm";
  const bool grid = argc > 2 && std::strcmp(argv[2], "grid") == 0;

  VerilatedContext ctx;
  Vsim_top top{&ctx};

  auto tick = [&]() {
    top.clk = 0; top.eval();
    top.clk = 1; top.eval();
  };

  top.rst_n = 0;
  for (int i = 0; i < 10; i++) tick();
  top.rst_n = 1;
  top.eval();

  const int HS = top.p_h_sync, HBP = top.p_h_bp, HA = top.p_h_active, HT = top.p_h_total;
  const int VS = top.p_v_sync, VBP = top.p_v_bp, VA = top.p_v_active, VT = top.p_v_total;
  const int HPOL = top.p_h_pol, VPOL = top.p_v_pol;
  std::printf("mode %dx%d, total %dx%d, hsync %d (pol %d), vsync %d lines (pol %d)\n",
              HA, VA, HT, VT, HS, HPOL, VS, VPOL);

  std::vector<unsigned char> img(size_t(HA) * VA * 3, 0);
  long cyc = 0, last_hs = -1, last_vs = -1, hs_w = 0, vs_w = 0;
  int hpos = 0, line = 0, frames_seen = 0, nonblack_blank = 0;
  int prev_hs = !HPOL, prev_vs = !VPOL;
  const long max_cycles = long(HT) * VT * 4 + 100000;

  while (frames_seen < 2 && cyc < max_cycles) {
    tick();
    cyc++;
    const int hs = top.hs, vs = top.vs;

    // ---- sync measurements -------------------------------------------------
    const bool hs_lead = (hs == HPOL && prev_hs != HPOL);
    const bool vs_lead = (vs == VPOL && prev_vs != VPOL);
    if (hs == HPOL) hs_w++;
    if (hs != HPOL && prev_hs == HPOL) { CHECK(hs_w == HS, "hsync width %ld != %d", hs_w, HS); hs_w = 0; }
    if (vs == VPOL) vs_w++;
    if (vs != VPOL && prev_vs == VPOL) { CHECK(vs_w == long(VS) * HT, "vsync width %ld != %d", vs_w, VS * HT); vs_w = 0; }
    if (hs_lead) {
      if (last_hs >= 0) CHECK(cyc - last_hs == HT, "hsync period %ld != %d", cyc - last_hs, HT);
      last_hs = cyc; hpos = 0; line++;
    }
    if (vs_lead) {
      if (last_vs >= 0) CHECK(cyc - last_vs == long(HT) * VT, "frame period %ld != %d", cyc - last_vs, HT * VT);
      last_vs = cyc; line = 0;
      frames_seen++;           // frame 1 starts here; frame 2 start = done
      if (frames_seen == 2) break;
    }
    prev_hs = hs; prev_vs = vs;

    // ---- pixels (only during the frame after the first vsync) ---------------
    if (frames_seen == 1) {
      const int px = hpos - (HS + HBP);
      const int py = line - (VS + VBP);
      const bool visible = px >= 0 && px < HA && py >= 0 && py < VA;
      if (visible) {
        unsigned char* p = &img[(size_t(py) * HA + px) * 3];
        p[0] = top.r * 17; p[1] = top.g * 17; p[2] = top.b * 17;
      } else if (top.r | top.g | top.b) {
        nonblack_blank++;
      }
    }
    hpos++;
  }

  CHECK(frames_seen == 2, "did not see 2 vsync pulses in %ld cycles", cyc);
  CHECK(nonblack_blank == 0, "%d non-black pixels during blanking", nonblack_blank);

  // ---- every 32x32 tile must be one colour ------------------------------------
  int bad_tiles = 0;
  for (int ty = 0; ty < VA / 32; ty++)
    for (int tx = 0; tx < HA / 32; tx++) {
      // reference = pixel (1,1) inside the tile (row/col 0 may be a grid line)
      const unsigned char* ref = &img[(size_t(ty * 32 + 1) * HA + tx * 32 + 1) * 3];
      for (int y = 0; y < 32; y++)
        for (int x = 0; x < 32; x++) {
          if (grid && (x == 0 || y == 0)) continue;
          const unsigned char* p = &img[(size_t(ty * 32 + y) * HA + tx * 32 + x) * 3];
          if (std::memcmp(p, ref, 3) != 0) { bad_tiles++; goto next_tile; }
        }
    next_tile:;
    }
  CHECK(bad_tiles == 0, "%d tiles are not a single colour (pipeline misaligned?)", bad_tiles);

  FILE* f = std::fopen(out, "wb");
  if (!f) { std::perror(out); return 2; }
  std::fprintf(f, "P6\n%d %d\n255\n", HA, VA);
  std::fwrite(img.data(), 1, img.size(), f);
  std::fclose(f);

  std::printf("simulated %ld clocks, wrote %s\n", cyc, out);
  if (errors) { std::printf("FAIL: %d errors\n", errors); return 1; }
  std::printf("PASS: sync timing, blanking and tile alignment OK\n");
  return 0;
}
