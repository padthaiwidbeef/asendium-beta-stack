# Asendium Development Agent

You are working on the Asendium application.

The workspace contains three independent repositories:

- `asendium-beta/`
  - Next.js frontend
  - TypeScript
  - React

- `Eagle/`
  - ASP.NET Core API
  - .NET 10
  - PostgreSQL backend

- `database/`
  - PostgreSQL database/schema/scripts

The repositories are separate Git repositories but together form one application.

---

# Core Operating Principle

Begin work immediately.

Do not stop to present a plan or request approval for ordinary implementation decisions.

Inspect the codebase, infer the existing patterns, make reasonable decisions, and proceed.

Only ask the user for clarification when the task is genuinely blocked by missing information that cannot reasonably be inferred from:

- the repositories
- `AGENTS.md`
- `TASK.md`
- existing code patterns
- existing database schema
- existing API contracts
- existing UI behaviour

Do not ask for approval simply because there are multiple reasonable implementation choices.

Prefer the choice that is:

1. most consistent with the existing architecture
2. least destructive
3. easiest to maintain
4. least likely to introduce unrelated changes

---

# Architecture

The application runs locally using Docker Compose.

Services:

- Frontend:
  - Container: `asendium-beta`
  - Host URL: `http://localhost:3000`

- API:
  - Container: `eagle-api`
  - Host URL: `http://localhost:5080`
  - Docker URL: `http://api:8080`

- PostgreSQL:
  - Container: `asendium-db`
  - Host port: `5432`
  - Docker hostname: `postgres`
  - Database: `myapp`

The frontend's server-side API proxy should communicate with Eagle using:

`http://api:8080`

Do not use `localhost:5080` for requests originating inside the frontend Docker container.

The Eagle API should connect to PostgreSQL using:

`Host=postgres;Port=5432;Database=myapp`

---

# Development Workflow

Before making changes:

1. Read this file.
2. Read `TASK.md` if present.
3. Read any repository-specific `AGENTS.md` files that apply.
4. Inspect the relevant repositories.
5. Check `git status` in every affected repository.
6. Understand existing patterns before introducing new abstractions.
7. Determine whether the task affects frontend, API, database, or multiple layers.

Do not pause after inspection unless there is a genuine blocker.

Proceed directly into implementation.

When implementing a feature:

1. Update the database/schema if required.
2. Update Eagle API models/services/controllers if required.
3. Update the Next.js frontend if required.
4. Verify contracts between layers.
5. Run relevant builds/tests.
6. Fix directly related issues discovered during verification.
7. Summarize what changed when finished.

---

# Autonomy

The agent is expected to work autonomously.

For ordinary development decisions:

- inspect the current implementation
- follow the existing architecture
- infer intent from surrounding code
- choose the least disruptive implementation
- proceed without asking the user

Do not pause merely to:

- present an implementation plan
- ask which naming option is preferred
- ask whether an existing pattern should be reused
- ask whether obvious supporting changes should be made
- ask for permission to edit normal source files
- ask for permission to run builds or tests
- ask for permission to run safe Docker commands

If a task naturally spans multiple repositories, make the necessary coordinated changes.

If a task exposes a directly related bug, fix it if doing so is low-risk and necessary for the requested work to function.

Do not broaden the scope into unrelated cleanup.

---

# When You Must Ask

Ask the user before doing anything that could be meaningfully destructive, irreversible, security-sensitive, or operationally risky.

This includes:

- deleting database data
- dropping tables
- dropping columns without a verified migration path
- removing existing data mappings
- deleting large sets of files
- changing Docker volumes
- deleting Docker volumes
- changing authentication architecture
- changing authorization rules
- changing security-sensitive behaviour
- rotating secrets
- exposing credentials
- changing production infrastructure
- making destructive Git operations
- resetting branches
- discarding user changes
- rebasing published branches
- force pushing
- committing
- pushing
- installing a major new framework
- replacing a major dependency or architectural layer
- changing ORM/data-access strategy
- making a migration that could lose existing data
- modifying external systems outside the local development environment

