I will modify the `calculateMD5` method in `Services/DirectoryService.swift` to use the **file name** for MD5 calculation instead of the file content.

This optimization avoids reading the entire file stream, which can be resource-intensive for large files.

**Changes:**
1.  Update `calculateMD5(for url: URL)` in `DirectoryService.swift`.
2.  The new implementation will:
    *   Extract the `lastPathComponent` (filename) from the URL.
    *   Convert the filename string to UTF-8 data.
    *   Calculate the MD5 hash of this data using `Insecure.MD5`.
    *   Return the hex string representation of the hash.

This change is safe and directly addresses the performance concern raised by the user.