const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const gtksource = @import("gtksource");
const jjresolve = @import("root.zig");

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

    pub fn setRevision(self: @This(), allocator: std.mem.Allocator, revision: jjresolve.Revision) !void {
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
