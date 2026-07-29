with open(r"C:\Users\win\.gemini\antigravity-ide\brain\90cb563e-64dd-4a9a-a8c6-0b6e9d0322f9\.system_generated\tasks\task-239.log", "r", encoding="utf-8") as f:
    log_content = f.read()

our_files = [
    "madrassa_progress_view.dart",
    "madrassa_dashboard.dart",
    "madrassa_providers.dart",
    "madrassa_local_storage.dart",
    "home_snapshot_widgets.dart"
]

print("Scanning analyzer output for errors in our modified/new files:")
has_error = False
for line in log_content.splitlines():
    if "error - " in line:
        for f in our_files:
            if f in line:
                print(f"  [ERROR] {line}")
                has_error = True

if not has_error:
    print("No errors found in any of our modified or new files!")
