# Specification Quality Checklist: Name Apple Health Wherever Rekkert Uses It

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-27
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Passed on the first validation pass. "Apple Health" is the product name the guideline is
  about, not an implementation detail; HealthKit, CareKit and other API names stay out of the
  requirements and appear only in the quoted rejection.
- No clarification markers were needed. The decisions taken as defaults, and worth a look in
  `/speckit-clarify`: the Apple Health section also shows on iPad (FR-001); Rekkert shows its
  own explanation before the first permission request (FR-015, User Story 3, P2); the workout
  controls stay hidden without a watch, with the section explaining why.
- FR-021 (the screen recording) and the review notes in FR-020 are done by hand in App Store
  Connect, outside the code.
