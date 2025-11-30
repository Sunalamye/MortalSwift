// libriichi FFI Header for Swift/C Integration
// Auto-generated - Do not edit manually

#ifndef LIBRIICHI_H
#define LIBRIICHI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define RIICHI_MAX_VERSION 4
#define RIICHI_ACTION_SPACE 46
#define RIICHI_OBS_CHANNELS_V4 1012
#define RIICHI_OBS_WIDTH 34

/**
 * Result codes for FFI functions
 */
typedef enum {
    /// Success, action required (obs/mask are valid)
    RIICHI_ACTION_REQUIRED = 0,
    /// Success, no action required
    RIICHI_NO_ACTION = 1,
    /// Error occurred
    RIICHI_ERROR = -1,
} RiichiResult;

/**
 * Opaque handle to a RiichiBot instance
 */
typedef struct RiichiBot RiichiBot;

/**
 * Create a new RiichiBot instance
 *
 * @param player_id Player seat (0-3)
 * @param version Model version (1-4, typically 4)
 * @return Pointer to RiichiBot, or NULL on error
 */
RiichiBot* riichi_bot_new(uint8_t player_id, uint32_t version);

/**
 * Free a RiichiBot instance
 *
 * @param bot Bot instance to free
 */
void riichi_bot_free(RiichiBot* bot);

/**
 * Get observation tensor shape for a model version
 *
 * @param version Model version (1-4)
 * @param channels Output: number of channels (e.g., 1012 for v4)
 * @param width Output: width (always 34)
 */
void riichi_obs_shape(uint32_t version, size_t* channels, size_t* width);

/**
 * Get action space size (always 46)
 *
 * @return Action space size
 */
size_t riichi_action_space(void);

/**
 * Update bot state with an MJAI event and get observation/mask if action needed
 *
 * @param bot Bot instance
 * @param mjai_json MJAI event as JSON string (null-terminated)
 * @param obs_out Output buffer for observation tensor (must be channels*34 floats)
 * @param mask_out Output buffer for action mask (must be 46 bytes, 0 or 1)
 * @return RIICHI_ACTION_REQUIRED (0) if action needed, RIICHI_NO_ACTION (1) if not, RIICHI_ERROR (-1) on error
 */
RiichiResult riichi_bot_update(
    RiichiBot* bot,
    const char* mjai_json,
    float* obs_out,
    uint8_t* mask_out
);

/**
 * Convert an action index to an MJAI response JSON
 *
 * @param bot Bot instance
 * @param action_idx Action index (0-45)
 * @return JSON string (caller must free with riichi_string_free), or NULL on error
 */
char* riichi_bot_get_action(RiichiBot* bot, size_t action_idx);

/**
 * Free a string returned by FFI functions
 *
 * @param s String to free
 */
void riichi_string_free(char* s);

/**
 * Get the last action candidates as JSON (for debugging)
 *
 * @param bot Bot instance
 * @return JSON string with available actions (caller must free with riichi_string_free)
 */
char* riichi_bot_get_candidates(const RiichiBot* bot);

#ifdef __cplusplus
}
#endif

#endif /* LIBRIICHI_H */
