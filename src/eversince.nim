## eversince: an event-modelling kit for Nim.
##
## Declare `event`, `command`, `view`, `query` and `processor` blocks, then call `sealModel`
## with the path of a model file. The compiler checks the code against the model file in both
## directions. See `README.md` and `spec/`.
##
## Not exported here, import them where wanted:
##   `eversince/picture`       the model file as an SVG
##   `eversince/store_sqlite`  the SQLite store (needs the system's SQLite library)

import eversince/[types, model, blocks, store, store_file, runtime, digest]
export types, model, blocks, store, store_file, runtime, digest
