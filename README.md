# cozroe

A gemini file server with a few extra features, implemented in Zig using [`zig-serve`](https://github.com/MasterQ32/zig-serve).

This is not meant to be a generic server, and is being tailored for my use cases, which will be documented more as I figure them out.

## Build

Requires [zigmod package manager](https://github.com/nektro/zigmod). Fetch all dependencies:

```bash
zigmod fetch
git submodule init
git submodule update
```

Apply custom patches to fix compilation issues, and modify logging statements:

```bash
./apply-patches.sh
```

Then build

```
zig build -Drelease-small
```

```
$ ./zig-out/bin/cozroe --help
    -h, --help
            Display this help and exit.

        --cert <str>
            Public certificate.

        --private_key <str>
            Private key.

        --dir <str>
            Directory to serve.

        --port <u16>
            Port to listen on.

        --database <str>
            SQLite database to store traffic logs.
```