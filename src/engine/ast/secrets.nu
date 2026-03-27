# ==============================================================================
# engine/secrets_ast.nu — Secrets AST projection.
#
# Extracts secrets-relevant subtree from the full AST.
# Not a parser — input is already a parsed AST from engine/parser.nu.
#
# Secrets pipeline needs:
#   - secrets     (all declared secret nodes)
#   - generators  (needed to resolve secret paths: {{ GIT_ROOT_DIR }}/secrets/...)
#   - providers   (all enabled)
#
# Does NOT include envfile node — secrets pipeline never touches .env.example.
# Pure — no side effects.
# ==============================================================================

use ../queries.nu

# Project full AST → secrets-relevant subtree.
@example "Project secrets ast from empty ast" { project { generators: [] secrets: [] envfile: { file: .env, pattern: .env.example, excluded: [] } providers: {} cfg: {} } }
export def project [ast: record] {
    {
        secrets: (queries secrets $ast)
        generators: (queries generators $ast)
        providers: ($ast | get --optional providers | default {})
        cfg: ($ast | get --optional cfg | default {})
    }
}
