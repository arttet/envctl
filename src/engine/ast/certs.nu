# ==============================================================================
# engine/certs_ast.nu — Certs AST projection.
#
# Extracts certs-relevant subtree from the full AST.
# Not a parser — input is already a parsed AST from engine/parser.nu.
#
# Certs pipeline needs:
#   - certs      — cert nodes from [certs.*] (record fields), topo-sorted
#   - certs_vars — substitution vars from [certs] scalar fields (UPPER_CASE)
#   - generators — needed to resolve {{ }} tokens in cert/key paths and config_template
#   - providers  — certs provider config
#   - cfg        — full normalized config
#
# Does NOT include secrets or envfile nodes.
# Pure — no side effects.
# ==============================================================================

use ../queries.nu

# Project full AST → certs-relevant subtree.
@example "Project certs ast from empty ast" { project { generators: [] certs: [] certs_vars: {} providers: {} cfg: {} } }
export def project [ast: record] {
    {
        certs: (queries certs $ast)
        certs_vars: (queries certs-vars $ast)
        generators: (queries generators $ast)
        providers: ($ast | get --optional providers | default {})
        cfg: ($ast | get --optional cfg | default {})
    }
}
