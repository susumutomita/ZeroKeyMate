// SPDX-License-Identifier: Apache-2.0
#ifndef MATE_AGE_H
#define MATE_AGE_H
#include <stddef.h>
#include <stdint.h>
// The caller supplies pinned PUBLIC setup-file paths and a bounded private JSON
// buffer in memory. No private-input files, logs, network or wallet operations.
// On success, out contains 384 proof bytes followed by 8 big-endian uint256s.
// Call on a background worker. Cancellation discards the result after proving;
// the current backend does not support interrupting an in-progress proof.
// Status: 0 success; 1 input; 2 parameters; 3 ABI; 4 proof; 5 verification;
// 6 encoding; 7 internal panic; 8 busy. Messages never contain private values.
int32_t mate_age_prove(const char *prover_path, const char *verifier_path,
    const uint8_t *input, size_t input_len, uint8_t *out, size_t out_len);
#endif
