const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gtksource = @import("gtksource");
const parser = @import("parser.zig");

pub const RevisionWidget = struct {
    change_label: *gtk.Label,
    commit_label: *gtk.Label,
    desc_label: *gtk.Label,

    pub fn new(parent: *gtk.Box) @This() {
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

        var vbox = gtk.Box.new(.vertical, 0);
        var hbox = gtk.Box.new(.horizontal, 0);
        gtk.Widget.setHexpand(hbox.as(gtk.Widget), 1);

        hbox.append(change_box.as(gtk.Widget));
        hbox.append(commit_box.as(gtk.Widget));
        vbox.append(hbox.as(gtk.Widget));
        vbox.append(desc_box.as(gtk.Widget));

        parent.append(vbox.as(gtk.Widget));

        return @This(){
            .change_label = change_label,
            .commit_label = commit_label,
            .desc_label = desc_label,
        };
    }

    pub fn setRevision(self: @This(), allocator: std.mem.Allocator, revision: parser.Revision) !void {
        const label_text = try allocator.dupeZ(u8, revision.changeID);
        self.change_label.setLabel(label_text);
        const commit_text = try allocator.dupeZ(u8, revision.commitID);
        self.commit_label.setLabel(commit_text);
        const desc_text = try allocator.dupeZ(u8, revision.description);
        self.desc_label.setLabel(desc_text);
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
                    gtksource.View.setHighlightCurrentLine(view, 0);
                    gtk.TextView.setEditable(view.as(gtk.TextView), 0);
                    gtk.TextView.setCursorVisible(view.as(gtk.TextView), 0);
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
                                gtksource.View.setHighlightCurrentLine(view, 0);
                                gtk.TextView.setEditable(view.as(gtk.TextView), 0);
                                gtk.TextView.setCursorVisible(view.as(gtk.TextView), 0);
                            },
                            .snapshot => {},
                        }
                    }
                },
            }
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
        gtksource.View.setHighlightCurrentLine(source_view, 1); // highlight current line
        gtksource.View.setTabWidth(source_view, 4);
        gtk.TextView.setMonospace(source_view.as(gtk.TextView), 1); // use monospace font

        // Wrap the source view in a scrolled window
        // var scrolled_window = gtk.ScrolledWindow.new();
        // gtk.ScrolledWindow.setChild(scrolled_window, source_view.as(gtk.Widget));
        // gtk.Widget.setVexpand(scrolled_window.as(gtk.Widget), 1); // fill vertical space
        // gtk.Widget.setHexpand(scrolled_window.as(gtk.Widget), 1); // fill horizontal space

        // box.append(source_view.as(gtk.Widget));

        return source_view;
    }

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

const ToggleValue = struct {
    conflict: *parser.Conflict,
    base_view: *BaseView,
};
