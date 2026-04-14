from datetime import datetime

BASE_PATH = "dbfs:/path/to/your/folder"   # <-- update this

folders = dbutils.fs.ls(BASE_PATH)

results = []

for f in folders:
    # Skip files — we only want directories
    if not f.path.endswith("/"):
        continue

    # Format timestamp
    ts = datetime.fromtimestamp(f.modificationTime / 1000).strftime("%m/%d/%Y %H:%M:%S")

    # Look for log files inside this folder
    logs = dbutils.fs.ls(f.path)
    log_files = [lf.path for lf in logs if lf.path.endswith("stderr.log") or lf.path.endswith("stdout.log")]

    found = False
    matched_logs = []

    for log_path in log_files:
        try:
            content = dbutils.fs.head(log_path, 50000)  # read first 50 KB
            if "init_r_volume" in content:
                found = True
                matched_logs.append(log_path)
        except:
            pass  # ignore missing/unreadable logs

    if found:
        results.append({
            "folder": f.path,
            "timestamp": ts,
            "logs_with_match": matched_logs
        })

results
