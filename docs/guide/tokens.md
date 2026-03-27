# Tokens & Grammar

`envctl` uses a flexible token system to resolve dynamic values in your configuration. Tokens are enclosed in double curly braces: <span v-pre>`{{ token }}`</span>.

## Token Types

There are three primary types of tokens supported by `envctl`:

| Type | Syntax | Resolution |
|---|---|---|
| **Variable** | <span v-pre>`{{ IDENT }}`</span> | Resolves to a value defined in the `[generators]` section. |
| **Secret** | <span v-pre>`{{ secret:IDENT }}`</span> | Resolves to the *contents* of the file at the path stored in the `IDENT` generator. |
| **Provider** | <span v-pre>`{{ provider:NAME.FN }}`</span> | Calls a function `FN` from provider `NAME` and returns its output. |

## Examples

### Variable Token
If you have a generator:
```toml
[generators]
PROJECT_NAME = "my-awesome-app"
```
You can use it as <span v-pre>`{{ PROJECT_NAME }}`</span> in your configuration or `.env` template.

### Provider Token
Use a provider to generate a secure password:
```toml
[secrets.DB_PASSWORD]
value_source = <span v-pre>`{{ provider:password.generate-password }}`</span>
```

### Secret Token
If `DB_PASS_FILE` points to `/path/to/password`, then <span v-pre>`{{ secret:DB_PASS_FILE }}`</span> will resolve to the password itself.

## Grammar Rules

1.  **Identifiers (`IDENT`)**: Must be alphanumeric and can include underscores.
2.  **Case Sensitivity**: Identifiers are case-sensitive.
3.  **No Nesting**: Tokens cannot currently be nested within each other.
4.  **Whitespace**: Whitespace inside the curly braces is ignored (e.g., <span v-pre>`{{ IDENT }}`</span> is the same as <span v-pre>`{{IDENT}}`</span>).

## Token Resolution Order

1.  **Providers**: All `provider:NAME.FN` tokens in the `[generators]` section are called first.
2.  **Generators**: The `[generators]` section is processed, resolving any cross-references.
3.  **Phase Execution**: Tokens in `[envfile]`, `[secrets]`, and `[certs]` are resolved using the compiled generators.
