// ABI adapter between Verity 0.3.2 and pinned ProveKit 4e011438.
// All proving is performed by the real upstream pk_prove_inputs implementation.
// The upstream API replaced pk_prove_json with a format-discriminated call.
#include <stdint.h>
#include <stddef.h>

#if MATE_NATIVE_PROOFS

typedef struct PKProver PKProver;
typedef struct {
    uint8_t *ptr;
    uintptr_t len;
    uintptr_t cap;
} PKBuf;
typedef enum { PK_INPUT_JSON = 0, PK_INPUT_TOML = 1 } PKInputFormat;

extern int pk_prove_inputs(const PKProver *prover, const char *inputs,
                           PKInputFormat format, PKBuf *out_proof);
int pk_prove_json(const PKProver *prover, const char *inputs, PKBuf *out_proof) {
    return pk_prove_inputs(prover, inputs, PK_INPUT_JSON, out_proof);
}
#endif
