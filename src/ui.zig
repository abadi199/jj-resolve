const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gtksource = @import("gtksource");
const parser = @import("parser.zig");
const output = @import("output.zig");

pub const RevisionWidget = struct {
    widget: *gtk.Widget,
    change_label: *gtk.Label,
    commit_label: *gtk.Label,
    type_label: *gtk.Label,
    desc_label: *gtk.Label,
    content: ?*gtk.Widget,
    content_box: *gtk.Box,
    check_button: ?*gtk.CheckButton,

    const Option = struct {
        is_radio: bool,
    };
    pub fn new(parent: *gtk.Box, content: ?*gtk.Widget, option: Option) @This() {
        // change label
        const change_box = gtk.Box.new(.horizontal, 0);
        const change = gtk.Label.new("Change ID: ");
        const change_label = gtk.Label.new(null);
        gtk.Widget.setHalign(change_label.as(gtk.Widget), .start);
        gtk.Widget.setHexpand(change_label.as(gtk.Widget), 1);
        change_box.append(change.as(gtk.Widget));
        change_box.append(change_label.as(gtk.Widget));

        // commit label
        const commit_box = gtk.Box.new(.horizontal, 0);
        const commit = gtk.Label.new("Commit ID: ");
        const commit_label = gtk.Label.new(null);
        gtk.Widget.setHalign(commit_label.as(gtk.Widget), .start);
        gtk.Widget.setHexpand(commit_label.as(gtk.Widget), 1);
        commit_box.append(commit.as(gtk.Widget));
        commit_box.append(commit_label.as(gtk.Widget));

        // desc label
        const desc_box = gtk.Box.new(.horizontal, 0);
        const desc = gtk.Label.new("Desc: ");
        const desc_label = gtk.Label.new(null);
        gtk.Widget.setHalign(desc_label.as(gtk.Widget), .start);
        gtk.Widget.setHexpand(desc_label.as(gtk.Widget), 1);
        desc_box.append(desc.as(gtk.Widget));
        desc_box.append(desc_label.as(gtk.Widget));

        // type label
        const type_box = gtk.Box.new(.horizontal, 0);
        const type_label = gtk.Label.new("Type: ");
        const type_value = gtk.Label.new(null);
        gtk.Widget.setHalign(type_value.as(gtk.Widget), .start);
        gtk.Widget.setHexpand(type_value.as(gtk.Widget), 1);
        type_box.append(type_label.as(gtk.Widget));
        type_box.append(type_value.as(gtk.Widget));

        // header box
        var header_box = gtk.Box.new(.vertical, 0);
        gtk.Widget.addCssClass(header_box.as(gtk.Widget), "revision-header-box");

        var hbox = gtk.Box.new(.horizontal, 0);
        gtk.Widget.setHexpand(hbox.as(gtk.Widget), 1);

        hbox.append(change_box.as(gtk.Widget));
        hbox.append(commit_box.as(gtk.Widget));

        header_box.append(hbox.as(gtk.Widget));
        header_box.append(type_box.as(gtk.Widget));
        header_box.append(desc_box.as(gtk.Widget));

        var content_box = gtk.Box.new(.vertical, 0);
        header_box.append(content_box.as(gtk.Widget));
        if (content) |c| {
            content_box.append(c);
        }

        // frame
        var frame = gtk.Frame.new(null);
        frame.setChild(header_box.as(gtk.Widget));
        gtk.Widget.addCssClass(frame.as(gtk.Widget), "revision-frame");

        var check_button: ?*gtk.CheckButton = null;
        if (option.is_radio) {
            // check_button
            check_button = gtk.CheckButton.new();
            gtk.Widget.addCssClass(check_button.?.as(gtk.Widget), "revision-check-button");
            check_button.?.setChild(frame.as(gtk.Widget));
            parent.append(check_button.?.as(gtk.Widget));
        } else {
            parent.append(frame.as(gtk.Widget));
        }

        return @This(){
            .widget = frame.as(gtk.Widget),
            .change_label = change_label,
            .type_label = type_value,
            .commit_label = commit_label,
            .desc_label = desc_label,
            .content = content,
            .content_box = content_box,
            .check_button = check_button,
        };
    }

    pub fn setRevision(self: @This(), allocator: std.mem.Allocator, revision: parser.Revision) !void {
        const label_text = try allocator.dupeZ(u8, revision.changeID);
        self.change_label.setLabel(label_text);

        const commit_text = try allocator.dupeZ(u8, revision.commitID);
        self.commit_label.setLabel(commit_text);

        const type_text = switch (revision.type) {
            .diff => "diff",
            .snapshot => "snapshot",
        };
        self.type_label.setLabel(type_text);

        const desc_text = try allocator.dupeZ(u8, revision.description);
        self.desc_label.setLabel(desc_text);
    }

    pub fn setContent(self: @This(), content: *gtk.Widget) void {
        if (self.content) |old_content| {
            self.content_box.remove(old_content);
        }

        self.content_box.append(content);
    }

    pub fn deinit(self: *@This()) void {
        self.revision = null;
    }
};

