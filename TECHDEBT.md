# Technical Debt

This document tracks the technical debt in the Tilix project, categorized by impact and actionability.

## Priority Legend
- 🔴 **Critical**: Blocking development or causing significant user issues
- 🟡 **High**: Important for project health and contributor experience
- 🟢 **Medium**: Would improve quality but not urgent
- 🔵 **Low**: Nice to have improvements

---

## 🔴 Critical: Maintainership and Project Governance

### Lack of Active Maintainers
**Status**: Ongoing, acknowledged in README.md

**Impact**:
- Slow response to issues and pull requests (some open for years)
- Security vulnerabilities may go unpatched
- Contributors become discouraged and move to other projects
- Project risks being perceived as abandoned

**Consequences**:
- Issue backlog continues to grow
- Pull requests go unreviewed or unmerged
- No clear decision-making authority for architectural changes
- Difficulty coordinating releases and version management

**Actionable Steps**:
1. Create a clear maintainer succession plan
2. Document maintainer responsibilities and authority levels
3. Establish a contributor escalation path (contributor → committer → maintainer)
4. Set up a rotating "issue triage" role among active contributors
5. Consider forming a small steering committee for major decisions
6. Document governance model in GOVERNANCE.md

**Related Issues**: See [issue #1700](https://github.com/gnunn1/tilix/issues/1700)

---

## 🟡 High Priority: Dependencies and Build System

### GtkD Version Mismatch
**Status**: Active concern

**Problem**: 
The `dub.json` specifies GtkD version `3.11.0` for both `gtk-d:gtkd` and `gtk-d:vte`, but the latest publicly available version of GtkD is `3.10.0`.

**Impact**:
- New contributors may struggle to build the project
- Unclear which version to use and where to obtain it
- Potential compatibility issues with newer GTK versions
- Documentation/support challenges for non-standard version

**Risks**:
- Build failures for new developers
- Incompatibility with future GTK releases
- Difficulty reproducing and fixing build-related bugs

**Actionable Steps**:
1. Document the exact GtkD version requirement and source in BUILD.md
2. Investigate if the project can work with GtkD 3.10.0
3. If custom GtkD build is required, document the differences
4. Consider contributing needed features upstream to GtkD
5. Add CI checks for dependency version compatibility
6. Provide Docker/container images with correct dependencies pre-installed

### GTK+ 3 End-of-Life Planning
**Status**: Future concern

**Problem**: 
GTK+ 3 is mature but GTK 4 has been released. Eventually, migration may be necessary.

**Impact**:
- Long-term sustainability concerns
- Some modern features unavailable
- Potential compatibility issues with future Linux distributions

**Actionable Steps**:
1. Monitor GTK 4 adoption in Linux distributions
2. Create a GTK 4 migration assessment document
3. Identify breaking changes in GtkD for GTK 4
4. Consider a phased migration approach
5. Track VTE widget GTK 4 compatibility

---

## 🟡 High Priority: Testing Infrastructure

### Minimal Test Coverage
**Status**: Significant gap

**Current State**:
- No unit tests found in repository
- No integration tests for terminal functionality
- No UI/acceptance tests
- Manual testing only

**Impact**:
- High risk when refactoring code
- Difficult to verify bug fixes
- Regressions may go unnoticed
- Slows down review process (reviewers must manually test)

**Challenges**:
- GTK+ applications are difficult to test automatically
- VTE widget behavior is complex to mock
- Terminal I/O is inherently asynchronous
- State management across multiple components

**Actionable Steps**:
1. **Phase 1 - Foundation**:
   - Add unit tests for utility functions (`gx/util/`, `gx/gtk/util.d`)
   - Test data model classes (ProfileManager, BookmarkManager)
   - Test serialization/deserialization (Session JSON loading)

2. **Phase 2 - Component Tests**:
   - Add tests for command-line parsing (`cmdparams.d`)
   - Test preferences management without GTK
   - Test color scheme parsing

3. **Phase 3 - Integration Tests**:
   - Set up Xvfb for headless GTK testing
   - Test basic application startup
   - Test session creation and layout

4. **Phase 4 - UI Tests** (optional):
   - Investigate Dogtail or similar tools for GNOME app testing
   - Add smoke tests for critical user workflows

**Tools to Consider**:
- D's built-in `unittest` blocks
- Xvfb for headless X11
- dub test configuration
- GitHub Actions for CI testing

---

## 🟡 High Priority: Documentation

### Code Documentation (Inline Comments)
**Status**: Inconsistent

**Current State**:
- Some modules well-documented, others sparse
- Complex functions lack explanation
- No consistent documentation style
- Limited API documentation

**Impact**:
- Steep learning curve for new contributors
- Difficult to understand complex logic (e.g., session layout)
- Hard to maintain without understanding intent

**Actionable Steps**:
1. Adopt a D documentation standard (DDoc format)
2. Document all public APIs and interfaces
3. Add high-level module documentation
4. Document complex algorithms (session deserialization, layout management)
5. Generate API docs with `dub build --build=docs` or `ddoc`
6. Publish generated docs to GitHub Pages

**Priority Areas**:
- `session.d` - Layout serialization logic
- `terminal/terminal.d` - VTE integration
- `application.d` - Application lifecycle
- All public interfaces

### User Documentation
**Status**: Scattered

**Current State**:
- README covers basics
- Wiki has some advanced topics
- No comprehensive user guide
- Feature discovery is difficult

**Impact**:
- Users unaware of advanced features (triggers, badges, custom links)
- Support burden from repetitive questions
- Underutilization of Tilix capabilities

**Actionable Steps**:
1. Create a USER_GUIDE.md with:
   - Getting started tutorial
   - Feature overview with screenshots
   - Configuration examples
   - Troubleshooting section
2. Document all keyboard shortcuts
3. Create video tutorials for complex features
4. Improve wiki organization and searchability

### Developer Documentation
**Status**: Now improved with ARCHITECTURE.md

**Remaining Gaps**:
- Build troubleshooting guide
- Contribution guidelines (CONTRIBUTING.md)
- Code style guide
- Release process documentation
- Debugging tips for GTK+/D

**Actionable Steps**:
1. Create CONTRIBUTING.md with:
   - Development environment setup
   - Build instructions for all platforms
   - Coding standards and style
   - Pull request process
   - How to run tests (once they exist)
2. Document common development issues
3. Create DEBUGGING.md with tips for GTK/VTE issues

---

## 🟢 Medium Priority: Code Quality

### Large Complex Files
**Status**: Maintenance burden

**Files of Concern**:
- `appwindow.d` - 83,155 bytes, 2,000+ lines
- `session.d` - 65,366 bytes, complex layout logic
- `terminal/terminal.d` - Large composite widget

**Impact**:
- Difficult to navigate and understand
- Hard to test in isolation
- Merge conflicts more likely
- Cognitive overhead for modifications

**Actionable Steps**:
1. Extract independent functionality into separate modules
2. Break up large classes with many responsibilities
3. Consider separating UI from logic (e.g., session layout logic from GTK widgets)
4. Use D's module system to create logical groupings
5. Refactor incrementally, one component at a time

### Error Handling Consistency
**Status**: Mixed approaches

**Current State**:
- Mix of exceptions, error codes, and assertions
- Inconsistent logging of errors
- Some error paths unhandled

**Actionable Steps**:
1. Establish error handling guidelines
2. Use exceptions for exceptional cases, expected errors via return values
3. Ensure all user-facing operations have proper error messages
4. Add error recovery where possible (graceful degradation)

### Memory Management
**Status**: Mostly good, some concerns

**Observations**:
- D's GC handles most memory management
- GTK+ objects require careful reference counting
- Potential leaks with circular references

**Actionable Steps**:
1. Review GTK object lifecycle management
2. Audit for circular references between GTK widgets
3. Use valgrind or similar tools to detect leaks
4. Document ownership semantics for complex objects

---

## 🟢 Medium Priority: Build and Development Experience

### Build System Duplication
**Status**: Two build systems (Dub and Meson)

**Current State**:
- `dub.json` for D developers
- `meson.build` for distribution packaging
- Must maintain both in sync

**Impact**:
- Double maintenance burden
- Risk of inconsistency
- Confusion for new contributors

**Trade-offs**:
- Dub is natural for D development
- Meson integrates better with Linux distribution packaging

**Actionable Steps**:
1. Document when to use each build system in BUILD.md
2. Add CI checks to ensure both builds work
3. Consider if one can be deprecated (unlikely given different use cases)
4. Script to verify both builds produce equivalent outputs

### Development Environment Setup
**Status**: Can be challenging

**Challenges**:
- GtkD version requirements
- Distribution-specific dependencies
- D compiler choice (DMD vs LDC)

**Actionable Steps**:
1. Provide Docker development container
2. Create platform-specific setup guides
3. Add VS Code devcontainer configuration
4. Document minimum GTK/VTE versions needed
5. Provide troubleshooting guide for common build issues

---

## 🔵 Low Priority: Feature Technical Debt

### VTE Patching Requirements
**Status**: Optional features require patched VTE

**Affected Features**:
- Triggers (automatic profile switching)
- Badges (visual indicators)
- Notifications (process completion)

**Impact**:
- Features unavailable in most distributions
- Confusing for users (features documented but don't work)
- Maintenance of VTE patches

**Actionable Steps**:
1. Clearly document which features require patched VTE
2. Provide build instructions for patched VTE
3. Consider contributing patches upstream to VTE project
4. Gracefully degrade when features unavailable
5. Add runtime detection of VTE capabilities

### Legacy Code from Terminix
**Status**: Historical artifact

**Background**: Tilix was renamed from Terminix

**Remnants**:
- Some references to old name in comments
- Migration guide for old settings

**Impact**: Minor, mostly cleanup

**Actionable Steps**:
1. Search and replace remaining Terminix references in comments
2. Can keep migration guide for historical users
3. Low priority cleanup task

---

## 🔵 Low Priority: Performance Optimization

### Startup Time
**Status**: Generally acceptable, room for improvement

**Potential Optimizations**:
- Lazy loading of color schemes
- Delayed loading of bookmarks
- Faster resource loading

**Actionable Steps**:
1. Profile startup time with D profiler
2. Identify bottlenecks
3. Optimize only if user complaints arise

### Memory Usage
**Status**: Typical for GTK+ application

**Considerations**:
- Each terminal spawns a shell process
- GTK+ and VTE have inherent memory requirements
- D's GC adds overhead

**Actionable Steps**:
1. Monitor for memory leaks (Valgrind)
2. Profile with large numbers of terminals
3. Optimize only if users report issues

---

## Technical Debt Summary

| Category | Priority | Estimated Effort | Blockers |
|----------|----------|------------------|----------|
| Maintainership | 🔴 Critical | Ongoing | Community building |
| GtkD Dependencies | 🟡 High | Medium | Investigation needed |
| Testing Infrastructure | 🟡 High | High | None |
| Code Documentation | 🟡 High | Medium | None |
| User Documentation | 🟡 High | Medium | None |
| Code Quality | 🟢 Medium | High | Requires tests first |
| Build Systems | 🟢 Medium | Low | None |
| VTE Patches | 🔵 Low | High | Upstream cooperation |
| Performance | 🔵 Low | Medium | Profiling needed |

---

## Contributing to Technical Debt Reduction

If you're interested in helping reduce Tilix's technical debt:

1. **Pick a specific item** from this document
2. **Open an issue** to discuss your approach
3. **Start small** - don't try to fix everything at once
4. **Document as you go** - improve docs while learning the code
5. **Add tests** - prevent future technical debt
6. **Communicate** - share your progress and challenges

For more information, see [CONTRIBUTING.md](CONTRIBUTING.md) (to be created) and [ROADMAP.md](ROADMAP.md).
