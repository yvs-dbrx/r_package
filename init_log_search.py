from datetime import datetime

BASE_PATH = "/Volumes/<catalog>/<schema>/<volume>/your-folder"

files = dbutils.fs.ls(BASE_PATH)

results = []

for f in files:
    # 1. Format timestamp
    ts = datetime.fromtimestamp(f.modificationTime / 1000).strftime("%m/%d/%Y %H:%M:%S")

    # 2. Look for logs inside this path
    init_hits = []
    for logname in ["stdout.log", "stderr.log"]:
        log_path = f"{f.path.rstrip('/')}/{logname}"
        try:
            content = dbutils.fs.head(log_path, 50000)  # read first 50 KB
            if "init_volume" in content:
                init_hits.append(logname)
        except Exception:
            pass  # log file may not exist

    results.append({
        "path": f.path,
        "timestamp": ts,
        "init_volume_found_in": init_hits
    })

results