pub const BaseView = struct {
    arena: std.heap.ArenaAllocator,
    callbacks: std.ArrayList(*const fn (u32) void),

    pub fn new(allocator: std.mem.Allocator) BaseView {
        return BaseView{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .callbacks = std.ArrayList(*const fn (u32) void).empty,
        };
    }

    pub fn deinit(self: BaseView) void {
        self.arena.deinit();
    }

    pub fn onConflictSelected(self: *BaseView, comptime callback: *const fn (u32) void) !void {
        try self.callbacks.append(self.arena.allocator(), callback);
    }

    pub fn render(self: *BaseView, file: parser.ParsedFile, parent: *gtk.Box) !void {
        _ = self.arena.reset(.retain_capacity);
        const allocator = self.arena.allocator();
        var scroll_window = gtk.ScrolledWindow.new();
        gtk.Widget.setVexpand(scroll_window.as(gtk.Widget), 1);
        parent.append(scroll_window.as(gtk.Widget));

        var box = gtk.Box.new(.vertical, 0);

        gtk.Widget.setVexpand(box.as(gtk.Widget), 1);
        gtk.Widget.setHexpand(box.as(gtk.Widget), 1);
        scroll_window.setChild(box.as(gtk.Widget));
        var radio_group_leader: ?*gtk.CheckButton = null;
        for (file.segments) |*segment| {
            switch (segment.*) {
                .no_conflict => |no_conflict| {
                    const buffer = gtksource.Buffer.new(null);
                    const content = try allocator.dupeZ(u8, try no_conflict.toString(allocator));
                    gtk.TextBuffer.setText(buffer.as(gtk.TextBuffer), content, -1);
                    const view = createCodeView(buffer);
                    box.append(view.as(gtk.Widget));
                },
                .conflict => |*conflict| {
                    var conflict_box = gtk.Box.new(.vertical, 0);

                    gtk.Widget.setMarginBottom(conflict_box.as(gtk.Widget), 2);
                    gtk.Widget.addCssClass(conflict_box.as(gtk.Widget), "conflict-box");
                    box.append(conflict_box.as(gtk.Widget));

                    // conflict radio
                    var conflict_radio = gtk.CheckButton.newWithLabel(try std.fmt.allocPrintSentinel(
                        allocator,
                        "Conflict {d} of {d}",
                        .{ conflict.index, conflict.total },
                        0,
                    ));
                    if (radio_group_leader) |leader| {
                        gtk.CheckButton.setGroup(conflict_radio, leader);
                    } else {
                        radio_group_leader = conflict_radio;
                    }
                    const toggle_value = try allocator.create(ToggleValue);
                    toggle_value.* = ToggleValue{
                        .base_view = self,
                        .conflict = @constCast(conflict),
                    };

                    _ = gtk.CheckButton.signals.toggled.connect(
                        conflict_radio,
                        ?*anyopaque,
                        &onToggledRadioActivate,
                        @constCast(toggle_value),
                        .{},
                    );
                    gtk.Widget.addCssClass(conflict_radio.as(gtk.Widget), "conflict-radio");
                    gtk.Widget.setHexpand(conflict_radio.as(gtk.Widget), 1);
                    conflict_box.append(conflict_radio.as(gtk.Widget));

                    for (conflict.conflict_markers) |marker| {
                        switch (marker) {
                            .diff => |diff| {
                                const buffer = gtksource.Buffer.new(null);
                                const content = try allocator.dupeZ(u8, try diff.getBaseContent(allocator));
                                gtk.TextBuffer.setText(buffer.as(gtk.TextBuffer), content, -1);
                                const frame = gtk.Frame.new(null);
                                gtk.Widget.addCssClass(frame.as(gtk.Widget), "conflict-frame");
                                const view = createCodeView(buffer);
                                frame.setChild(view.as(gtk.Widget));
                                conflict_box.append(frame.as(gtk.Widget));
                            },
                            .snapshot => {},
                        }
                    }
                },
            }
        }
    }

    const ToggleValue = struct {
        conflict: *parser.Conflict,
        base_view: *BaseView,
    };
    fn onToggledRadioActivate(button: *gtk.CheckButton, conflict_ptr: ?*anyopaque) callconv(.c) void {
        if (button.getActive() == 0) {
            return;
        }

        if (conflict_ptr) |ptr| {
            const value: *ToggleValue = @ptrCast(@alignCast(ptr));
            std.log.info("Conflict {any} activated", .{value.conflict.index});
            for (value.base_view.callbacks.items) |callback| {
                callback(value.conflict.index);
            }
        } else {
            std.log.err("Conflict pointer is null", .{});
        }
    }
};

