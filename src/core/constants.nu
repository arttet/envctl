# ==============================================================================
# core/constants.nu — Project-wide default values.
#
# Single source of truth for all default paths and settings.
# Import selectively: use core/constants.nu [DEFAULT_ENVFILE DEFAULT_PATTERN]
# ==============================================================================

# Path to the main envctl config file
export const DEFAULT_CONFIG_PATH = ".envctl.toml"
# Path to the lock file — committed to git, tracks provider/backend versions
export const DEFAULT_LOCK_PATH = ".envctl.lock"
# Directory for generated runtime files — NOT committed to git
# Add to .gitignore: .envctl/
export const DEFAULT_BAK_DIR = ".envctl"
# Path to the local audit state file — NOT committed to git
export const DEFAULT_STATE_PATH = ".envctl/state.ndjson"
# Path to the generated .env file written by envfile generate
export const DEFAULT_ENVFILE = ".env"
# Path to the .env template file read by envfile generate
export const DEFAULT_PATTERN = ".env.example"
# Base directory for generated secret files
export const DEFAULT_SECRETS_DIR = "."
# Default stage when --stage is not provided
export const DEFAULT_STAGE = "dev"
# Directory containing TOML schema files
export const SCHEMAS_DIR = "schemas"
# Maximum passes for generator resolution loop — prevents infinite cycles
export const MAX_GENERATOR_PASSES = 10
# Current envctl version — single source of truth
export const ENVCTL_VERSION = "1.2.0-dev"
