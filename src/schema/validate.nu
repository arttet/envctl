# ==============================================================================
# schema/validate.nu — Generic schema validation engine.
#
# Reads TOML schema files from schemas/ directory.
# Pure engine — no knowledge of .envctl structure or providers.
#
# Schema format:
#   [fields.FIELD_NAME]
#   type     = "string" | "int" | "float" | "bool" | "record" | "list<string>"
#   required = true | false   (default: false)
#   default  = <value>
#   enum     = ["a", "b"]
#   min      = <number>
#   max      = <number>
# ==============================================================================

use ../core/constants.nu [SCHEMAS_DIR]

# Validate a record against a named schema file.
# Checks types, enums, required fields, min/max constraints.
@example "Validate against envctl config schema" { validate-schema { schema: "v1" } "envctl.config.schema.toml" }
@example "Validate empty record — all defaults valid" { validate-schema {} "envctl.config.schema.toml" }
@example "Validate ctx stage field" { validate-schema { stage: "dev" } "ctx.schema.toml" }
export def validate-schema [
    data:        record   # Record to validate
    schema_name: string   # Schema filename in schemas/ (e.g. "envctl.config.schema.toml")
]: nothing -> nothing {

    let schema_path = ($env.ENVCTL_HOME? | default "." | path join "schemas" $schema_name)
    if not ($schema_path | path exists) {
        error make {
            msg: $"[schema] schema file not found: ($schema_path)"
        }
    }

    let fields = (open $schema_path | get --optional fields | default {})
    for field in ($fields | columns) {
        let spec = ($fields | get $field)
        let value = ($data | get --optional $field)
        let req = ($spec | get --optional required | default false)
        if $req and ($value == null) {
            error make {
                msg: $"[schema/($schema_name)] required field '($field)' is missing"
            }
        }

        if $value == null {
            continue
        }

        let expected_type = ($spec | get --optional type | default "")
        if not ($expected_type | is-empty) {
            check-type $field $value $expected_type $schema_name
        }

        let enum_vals = ($spec | get --optional enum | default [])
        if not ($enum_vals | is-empty) and not ($value in $enum_vals) {
            error make {
                msg: $"[schema/($schema_name)] field '($field)' value '($value)' not in enum ($enum_vals)"
            }
        }

        let min = ($spec | get --optional min)
        let max = ($spec | get --optional max)

        if $min != null and $value < $min {
            error make {
                msg: $"[schema/($schema_name)] field '($field)' value ($value) is below min ($min)"
            }
        }

        if $max != null and $value > $max {
            error make {
                msg: $"[schema/($schema_name)] field '($field)' value ($value) exceeds max ($max)"
            }
        }
    }
}

# Apply defaults from schema to a record — fills missing optional fields.
# Returns a new record with defaults applied — does not mutate input.
@example "Apply defaults to empty record" { apply-defaults {} "envctl.config.schema.toml" }
@example "Apply defaults to partial ctx" { apply-defaults { stage: "prod" } "ctx.schema.toml" }
export def apply-defaults [data: record, schema_name: string] {
    let schema_path = ($env.ENVCTL_HOME? | default "." | path join "schemas" $schema_name)
    if not ($schema_path | path exists) {
        return $data
    }

    let fields = (open $schema_path | get --optional fields | default {})
    $fields | columns | reduce --fold $data {|field, acc|
        let spec    = ($fields | get $field)
        let current = ($acc | get --optional $field)
        let default = ($spec | get --optional default)

        if $current == null and $default != null {
            $acc | insert $field $default
        } else {
            $acc
        }
    }
}

def check-type [
    field: string
    value
    expected: string
    schema_name: string
] {
    let ok = match $expected {
        "string" => ($value | describe | str starts-with "string")
        "int" => ($value | describe | str starts-with "int")
        "float" => ($value | describe | str starts-with "float")
        "bool" => ($value | describe | str starts-with "bool")
        "record" => ($value | describe | str starts-with "record")
        "list<string>" => (($value | describe | str starts-with "list") and ($value | all { |i| ($i | describe | str starts-with "string") }))
        _ => true
    }

    if not $ok {
        error make {
            msg: $"[schema/($schema_name)] field '($field)' expected '($expected)', got '($value | describe)'"
        }
    }
}
