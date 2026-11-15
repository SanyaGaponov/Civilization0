// Virtual monitor: checks the VGA output and saves one frame.
// Usage: sim_frame out.ppm [KEYS]   (C U D L R = buttons to press first)
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
  const char* out  = argc > 1 ? argv[1] : "frame.ppm";
  const char* keys = argc > 2 ? argv[2] : "";

  VerilatedContext ctx;
  Vsim_top top{&ctx};

  auto tick = [&]() {
    top.clk = 0; top.eval();
    top.clk = 1; top.eval();
  };

  top.btn = 0;
  top.rst_n = 0;
  for (int i = 0; i < 10; i++) tick();
  top.rst_n = 1;
  for (int i = 0; i < 10; i++) tick();

  // Press the buttons in KEYS, one after another
  for (const char* k = keys; *k; k++) {
    int bit = -1;
    switch (*k) {
      case 'C': bit = 0; break;  case 'U': bit = 1; break;  case 'D': bit = 2; break;
      case 'L': bit = 3; break;  case 'R': bit = 4; break;
      default: std::printf("ignoring unknown key '%c'\n", *k); continue;
    }
    top.btn = 1u << bit;                   // hold longer than one button look (2^20 clocks)
    for (int i = 0; i < (1 << 20) + 16; i++) tick();
    top.btn = 0;                           // release
    for (int i = 0; i < (1 << 20) + 16; i++) tick();
  }
  if (*keys) std::printf("pressed keys: %s\n", keys);

  const int HS = top.p_h_sync, HBP = top.p_h_bp, HA = top.p_h_active, HT = top.p_h_total;
  const int VS = top.p_v_sync, VBP = top.p_v_bp, VA = top.p_v_active, VT = top.p_v_total;
  const int HPOL = top.p_h_pol, VPOL = top.p_v_pol;
  const unsigned tcol[6] = {top.p_tcol0, top.p_tcol1, top.p_tcol2, top.p_tcol3, top.p_tcol4, top.p_tcol5};
  const unsigned pcol[2] = {top.p_pcol0, top.p_pcol1};
  std::printf("mode %dx%d, total %dx%d, hsync %d (pol %d), vsync %d lines (pol %d)\n",
              HA, VA, HT, VT, HS, HPOL, VS, VPOL);

  std::vector<unsigned> img(size_t(HA) * VA, 0);   // 12-bit colours
  long cyc = 0, last_hs = -1, last_vs = -1, hs_w = 0, vs_w = 0;
  int hpos = 0, line = 0, frames_seen = 0, nonblack_blank = 0;
  // Measure only sync pulses whose start we saw
  int prev_hs = top.hs, prev_vs = top.vs;
  bool hs_started = false, vs_started = false;
  const long max_cycles = long(HT) * VT * 4 + 100000;

  while (frames_seen < 2 && cyc < max_cycles) {
    tick();
    cyc++;
    const int hs = top.hs, vs = top.vs;

    // Sync timing
    const bool hs_lead = (hs == HPOL && prev_hs != HPOL);
    const bool vs_lead = (vs == VPOL && prev_vs != VPOL);
    if (hs_lead) hs_started = true;
    if (vs_lead) vs_started = true;
    if (hs == HPOL) hs_w++;
    if (hs != HPOL && prev_hs == HPOL) {
      if (hs_started) CHECK(hs_w == HS, "hsync width %ld != %d", hs_w, HS);
      hs_w = 0;
    }
    if (vs == VPOL) vs_w++;
    if (vs != VPOL && prev_vs == VPOL) {
      if (vs_started) CHECK(vs_w == long(VS) * HT, "vsync width %ld != %d", vs_w, VS * HT);
      vs_w = 0;
    }
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

    // Pixels of the frame after the first vsync
    if (frames_seen == 1) {
      const int px = hpos - (HS + HBP);
      const int py = line - (VS + VBP);
      const unsigned c = (unsigned(top.r) << 8) | (unsigned(top.g) << 4) | top.b;
      if (px >= 0 && px < HA && py >= 0 && py < VA) img[size_t(py) * HA + px] = c;
      else if (c) nonblack_blank++;
    }
    hpos++;
  }

  CHECK(frames_seen == 2, "did not see 2 vsync pulses in %ld cycles", cyc);
  CHECK(nonblack_blank == 0, "%d non-black pixels during blanking", nonblack_blank);

  // Outside the map: black
  const int ML = top.p_map_left, MT = top.p_map_top, MW = top.p_play_w, MH = top.p_play_h;
  int bad_border = 0;
  for (int y = 0; y < VA; y++)
    for (int x = 0; x < HA; x++)
      if ((x < ML || x >= ML + MW * 32 || y < MT || y >= MT + MH * 32) && img[size_t(y) * HA + x])
        bad_border++;
  CHECK(bad_border == 0, "%d non-black pixels around the map", bad_border);

  // Each tile shows one terrain colour
  auto is_terrain = [&](unsigned c) { for (unsigned t : tcol) if (c == t) return true; return false; };
  int bad_tiles = 0;
  for (int ty = 0; ty < MH; ty++)
    for (int tx = 0; tx < MW; tx++) {
      unsigned ref = ~0u;
      bool bad = false;
      for (int y = 0; y < 32 && !bad; y++)
        for (int x = 0; x < 32; x++) {
          const unsigned c = img[size_t(MT + ty * 32 + y) * HA + ML + tx * 32 + x];
          if (!is_terrain(c)) continue;          // city / unit / cursor pixel
          if (ref == ~0u) ref = c;
          else if (c != ref) { bad = true; break; }
        }
      if (bad) bad_tiles++;
    }
  CHECK(bad_tiles == 0, "%d tiles mix two terrain colours (pipeline misaligned?)", bad_tiles);

  // Both players' colours are on screen
  for (int p = 0; p < 2; p++) {
    long n = 0;
    for (unsigned c : img) n += (c == pcol[p]);
    CHECK(n > 0, "no pixels in Player %d's colour (city/unit missing)", p + 1);
  }

  FILE* f = std::fopen(out, "wb");
  if (!f) { std::perror(out); return 2; }
  std::fprintf(f, "P6\n%d %d\n255\n", HA, VA);
  for (unsigned c : img) {
    const unsigned char rgb[3] = {(unsigned char)(((c >> 8) & 15) * 17),
                                  (unsigned char)(((c >> 4) & 15) * 17),
                                  (unsigned char)((c & 15) * 17)};
    std::fwrite(rgb, 1, 3, f);
  }
  std::fclose(f);

  std::printf("simulated %ld clocks, wrote %s\n", cyc, out);
  if (errors) { std::printf("FAIL: %d errors\n", errors); return 1; }
  std::printf("PASS: sync timing, blanking, black border, tile alignment, both players drawn\n");
  return 0;
}