pub const RevisionsView = struct {
    conflict_index: u32,
    arena: std.heap.ArenaAllocator,
    callbacks: std.ArrayList(*const fn (u32, revision: parser.Revision) void),

    pub fn new(allocator: std.mem.Allocator, conflict_index: u32) RevisionsView {
        return RevisionsView{
            .conflict_index = conflict_index,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .callbacks = std.ArrayList(*const fn (u32, parser.Revision) void).empty,
        };
    }

    pub fn render(self: *RevisionsView, file: parser.ParsedFile, parent: *gtk.Box) !void {
        removeAllChildren(parent);
        const allocator = self.arena.allocator();
        const scroll_window = gtk.ScrolledWindow.new();
        gtk.Widget.setVexpand(scroll_window.as(gtk.Widget), 1);
        gtk.Widget.setHexpand(scroll_window.as(gtk.Widget), 1);
        const box = gtk.Box.new(.vertical, 10);
        scroll_window.setChild(box.as(gtk.Widget));
        parent.append(scroll_window.as(gtk.Widget));

        const revisions = try file.getRevisions(allocator, self.conflict_index);
        var group_leader: ?*gtk.CheckButton = null;
        for (revisions) |*revision| {
            const revision_widget = try self.renderRevision(file, revision.*, box);
            if (revision_widget.check_button) |check_button| {
                if (group_leader) |leader| {
                    gtk.CheckButton.setGroup(check_button, leader);
                } else if (revision_widget.check_button) |cb| {
                    group_leader = cb;
                }

                const toggle_value = try allocator.create(ToggleValue);
                toggle_value.* = ToggleValue{
                    .revision = @constCast(revision),
                    .self = self,
                };
                _ = gtk.CheckButton.signals.toggled.connect(
                    check_button,
                    ?*anyopaque,
                    &onToggleRadio,
                    @constCast(toggle_value),
                    .{},
                );
            }
        }
    }

    pub fn onRevisionSelected(self: *RevisionsView, comptime callback: *const fn (u32, parser.Revision) void) !void {
        try self.callbacks.append(self.arena.allocator(), callback);
    }

    const ToggleValue = struct {
        revision: *parser.Revision,
        self: *RevisionsView,
    };
    fn onToggleRadio(button: *gtk.CheckButton, commit_id_ptr: ?*anyopaque) callconv(.c) void {
        if (button.getActive() == 0) {
            return;
        }

        if (commit_id_ptr) |ptr| {
            const value: *ToggleValue = @ptrCast(@alignCast(ptr));
            std.log.info("Revision {s} activated", .{value.revision.commitID});
            for (value.self.callbacks.items) |callback| {
                callback(value.self.conflict_index, value.revision.*);
            }
        } else {
            std.log.err("Conflict pointer is null", .{});
        }
    }

    fn renderRevision(self: *RevisionsView, file: parser.ParsedFile, revision: parser.Revision, parent: *gtk.Box) !RevisionWidget {
        const allocator = self.arena.allocator();
        // code view
        const buffer = gtksource.Buffer.new(null);
        const content = try file.getConflictContent(allocator, self.conflict_index, revision);
        const content_z = try allocator.dupeZ(u8, content);
        gtk.TextBuffer.setText(buffer.as(gtk.TextBuffer), content_z, -1);
        const view = createCodeView(buffer);

        // revision widget
        const rev_widget: RevisionWidget = .new(parent, view.as(gtk.Widget), .{ .is_radio = true });
        try rev_widget.setRevision(allocator, revision);

        return rev_widget;
    }

    pub fn deinit(self: RevisionsView) void {
        self.arena.deinit();
    }
};

