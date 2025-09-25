#pragma once

// This shim header exposes the llama.cpp C API header to Swift via a
// system module and declares stable wrapper functions used from Swift.
// Ensure the include path for llama.h is visible to the compiler (Homebrew or custom).

#include <stdbool.h>
#include <stdint.h>
#include <llama.h>

// Opaque aliases for Swift
typedef struct llama_model   llc_model;
typedef struct llama_context llc_context;
typedef llama_token          llc_token;

#ifdef __cplusplus
extern "C" {
#endif

// Backend lifecycle
void        llc_backend_init(void);
void        llc_backend_free(void);

// Model/context lifecycle
llc_model * llc_load_model(const char * path, int32_t n_gpu_layers);
void        llc_free_model(llc_model * m);
llc_context*llc_new_context(llc_model * m, int32_t n_ctx, int32_t n_threads);
void        llc_free_context(llc_context * c);

// Tokenization and inference (eval)
// If out == NULL or max_tokens <= 0, returns the number of tokens required.
int32_t     llc_tokenize(llc_model * m, const char * text, bool add_bos, llc_token * out, int32_t max_tokens);
int         llc_eval(llc_context * c, const llc_token * tokens, int32_t n_tokens, int32_t n_past, int32_t n_threads);
const float*llc_get_logits(llc_context * c);

// Vocabulary helpers
int32_t     llc_n_vocab(const llc_model * m);
int32_t     llc_eos_token(const llc_model * m);
int         llc_token_to_piece(const llc_model * m, llc_token token, char * buf, int32_t buf_size);

#ifdef __cplusplus
}
#endif
