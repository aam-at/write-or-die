# Contributing

Contributions to `write-or-die` are welcome.

## Development requirements

- Emacs 31.1 or newer
- `make`
- Optional: `package-lint` from MELPA

No third-party runtime package is required. `nerd-icons` is optional and must
stay optional.

## Local checks

Before opening a pull request, run:

```bash
make ci
```

If installed, also run:

```bash
make package-lint
```

## Design constraints

Keep these guarantees:

- no hard-coded theme colors;
- no required icon package or special font;
- no required audio backend;
- no document text in persistent history;
- destructive behavior remains opt-in;
- sprint state stays buffer-local;
- source checkouts and packaged installs must both find bundled assets.

## Style

- Use lexical binding.
- Keep public names under the `write-or-die-` namespace.
- Keep internal names under `write-or-die--`.
- Add ERT coverage for behavior changes.
- Run `checkdoc` and `package-lint` before a release.

## Releases

Update `CHANGELOG.md` and the `Version` header in `lisp/write-or-die.el`.
Use `vMAJOR.MINOR.PATCH` release tags, such as `v0.1.0`.
