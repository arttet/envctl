# Architecture

envctl is designed as a modular compiler and execution engine. This page details the internal structure and how the different components interact.

## Execution Flow

The following diagram illustrates how a command flows through the envctl system:

```text
CLI Command / Environment Variables
    ↓
runtime/pipeline.nu              ← Profile switch & main orchestrator
    ↓
engine/parser.nu                 ← Parses .envctl.toml into a full AST
                                   Uses language/grammar.nu for tokenization
    ↓
engine/ast/envfile.nu            ← Full AST → envfile subtree  (profile: envfile + all)
engine/ast/secrets.nu            ← Full AST → secrets subtree  (profile: secrets + all)
engine/ast/certs.nu              ← Full AST → certs subtree    (profile: certs + all)
    ↓
engine/validator.nu              ← Schema checks & token linking via manifest.provides
    ↓
engine/plan.nu                   ← Validated AST + Profile → ExecutionPlan
                                   Resolves generator values
    ↓
engine/executor.nu               ← ExecutionPlan → Side Effects
                                   Renders .env, calls backend dispatch
    ↓
engine/diff.nu                   ← Compares resolved plan with disk/state
    ↓
pipeline.nu writes lock + state  ← After success (only if not dry-run)
```

## Layer Responsibilities

| Layer | Responsibility |
|---|---|
| `language/` | Pure utilities for tokenization, keyword registry, and `.env.example` parsing. |
| `engine/` | The core compiler logic: parsing, AST projection, validation, planning, execution, and diffing. |
| `schema/` | Universal validation engine that enforces TOML schemas. No project-specific knowledge. |
| `runtime/` | Orchestration: assembling the execution context, loading plugins, and dispatching tasks. |
| `state/` | Reproducibility and audit: managing the `.envctl.lock` and `.envctl.state.ndjson` files. |
| `commands/` | The CLI interface that translates user input into pipeline calls. Never calls engine directly. |
| `core/` | Constants and structured logging shared across all layers. |
| `plugins/` | Payloads for providers and backends that extend the system's capabilities. |

## Plugin Boundary Rules

To maintain a clean and maintainable codebase, envctl enforces strict rules for plugins:

- **Self-contained**: Plugins in `plugins/` must NOT import anything from `src/`.
- **Pure Payloads**: Plugins should only contain manifests and functions; orchestration logic belongs in `src/runtime/`.
- **Registry Only**: Only `src/runtime/providers/registry.nu` and `src/runtime/backends/registry.nu` are allowed to import from the `plugins/` directory.
