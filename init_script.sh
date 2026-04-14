#!/bin/bash
set -euo pipefail

log() { echo "[init_r_volume] $*"; }

# ── CONFIGURE THESE FOR YOUR ENVIRONMENT ─────────────────────────────
VOLUME_BASE="/Volumes/<catalog>/<schema>/<volume>"
PKG_DIR="${VOLUME_BASE}/r-packages"   # where your .tar.gz files live
R_LIB="${VOLUME_BASE}/r-lib"          # persistent R library on the volume
# ──────────────────────────────────────────────────────────────────────

log "Using package dir: ${PKG_DIR}"
log "Using R library:   ${R_LIB}"

mkdir -p "${R_LIB}"

# If no tarballs, just set up the library path and exit
shopt -s nullglob
TARBALLS=( "${PKG_DIR}"/*.tar.gz )
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  log "No .tar.gz files found in ${PKG_DIR} — skipping install, only wiring .libPaths()."
else
  log "Found ${#TARBALLS[@]} package tarballs to install."

  export R_INIT_LIB="${R_LIB}"
  export R_INIT_PKG_DIR="${PKG_DIR}"

  /usr/bin/Rscript - <<'RSCRIPT'
    lib_dir  <- Sys.getenv("R_INIT_LIB")
    pkg_dir  <- Sys.getenv("R_INIT_PKG_DIR")

    dir.create(lib_dir, showWarnings = FALSE, recursive = TRUE)

    tarballs  <- list.files(pkg_dir, pattern = "\\.tar\\.gz$", full.names = TRUE)
    if (length(tarballs) == 0L) {
      message("[init_r_volume] No tarballs found at runtime, nothing to install.")
      quit(status = 0L)
    }

    # Only check this custom lib, not system libs
    installed <- rownames(installed.packages(lib.loc = lib_dir, noCache = TRUE))
    pkg_names <- sub("_.*", "", basename(tarballs))
    pending   <- tarballs[!pkg_names %in% installed]

    if (length(pending) == 0L) {
      message("[init_r_volume] All packages already installed in ", lib_dir)
      quit(status = 0L)
    }

    message("[init_r_volume] Installing ", length(pending), " packages into ", lib_dir, " ...")

    remaining <- pending
    for (i in seq_len(3L)) {
      if (length(remaining) == 0L) break
      results <- vapply(
        remaining,
        function(p) {
          nm <- sub("_.*", "", basename(p))
          message("  [install] ", nm)
          ok <- tryCatch({
            install.packages(p, repos = NULL, type = "source",
                             lib = lib_dir, quiet = TRUE)
            TRUE
          }, error = function(e) {
            message("  [FAIL] ", nm, ": ", conditionMessage(e))
            FALSE
          })
          ok
        },
        logical(1L)
      )
      remaining <- remaining[!results]
    }

    if (length(remaining) > 0L) {
      message("[init_r_volume] WARN: ", length(remaining), " packages failed to install:")
      message(paste(sub("_.*", "", basename(remaining)), collapse = ", "))
      quit(status = 1L)
    }

    message("[init_r_volume] All packages installed successfully into ", lib_dir)
RSCRIPT

fi

# Wire the volume-backed library into Rprofile.site so every R session sees it
R_HOME_ETC="$(/usr/bin/Rscript -e 'cat(R.home("etc"))')"
RPROFILE_SITE="${R_HOME_ETC}/Rprofile.site"

if ! grep -q "init_r_volume" "${RPROFILE_SITE}" 2>/dev/null; then
  cat >> "${RPROFILE_SITE}" <<RPROFILE_EOF

# Added by init_r_volume.sh — prefer volume-backed R library
local({
  vol_lib <- "${R_LIB}"
  if (dir.exists(vol_lib)) {
    .libPaths(c(vol_lib, .libPaths()))
  }
})
RPROFILE_EOF
  log "Updated Rprofile.site: ${RPROFILE_SITE}"
else
  log "Rprofile.site already configured for volume-backed R lib."
fi

log "Init script complete. R library: ${R_LIB}"
