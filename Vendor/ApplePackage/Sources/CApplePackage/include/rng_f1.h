#ifndef SAP_RNG_F1_H
#define SAP_RNG_F1_H
#include <stdint.h>
#include <stddef.h>

/* This is the measured per-word-twist MT variant, not a standard MT stream. */
typedef struct { uint32_t words[624]; uint32_t cursor; } sap_rng_state;
void sap_rng_initialize(sap_rng_state *state, uint32_t mt_seed, uint32_t key_word3,
                        uint32_t key_word0, uint32_t seconds, uint32_t microseconds,
                        uint32_t pool[128]);
void sap_rng_setup(sap_rng_state *state, uint32_t seed, uint32_t address,
                   uint8_t *output, size_t count);
void sap_rng_exchange(sap_rng_state *state, uint32_t seed, uint32_t address,
                      uint8_t *output, size_t count);
uint32_t sap_rng_word(sap_rng_state *state);
void sap_rng_fill(sap_rng_state *state, uint32_t seed, uint32_t address,
                  const uint8_t table[256], uint8_t mask, uint8_t *output, size_t count);

/* Address arguments are explicit 32-bit salts from the target's virtual layout. */
void sap_rng_iv(sap_rng_state *state, uint32_t seed54, uint32_t virtual_output_address,
                uint8_t output[16]);
void sap_rng_f1_material(sap_rng_state *state, uint32_t seed30,
                        uint32_t virtual_first_material_address, uint8_t output[78]);
void sap_f1_from_material(const uint8_t material[78], uint8_t output[256]);
void sap_rng_f1(sap_rng_state *state, uint32_t seed30,
                uint32_t virtual_first_material_address, uint8_t output[256]);
#endif
