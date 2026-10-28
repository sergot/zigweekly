const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;
const md = @import("md.zig");

const usage =
    \\usage:
    \\  zw render <issue.md> [--to web|email|text] [-o out]
    \\  zw site <issues_dir> <out_dir> [--title T] [--url https://site] [--form-action URL]
    \\
    \\render: one issue to stdout (or -o file). web = full HTML page,
    \\        email = table layout with inline styles, text = plain text.
    \\site:   writes <out>/index.html (past issues, subscribe form if --form-action),
    \\        <out>/feed.xml (Atom) and rss.xml (RSS 2.0), only with --url,
    \\        <out>/issues/<name>.html, and <out>/email/<name>.{html,txt}.
    \\
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) usageExit();
    if (std.mem.eql(u8, args[1], "render")) return cmdRender(gpa, io, args[2..]);
    if (std.mem.eql(u8, args[1], "site")) return cmdSite(gpa, io, args[2..]);
    usageExit();
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn usageExit() noreturn {
    fail("{s}", .{usage});
}

const max_file_bytes = 1 << 20;

fn cmdRender(gpa: std.mem.Allocator, io: Io, args: []const [:0]const u8) !void {
    var path: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var fmt: md.Format = .web;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--to")) {
            i += 1;
            if (i >= args.len) usageExit();
            fmt = std.meta.stringToEnum(md.Format, args[i]) orelse usageExit();
        } else if (std.mem.eql(u8, args[i], "-o")) {
            i += 1;
            if (i >= args.len) usageExit();
            out = args[i];
        } else path = args[i];
    }
    const src_path = path orelse usageExit();

    const src = Io.Dir.cwd().readFileAlloc(io, src_path, gpa, .limited(max_file_bytes)) catch |e|
        fail("error: cannot read {s}: {t}\n", .{ src_path, e });
    defer gpa.free(src);

    var aw: Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try renderIssue(&aw.writer, md.parseIssue(src), fmt, .{});

    if (out) |o| {
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = o, .data = aw.written() });
    } else {
        var buf: [4096]u8 = undefined;
        var fw: Io.File.Writer = .init(.stdout(), io, &buf);
        try fw.interface.writeAll(aw.written());
        try fw.interface.flush();
    }
}

const RenderOptions = struct {
    site_title: []const u8 = "",
    feed_prefix: ?[]const u8 = null,
};

fn renderIssue(w: *Writer, issue: md.Issue, fmt: md.Format, opts: RenderOptions) !void {
    switch (fmt) {
        .text => {
            if (issue.title.len > 0) try w.print("{s}\n\n", .{issue.title});
            try md.render(w, issue.body, .text);
        },
        .web => {
            try pageHead(w, issue.title, false);
            try w.writeAll("<main>\n<p><a href=\"../\">&larr; All issues</a></p>\n");
            try meta(w, issue);
            try md.render(w, issue.body, .web);
            try w.writeAll("<p><a href=\"../\">&larr; All issues</a></p>\n<p class=\"meta\">" ++ disclaimer ++ "</p>\n");
            try feedLink(w, opts.feed_prefix);
            try w.writeAll("</main>\n</body>\n</html>\n");
        },
        .email => {
            try w.writeAll("<!doctype html>\n<html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>");
            try md.escape(w, issue.title);
            try w.writeAll("</title></head>\n<body style=\"margin:0;padding:0;background:#f4f4f4;\">\n" ++
                "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td align=\"center\">\n" ++
                "<table role=\"presentation\" width=\"600\" cellpadding=\"0\" cellspacing=\"0\" style=\"max-width:600px;background:#ffffff;padding:24px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.5;color:#222;\"><tr><td>\n");
            if (opts.site_title.len > 0) {
                try w.writeAll("<p style=\"margin:0 0 12px;font-weight:bold;color:#c27800;\">");
                try md.escape(w, opts.site_title);
                try w.writeAll("</p>\n");
            }
            try md.render(w, issue.body, .email);
            try w.writeAll("<p style=\"margin:24px 0 0;font-size:13px;color:#777;\">" ++ disclaimer ++ "</p>\n");
            try w.writeAll("</td></tr></table>\n</td></tr></table>\n</body></html>\n");
        },
    }
}

