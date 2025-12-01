# Vision

This project explores a deliberately opinionated approach to Terraform module design.

Rather than building highly flexible modules that expose many configuration options, each module should represent a narrow, well-defined infrastructure pattern with heavily constrained inputs and outputs.

## Core Idea

Traditional Terraform modules often support many use cases through variables, feature flags, optional resources, and configurable security settings.

For example, a single module might allow callers to:

- use AWS-managed server-side encryption;
- provide an existing KMS key ARN;
- provision a new KMS key;
- disable or alter related security controls; or
- combine these behaviours through additional configuration.

This flexibility creates a large configuration domain. Some combinations may satisfy the intended security model, while others may weaken or violate it.

This project takes the opposite approach.

Instead of one flexible module, it provides multiple narrowly scoped modules representing specific, opinionated patterns.

For example:

- one module may always use AWS-managed server-side encryption and expose no KMS configuration at all;
- another may require the caller to provide a KMS key;
- another may always provision and manage its own KMS key.

The caller chooses a pattern rather than constructing one through configuration.

## Constrain the Configuration Domain

A primary objective is to reduce the number of possible system states.

The module API should expose only the choices that are necessary for the pattern it represents. Security-relevant decisions should, wherever practical, be encoded into the module rather than delegated to every caller.

The goal is not merely to provide secure defaults.

The stronger goal is to make configurations that violate the module's intended security properties impossible, or at minimum materially more difficult, to express.

In other words:

> Do not expose configuration simply because the underlying provider supports it.

Expose only the configuration required by the pattern.

## Patterns as Security Boundaries

Each module should correspond to a pattern whose behaviour can be analysed and attested independently.

Because the possible configuration space is deliberately small, a module can carry stronger assertions about:

- its threat model;
- the threats it is intended to mitigate;
- the security controls it always applies;
- the assumptions it makes;
- the behaviours it permits;
- the behaviours it explicitly does not support.

Adopting a module therefore also means adopting a known infrastructure and security pattern.

The caller should not need to independently reconstruct the threat analysis for every invocation.

## Security Through Structural Constraints

In a highly configurable module, security often depends on the caller selecting the correct combination of variables.

In this project, security should instead emerge from the structure of the module itself.

Where a security property is fundamental to a pattern, the preferred implementation is:

1. encode the property directly into the resources;
2. avoid exposing variables that could undermine it;
3. expose separate modules when materially different security models are required.

This reduces reliance on documentation, convention, policy checks, or callers remembering to enable the right options.

Those controls may still exist, but they should reinforce the design rather than compensate for an excessively permissive module API.

## Design Principle

The fundamental design principle is:

> Prefer several small, strongly opinionated modules with narrow configuration domains over one highly configurable module representing many materially different infrastructure patterns.

The resulting modules may appear repetitive compared with generalized Terraform abstractions.

That repetition is intentional.

The objective is not to minimize Terraform code. The objective is to minimize ambiguity, configuration variance, and the number of ways infrastructure can diverge from its intended security model.

## Desired Outcome

A consumer examining a module should be able to determine, largely from the module they selected:

- what pattern is being deployed;
- which important security decisions have already been made;
- which threat model the pattern is designed around;
- what configuration remains under their control; and
- what classes of configuration the module intentionally makes impossible.

The repository should therefore function not only as a collection of Terraform modules, but as a catalogue of constrained, reviewable, and attestable infrastructure patterns.
