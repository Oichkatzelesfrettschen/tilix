# Roadmap

This document outlines the strategic roadmap for the Tilix project, organized by time horizons and measurable goals.

## Vision Statement

**Make Tilix the most powerful and user-friendly tiling terminal emulator for Linux**, with an active community of contributors and maintainers, excellent documentation, and sustainable long-term development.

---

## Immediate Priorities (Next 3-6 Months)

These are critical foundational improvements that will enable future development.

### 1. 🔴 Stabilize Maintainership (Critical)

**Goal**: Establish a sustainable maintainer structure

**Success Metrics**:
- [ ] At least 2-3 active maintainers with commit rights
- [ ] 80% of new issues receive a response within 7 days
- [ ] Average PR review time under 14 days
- [ ] Monthly triage of issue backlog

**Key Actions**:
- Create GOVERNANCE.md documenting decision-making process
- Establish maintainer roles and responsibilities
- Set up rotating issue triage schedule
- Create MAINTAINERS.md listing active maintainers and their areas
- Recruit from active contributors (see [issue #1700](https://github.com/gnunn1/tilix/issues/1700))

**Dependencies**: Community engagement, time commitment from volunteers

---

### 2. 🟡 Resolve Dependency Issues (High Priority)

**Goal**: Clarify and stabilize build dependencies

**Success Metrics**:
- [ ] GtkD version clearly documented with source
- [ ] New contributors can build successfully on first try (>80% success rate)
- [ ] CI builds passing consistently
- [ ] Docker dev container available

**Key Actions**:
- Investigate GtkD 3.11.0 vs 3.10.0 discrepancy
- Document exact dependency requirements in BUILD.md
- Create Docker/Podman development container
- Add CI checks for multiple D compiler versions (DMD, LDC)
- Provide pre-built binaries for major distributions

**Dependencies**: Investigation time, testing across platforms

---

### 3. 🟡 Improve Documentation (High Priority)

**Goal**: Make Tilix accessible to new users and contributors

**Success Metrics**:
- [ ] CONTRIBUTING.md created with clear guidelines
- [ ] ARCHITECTURE.md comprehensive (✅ Done)
- [ ] USER_GUIDE.md with tutorials and examples
- [ ] 90% of public APIs documented
- [ ] Generated API documentation published

**Key Actions**:
- Create CONTRIBUTING.md (development setup, coding standards, PR process)
- Write USER_GUIDE.md (feature overview, configuration examples)
- Add DDoc comments to all public APIs
- Generate and publish API documentation to GitHub Pages
- Create video tutorials for complex features (triggers, badges, layouts)
- Improve wiki organization and searchability

**Dependencies**: None - can start immediately

**Status**: ARCHITECTURE.md and TECHDEBT.md significantly expanded ✅

---

### 4. 🟡 Address Critical Bugs (High Priority)

**Goal**: Fix most impactful bugs affecting user experience

**Success Metrics**:
- [ ] All "critical" and "high" severity bugs triaged
- [ ] Top 10 most-commented issues addressed
- [ ] Zero known security vulnerabilities
- [ ] Crash reports reduced by 50%

**Key Actions**:
- Triage all open issues by severity and impact
- Fix crashes and data loss bugs first
- Address accessibility issues
- Resolve memory leaks
- Fix display/rendering issues on different DEs

**Dependencies**: Maintainer availability, reproducible test cases

---

## Short-Term Goals (6-12 Months)

Building on the foundation, these goals improve quality and contributor experience.

### 5. 🟡 Establish Testing Infrastructure (High Priority)

**Goal**: Enable confident refactoring and prevent regressions

**Success Metrics**:
- [ ] Unit test framework set up with dub test
- [ ] 30%+ code coverage on core logic
- [ ] CI runs tests on every PR
- [ ] Integration tests for critical workflows
- [ ] No regressions in releases

**Key Actions**:
- **Phase 1**: Unit tests for utility functions, data models, serialization
- **Phase 2**: Tests for command-line parsing, preferences management
- **Phase 3**: Integration tests with Xvfb for GTK components
- **Phase 4**: Smoke tests for critical user workflows
- Set up code coverage reporting
- Add test status badge to README

**Dependencies**: Time investment, learning GTK testing approaches

---

### 6. 🟢 Code Quality Improvements (Medium Priority)

**Goal**: Make codebase more maintainable and approachable

**Success Metrics**:
- [ ] Static analysis tools integrated (dscanner)
- [ ] Code style consistently applied
- [ ] Large files refactored (appwindow.d, session.d)
- [ ] Error handling standardized
- [ ] Reduced compiler warnings to zero

**Key Actions**:
- Integrate dscanner or similar static analysis
- Define and document code style guide
- Incrementally refactor large files (break into logical modules)
- Standardize error handling patterns
- Add pre-commit hooks for code quality

**Dependencies**: Testing infrastructure (to prevent regressions during refactoring)

---

### 7. 🟢 Improve Development Experience (Medium Priority)

**Goal**: Make contributing to Tilix easier and more enjoyable

**Success Metrics**:
- [ ] Build time under 30 seconds for incremental builds
- [ ] One-command setup for new developers
- [ ] VS Code and other IDE integration documented
- [ ] 90% of new contributors successfully build on first try

**Key Actions**:
- Create VS Code devcontainer configuration
- Document debugger setup (GDB with D)
- Create Makefile or justfile for common tasks
- Optimize build configuration for faster iteration
- Document common development workflows

**Dependencies**: None

---

### 8. 🟢 Feature Parity and Polish (Medium Priority)

**Goal**: Ensure existing features work reliably

**Success Metrics**:
- [ ] All documented features working as expected
- [ ] Quake mode fully functional
- [ ] Custom hyperlinks robust
- [ ] Drag-and-drop between windows reliable
- [ ] Profile switching works consistently

**Key Actions**:
- Audit all features mentioned in README and wiki
- Fix known issues with each feature
- Add tests for critical features
- Improve error messages and user feedback
- Polish UI/UX rough edges

**Dependencies**: Bug fixing, testing infrastructure

---

## Medium-Term Goals (1-2 Years)

Strategic improvements and new capabilities.

### 9. 🟢 VTE Integration and Patches (Medium Priority)

**Goal**: Improve terminal functionality and reduce maintenance burden

**Success Metrics**:
- [ ] Triggers and badges work without patched VTE (or clearly documented alternative)
- [ ] Runtime detection of VTE capabilities
- [ ] Graceful degradation for unsupported features
- [ ] Build instructions for patched VTE available

**Key Actions**:
- Contribute patches upstream to VTE project
- Work with VTE maintainers on API extensions
- Implement fallback behavior for features requiring patches
- Document VTE version requirements clearly
- Provide pre-built VTE packages for popular distributions

**Dependencies**: Collaboration with VTE project, testing across distributions

---

### 10. 🟢 Performance Optimization (Medium Priority)

**Goal**: Ensure Tilix performs well with many terminals

**Success Metrics**:
- [ ] Startup time under 1 second (from cold start)
- [ ] Smooth performance with 20+ terminals
- [ ] Memory usage within 10% of competitors
- [ ] No UI lag when scrolling or switching terminals

**Key Actions**:
- Profile startup time and optimize bottlenecks
- Lazy-load resources (color schemes, bookmarks)
- Optimize terminal rendering and layout updates
- Reduce memory footprint where possible
- Profile with large numbers of terminals

**Dependencies**: Profiling tools, benchmark suite

---

### 11. 🔵 Platform Expansion (Low Priority)

**Goal**: Improve Tilix support across Linux distributions

**Success Metrics**:
- [ ] Packages available for top 10 Linux distributions
- [ ] Flatpak and Snap packages maintained
- [ ] AppImage available
- [ ] Package installation documented for all major distros

**Key Actions**:
- Work with distribution maintainers
- Set up automated packaging pipeline
- Create and maintain Flatpak manifest
- Document packaging process for new distributions
- Ensure compatibility with different desktop environments (KDE, XFCE, etc.)

**Dependencies**: Distribution maintainer cooperation, testing resources

---

### 12. 🔵 Accessibility (Low Priority but Important)

**Goal**: Make Tilix accessible to users with disabilities

**Success Metrics**:
- [ ] Screen reader support verified
- [ ] Keyboard navigation complete (no mouse required)
- [ ] High contrast themes available
- [ ] Accessibility compliance (WCAG 2.1 where applicable)

**Key Actions**:
- Audit accessibility with screen readers (Orca)
- Ensure all functions keyboard-accessible
- Test with high contrast themes
- Add accessibility documentation
- Implement accessibility-focused features (font scaling, color blindness support)

**Dependencies**: Accessibility testing expertise

---

## Long-Term Vision (2+ Years)

Strategic direction and major initiatives.

### 13. 🔵 GTK 4 Migration (Future Planning)

**Goal**: Ensure long-term compatibility with modern GTK

**Current Status**: Evaluation phase

**Success Metrics**:
- [ ] Migration feasibility assessed
- [ ] Breaking changes documented
- [ ] Migration plan created
- [ ] Prototype GTK 4 version functional

**Key Actions**:
- Monitor GTK 4 adoption in major distributions
- Evaluate GtkD GTK 4 support maturity
- Assess VTE widget GTK 4 compatibility
- Create migration plan with phased approach
- Consider supporting both GTK 3 and GTK 4 branches temporarily

**Timeline**: Begin assessment in late 2026, migration in 2027+ (depending on ecosystem readiness)

**Dependencies**: GTK 4 adoption, GtkD GTK 4 support, VTE GTK 4 compatibility

---

### 14. 🔵 Advanced Features (Exploratory)

**Goal**: Differentiate Tilix with unique capabilities

**Potential Features** (to be evaluated based on community interest):
- **Terminal multiplexing**: Built-in tmux-like functionality
- **Remote terminal support**: SSH session management
- **Container integration**: Direct Docker/Podman terminal access
- **Terminal sharing**: Collaborative terminal sessions
- **Cloud sync**: Sync settings/sessions across machines
- **Plugin system**: Allow community extensions
- **AI integration**: Command suggestions, error explanations
- **Advanced tiling**: More layout algorithms (Fibonacci, Golden ratio)

**Approach**:
- Gather community feedback on desired features
- Prototype features in experimental branch
- Evaluate implementation complexity vs. value
- Prioritize based on user demand and maintainability

**Dependencies**: Stable maintainership, solid testing, community input

---

### 15. 🟢 Community Building (Ongoing)

**Goal**: Build a thriving, sustainable community

**Success Metrics**:
- [ ] 1,000+ GitHub stars
- [ ] Active Discord/Matrix/IRC community
- [ ] Regular contributor meetups (virtual)
- [ ] Comprehensive contributor onboarding
- [ ] 10+ regular contributors

**Key Actions**:
- Create community chat (Discord, Matrix, or IRC)
- Establish "good first issue" program for newcomers
- Create contributor recognition program
- Host virtual contributor meetups quarterly
- Engage with GNOME and terminal emulator communities
- Present at Linux/GNOME conferences
- Create social media presence for updates

**Dependencies**: Maintainer time, community engagement

---

### 16. 🔵 Sustainability and Funding (Exploratory)

**Goal**: Ensure long-term project sustainability

**Potential Approaches**:
- **Sponsorship**: GitHub Sponsors, Open Collective
- **Corporate backing**: Seek company sponsorship
- **Grants**: Apply for FOSS development grants
- **Bounties**: Offer bounties for specific features/fixes

**Considerations**:
- Maintain project independence and FOSS values
- Transparent fund management
- Fair compensation for maintainers/contributors
- Avoid feature paywalls or premium versions

**Dependencies**: Community growth, maintainer consensus

---

## Success Indicators

### Project Health Metrics
- **Issue Response Time**: 80% of issues responded to within 7 days
- **PR Merge Time**: Average PR merged or closed within 14 days
- **Release Cadence**: Regular releases every 3-6 months
- **Test Coverage**: 50%+ code coverage on core functionality
- **Documentation Coverage**: 90%+ of public APIs documented
- **Build Success Rate**: 95%+ successful builds for new contributors
- **Community Growth**: 10+ active contributors, 1,000+ stars

### User Satisfaction
- **Bug Reports**: Decreasing trend in critical/high bugs
- **Feature Requests**: Clear prioritization and roadmap alignment
- **User Feedback**: Positive sentiment in issue discussions
- **Adoption**: Growing number of packages and installations

---

## How to Contribute to Roadmap Items

### Getting Involved
1. **Choose an item** that interests you from this roadmap
2. **Check existing issues** to see if someone is already working on it
3. **Open a discussion issue** to propose your approach
4. **Start with small PRs** - break large items into incremental changes
5. **Communicate progress** - update issues with your status
6. **Ask for help** - maintainers and community are here to support

### For Maintainers
- **Review this roadmap quarterly** and update based on progress
- **Prioritize based on community needs** - be flexible
- **Celebrate milestones** - acknowledge progress and contributors
- **Track metrics** - use GitHub insights and project boards
- **Adjust priorities** - roadmaps are living documents

---

## Roadmap Revision History

This roadmap will be reviewed and updated every 3-6 months to reflect:
- Progress on existing goals
- New priorities based on community feedback
- Changes in the GTK/Linux ecosystem
- Maintainer capacity and focus

**Last Updated**: 2026-01-02
**Next Review**: 2026-04-02

---

## Related Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) - Understanding Tilix's structure
- [TECHDEBT.md](TECHDEBT.md) - Technical debt to address
- [CONTRIBUTING.md](CONTRIBUTING.md) - How to contribute (to be created)
- [README.md](README.md) - Project overview and getting started

---

## Conclusion

This roadmap balances immediate needs (maintainership, dependencies, documentation) with long-term vision (GTK 4, community, sustainability). The focus is on building a solid foundation before pursuing advanced features.

**Remember**: The best terminal emulator is one that is actively maintained, well-documented, thoroughly tested, and supported by a vibrant community. That's what we're building together.
