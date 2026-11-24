# Vendored: Planet Kubb Notation's reader

`notation-parser.js`, `canonical.js` and `kubb.js` are pk-kubb-score's own files at the
tag in `SOURCE`, byte for byte (`SHA256SUMS`). `scripts/vendor-notation.sh sync` copies
them and `check` proves them; never edit them here. `Reader.swift` runs them in
JavaScriptCore, turning each ES module into a classic script when it loads.

Kubb Engine v1.1.0 distributes the same reader, canonical writer and grammar code
under the [MIT License](../../../../LICENSE). The generated parser also includes
code from Peggy, covered by its [MIT notice](LICENSE-Peggy.txt).