pub const OutputView = struct {
    arena: std.heap.ArenaAllocator,
    output_file: output.OutputFile,
    buffers: []*gtksource.Buffer,

    pub fn new(allocator: std.mem.Allocator, file: parser.ParsedFile) !OutputView {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        const output_file = try output.OutputFile.from(arena_allocator, file);
        std.log.debug("output_file: {}", .{output_file});
        return .{
            .arena = arena,
            .output_file = output_file,
            .buffers = &[0]*gtksource.Buffer{},
        };
    }

    pub fn render(self: *OutputView, parent: *gtk.Box) !void {
        const allocator = self.arena.allocator();
        var frame = gtk.Frame.new("Output");
        gtk.Widget.setVexpand(frame.as(gtk.Widget), 1);
        gtk.Widget.addCssClass(frame.as(gtk.Widget), "output-frame");
        parent.append(frame.as(gtk.Widget));

        var scroll_window = gtk.ScrolledWindow.new();
        var box = gtk.Box.new(.vertical, 0);
        scroll_window.setChild(box.as(gtk.Widget));
        frame.setChild(scroll_window.as(gtk.Widget));

        var buffers = std.ArrayList(*gtksource.Buffer).empty;

        for (self.output_file.segments) |segment| {
            switch (segment) {
                .no_conflict => |no_conflict| {
                    var buffer = gtksource.Buffer.new(null);
                    const text = try allocator.dupeZ(u8, no_conflict.text);
                    gtk.TextBuffer.setText(buffer.as(gtk.TextBuffer), text, -1);
                    const view = createCodeView(buffer);
                    gtk.TextView.setEditable(view.as(gtk.TextView), 1);
                    gtk.TextView.setCursorVisible(view.as(gtk.TextView), 1);
                    box.append(view.as(gtk.Widget));
                },
                .conflict => |conflict| {
                    var conflict_frame = gtk.Frame.new(try std.fmt.allocPrintSentinel(allocator, "Conflict {d} of {d}", .{ conflict.conflict_index, conflict.total }, 0));
                    var conflict_box = gtk.Box.new(.vertical, 0);
                    box.append(conflict_frame.as(gtk.Widget));
                    conflict_frame.setChild(conflict_box.as(gtk.Widget));

                    gtk.Widget.addCssClass(conflict_box.as(gtk.Widget), "conflict-box");

                    gtk.Widget.addCssClass(conflict_frame.as(gtk.Widget), "conflict-frame");
                    conflict_box.append(conflict_frame.as(gtk.Widget));

                    const buffer = gtksource.Buffer.new(null);
                    try buffers.append(allocator, buffer);
                    const code_view = createCodeView(buffer);
                    gtksource.View.setHighlightCurrentLine(code_view, 1);
                    gtk.TextView.setEditable(code_view.as(gtk.TextView), 1);
                    gtk.TextView.setCursorVisible(code_view.as(gtk.TextView), 1);
                    conflict_box.append(code_view.as(gtk.Widget));
                },
            }
        }

        self.buffers = try buffers.toOwnedSlice(allocator);
    }

    pub fn setContent(self: *OutputView, allocator: std.mem.Allocator, conflict_index: u32, content: []const u8) !void {
        const buffer = self.buffers[conflict_index - 1];
        const text_z = try allocator.dupeZ(u8, content);
        gtk.TextBuffer.setText(buffer.as(gtk.TextBuffer), text_z, -1);
        for (self.output_file.segments) |*segment| {
            switch (segment.*) {
                .conflict => |*conflict| {
                    if (conflict.conflict_index == conflict_index) {
                        conflict.text = content;
                    }
                },
                .no_conflict => {},
            }
        }
    }

    pub fn deinit(self: OutputView) void {
        self.output_file.deinit(self.arena.allocator());
        self.arena.deinit();
    }
};

// Helpers

pub fn removeAllChildren(box: *gtk.Box) void {
    while (gtk.Widget.getFirstChild(box.as(gtk.Widget))) |child| {
        box.remove(child);
    }
}

pub fn createCodeView(buffer: *gtksource.Buffer) *gtksource.View {
    const lang_manager = gtksource.LanguageManager.getDefault();
    if (gtksource.LanguageManager.getLanguage(lang_manager, "typescript")) |language| {
        gtksource.Buffer.setLanguage(buffer, language);
    }

    const scheme_manager = gtksource.StyleSchemeManager.getDefault();
    if (gtksource.StyleSchemeManager.getScheme(scheme_manager, "Adwaita-dark")) |scheme| {
        gtksource.Buffer.setStyleScheme(buffer, scheme);
    }

    // Create the GtkSourceView with the buffer
    var source_view = gtksource.View.newWithBuffer(buffer.as(gtksource.Buffer));
    gtksource.View.setShowLineNumbers(source_view, 0); // show line numbers
    gtksource.View.setHighlightCurrentLine(source_view, 0); // highlight current line
    gtksource.View.setTabWidth(source_view, 4);
    gtk.TextView.setMonospace(source_view.as(gtk.TextView), 1); // use monospace font
    gtk.TextView.setEditable(source_view.as(gtk.TextView), 0);
    gtk.TextView.setCursorVisible(source_view.as(gtk.TextView), 0);

    return source_view;
}
