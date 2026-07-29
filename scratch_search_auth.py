import os

for root, dirs, files in os.walk("e:/GMWF/gmwf/lib"):
    for file in files:
        if file.endswith(".dart"):
            path = os.path.join(root, file)
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
                if "signInAnonymously" in content or "signInWith" in content:
                    print(f"Auth found in {path}")