fn feedLink(w: *Writer, prefix: ?[]const u8) !void {
    const pre = prefix orelse return;
    try w.print("<p class=\"meta\"><a href=\"{s}feed.xml\">Atom feed</a> · <a href=\"{s}rss.xml\">RSS feed</a></p>\n", .{ pre, pre });
}

fn meta(w: *Writer, issue: md.Issue) !void {
    if (issue.title.len > 0) {
        try w.writeAll("<h1>");
        try md.escape(w, issue.title);
        try w.writeAll("</h1>\n");
    }
    if (issue.date.len > 0) {
        try w.writeAll("<p class=\"meta\">");
        try md.escape(w, issue.date);
        try w.writeAll("</p>\n");
    }
}

const css =
    \\<style>
    \\body{font-family:system-ui,sans-serif;line-height:1.55;color:#222;margin:0}
    \\main{max-width:42rem;margin:0 auto;padding:1rem}
    \\a{color:#c27800}
    \\h2{border-bottom:1px solid #ddd;padding-bottom:.2rem;margin-top:2rem}
    \\blockquote{margin:1rem 0;padding:.1rem 1rem;border-left:4px solid #f7a41d;color:#555}
    \\pre{background:#f4f4f4;padding:.75rem;overflow:auto}
    \\code{background:#f4f4f4;padding:0 .2rem}
    \\pre code{background:none;padding:0}
    \\.meta{color:#777}
    \\form{display:flex;gap:.5rem;flex-wrap:wrap;margin:1.5rem 0}
    \\input[type=email]{flex:1 1 14rem;padding:.5rem}
    \\button{padding:.5rem 1rem}
    \\@media(prefers-color-scheme:dark){body{background:#181818;color:#ddd}pre,code{background:#2a2a2a}blockquote{color:#aaa}a{color:#f7a41d}}
    \\</style>
    \\
;

fn pageHead(w: *Writer, title: []const u8, feeds: bool) !void {
    try w.writeAll("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>");
    try md.escape(w, title);
    try w.writeAll("</title>\n");
    if (feeds) try w.writeAll("<link rel=\"alternate\" type=\"application/atom+xml\" href=\"feed.xml\">\n<link rel=\"alternate\" type=\"application/rss+xml\" href=\"rss.xml\">\n");
    try w.writeAll(css);
    try w.writeAll("</head>\n<body>\n");
}

const disclaimer = "Independent community newsletter, not affiliated with the Zig Software Foundation.";

const repo_url = "https://github.com/sergot/zigweekly";

const feed_limit = 10;
const index_limit = 5;

const tagline = "A weekly digest of what is happening in the Zig community.";

const Site = struct {
    title: []const u8 = "Zig Weekly",
    form_action: []const u8 = "",
    url: []const u8 = "",
};

const Output = struct { fmt: md.Format, dir: []const u8, ext: []const u8 };

const outputs = [_]Output{
    .{ .fmt = .web, .dir = "issues", .ext = "html" },
    .{ .fmt = .email, .dir = "email", .ext = "html" },
    .{ .fmt = .text, .dir = "email", .ext = "txt" },
};

fn cmdSite(gpa: std.mem.Allocator, io: Io, args: []const [:0]const u8) !void {
    const Flag = enum { @"--title", @"--form-action", @"--url" };
    var site: Site = .{};
    var issues_dir: ?[]const u8 = null;
    var out_dir: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "--")) {
            const flag = std.meta.stringToEnum(Flag, args[i]) orelse usageExit();
            i += 1;
            if (i >= args.len) usageExit();
            switch (flag) {
                .@"--title" => site.title = args[i],
                .@"--form-action" => site.form_action = args[i],
                .@"--url" => site.url = std.mem.trimEnd(u8, args[i], "/"),
            }
        } else if (issues_dir == null) issues_dir = args[i] else out_dir = args[i];
    }
    const in_path = issues_dir orelse usageExit();
    const out_path = out_dir orelse usageExit();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var in = Io.Dir.cwd().openDir(io, in_path, .{ .iterate = true }) catch |e|
        fail("error: cannot open {s}: {t}\n", .{ in_path, e });
    defer in.close(io);
    const stems = try issueStems(arena, io, in);

    var out = try Io.Dir.cwd().createDirPathOpen(io, out_path, .{});
    defer out.close(io);
    try out.createDirPath(io, "issues");
    try out.createDirPath(io, "email");

    var index: Writer.Allocating = .init(arena);
    try indexHead(&index.writer, site);

    var atom_entries: Writer.Allocating = .init(arena);
    var rss_items: Writer.Allocating = .init(arena);
    var newest: []const u8 = "1970-01-01";

    for (stems, 0..) |stem, n| {
        const issue = try readIssue(arena, io, in, in_path, stem);
        const name = if (issue.title.len > 0) issue.title else stem;

        for (outputs) |o| {
            var aw: Writer.Allocating = .init(arena);
            try renderIssue(&aw.writer, issue, o.fmt, .{
                .site_title = site.title,
                .feed_prefix = if (site.url.len > 0) "../" else null,
            });
            try out.writeFile(io, .{
                .sub_path = try std.fmt.allocPrint(arena, "{s}/{s}.{s}", .{ o.dir, stem, o.ext }),
                .data = aw.written(),
            });
        }

        if (site.url.len > 0 and n < feed_limit) {
            const date = if (issue.date.len == 10) issue.date else if (stem.len >= 10) stem[0..10] else "1970-01-01";
            if (n == 0) newest = date;
            try feedItems(arena, &atom_entries.writer, &rss_items.writer, site, stem, name, date, issue);
        }

        if (n < index_limit) try indexItem(&index.writer, stem, name, issue.date);
    }
    if (stems.len == 0) try index.writer.writeAll("<li>No issues yet.</li>\n");
    try index.writer.writeAll("</ul>\n<p class=\"meta\">" ++ disclaimer ++ "</p>\n<p class=\"meta\"><a href=\"" ++ repo_url ++ "\">Source code</a> · <a href=\"privacy\">Privacy policy</a> · Content: <a href=\"https://creativecommons.org/licenses/by-sa/4.0/\">CC BY-SA 4.0</a></p>\n");
    if (site.url.len > 0) try feedLink(&index.writer, "");
    try index.writer.writeAll("</main>\n</body>\n</html>\n");

    if (site.url.len > 0) try writeFeeds(arena, io, out, site, atom_entries.written(), rss_items.written(), newest);
    try out.writeFile(io, .{ .sub_path = "index.html", .data = index.written() });

    // Every pages/<name>.md becomes <name>.html (privacy policy, subscribe thank-you pages).
    var pages = Io.Dir.cwd().openDir(io, "pages", .{ .iterate = true }) catch |e|
        fail("error: cannot open pages: {t}\n", .{e});
    defer pages.close(io);
    for (try issueStems(arena, io, pages)) |stem| {
        const page = try readIssue(arena, io, pages, "pages", stem);
        var pw: Writer.Allocating = .init(arena);
        try pageHead(&pw.writer, page.title, false);
        try pw.writer.writeAll("<main>\n<p><a href=\"./\">&larr; Zig Weekly</a></p>\n");
        try meta(&pw.writer, page);
        try md.render(&pw.writer, page.body, .web);
        try pw.writer.writeAll("</main>\n</body>\n</html>\n");
        try out.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}.html", .{stem}), .data = pw.written() });
    }
}

fn issueStems(arena: std.mem.Allocator, io: Io, dir: Io.Dir) ![]const []const u8 {
    var stems: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".md")) continue;
        try stems.append(arena, try arena.dupe(u8, e.name[0 .. e.name.len - 3]));
    }
    std.mem.sort([]const u8, stems.items, {}, struct {
        fn gt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .gt;
        }
    }.gt);
    return stems.items;
}

fn readIssue(arena: std.mem.Allocator, io: Io, dir: Io.Dir, dir_path: []const u8, stem: []const u8) !md.Issue {
    const src = dir.readFileAlloc(io, try std.fmt.allocPrint(arena, "{s}.md", .{stem}), arena, .limited(max_file_bytes)) catch |e|
        fail("error: cannot read {s}/{s}.md: {t}\n", .{ dir_path, stem, e });
    if (std.mem.indexOf(u8, src, "<!-- DRAFT") != null)
        fail("error: {s}/{s}.md still has a DRAFT marker; review it and remove the marker first\n", .{ dir_path, stem });
    return md.parseIssue(src);
}

fn indexHead(w: *Writer, site: Site) !void {
    try pageHead(w, site.title, site.url.len > 0);
    try w.writeAll("<main>\n<h1>");
    try md.escape(w, site.title);
    try w.writeAll("</h1>\n<p>" ++ tagline);
    if (site.url.len > 0) try w.writeAll(" Follow by <a href=\"feed.xml\">Atom</a> or <a href=\"rss.xml\">RSS</a>.");
    try w.writeAll("</p>\n");
    if (site.form_action.len > 0) {
        try w.writeAll("<form method=\"post\" action=\"");
        try md.escape(w, site.form_action);
        try w.writeAll("\"><input type=\"email\" name=\"email\" placeholder=\"you@example.com\" required aria-label=\"Email address\"><button type=\"submit\">Subscribe</button></form>\n<p class=\"meta\">By subscribing you agree to the <a href=\"privacy\">privacy policy</a>. Unsubscribe any time.</p>\n");
    }
    try w.writeAll("<h2>Past issues</h2>\n<ul>\n");
}

fn indexItem(w: *Writer, stem: []const u8, name: []const u8, date: []const u8) !void {
    // No ".html": Cloudflare Pages serves issues/<stem>.html at issues/<stem> and redirects the long form.
    try w.print("<li><a href=\"issues/{f}\">", .{esc(stem)});
    try md.escape(w, name);
    try w.writeAll("</a>");
    if (date.len > 0) {
        try w.writeAll(" <span class=\"meta\">");
        try md.escape(w, date);
        try w.writeAll("</span>");
    }
    try w.writeAll("</li>\n");
}

fn feedItems(arena: std.mem.Allocator, atom: *Writer, rss: *Writer, site: Site, stem: []const u8, name: []const u8, date: []const u8, issue: md.Issue) !void {
    const url = site.url;
    var html: Writer.Allocating = .init(arena);
    try md.render(&html.writer, issue.body, .web);

    try atom.writeAll("<entry><title>");
    try md.escape(atom, name);
    try atom.print("</title><id>{f}/issues/{f}</id><link href=\"{f}/issues/{f}\"/><updated>{f}T00:00:00Z</updated><author><name>{f}</name></author><content type=\"html\">", .{ esc(url), esc(stem), esc(url), esc(stem), esc(date), esc(site.title) });
    try md.escape(atom, html.written());
    try atom.writeAll("</content></entry>\n");

    try rss.writeAll("<item><title>");
    try md.escape(rss, name);
    try rss.print("</title><link>{f}/issues/{f}</link><guid isPermaLink=\"true\">{f}/issues/{f}</guid><pubDate>{s}</pubDate><description>", .{ esc(url), esc(stem), esc(url), esc(stem), try rfc822(arena, date) });
    try md.escape(rss, html.written());
    try rss.writeAll("</description></item>\n");
}

fn writeFeeds(arena: std.mem.Allocator, io: Io, out: Io.Dir, site: Site, atom_entries: []const u8, rss_items: []const u8, newest: []const u8) !void {
    var feed: Writer.Allocating = .init(arena);
    const f = &feed.writer;
    try f.writeAll("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>");
    try md.escape(f, site.title);
    try f.print("</title><id>{f}/</id><link href=\"{f}/\"/><link rel=\"self\" href=\"{f}/feed.xml\"/><updated>{f}T00:00:00Z</updated>\n", .{ esc(site.url), esc(site.url), esc(site.url), esc(newest) });
    try f.writeAll(atom_entries);
    try f.writeAll("</feed>\n");
    try out.writeFile(io, .{ .sub_path = "feed.xml", .data = feed.written() });

    var rss: Writer.Allocating = .init(arena);
    const r = &rss.writer;
    try r.writeAll("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\"><channel><title>");
    try md.escape(r, site.title);
    try r.print("</title><link>{f}/</link><description>" ++ tagline ++ "</description><language>en</language><lastBuildDate>{s}</lastBuildDate><atom:link href=\"{f}/rss.xml\" rel=\"self\" type=\"application/rss+xml\"/>\n", .{ esc(site.url), try rfc822(arena, newest), esc(site.url) });
    try r.writeAll(rss_items);
    try r.writeAll("</channel></rss>\n");
    try out.writeFile(io, .{ .sub_path = "rss.xml", .data = rss.written() });
}

/// Formats a string XML/HTML-escaped via `{f}`.
const Esc = struct {
    s: []const u8,
    pub fn format(self: Esc, w: *Writer) Writer.Error!void {
        try md.escape(w, self.s);
    }
};

fn esc(s: []const u8) Esc {
    return .{ .s = s };
}

fn rfc822(arena: std.mem.Allocator, date: []const u8) ![]const u8 {
    const fallback = "Thu, 01 Jan 1970 00:00:00 GMT";
    if (date.len != 10 or date[4] != '-' or date[7] != '-') return fallback;
    const y = std.fmt.parseInt(i32, date[0..4], 10) catch return fallback;
    const m = std.fmt.parseInt(u8, date[5..7], 10) catch return fallback;
    const d = std.fmt.parseInt(u8, date[8..10], 10) catch return fallback;
    const leap = @mod(y, 4) == 0 and (@mod(y, 100) != 0 or @mod(y, 400) == 0);
    const days_in_month = [_]u8{ 31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (m < 1 or m > 12 or d < 1 or d > days_in_month[m - 1]) return fallback;
    const t = [_]i32{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    const yy = if (m < 3) y - 1 else y;
    const dow: usize = @intCast(@mod(yy + @divFloor(yy, 4) - @divFloor(yy, 100) + @divFloor(yy, 400) + t[m - 1] + d, 7));
    const days = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    return std.fmt.allocPrint(arena, "{s}, {d:0>2} {s} {d} 00:00:00 GMT", .{ days[dow], d, months[m - 1], y });
}

test "rfc822" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("Mon, 26 Oct 2026 00:00:00 GMT", try rfc822(arena.allocator(), "2026-10-26"));
    try std.testing.expectEqualStrings("Thu, 01 Jan 1970 00:00:00 GMT", try rfc822(arena.allocator(), "junk"));
    try std.testing.expectEqualStrings("Thu, 01 Jan 1970 00:00:00 GMT", try rfc822(arena.allocator(), "2026-02-31"));
}

test "feed escapes site title and stem" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var atom: Writer.Allocating = .init(arena.allocator());
    var rss: Writer.Allocating = .init(arena.allocator());
    const site: Site = .{ .title = "A & B", .url = "https://x.dev" };
    try feedItems(arena.allocator(), &atom.writer, &rss.writer, site, "a&b", "n", "2026-10-26", .{ .body = "hi" });
    try std.testing.expect(std.mem.indexOf(u8, atom.written(), "<name>A &amp; B</name>") != null);
    try std.testing.expect(std.mem.indexOf(u8, atom.written(), "issues/a&amp;b</id>") != null);
    try std.testing.expect(std.mem.indexOf(u8, rss.written(), "issues/a&amp;b</link>") != null);
    try std.testing.expect(std.mem.indexOf(u8, atom.written(), ".html") == null);
}

test {
    _ = md;
}
