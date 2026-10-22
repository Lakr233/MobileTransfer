#include "rng_f1.h"
#include <string.h>
#include "algorithm_tables.inc"
#include "setup_tables.inc"

uint32_t sap_rng_word(sap_rng_state *s) {
    for (unsigned i=0;i<624;i++) {
        uint32_t y=(s->words[i]&0x80000000u)|(s->words[(i+1)%624]&0x7fffffffu);
        s->words[i]=s->words[(i+397)%624]^(y>>1)^((y&1)?0x9908b0dfu:0u);
    }
    if (s->cursor>=624) s->cursor=0;
    uint32_t y=s->words[s->cursor++];
    y^=y>>11; y^=(y<<7)&0x9d2c5680u; y^=(y<<15)&0xefc60000u; y^=y>>18;
    return y;
}

void sap_rng_fill(sap_rng_state *s,uint32_t seed,uint32_t address,
                  const uint8_t table[256],uint8_t mask,uint8_t *output,size_t n) {
    size_t remain=n;
    while (remain) {
        uint32_t word=sap_rng_word(s);
        for (unsigned shift=0;shift<32 && remain;shift+=8) {
            uint32_t h=(seed^(address+(uint32_t)remain-1))&0x7fffffffu;
            h*=0x84edb2ebu; h^=h>>16; h*=0x84edb2ebu;
            uint8_t value=(uint8_t)((word>>shift)^h^table[h>>24]^mask);
            output[remain-1]=value;
            if (value) --remain;
        }
    }
}

void sap_rng_iv(sap_rng_state *s,uint32_t seed,uint32_t address,uint8_t output[16]) {
    sap_rng_fill(s,seed,address,IV_WHITEN,0x12,output,16);
}

void sap_rng_f1_material(sap_rng_state *s,uint32_t seed,uint32_t address,uint8_t output[78]) {
    sap_rng_fill(s,seed,address,F1_WHITEN,0x27,output,60);
    sap_rng_fill(s,seed,address+0xaau,F1_WHITEN,0x27,output+60,18);
}

static void round_g(const uint8_t high[64],uint8_t output[64]) {
    uint8_t a[80];
    memcpy(a,high,64); memcpy(a+64,F1_RC,16);
    for (unsigned i=0;i<80;i++) a[i]=(uint8_t)((a[i]^0x2d)+i);
    for (unsigned i=0;i<80;i++) a[i]=(uint8_t)(F1_G[0][a[i]]+0x25+i);
    static const uint8_t constants[4]={0x5d,0xae,0xff,0x50};
    for (unsigned r=0;r<4;r++) for (unsigned i=0;i<80;i++)
        a[i]^=(uint8_t)(constants[r]+i+F1_G[1][a[(i+75)%80]]+F1_G[2][a[(i+55)%80]]);
    for (unsigned i=0;i<80;i++) a[i]=(uint8_t)(F1_G[3][a[i]]+0xc4+i);
    memcpy(output,a,64);
}

void sap_f1_from_material(const uint8_t material[78],uint8_t output[256]) {
    uint8_t pre[256]; memcpy(pre,F1_TEMPLATE,256);
    memcpy(pre+68,material,60); memcpy(pre+238,material+60,18);
    for (unsigned half=0;half<2;half++) {
        uint8_t low[64],high[64],g[64];
        memcpy(low,pre+half*128,64); memcpy(high,pre+half*128+64,64);
        for (unsigned round=0;round<7;round++) {
            round_g(high,g);
            for (unsigned i=0;i<64;i++) { uint8_t old=low[i];low[i]=high[i];high[i]=old^g[i]; }
        }
        for (unsigned i=0;i<64;i++) { output[half*128+i]=low[i]^0x2d; output[half*128+64+i]=high[i]^0x2d; }
    }
}

void sap_rng_f1(sap_rng_state *s,uint32_t seed,uint32_t address,uint8_t output[256]) {
    uint8_t material[78]; sap_rng_f1_material(s,seed,address,material); sap_f1_from_material(material,output);
}

void sap_rng_initialize(sap_rng_state *s, uint32_t mt_seed, uint32_t key_word3,
                        uint32_t key_word0, uint32_t seconds, uint32_t microseconds,
                        uint32_t pool[128]) {
    uint32_t keys[4] = {key_word0, microseconds, seconds, key_word3};
    s->words[0] = mt_seed;
    for (unsigned i = 1; i < 624; i++) {
        uint32_t previous = s->words[i - 1];
        s->words[i] = 1812433253u * (previous ^ (previous >> 30)) + i;
    }
    unsigned i = 1, j = 0;
    for (unsigned k = 0; k < 624; k++) {
        uint32_t previous = s->words[i - 1];
        s->words[i] = (s->words[i] ^ ((previous ^ (previous >> 30)) * 1664525u)) + keys[j] + j;
        if (++i == 624) { s->words[0] = s->words[623]; i = 1; }
        if (++j == 4) { keys[0] ^= 0x200u; j = 0; }
        else { keys[j] ^= 0x201u; }
    }
    for (unsigned k = 0; k < 623; k++) {
        uint32_t previous = s->words[i - 1];
        s->words[i] = (s->words[i] ^ ((previous ^ (previous >> 30)) * 1566083941u)) - i;
        if (++i == 624) { s->words[0] = s->words[623]; i = 1; }
    }
    s->words[0] = 0x80000000u;
    s->cursor = 0;
    for (unsigned k = 0; k < 128; k++) pool[k] = sap_rng_word(s);
    for (unsigned k = 0; k < 64; k += 4) pool[k] |= ~pool[pool[k] & 62] << 16;
    /* Zero-byte retries advance the stream; this cannot be replaced by a fixed skip. */
    uint8_t auxiliary[1024];
    sap_rng_fill(s, pool[0x30 / 4], 0x7ff9b0u, INITIALIZE_WHITEN, 0x35, auxiliary, sizeof(auxiliary));
}

void sap_rng_setup(sap_rng_state *s, uint32_t seed, uint32_t address, uint8_t *output, size_t count) {
    sap_rng_fill(s, seed, address, IV_WHITEN, 0x12, output, count);
}

void sap_rng_exchange(sap_rng_state *s, uint32_t seed, uint32_t address, uint8_t *output, size_t count) {
    sap_rng_fill(s, seed, address, EXCHANGE_WHITEN, 0x4b, output, count);
}
