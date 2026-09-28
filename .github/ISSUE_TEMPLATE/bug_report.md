---
name: Bug report
about: Install failed, mounted but not writable, or helper error. Attach the in-app diagnostic zip, or paste diagnose --json.
title: "[Bug] "
labels: bug
---

**macOS version**
<!-- Apple menu → About This Mac. Example: macOS 15.6 -->


**Chip**
<!-- Apple Silicon (supported) / Intel or other (not supported) -->


**Helper installed?**
<!-- Settings should show whether the mount helper is installed. Yes / No / Unknown -->


**Diagnose output (required)**

In the app: **Diagnose Environment…** → **Export Diagnostic Report**, then attach the zip (`NTFSMount-diagnose-YYYYMMDD.zip`). The zip may include **disk names**.

Alternatively, from a clone, paste the JSON below:

```bash
./scripts/ntfsmount diagnose --json
```

Output may include **disk names**. That is expected; redact anything you do not want public.

```json
<!-- paste diagnose --json here if you did not attach the zip -->
```

**Disk format**
<!-- What Disk Utility / Finder reports. Example: NTFS, exFAT, unknown -->


**Ejected from Windows?**
<!-- Yes (hibernation / Fast Startup likely) / No (fully ejected or shut down) / Unknown -->


**What happened**
<!-- Error text, dialog, or unexpected state. -->
