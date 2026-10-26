# Zig Weekly

A weekly, community-driven digest of what is happening in the Zig ecosystem:
language and compiler changes, ZLS, community projects, articles, events and jobs.

Website: <https://zigweekly.com>

This is an independent community project, not affiliated with the Zig Software Foundation.

## How it works

- `draft/` holds the issue being prepared. Anyone can open a pull request to add a link.
- Publishing an issue means moving its file from `draft/` to `issues/` in a pull request.
  When that merges to `main`, the site is built and deployed automatically.
- `zw` (in `src/`) is the small tool that turns issue Markdown files into the website,
  an Atom feed, an RSS feed, and email and plain-text versions.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: one link per pull request, against the file in `draft/`.

Want something removed or credited differently? Open an issue or pull request, or email hello@zigweekly.com.

## Build locally

You need [Zig](https://ziglang.org/download/) 0.17.0 or newer.

```sh
zig build test
zig build run -- site issues out --url https://zigweekly.com
```

Preview a single issue, or the draft:

```sh
zig build run -- render draft/<file>.md --to web -o /tmp/preview.html
```

The build refuses to publish an issue that still has a `<!-- DRAFT` marker in it.

## License

Code: MIT, see [LICENSE](LICENSE). Newsletter text: CC BY-SA 4.0, see [LICENSE-CONTENT.md](LICENSE-CONTENT.md).
