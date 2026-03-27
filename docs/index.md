---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "envctl"
  text: "Nushell-native configuration compiler"
  tagline: Generate .env files, manage secrets, and PKI certificate chains with ease.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/introduction
    - theme: alt
      text: CLI Reference
      link: /reference/commands

features:
  - title: Compile Phase
    details: Pure, deterministic parsing and validation of your configuration before any side effects.
  - title: Secret Management
    details: Generate and deliver secrets to multiple backends like local files or Infisical.
  - title: PKI Certificate Chains
    details: Built-in support for Root CA, Intermediate, and Leaf certificate generation.
  - title: Schema-driven
    details: Full validation for configs, providers, and runtime context using TOML schemas.
  - title: Drift Detection
    details: Monitor health and detect drift between your configuration and the actual state.
  - title: Nushell Native
    details: Built entirely in Nushell for a modern, type-safe, and high-performance experience.
---