If a destructive change appears necessary, prefer a non-destructive migration path first.

---

# Docker

The whole stack is controlled by the root `docker-compose.yml`.

Do not create independent Docker Compose files inside individual repositories unless explicitly requested.

The development environment supports hot reload.

Do not rebuild containers unnecessarily for ordinary source-code changes.

You may run safe commands such as:

- `docker compose up`
- `docker compose up -d`
- `docker compose restart`
- `docker compose ps`
- `docker compose logs`
- `docker compose logs -f`
- `docker compose exec`
- non-destructive database queries

Do not run destructive Docker commands without confirmation, including commands that remove persistent volumes.

---

# Database

PostgreSQL is the source of truth.

Do not drop:

- databases
- tables
- columns
- schemas
- persistent data

unless explicitly instructed or approved.

For schema changes:

- prefer migrations
- prefer additive changes
- preserve existing data
- provide a migration path before removing legacy fields
- understand existing relationships before changing them

If replacing an existing field or relationship:

1. add the new structure
2. migrate or map existing data where practical
3. update application code
4. verify behaviour
5. only remove legacy structures when it is safe and explicitly appropriate

Never silently destroy existing data.

Do not manually mutate development data in a way that cannot be reproduced if a seed or migration mechanism can be used instead.

---

# API

Follow the existing Eagle project structure.

Use dependency injection.

Keep controllers thin.

Place business logic in appropriate services.

Use async APIs for database and network operations.

Follow existing:

- naming conventions
- namespaces
- DTO patterns
- service patterns
- validation patterns
- error handling patterns
- data-access patterns

Do not introduce a second ORM or data-access pattern unless explicitly requested.

Do not duplicate existing infrastructure.

Prefer extending existing abstractions.

---

# Frontend

Follow the existing Next.js architecture.

Use TypeScript.

Reuse existing components and design patterns before creating new ones.

Prefer existing:

- form components
- table components
- styling conventions
- hooks
- API helpers
- validation patterns
- loading patterns
- error patterns

Do not hardcode backend hostnames in client components.

Browser-facing code should generally call the Next.js API proxy rather than Eagle directly.

Server-side container-to-container calls may use:

`http://api:8080`

Avoid unnecessary new dependencies.

Do not introduce a new UI library if the existing project already has an established component system.

---

# Cross-Repository Work

Treat the three repositories as one application.

When a feature requires changes in multiple repositories, make coordinated changes.

Typical dependency order:

1. database
2. Eagle API
3. Next.js frontend

But do not follow this mechanically if the existing implementation suggests a different order.

Keep contracts aligned across layers.

For example:

- database column names
- API DTOs
- endpoint routes
- request/response shapes
- frontend types
- frontend forms

Do not leave one layer knowingly incompatible with another.

---

# Code Quality

Before finishing a task:

- check for compile errors
- check TypeScript errors
- check obvious runtime errors
- run relevant tests
- run builds where practical
- verify API contracts
- verify database migrations
- verify changed forms/pages
- verify any directly affected Docker service starts successfully

Do not claim something works unless it was verified.

If something could not be verified, state that clearly.

If a test fails due to an unrelated existing issue, distinguish that from failures caused by your changes.

---

# Testing

Prefer targeted verification first.

Examples:

Frontend:

- relevant TypeScript check
- relevant component/page behaviour
- frontend build if practical

API:

- `dotnet build`
- relevant tests
- endpoint verification

Database:

- migration applies successfully
- expected tables/columns exist
- seed data inserts correctly
- existing data remains intact

End-to-end:

- verify the user flow affected by the task
- verify data persists after reload where applicable

Do not spend excessive time fixing unrelated failing tests.

---

# Git

The three repositories are independent.

Do not create commits unless explicitly asked.

Do not push changes unless explicitly asked.

Do not rewrite Git history.

Do not reset or discard existing user changes.

Do not overwrite uncommitted user changes.

Before making broad changes, inspect `git status` in every affected repository.

If files already contain user modifications:

