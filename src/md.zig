const std = @import("std");
const Writer = std.Io.Writer;

pub const Format = enum { web, email, text };

pub const Issue = struct {
    title: []const u8 = "",
    date: []const u8 = "",
    body: []const u8,
};

const fence = "---";

pub fn parseIssue(src: []const u8) Issue {
    var lines = std.mem.splitScalar(u8, src, '\n');
    if (!std.mem.eql(u8, std.mem.trimEnd(u8, lines.next().?, "\r"), fence)) return .{ .body = src };
    var issue: Issue = .{ .body = src };
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.eql(u8, line, fence)) {
            issue.body = std.mem.trimStart(u8, lines.rest(), "\r\n");
            return issue;
        }
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const val = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.mem.eql(u8, key, "title")) issue.title = val;
        if (std.mem.eql(u8, key, "date")) issue.date = val;
    }
    return .{ .body = src };
}

const Block = ?Tag;

const Tag = enum { h1, h2, h3, p, ul, ol, li, blockquote, pre, code, a };

pub fn render(w: *Writer, body: []const u8, fmt: Format) Writer.Error!void {
    var block: Block = null;
    var in_comment = false;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");

        if (block != .pre) {
            if (in_comment or std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "<!--")) {
                in_comment = std.mem.indexOf(u8, line, "-->") == null;
                continue;
            }
        }

        if (block == .pre) {
            if (std.mem.startsWith(u8, line, "```")) {
                try closeBlock(w, &block, fmt);
            } else {
                try escape(w, line);
                try w.writeByte('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, line, "```")) {
            try closeBlock(w, &block, fmt);
            try open(w, fmt, .pre);
            block = .pre;
            continue;
        }
        if (std.mem.trim(u8, line, " \t").len == 0) {
            try closeBlock(w, &block, fmt);
            continue;
        }
        if (heading(line)) |h| {
            try closeBlock(w, &block, fmt);
            try renderHeading(w, h.level, h.text, fmt);
            continue;
        }
        if (listItem(line)) |item| {
            const want: Tag = if (item.ordered) .ol else .ul;
            if (block != want) {
                try closeBlock(w, &block, fmt);
                try open(w, fmt, want);
                block = want;
            }
            try open(w, fmt, .li);
            try inlineMd(w, item.text, fmt);
            try close(w, fmt, .li);
            continue;
        }
        if (std.mem.startsWith(u8, line, ">")) {
            const text = std.mem.trimStart(u8, line[1..], " ");
            if (block != .blockquote) {
                try closeBlock(w, &block, fmt);
                try open(w, fmt, .blockquote);
                block = .blockquote;
            } else try w.writeByte(' ');
            try inlineMd(w, text, fmt);
            continue;
        }
        if (block == .p) {
            try w.writeByte(' ');
        } else {
            try closeBlock(w, &block, fmt);
            try open(w, fmt, .p);
            block = .p;
        }
        try inlineMd(w, std.mem.trim(u8, line, " \t"), fmt);
    }
    try closeBlock(w, &block, fmt);
}

fn closeBlock(w: *Writer, block: *Block, fmt: Format) Writer.Error!void {
    const tag = block.* orelse return;
    try close(w, fmt, tag);
    block.* = null;
}

const Heading = struct { level: u8, text: []const u8 };

fn heading(line: []const u8) ?Heading {
    var n: usize = 0;
    while (n < line.len and line[n] == '#') n += 1;
    if (n == 0 or n > 3 or n >= line.len or line[n] != ' ') return null;
    return .{ .level = @intCast(n), .text = std.mem.trim(u8, line[n..], " \t") };
}

const Item = struct { ordered: bool, text: []const u8 };

fn listItem(line: []const u8) ?Item {
    if (line.len > 2 and (line[0] == '-' or line[0] == '*') and line[1] == ' ')
        return .{ .ordered = false, .text = line[2..] };
    var i: usize = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
    if (i > 0 and i + 1 < line.len and line[i] == '.' and line[i + 1] == ' ')
        return .{ .ordered = true, .text = line[i + 2 ..] };
    return null;
}

fn renderHeading(w: *Writer, level: u8, text: []const u8, fmt: Format) Writer.Error!void {
    if (fmt == .text) {
        try inlineMd(w, text, fmt);
        try w.writeByte('\n');
        if (level < 3) {
            const ch: u8 = if (level == 1) '=' else '-';
            try w.splatByteAll(ch, @max(text.len, 3));
            try w.writeByte('\n');
        }
        try w.writeByte('\n');
        return;
    }
    const tag: Tag = switch (level) {
        1 => .h1,
        2 => .h2,
        else => .h3,
    };
    try open(w, fmt, tag);
    try inlineMd(w, text, fmt);
    try close(w, fmt, tag);
}

fn tagStyle(tag: Tag) []const u8 {
    return switch (tag) {
        .h1 => "font-size:26px;margin:24px 0 12px;",
        .h2 => "font-size:20px;margin:28px 0 8px;border-bottom:1px solid #ddd;padding-bottom:4px;",
        .h3 => "font-size:16px;margin:20px 0 6px;",
        .p => "margin:0 0 12px;",
        .ul, .ol => "margin:0 0 12px;padding-left:24px;",
        .li => "margin:0 0 6px;",
        .blockquote => "margin:0 0 12px;padding:4px 12px;border-left:4px solid #f7a41d;color:#555;",
        .pre => "margin:0 0 12px;padding:10px;background:#f4f4f4;overflow:auto;font-family:monospace;font-size:13px;",
        .code => "font-family:monospace;background:#f4f4f4;padding:0 3px;",
        .a => "color:#c27800;",
    };
}

