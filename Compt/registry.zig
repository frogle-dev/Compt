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
    const templates_fs = @typeInfo(@TypeOf(templates)).@"struct".fields;

    return struct {
        allocator: std.mem.Allocator,

        templates: TemplatesStorage(),
        enabled_components: [templates_fs.len]std.DynamicBitSet,
        entity_positions: std.AutoHashMap(EntityID, EntityPosition),
        next_id: EntityID = 0,

        const Self = @This();

        fn TemplatesStorage() type {
            RequireStruct(@TypeOf(templates), "templates");

            comptime var types: [templates_fs.len]type = undefined;

            inline for (templates_fs, 0..) |templates_f, templates_i| {
                const Template = @field(templates, templates_f.name);
                RequireStruct(Template, "templates field");

                types[templates_i] = std.MultiArrayList(Template);
            }

            return @Tuple(&types);
        }

        fn initTemplatesStorage() TemplatesStorage() {
            var storage: TemplatesStorage() = undefined;

            const template_storage_fs = @typeInfo(TemplatesStorage()).@"struct".fields;
            inline for (template_storage_fs) |template_storage_f| {
                @field(storage, template_storage_f.name) = .{};
            }

            return storage;
        }

        pub fn init(allocator: std.mem.Allocator) !Self {
            var enabled_components: [templates_fs.len]std.DynamicBitSet = undefined;
            for (0..enabled_components.len) |i| {
                enabled_components[i] = try std.DynamicBitSet.initFull(allocator, 0);
            }

            return .{
                .allocator = allocator,
                .templates = initTemplatesStorage(),
                .enabled_components = enabled_components,
                .entity_positions = std.AutoHashMap(EntityID, EntityPosition).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            const template_storage_fs = @typeInfo(TemplatesStorage()).@"struct".fields;
            inline for (template_storage_fs) |template_storage_f| {
                @field(self.templates, template_storage_f.name).deinit(self.allocator);
            }

            for (&self.enabled_components) |*dynamic_bit_set| {
                dynamic_bit_set.deinit();
            }

            self.entity_positions.deinit();
        }

        /// Registers a new entity: matches entity to the correct archetype and adds the data
        /// entity_data - struct instance containing data for an entity matching an archetype
        pub fn spawn(self: *Self, entity_data: anytype) !EntityID {
            const Template = @TypeOf(entity_data);
            RequireStruct(Template, "entity_data");

            comptime var template_fs_len: usize = undefined;
            comptime var templates_i: ?TemplateIdx = null;
            inline for (templates_fs, 0..) |templates_f, i| {
                if (@field(templates, templates_f.name) == Template) {
                    templates_i = i;

                    template_fs_len = @typeInfo(Template).@"struct".fields.len;
                    break;
                }
            }

            const id = self.next_id;

            const template_idx = templates_i orelse @compileError(@typeName(Template) ++ " does not match the type of any templates");

            try self.enabled_components[template_idx].resize(self.enabled_components[template_idx].count() + template_fs_len, true);

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
        pub fn query(self: Self, comptime has: anytype, comptime not: anytype, comptime maybe: anytype) ![]std.MultiArrayList(type).Slice {
            RequireStruct(@TypeOf(has), "has");
            RequireStruct(@TypeOf(not), "not");
            RequireStruct(@TypeOf(maybe), "maybe");

            comptime var template_data_slices = std.ArrayList(std.MultiArrayList.Slice).empty;

            const has_fs = @typeInfo(@TypeOf(has)).@"struct".fields; // {Position, Velocity}
            const not_fs = @typeInfo(@TypeOf(not)).@"struct".fields; // {Attack}
            const maybe_fs = @typeInfo(@TypeOf(maybe)).@"struct".fields; // {Health}

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

        // TODO:
        pub fn enableComponent() !void {}

        pub fn disableComponent() !void {}

        pub fn isComponentEnabled() !bool {}
    };
}
