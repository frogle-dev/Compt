const std = @import("std");

pub const TemplateIdx = usize;
pub const EntityIdx = usize;
pub const EntityID = u32;

pub const EntityPosition = struct {
    template_idx: TemplateIdx,
    entity_idx: EntityIdx,
};

fn getStructFields(comptime T: type) []const std.builtin.Type.StructField {
    return @typeInfo(T).@"struct".fields;
}

/// Removes file name prepended to type name. ie: tests.Position. Used so accessing component slices from query is more elegant
fn shortTypeName(comptime T: type) [:0]const u8 {
    const full = @typeName(T);

    comptime var i = full.len;
    while (i > 0) : (i -= 1) {
        if (full[i - 1] == '.') return full[i..];
    }

    return full;
}

/// Registry stores and manages all the data of the ECS
pub fn Registry(comptime templates: anytype) type {
    const templates_fs = comptime getStructFields(@TypeOf(templates));

    return struct {
        allocator: std.mem.Allocator,

        templates: TemplatesStorage(),
        enabled_components: [templates_fs.len]std.DynamicBitSet,
        entity_positions: std.AutoHashMap(EntityID, EntityPosition),
        next_id: EntityID = 0,

        const Self = @This();

        fn TemplatesStorage() type {
            comptime var types: [templates_fs.len]type = undefined;

            inline for (templates_fs, 0..) |templates_f, templates_i| {
                const Template = @field(templates, templates_f.name);

                types[templates_i] = std.MultiArrayList(Template);
            }

            return @Tuple(&types);
        }

        fn initTemplatesStorage() TemplatesStorage() {
            var storage: TemplatesStorage() = undefined;

            const template_storage_fs = comptime getStructFields(TemplatesStorage());
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
            const template_storage_fs = comptime getStructFields(TemplatesStorage());
            inline for (template_storage_fs) |template_storage_f| {
                @field(self.templates, template_storage_f.name).deinit(self.allocator);
            }

            for (&self.enabled_components) |*dynamic_bit_set| {
                dynamic_bit_set.deinit();
            }

            self.entity_positions.deinit();
        }

        /// Registers a new entity: matches entity to the correct template and adds the data
        /// entity_data - struct instance containing data for an entity matching an template
        pub fn spawn(self: *Self, entity_data: anytype) !EntityID {
            const Template = @TypeOf(entity_data);

            comptime var template_fs_len: usize = undefined;
            comptime var templates_i: ?TemplateIdx = null;
            inline for (templates_fs, 0..) |templates_f, i| {
                if (@field(templates, templates_f.name) == Template) {
                    templates_i = i;

                    template_fs_len = comptime getStructFields(Template).len;
                    break;
                }
            }

            const id = self.next_id;

            const template_idx = templates_i orelse @compileError(@typeName(Template) ++ " does not match the type of any templates");

            try self.enabled_components[template_idx].resize(self.enabled_components[template_idx].count() + template_fs_len, true);

            // const template_data = &@field(self.templates, std.fmt.comptimePrint("{}", .{template_idx}));
            var template_data = &@field(self.templates, std.fmt.comptimePrint("{}", .{template_idx}));
            try template_data.append(self.allocator, entity_data);
            const entity_pos_idx = template_data.len - 1;

            try self.entity_positions.put(id, .{
                .template_idx = template_idx,
                .entity_idx = entity_pos_idx,
            });

            self.next_id += 1;

            return id;
        }

        pub fn QueryResult(comptime has: anytype, comptime maybe: anytype) type {
            const has_fs = comptime getStructFields(@TypeOf(has));
            const maybe_fs = comptime getStructFields(@TypeOf(maybe));
            const len = comptime has_fs.len + maybe_fs.len;

            comptime var names: [len][]const u8 = undefined;
            comptime var types: [len]type = undefined;
            comptime var attrs: [len]std.builtin.Type.StructField.Attributes = undefined;

            inline for (has_fs, 0..) |has_f, i| {
                const Component = @field(has, has_f.name);
                names[i] = comptime shortTypeName(Component);
                types[i] = *Component;
                attrs[i] = std.builtin.Type.StructField.Attributes{
                    .@"align" = @alignOf(*Component),
                    .@"comptime" = false,
                    .default_value_ptr = null,
                };
            }

            inline for (maybe_fs, 0..) |maybe_f, i| {
                const Component = @field(maybe, maybe_f.name);
                names[has_fs.len + i] = comptime shortTypeName(Component);
                types[has_fs.len + i] = ?*Component;
                attrs[has_fs.len + i] = std.builtin.Type.StructField.Attributes{
                    .@"align" = @alignOf(*Component),
                    .@"comptime" = false,
                    .default_value_ptr = null,
                };
            }

            return @Struct(.auto, null, &names, &types, &attrs);
        }

        pub fn Query(comptime has: anytype, comptime maybe: anytype) type {
            const Result = QueryResult(has, maybe);

            return struct {
                data_view: std.MultiArrayList(Result) = std.MultiArrayList(Result).empty,

                pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
                    self.data_view.deinit(gpa);
                }

                pub fn queryResultCount(self: @This()) usize {
                    return self.data_view.len;
                }

                pub fn getHasComponents(self: @This(), comptime Component: type) []*Component {
                    const FieldEnum = std.meta.FieldEnum(Result);
                    const field_tag = comptime std.meta.stringToEnum(FieldEnum, shortTypeName(Component)).?;
                    return self.data_view.items(field_tag);
                }

                pub fn getMaybeComponents(self: @This(), comptime Component: type) []?*Component {
                    const FieldEnum = std.meta.FieldEnum(Result);
                    const field_tag = comptime std.meta.stringToEnum(FieldEnum, shortTypeName(Component)).?;
                    return self.data_view.items(field_tag);
                }
            };
        }

        /// Queries for component types within the templates
        /// has - tuple of types, what components an template must have
        /// not - tuple of types, what components an template must not have
        /// maybe - tuple of types, what components an template could have, captures components if an template has them
        /// RETURNS - std.MultiArrayList containing a QueryResult which stores pointers to the components listed in has and maybe
        ///
        /// EX: query(.{Position, Velocity}, .{Attack}, .{Health})
        pub fn query(self: Self, comptime has: anytype, comptime not: anytype, comptime maybe: anytype) !Query(has, maybe) {
            var query_result_soa = std.MultiArrayList(QueryResult(has, maybe)).empty;

            const has_fs = comptime getStructFields(@TypeOf(has)); // {Position, Velocity}
            const not_fs = comptime getStructFields(@TypeOf(not)); // {Attack}

            templates_for: inline for (templates_fs, 0..) |templates_f, templates_i| {
                const Template = @field(templates, templates_f.name); // Player
                const template_fs = comptime getStructFields(Template); // {Health, Position, Velocity, Attack, ...}

                comptime var matched = false;
                inline for (template_fs) |template_f| {
                    // skip templates containing components in NOT
                    inline for (not_fs) |not_f| {
                        const Not = @field(not, not_f.name);

                        if (template_f.type == Not) {
                            continue :templates_for;
                        }
                    }

                    // skip templates not containing all components in HAS
                    inline for (has_fs) |has_f| {
                        const Has = @field(has, has_f.name);
                        if (template_f.type == Has) {
                            matched = true;
                            break;
                        }
                    }
                }
                if (!matched) {
                    continue :templates_for;
                }

                // get found data
                const template_data = @field(self.templates, std.fmt.comptimePrint("{}", .{templates_i}));
                for (0..template_data.len) |entity_i| {
                    var query_result: QueryResult(has, maybe) = undefined;

                    inline for (comptime getStructFields(QueryResult(has, maybe))) |query_result_f| {
                        const Component =
                            if (@typeInfo(query_result_f.type) == .optional) std.meta.Child(std.meta.Child(query_result_f.type)) else std.meta.Child(query_result_f.type);

                        comptime var component_name: ?[]const u8 = null;
                        inline for (template_fs) |template_f| {
                            if (template_f.type == Component) {
                                component_name = template_f.name;
                            }
                        }

                        if (component_name) |name| { // HAS field
                            const FieldEnum = comptime std.meta.FieldEnum(Template);
                            const field_tag = comptime std.meta.stringToEnum(FieldEnum, name).?;
                            const slice = template_data.items(field_tag);
                            @field(query_result, shortTypeName(Component)) = &slice[entity_i];
                        } else { // MAYBE field
                            @field(query_result, shortTypeName(Component)) = null;
                        }
                    }

                    try query_result_soa.append(self.allocator, query_result);
                }
            }

            return .{
                .data_view = query_result_soa,
            };
        }

        // TODO:
        pub fn enableComponent() !void {}

        pub fn disableComponent() !void {}

        pub fn isComponentEnabled() !bool {}
    };
}
