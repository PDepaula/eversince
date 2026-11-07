# `import eversince` works from examples/, tests/ and tools/ without installing the package.
switch("path", thisDir() & "/src")
# Compiled programs go to bin/ (ignored by git), not next to the source.
switch("outdir", thisDir() & "/bin")