- preserve them
- work around them where practical
- do not assume they can be reverted

Do not use destructive Git commands such as:

- `git reset --hard`
- `git clean -fd`
- force checkout of modified files
- force push

without explicit approval.

---

# Existing User Work

Assume existing uncommitted changes may be intentional.

Do not remove, overwrite, or "clean up" user code simply because it appears incomplete.

When editing a file with existing user changes:

- preserve unrelated modifications
- make the smallest necessary diff
- avoid reformatting the entire file unless required

---

# Scope Control

Keep changes focused on the requested task.

Do not perform large unrelated refactors.

Do not rename large areas of the codebase unless required.

Do not convert architectural patterns merely because another approach seems preferable.

Do not "modernize" unrelated code as part of a feature.

Small directly related cleanup is acceptable when it reduces duplication or is necessary for the requested feature.

---

# Ambiguity

If a requirement is ambiguous:

1. inspect existing code
2. inspect similar features
3. inspect data models
4. inspect API patterns
5. inspect UI patterns
6. infer the most likely intended behaviour
7. proceed

Only ask the user when the ambiguity cannot reasonably be resolved.

When choosing between reasonable options, prefer consistency with the existing system over introducing a new pattern.

---

# External Dependencies

Do not introduce new third-party dependencies unless they provide a clear benefit and existing dependencies cannot reasonably solve the problem.

Minor development dependencies may be added when clearly justified.

Ask before:

- adding a major framework
- replacing a core library
- introducing a new ORM
- introducing a new state-management system
- introducing a new authentication system
- introducing infrastructure that materially changes the architecture

---

# Error Handling

Do not hide errors.

Use existing application error patterns.

For user-facing functionality:

- handle loading states
- handle empty states
- handle API failures
- avoid silent failures

For API code:

- validate inputs
- return appropriate status codes
- preserve useful error information without exposing sensitive details

---

# Security

Do not expose:

- passwords
- secrets
- connection strings containing real credentials
- API keys
- tokens

Do not commit secrets.

Do not weaken authentication or authorization to make development easier unless explicitly instructed.

Do not disable security controls globally as a shortcut.

---

# Allowed Without Asking

You may:

- inspect any repository in this workspace
- read any source file
- search the codebase
- edit source code
- create source files
- create migrations
- create seed scripts
- update development configuration
- run builds
- run tests
- run linters
- run formatters when appropriate
- run safe `docker compose` commands
- query the local development database
- inspect database schema
- inspect Docker logs
- restart development services
- modify frontend components
- modify API code
- add non-destructive database structures
- fix directly related bugs
- update types and contracts across repositories
- make reasonable implementation decisions without approval

---

# Require Confirmation

Ask before:

- deleting database data
- dropping databases
- dropping tables
- dropping columns without a safe migration
- deleting large sets of files
- changing or deleting Docker volumes
- changing authentication/security architecture
- weakening authorization
- exposing secrets
- changing production infrastructure
- installing major new frameworks
- replacing core architectural dependencies
- making destructive Git operations
- discarding existing user changes
- committing
- pushing
- force pushing
- rewriting Git history
- making irreversible external-system changes
- performing migrations likely to lose data

---

# Behaviour

Prefer making the requested change rather than explaining how to make it.

Begin work immediately.

Do not stop merely to provide a plan.

Do not ask unnecessary questions.

Do not ask for approval for ordinary implementation details.

Use the codebase itself as the primary source of truth.

Make reasonable, conservative assumptions where necessary.

Preserve existing behaviour unless the task explicitly requires changing it.

Keep changes maintainable and consistent with existing patterns.

Explain cross-repository changes clearly when finished.

---

# Completion Behaviour

When work is complete, provide a concise summary containing:

- what was changed
- which repositories were affected
- important architectural decisions
- database migrations created
- API endpoints added or changed
- frontend components added or changed
- tests/builds run
- anything not verified
- any blockers or follow-up work

Do not provide a lengthy implementation plan after the work is already complete.

Do not claim verification that did not actually occur.