fn open(w: *Writer, fmt: Format, tag: Tag) Writer.Error!void {
    switch (fmt) {
        .web => try w.print("<{t}>", .{tag}),
        .email => try w.print("<{t} style=\"{s}\">", .{ tag, tagStyle(tag) }),
        .text => if (tag == .li) try w.writeAll("- "),
    }
}

fn close(w: *Writer, fmt: Format, tag: Tag) Writer.Error!void {
    switch (fmt) {
        .web, .email => try w.print("</{t}>\n", .{tag}),
        .text => try w.writeAll(switch (tag) {
            .li, .ul, .ol => "\n",
            else => "\n\n",
        }),
    }
}

pub fn escape(w: *Writer, s: []const u8) Writer.Error!void {
    for (s) |c| try escapeByte(w, c);
}

fn escapeByte(w: *Writer, c: u8) Writer.Error!void {
    switch (c) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        else => try w.writeByte(c),
    }
}

fn safeUrl(url: []const u8) bool {
    if (std.mem.indexOfScalar(u8, url, ':') == null) return true;
    return std.mem.startsWith(u8, url, "https://") or
        std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "mailto:");
}

fn inlineMd(w: *Writer, s: []const u8, fmt: Format) Writer.Error!void {
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == '`') {
            if (std.mem.indexOfScalarPos(u8, s, i + 1, '`')) |end| {
                if (fmt == .text) {
                    try w.writeAll(s[i + 1 .. end]);
                } else {
                    try open(w, fmt, .code);
                    try escape(w, s[i + 1 .. end]);
                    try w.writeAll("</code>");
                }
                i = end + 1;
                continue;
            }
        } else if (c == '[') {
            if (link(s, i)) |l| {
                if (fmt == .text) {
                    try inlineMd(w, l.text, fmt);
                    try w.print(" ({s})", .{l.url});
                } else if (safeUrl(l.url)) {
                    if (fmt == .email) {
                        try w.writeAll("<a style=\"");
                        try w.writeAll(tagStyle(.a));
                        try w.writeAll("\" href=\"");
                    } else try w.writeAll("<a href=\"");
                    try escape(w, l.url);
                    try w.writeAll("\">");
                    try inlineMd(w, l.text, fmt);
                    try w.writeAll("</a>");
                } else try inlineMd(w, l.text, fmt);
                i = l.end;
                continue;
            }
        } else if (c == '*') {
            const double = i + 1 < s.len and s[i + 1] == '*';
            const mark: []const u8 = if (double) "**" else "*";
            if (std.mem.indexOfPos(u8, s, i + mark.len, mark)) |end| {
                if (end > i + mark.len) {
                    if (fmt != .text) try w.writeAll(if (double) "<strong>" else "<em>");
                    try inlineMd(w, s[i + mark.len .. end], fmt);
                    if (fmt != .text) try w.writeAll(if (double) "</strong>" else "</em>");
                    i = end + mark.len;
                    continue;
                }
            }
        }
        if (fmt == .text) try w.writeByte(c) else try escapeByte(w, c);
        i += 1;
    }
}

const Link = struct { text: []const u8, url: []const u8, end: usize };

fn link(s: []const u8, start: usize) ?Link {
    const close_b = std.mem.indexOfScalarPos(u8, s, start + 1, ']') orelse return null;
    if (close_b + 1 >= s.len or s[close_b + 1] != '(') return null;
    const close_p = std.mem.indexOfScalarPos(u8, s, close_b + 2, ')') orelse return null;
    return .{ .text = s[start + 1 .. close_b], .url = s[close_b + 2 .. close_p], .end = close_p + 1 };
}

fn expectRender(src: []const u8, fmt: Format, expected: []const u8) !void {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try render(&aw.writer, src, fmt);
    try std.testing.expectEqualStrings(expected, aw.written());
}

test "web blocks and inline" {
    try expectRender(
        "## Hi\n\nA **b** and *i* with `x<y` and [z](https://z.dev).\n\n- one\n- two\n",
        .web,
        "<h2>Hi</h2>\n<p>A <strong>b</strong> and <em>i</em> with <code>x&lt;y</code> and <a href=\"https://z.dev\">z</a>.</p>\n<ul><li>one</li>\n<li>two</li>\n</ul>\n",
    );
}

test "unsafe link scheme is dropped, html escaped" {
    try expectRender("[x](javascript:evil) <b>", .web, "<p>x &lt;b&gt;</p>\n");
}

test "text format" {
    try expectRender("# T\n\n[a](https://a.dev)\n\n- x\n", .text, "T\n===\n\na (https://a.dev)\n\n- x\n\n");
}

test "html comments are dropped, single and multi line" {
    try expectRender("<!-- note -->\n\npara\n\n<!-- a\nb -->\n\nend\n", .web, "<p>para</p>\n<p>end</p>\n");
}

test "email uses inline styles" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try render(&aw.writer, "para", .email);
    try std.testing.expectStringStartsWith(aw.written(), "<p style=\"");
}

test "front matter" {
    const i = parseIssue("---\ntitle: T\ndate: 2026-10-26\n---\n\nbody\n");
    try std.testing.expectEqualStrings("T", i.title);
    try std.testing.expectEqualStrings("body\n", i.body);
}

test "front matter edge cases" {
    try std.testing.expectEqualStrings("body", parseIssue("---\n---\nbody").body);
    try std.testing.expectEqualStrings("---\ntitle: T\nbody", parseIssue("---\ntitle: T\nbody").body);
}

test "overlong heading marker does not overflow" {
    const hashes: [300]u8 = @splat('#');
    try expectRender(&hashes, .web, "<p>" ++ hashes ++ "</p>\n");
}
