# ==============================================================================
# engine/envfile_ast.nu — Envfile AST projection.
#
# Extracts envfile-relevant subtree from the full AST.
# Not a parser — input is already a parsed AST from engine/parser.nu.
#
# Envfile pipeline needs:
#   - generators  (all — needed for template resolution)
#   - envfile     (file, pattern, excluded)
#   - providers   (all enabled)
#
# Does NOT include secrets — envfile pipeline never touches secrets.
# Pure — no side effects.
# ==============================================================================

use ../queries.nu

# Project full AST → envfile-relevant subtree.
@example "Project envfile ast from empty ast" { project { generators: [] secrets: [] envfile: { file: .env, pattern: .env.example, excluded: [] } providers: {} cfg: {} } }
export def project [ast: record] {
    {
        generators: (queries generators $ast)
        envfile: ($ast | get --optional envfile | default {file: .env, pattern: .env.example, excluded: []})
        providers: ($ast | get --optional providers | default {})
        cfg: ($ast | get --optional cfg | default {})
    }
}
