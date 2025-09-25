#include "shim.h"
#include <string.h>

void llc_backend_init(void) {
    llama_backend_init(false);
}

void llc_backend_free(void) {
    llama_backend_free();
}

llc_model * llc_load_model(const char * path, int32_t n_gpu_layers) {
    struct llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = n_gpu_layers;
    return (llc_model *) llama_load_model_from_file(path, mp);
}

void llc_free_model(llc_model * m) {
    if (m) llama_free_model((const struct llama_model *) m);
}

llc_context * llc_new_context(llc_model * m, int32_t n_ctx, int32_t n_threads) {
    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx = n_ctx;
    cp.n_threads = n_threads;
    return (llc_context *) llama_new_context_with_model((const struct llama_model *) m, cp);
}

void llc_free_context(llc_context * c) {
    if (c) llama_free((struct llama_context *) c);
}

int32_t llc_tokenize(llc_model * m, const char * text, bool add_bos, llc_token * out, int32_t max_tokens) {
    int32_t len = (int32_t) strlen(text);
    return llama_tokenize((const struct llama_model *) m, text, len, (llama_token *) out, max_tokens, add_bos, false);
}

int llc_eval(llc_context * c, const llc_token * tokens, int32_t n_tokens, int32_t n_past, int32_t n_threads) {
    return llama_eval((struct llama_context *) c, (const llama_token *) tokens, n_tokens, n_past, n_threads);
}

const float * llc_get_logits(llc_context * c) {
    return llama_get_logits((struct llama_context *) c);
}

int32_t llc_n_vocab(const llc_model * m) {
    return llama_n_vocab((const struct llama_model *) m);
}

int32_t llc_eos_token(const llc_model * m) {
    return (int32_t) llama_token_eos((const struct llama_model *) m);
}

int llc_token_to_piece(const llc_model * m, llc_token token, char * buf, int32_t buf_size) {
    // Convert token to text piece; return number of bytes written (excluding null)
    return llama_token_to_piece((const struct llama_model *) m, (llama_token) token, buf, buf_size, /*special*/ false);
}

