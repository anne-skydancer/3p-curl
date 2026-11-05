# 3p-curl (Vulkanstorm)

[Autobuild][]-packaged libcurl for the Vulkanstorm viewer, forked from
secondlife/3p-curl. Prototype: built and tested locally on windows64; not
published. See the viewer's `doc/tls-upgrade-patches.md`.

Branches:

- `vks/7.54.1-openssl35`: LL's curl 7.54.1 source and build script,
  unchanged, rebuilt against the Vulkanstorm OpenSSL 3.5.9 package. Only
  `autobuild.xml` changes (the `openssl` dependency). This is the curl that
  ships with the OpenSSL step.
- `vks/curl-8.23.0`: curl 8.23.0 from the signed release tarball, HTTP and
  HTTPS only, static, OpenSSL 3.5 + nghttp2 + zlib-ng.

The `openssl` entry in `autobuild.xml` points at a local archive
(`file:///C:/Users/annes/source/repos/work/3p-openssl/...`) while the OpenSSL
package is unpublished; replace it with the release URL and its hash before
publishing, and add the linux64 archive the same way.

```
autobuild install -A 64
autobuild build -A 64
autobuild package -A 64 --archive-format tzst
```

[Autobuild]: https://wiki.secondlife.com/wiki/Autobuild
