@echo off
setlocal enabledelayedexpansion

echo Setting up AI agent system...

:: Create spec structure
mkdir spec\features 2>nul
mkdir spec\contracts 2>nul
mkdir spec\acceptance 2>nul

:: Create spec README
(
echo # Specifications
echo.
echo This directory contains all feature specifications for the project.
echo.
echo ## Structure
echo.
echo - `features/` — Feature specifications
echo - `contracts/` — API contracts ^(OpenAPI, AsyncAPI^)
echo - `acceptance/` — Acceptance criteria and scenarios
echo.
echo ## Quick Links
echo.
echo - [Feature Index](features/README.md^)
echo.
echo ## Rules
echo.
echo 1. **Spec before code** — Every feature needs a spec before implementation
echo 2. **Keep specs updated** — Specs are the source of truth
echo 3. **Index all features** — Every feature must be in the index
) > spec\README.md

:: Create feature index
(
echo # Feature Index
echo.
echo ## Overview
echo.
echo All features in this system, with their implementation status.
echo.
echo ## Features
echo.
echo ^| Feature ^| Spec ^| Backend ^| Frontend ^| Status ^|
echo ^|---------|------|---------|----------|--------|
echo ^| *No features yet* ^| ^| ^| ^| ^|
echo.
echo ## Adding a Feature
echo.
echo 1. Create directory: `spec/features/^<feature-name^>/`
echo 2. Create spec from template: copy `_template.md` to `^<feature-name^>/^<feature^>.md`
echo 3. Fill in the spec completely
echo 4. Add entry to this index
echo 5. Write tests, then implementation
echo 6. Update status as you progress
) > spec\features\README.md

:: Create feature template
(
echo # Feature: ^<Feature Name^>
echo.
echo ## Overview
echo.
echo Brief description of what this feature does and why it exists.
echo.
echo ## User Stories
echo.
echo - As a ^<role^>, I want ^<goal^>, so that ^<benefit^>
echo.
echo ## Behavior
echo.
echo ### Happy Path
echo.
echo 1. Given ^<precondition^>
echo 2. When ^<action^>
echo 3. Then ^<expected outcome^>
echo.
echo ### Edge Cases
echo.
echo ^| Scenario ^| Behavior ^|
echo ^|----------|----------|
echo ^| ^<edge case^> ^| ^<what happens^> ^|
echo.
echo ### Error Cases
echo.
echo ^| Error Condition ^| Response ^|
echo ^|-----------------|----------|
echo ^| ^<condition^> ^| ^<error response^> ^|
echo.
echo ## API
echo.
echo ### Endpoint
echo.
echo ```
echo POST /api/v1/^<resource^>
echo ```
echo.
echo ### Request
echo.
echo ```json
echo {
echo   "field": "value"
echo }
echo ```
echo.
echo ### Response
echo.
echo ```json
echo {
echo   "id": "uuid",
echo   "field": "value"
echo }
echo ```
echo.
echo ### Error Codes
echo.
echo ^| Code ^| Meaning ^|
echo ^|------|---------|
echo ^| 400 ^| Invalid request ^|
echo ^| 404 ^| Resource not found ^|
echo ^| 409 ^| Conflict ^|
echo.
echo ## Dependencies
echo.
echo - **Requires:** ^<upstream dependencies^>
echo - **Used by:** ^<downstream consumers^>
echo.
echo ## Status
echo.
echo - [ ] Spec complete
echo - [ ] Acceptance tests
echo - [ ] Backend implemented
echo - [ ] Unit tests
echo - [ ] Contract tests
echo - [ ] Frontend implemented
echo - [ ] Documentation updated
) > spec\features\_template.md

:: Create OpenAPI template
(
echo openapi: 3.0.3
echo info:
echo   title: Project API
echo   version: 1.0.0
echo   description: ^|
echo     API specification for the project.
echo.
echo     ## Versioning
echo     All endpoints are versioned with URL path: `/api/v1/`
echo.
echo     ## Authentication
echo     All endpoints require Bearer token authentication.
echo.
echo servers:
echo   - url: /api/v1
echo     description: API v1
echo.
echo paths: {}
echo.
echo components:
echo   securitySchemes:
echo     bearerAuth:
echo       type: http
echo       scheme: bearer
echo       bearerFormat: JWT
echo.
echo   schemas:
echo     Error:
echo       type: object
echo       required:
echo         - code
echo         - message
echo       properties:
echo         code:
echo           type: string
echo           description: Machine-readable error code
echo         message:
echo           type: string
echo           description: Human-readable error message
echo         traceId:
echo           type: string
echo           description: Correlation ID for debugging
echo         timestamp:
echo           type: string
echo           format: date-time
echo         details:
echo           type: object
echo           additionalProperties:
echo             type: string
echo           description: Field-level error details
echo.
echo security:
echo   - bearerAuth: []
) > spec\contracts\openapi.yaml

echo.
echo Setup complete!
echo.
echo Structure created:
echo.
echo spec\
echo +-- README.md
echo +-- features\
echo ^|   +-- README.md
echo ^|   +-- _template.md
echo +-- contracts\
echo ^|   +-- openapi.yaml
echo +-- acceptance\
echo.
echo Next steps:
echo 1. Create your first feature: mkdir spec\features\my-feature
echo 2. Copy template: copy spec\features\_template.md spec\features\my-feature\feature.md
echo 3. Fill in the spec
echo 4. Add to spec\features\README.md index
echo 5. Write tests, then implement

endlocal
