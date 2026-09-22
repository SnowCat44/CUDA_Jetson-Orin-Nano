#ifndef PQCLEAN_MLDSA87_CLEAN_POLY_H
#define PQCLEAN_MLDSA87_CLEAN_POLY_H
#include "params.h"
#include <stdint.h>

typedef struct {
    int32_t coeffs[N];
} poly;

MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_reduce(poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_caddq(poly *a);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_add(poly *c, const poly *a, const poly *b);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_sub(poly *c, const poly *a, const poly *b);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_shiftl(poly *a);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_ntt(poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_invntt_tomont(poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_pointwise_montgomery(poly *c, const poly *a, const poly *b);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_power2round(poly *a1, poly *a0, const poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_decompose(poly *a1, poly *a0, const poly *a);
MLD_HD unsigned int PQCLEAN_MLDSA87_CLEAN_poly_make_hint(poly *h, const poly *a0, const poly *a1);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_use_hint(poly *b, const poly *a, const poly *h);

MLD_HD int PQCLEAN_MLDSA87_CLEAN_poly_chknorm(const poly *a, int32_t B);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_uniform(poly *a,
                                        const uint8_t seed[SEEDBYTES],
                                        uint16_t nonce);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_uniform_eta(poly *a,
        const uint8_t seed[CRHBYTES],
        uint16_t nonce);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_uniform_gamma1(poly *a,
        const uint8_t seed[CRHBYTES],
        uint16_t nonce);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_poly_challenge(poly *c, const uint8_t seed[CTILDEBYTES]);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyeta_pack(uint8_t *r, const poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyeta_unpack(poly *r, const uint8_t *a);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyt1_pack(uint8_t *r, const poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyt1_unpack(poly *r, const uint8_t *a);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyt0_pack(uint8_t *r, const poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyt0_unpack(poly *r, const uint8_t *a);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyz_pack(uint8_t *r, const poly *a);
MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyz_unpack(poly *r, const uint8_t *a);

MLD_HD void PQCLEAN_MLDSA87_CLEAN_polyw1_pack(uint8_t *r, const poly *a);

#endif
