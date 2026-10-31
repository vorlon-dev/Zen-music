# Contributing to ZenMusic

Thank you for your interest in contributing to ZenMusic! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Handling Sensitive Information](#handling-sensitive-information)
- [Contributing Guidelines](#contributing-guidelines)
- [Pull Request Process](#pull-request-process)
- [Issue Guidelines](#issue-guidelines)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Release Process](#release-process)
- [Community Guidelines](#community-guidelines)

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md):

### Our Pledge

We are committed to providing a welcoming and inspiring community for all. We pledge to:

- Be respectful and inclusive
- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Accept constructive criticism gracefully
- Focus on what's best for the community
- Show empathy towards other community members

### Unacceptable Behavior

- The use of sexualized language or imagery
- Trolling, insulting/derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information without explicit permission
- Other conduct which could reasonably be considered inappropriate in a professional setting

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- Android Studio or VS Code with the Flutter and Dart plugins
- JDK 17 or later
- Android SDK and an Android device or emulator
- Git
- Basic knowledge of Dart and Flutter development

ZenMusic targets **Android only**.

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/Zen-music.git
   cd Zen-music
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/vorlon-dev/Zen-music.git
   ```

## Development Setup

### 1. Environment Setup

1. **Install Flutter** and run `flutter doctor` until the Android toolchain shows no issues
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Run the app** on a connected Android device or emulator:
   ```bash
   flutter run
   ```

### 2. Build the Project

```bash
# Debug build
flutter build apk --debug

# Release builds
flutter build apk --release --split-per-abi   # per-ABI splits
flutter build apk --release                   # universal APK
```

If no keystore is configured, release builds fall back to debug signing so the build still works. Use your own release keystore for any APK you distribute, because Android only installs updates signed with the same key.

## Handling Sensitive Information

When contributing to ZenMusic, it's crucial to handle sensitive information properly.

### Files That Should Never Be Committed

1. **local.properties**
    - Contains your local SDK path
2. **Signing files**
    - `*.keystore`, `*.jks` and `key.properties` contain app signing keys and passwords
3. **API keys and secrets**
    - Never commit tokens, keys, or `.env` files
4. **Build outputs**
    - Never commit `.apk`, `.aab`, or the `build/` directory
5. **IDE-specific files**
    - Most `.idea/` contents should not be committed

### Best Practices

- **API Keys**: Never hardcode API keys in the source code
- **Credentials**: Never include usernames, passwords, or tokens in commits
- **Personal Information**: Remove any personal information before committing
- **Before Committing**: Always review your changes to ensure no sensitive information is included
- **If Accidentally Committed**: If you accidentally commit sensitive information, contact the maintainer immediately

## Contributing Guidelines

### Types of Contributions

We welcome various types of contributions:

- **Bug Fixes**: Fix existing issues and improve stability
- **New Features**: Add new functionality and capabilities
- **Documentation**: Improve documentation and guides
- **UI/UX Improvements**: Enhance user interface and experience
- **Performance**: Optimize app performance and memory usage
- **Testing**: Add or improve tests and test coverage
- **Code Quality**: Refactor code and improve architecture
- **Security**: Identify and fix security vulnerabilities

### Before You Start

1. **Check existing issues** to see if your idea is already being discussed
2. **Create an issue** for significant changes to discuss the approach
3. **Fork the repository** and create a feature branch
4. **Follow the coding standards** outlined below

## Pull Request Process

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-number-description
```

### 2. Make Your Changes

- Write clean, readable code
- Follow the existing code style
- Add comments for complex logic
- Update documentation if needed
- Add tests for new features

### 3. Test Your Changes

```bash
# Format code
dart format .

# Static analysis
flutter analyze

# Run tests
flutter test

# Build the project
flutter build apk --debug
```

Please also test on a real device before submitting.

### 4. Commit Your Changes

Use clear, descriptive commit messages:

```bash
git add .
git commit -m "feat: add dark mode toggle to settings

- Add dark mode preference in settings
- Update theme switching logic

Fixes #123"
```

### 5. Push and Create PR

```bash
git push origin feature/your-feature-name
```

**PULL REQUEST FORMATTING RULES:**
When creating a Pull Request on GitHub, please follow these rules. PRs that do not meet them may be closed or sent back for changes.

1. **Title Format:** Follow Conventional Commits (e.g., `feat(ui): add new player screen` or `fix(playback): resolve crash on skip`).
2. **Detailed Description:** The PR body must clearly explain *what* changed and *why*. Vague descriptions like "fixed bug" or "UI improvements" are not accepted.
3. **Reference Issues:** Always link related issues using keywords (e.g., `Fixes #123` or `Closes #456`).
4. **Screenshots/Videos:** **Required** for any UI/UX changes.
5. **Testing Instructions:** Provide clear, step-by-step instructions on how the reviewer can test your changes.
6. **Release Notes:** Your PR title and description may be used directly in release notes. Keep them grammatically correct and professional.

Please keep pull requests focused on a single change.

## Issue Guidelines

### Bug Reports

When reporting bugs, please include:

1. **Clear title** describing the issue
2. **Steps to reproduce** the bug
3. **Expected behavior** vs actual behavior
4. **Screenshots** or videos if applicable
5. **Device information** (Android version, device model)
6. **App version** and install source (GitHub, Obtainium, nightly, etc.)
7. **Logs** if available
8. **Music source** involved (JioSaavn, YouTube Music) if relevant

### Feature Requests

When requesting features, please include:

1. **Clear title** describing the feature
2. **Detailed description** of the feature
3. **Use case** and why it would be useful
4. **Mockups** or examples if applicable
5. **Alternative solutions** you've considered

## Coding Standards

### Dart Style

- Follow the [Effective Dart](https://dart.dev/effective-dart) guidelines
- Run `dart format .` before committing
- Fix all `flutter analyze` warnings in the code you touch
- Use meaningful variable and function names
- Prefer `final` and `const` where possible
- Keep widgets small and reusable

### Flutter Best Practices

- Follow the project's existing state management approach
- Keep UI, business logic and data access separated
- Dispose controllers, streams and subscriptions properly
- Avoid blocking the UI thread with heavy work
- Handle network and playback errors gracefully

### Code Organization

Follow the existing structure under `lib/`. Put new code next to similar existing code, and keep each file focused on one responsibility.

### Naming Conventions

- **Classes**: UpperCamelCase (`MusicPlayer`)
- **Functions and variables**: lowerCamelCase (`playMusic()`, `currentSong`)
- **Constants**: lowerCamelCase (`maxVolume`)
- **Files and packages**: snake_case (`music_player.dart`)

## Testing

- Write unit tests for business logic and utilities
- Write widget tests for critical UI flows where practical
- Test on a real device, including different screen sizes and orientations

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/music_player_test.dart
```

## Documentation

- Document public APIs with `///` doc comments
- Add inline comments for complex logic
- Keep the README updated when features change
- Document configuration changes

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `style:` for formatting changes
- `refactor:` for code refactoring
- `test:` for adding tests
- `chore:` for maintenance tasks

Examples:
```
feat: add playlist sharing functionality
fix: resolve crash when switching songs
docs: update build instructions
```

## Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/). The version is set in `pubspec.yaml`:
- **MAJOR**: Incompatible changes
- **MINOR**: New functionality (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Signing

Release APKs are signed with a release key so users can update between versions. The key is never committed.

1. Create a keystore once and keep it (and its passwords) safe. Losing it means users must uninstall to update:
   ```bash
   keytool -genkeypair -v -keystore zenmusic-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias zenmusic
   ```
2. Encode it as base64:
   ```bash
   base64 -w0 zenmusic-release.jks                                                     # Linux / macOS
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("zenmusic-release.jks"))           # Windows PowerShell
   ```
3. Add these GitHub repository secrets (Settings > Secrets and variables > Actions):
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

The release and nightly workflows write `android/key.properties` from these secrets. Without them, builds fall back to the debug key (for testing only).

### Release Checklist

- [ ] All tests pass
- [ ] Documentation is updated
- [ ] Version number is bumped in `pubspec.yaml`
- [ ] APKs are signed with the release keystore
- [ ] Release notes are prepared

## Community Guidelines

### Communication Channels

- **GitHub Discussions**: For general questions and discussions
- **GitHub Issues**: For bug reports and feature requests
- **Pull Requests**: For code contributions and reviews

### Getting Help

If you have questions about contributing:

1. Check the [GitHub Discussions](https://github.com/vorlon-dev/Zen-music/discussions)
2. Create a new discussion
3. Contact the maintainer through GitHub

### Recognition

Contributors will be recognized in:
- README.md contributors section
- Release notes
- GitHub contributors page

Thank you for contributing to ZenMusic!

---

<div align="center">

**Made with ❤️ by [vorlon-dev](https://github.com/vorlon-dev)**

</div>