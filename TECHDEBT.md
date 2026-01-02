# Technical Debt

This document tracks the technical debt in the Tilix project.

## Maintainership

The most significant technical debt in Tilix is the lack of active maintainers. As noted in the `README.md` file, the project is currently in a state of minimal maintenance. This has a number of consequences, including:

* **Slow response to issues and pull requests**: Without active maintainers, it can take a long time for issues and pull requests to be addressed. This can be frustrating for users and contributors, and it can also lead to the accumulation of technical debt.

* **Lack of a clear roadmap**: Without active maintainers, there is no clear roadmap for the future of Tilix. This can make it difficult to attract new contributors, and it can also lead to the project stagnating.

* **Outdated dependencies**: Without active maintainers, it is more likely that the project's dependencies will become outdated. This can lead to security vulnerabilities and other problems.

## Documentation

The documentation for Tilix is another area of technical debt. While the `README.md` file provides a good overview of the project, there is a lack of in-depth documentation. This can make it difficult for new contributors to get started, and it can also make it difficult for users to understand how to use all of the features of Tilix.

Specifically, the following areas of documentation need to be improved:

* **Architectural overview**: There is no high-level overview of the Tilix architecture. This can make it difficult for new contributors to understand how the different parts of the project fit together.

* **Code documentation**: The code is not well-documented. This can make it difficult for new contributors to understand the code, and it can also make it difficult to maintain the code.

* **User documentation**: The user documentation is not comprehensive. This can make it difficult for users to understand how to use all of the features of Tilix.

## Testing

The testing for Tilix is another area of technical debt. While there are some tests, there is not a comprehensive test suite. This can make it difficult to ensure that the project is free of bugs, and it can also make it difficult to refactor the code without introducing new bugs.

## Dependencies

The project's dependencies are another potential source of technical debt. The `dub.json` file specifies that the project depends on `gtk-d:gtkd` and `gtk-d:vte`, both at version `3.11.0`. However, the latest publicly available version of GtkD is `3.10.0`.

Using a version of a library that is not publicly available can be a form of technical debt for the following reasons:

* **Lack of documentation**: It can be difficult to find documentation for a version of a library that is not publicly available.
* **Lack of support**: It can be difficult to get support for a version of a library that is not publicly available.
* **Instability**: A version of a library that is not publicly available may be unstable.
