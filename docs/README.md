# Developer documentation

These guides follow the same intent and workflow as the sibling Photo-Archival project: durable architecture notes and a practical developer getting-started guide, maintained in Markdown and generated as Word documents.

| Guide | Markdown source | Generated Word copy |
|---|---|---|
| Architecture and source map | [Architecture](dev/architecture.md) | [Word](dev/architecture.docx) |
| Developer setup and workflow | [Getting started](dev/getting-started.md) | [Word](dev/getting-started.docx) |
| App Store feasibility and deployment | [Deployment plan](app-store-deployment-plan.md) | [Word](app-store-deployment-plan.docx) |

Edit the Markdown sources, then run:

```sh
python3 docs/build-docx.py
python3 docs/build-docx.py --check
```

The converter is adapted from Photo-Archival's dependency-free Python OOXML generator. All native Xcode builds and their shell wrappers regenerate registered Word documents through the shared documentation target before compiling; `./build.sh` does so before standalone CLI compilation. `./MacApp/package.sh` includes the native build step. Generation errors stop the build. For documentation-only work, run the converter directly without rebuilding the app. It supports one-file conversion with `IN.md OUT.docx` and produces deterministic output. Preserve the Markdown and Word files together in source control. Check rendered Word pages when changing content or formatting.

The root [README](../README.md) remains the end-user guide. [README-DEVELOPER](../README-DEVELOPER.md) retains detailed engineering CLI, timer and release notes. Reports, real email fixtures and private configuration are not documentation sources to publish.

Native development starts with `Mail-Filter.xcodeproj` at the repository root. The [build configuration guide](../MacApp/Build/README.md) maps its local, installer, sandboxed check, Store and CLI workflows; the getting-started guide above provides the detailed Xcode steps. The CLI's separate Swift package remains available for standalone engineering builds.

The [Store build workflow](../MacApp/Store/README.md) covers unsigned checks, isolated signing configurations, archiving and local export. [Store review preparation](store-review-preparation.md) is a Markdown publisher worksheet with privacy and entitlement drafts; it remains separate from the generated engineering guides. `./MacApp/store-build.sh` also regenerates the registered Word documents before compilation.

The [build 24 model qualification record](model-reliability-qualification.md) documents fault injection, the synthetic model comparison, Dev isolation and the limits of those tests.

The [local reproduction plan](model-reproduction-plan.md) covers frozen-request replay, durable private evidence, controlled comparisons and local Dev qualification. Debugging takes place on the publisher’s Mac; a remote family member is only an optional beta tester. The plan records hardware-emulation limits and the outstanding release gate.

The [model-failure history audit](model-failure-history.md) traces the original failures on this host, the introduction of retries and section-size reduction, and the relationship to the later beta report. It distinguishes runtime evidence from code changes and identifies the remaining timing tests.

The [timing and queue investigation](timing-and-queue-investigation.md) records the real-model historical context control, queued/paced comparison, full-duration timeout tests and candidate build-26 architecture corrections. It preserves the distinction between confirmed defects and the still-unexplained invalid-label failure.
