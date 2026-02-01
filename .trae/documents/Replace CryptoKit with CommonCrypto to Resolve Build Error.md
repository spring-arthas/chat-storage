I will resolve the "Cannot find 'CryptoKit' in scope" error by replacing the dependency with **CommonCrypto**, which is a lower-level system framework that is universally available on macOS and less prone to module linking issues.

**Plan:**
1.  Modify `Services/DirectoryService.swift` to:
    *   Remove `import CryptoKit`.
    *   Add `import CommonCrypto`.
    *   Rewrite the `calculateMD5` method to use the C-based `CC_MD5` function instead of the Swift `CryptoKit` API.

This approach maintains the same functionality (hashing the filename) but bypasses the Swift framework linking issue.