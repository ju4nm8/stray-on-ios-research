#!/usr/bin/env python3
"""
validate_diagnostics.py — Static validation for configs, repos, and diagnostic assets.
"""

import sys
import os
import re
import configparser

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

FORBIDDEN_EXTENSIONS = {
    ".pak", ".uasset", ".ubulk", ".uptnl", ".app", ".ipa",
    ".mobileprovision", ".p12", ".cer", ".p8", ".key"
}

REQUIRED_INI_KEYS = [
    ("SystemSettings", "r.HZBOcclusion"),
    ("SystemSettings", "r.AllowOcclusionQueries"),
    ("SystemSettings", "r.EarlyZPass"),
]

def check_forbidden_files():
    print("Checking repository for forbidden proprietary binaries or credentials...")
    violations = []
    for root, dirs, files in os.walk(REPO_ROOT):
        # Ignore .git and build directories
        if ".git" in root or "build" in root or "node_modules" in root:
            continue
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in FORBIDDEN_EXTENSIONS:
                violations.append(os.path.relpath(os.path.join(root, f), REPO_ROOT))
    if violations:
        print(f"FAILED: Found forbidden file types in repository:\n" + "\n".join(violations))
        return False
    print("PASS: No forbidden proprietary files or credentials found.")
    return True

def check_ini_file(path):
    print(f"Validating INI file: {os.path.relpath(path, REPO_ROOT)}...")
    if not os.path.exists(path):
        print(f"WARNING: INI file not found at {path}")
        return True
    
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    # Verify no unclosed sections or corrupt characters
    sections = re.findall(r"^\[(.*?)\]", content, flags=re.MULTILINE)
    if not sections:
        print(f"FAILED: No sections found in {path}")
        return False

    print(f"  Found {len(sections)} sections: {', '.join(sections[:5])}...")
    
    # Check for critical Core.System plugin content paths if present
    if "Core.System" in sections:
        match = re.search(r"Paths=\.\./\.\./\.\./Hk_project/Plugins/GFur/Content", content)
        if match:
            print("  PASS: Found GFur plugin content path.")
        else:
            print("  WARNING: Core.System present but missing GFur content path.")

    return True

def check_secrets_and_pii():
    print("Scanning text files for private keys or certificates...")
    bad_patterns = [
        re.compile(r"-----BEGIN " + r"[A-Z ]*PRIVATE KEY-----"),
        re.compile(r"-----BEGIN " + r"CERTIFICATE-----"),
    ]
    violations = []
    for root, dirs, files in os.walk(REPO_ROOT):
        if ".git" in root or "build" in root or ".gemini" in root:
            continue
        for f in files:
            # Skip this validation script itself
            if f == "validate_diagnostics.py":
                continue
            if f.endswith((".m", ".h", ".py", ".sh", ".md", ".txt", ".ini", ".yml", ".yaml")):
                fpath = os.path.join(root, f)
                try:
                    with open(fpath, "r", encoding="utf-8", errors="ignore") as fh:
                        data = fh.read()
                        for pat in bad_patterns:
                            if pat.search(data):
                                violations.append(f"{os.path.relpath(fpath, REPO_ROOT)} matched {pat.pattern}")
                except Exception as e:
                    pass
    if violations:
        print("FAILED: Potential secret leak detected:\n" + "\n".join(violations))
        return False
    print("PASS: No private keys or certificates detected.")
    return True

def main():
    print("=== Running Stray iOS Static & Diagnostic Validation ===")
    ok = True
    ok = check_forbidden_files() and ok
    ok = check_secrets_and_pii() and ok

    ini_targets = [
        os.path.join(REPO_ROOT, "configs", "Engine.ini"),
        os.path.join(REPO_ROOT, "community", "diagnostics", "Engine.sanitized.ini"),
    ]
    for target in ini_targets:
        if os.path.exists(target):
            ok = check_ini_file(target) and ok

    if not ok:
        print("=== VALIDATION FAILED ===")
        sys.exit(1)
    print("=== ALL STATIC DIAGNOSTIC CHECKS PASSED ===")

if __name__ == "__main__":
    main()
