const std = @import("std");

pub const TemplateIdx = usize;
pub const EntityIdx = usize;
pub const EntityID = u32;

pub const EntityPosition = struct {
    template_idx: TemplateIdx,
    entity_idx: EntityIdx,
};

fn RequireStruct(comptime T: type, comptime name: []const u8) void {
    if (@typeInfo(T) != .@"struct")
        @compileError(@typeName(T) ++ " is not a struct: '" ++ name ++ "' must be a struct");
}

/// Registry stores and manages all the data of the ECS
pub fn Registry(comptime templates: anytype) type {
    return struct {
        allocator: std.mem.Allocator,

        templates: TemplateStorage(),
        enabled_components: []
        entity_positions: std.AutoHashMap(EntityID, EntityPosition),
        next_id: EntityID = 0,

        const Self = @This();

        fn TemplateStorage() type {
            const template_fs = @typeInfo(@TypeOf(templates)).@"struct".fields;
            comptime var types: [template_fs.len]type = undefined;

            inline for (template_fs, 0..) |template_f, template_i| {
                const Template = @field(templates, template_f.name);

                types[template_i] = std.MultiArrayList(Template);
            }

            return @Tuple(&types);
        }

        fn initTemplateStorage() TemplateStorage() {
            var storage: TemplateStorage() = undefined;

            const template_storage_fs = @typeInfo(TemplateStorage()).@"struct".fields;
            inline for (template_storage_fs) |template_storage_f| {
                @field(storage, template_storage_f.name) = .{};
            }

            return storage;
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .templates = initTemplateStorage(),
                .entity_positions = std.AutoHashMap(EntityID, EntityPosition).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            const template_storage_fs = @typeInfo(TemplateStorage()).@"struct".fields;
            inline for (template_storage_fs) |template_storage_f| {
                @field(self.templates, template_storage_f.name).deinit(self.allocator);
            }

            self.entity_positions.deinit();
        }

        /// Registers a new entity: matches entity to the correct archetype and adds the data
        /// entity_data - struct instance containing data for an entity matching an archetype
        pub fn spawn(self: *Self, entity_data: anytype) !EntityID {
            const Template = @TypeOf(entity_data);
            RequireStruct(Template, "entity_data");

            const template_fs = @typeInfo(@TypeOf(templates)).@"struct".fields;
            comptime var template_i: ?TemplateIdx = null;
            inline for (template_fs, 0..) |template_f, i| {
                if (@field(templates, template_f.name) == Template) {
                    template_i = i;
                    break;
                }
            }

            const id = self.next_id;

            const template_idx = template_i orelse @compileError(@typeName(Template) ++ " does not match the type of any templates");

            const template_data = &@field(self.templates, std.fmt.comptimePrint("{}", .{template_idx}));
            try template_data.append(self.allocator, entity_data);
            const entity_pos_idx = template_data.len - 1;

            try self.entity_positions.put(id, .{
                .template_idx = template_idx,
                .entity_idx = entity_pos_idx,
            });

            self.next_id += 1;

            return id;
        }

        /// Queries for component types within the archetypes
        /// has - tuple of types, what components an archetype must have
        /// not - tuple of types, what components an archetype must not have
        /// maybe - tuple of types, what components an archetype could have, captures components if an archetype has them
        /// RETURNS - std.ArrayList of pointers to components
        ///
        /// EX: query(.{Position, Velocity}, .{Attack}, .{Health})
        pub fn query(self: Self, comptime has: anytype, comptime not: anytype, comptime maybe: anytype) !std.ArrayList(std.MultiArrayList(type).Slice) {
            RequireStruct(@TypeOf(has), "has");
            RequireStruct(@TypeOf(not), "not");
            RequireStruct(@TypeOf(maybe), "maybe");

            comptime var template_data_slices = std.ArrayList(std.MultiArrayList.Slice).empty;

            const has_fs = @typeInfo(@TypeOf(has)).@"struct".fields; // {Position, Velocity}
            const not_fs = @typeInfo(@TypeOf(not)).@"struct".fields; // {Attack}
            const maybe_fs = @typeInfo(@TypeOf(maybe)).@"struct".fields; // {Health}

            const templates_fs = @typeInfo(@TypeOf(templates)).@"struct".fields; // {Player, Tree, UI_Element, ...}
            archetype_for: inline for (templates_fs, 0..) |templates_f, templates_i| {
                const Template = @field(templates, templates_f.name); // Player
                const template_fs = @typeInfo(Template).@"struct".fields; // {Health, Position, Velocity, Attack, ...}

                inline for (template_fs) |template_f| {
                    inline for (not_fs) |not_f| {
                        const Required = @field(not, not_f.name);

                        if (template_f.type == Required) {
                            continue :archetype_for;
                        }
                    }

                    inline for (has_fs) |has_f| {
                        const Required = @field(has, has_f.name);
                        comptime var found = false;
                        if (template_f.type == Required) {
                            found = true;
                            break;
                        }
                        if (!found) continue :archetype_for;
                    }

                    inline for (maybe_fs) |maybe_f| {
                        const Required = @field(maybe, maybe_f.name);

                        if (template_f.type == Required) {
                            break;
                        }
                    }

                    const template_data = &@field(self.archetypes, std.fmt.comptimePrint("{}", .{templates_i}));
                    @compileLog(template_data.slice());
                    template_data_slices.append(self.allocator, template_data.slice());
                }
            }

            return;
        }
    };
}
