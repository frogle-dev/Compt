const std = @import("std");

pub const TemplateIdx = usize;
pub const EntityIdx = usize;
pub const Entity = u32;

pub const EntityLocation = struct {
    template_idx: TemplateIdx,
    entity_idx: EntityIdx,
};

pub const StructInfo = struct {
    names: []const [:0]const u8,
    types: []const type,
    attrs: []const std.builtin.Type.Struct.FieldAttributes,
    len: usize,
};

fn getStructFields(comptime T: type) StructInfo {
    comptime {
        const info = @typeInfo(T).@"struct";

        return .{
            .names = info.field_names,
            .types = info.field_types,
            .attrs = info.field_attrs,
            .len = info.field_names.len,
        };
    }
}

/// ex: "main.Position" -> "Position"
fn stripTypePrefix(comptime name: [:0]const u8) []const u8 {
    _, const after = std.mem.cutScalarLast(u8, name, '.') orelse return name;

    return after;
}

fn checkForDuplicateComponents(comptime templates: anytype, comptime templates_info: StructInfo) void {
    comptime {
        for (templates_info.names) |template_name| {
            const Template = @field(templates, template_name);
            const template_info = getStructFields(Template);

            for (template_info.types, 0..) |component_type, component_i| {
                for (template_info.types, 0..) |other_type, other_i| {
                    if (component_i != other_i and component_type == other_type) {
                        @compileError("Template '" ++ @typeName(Template) ++ "' has duplicate component type: " ++ @typeName(component_type));
                    }
                }
            }
        }
    }
}

pub fn World(comptime templates: anytype) type {
    const ts_info = comptime getStructFields(@TypeOf(templates));

    checkForDuplicateComponents(templates, ts_info);

    return struct {
        allocator: std.mem.Allocator,

        storage: StorageType(),

        entity_locations: std.AutoHashMap(Entity, EntityLocation),
        next_entity: Entity = 0,

        fn StorageType() type {
            comptime {
                var types: [ts_info.len]type = undefined;

                for (ts_info.names, 0..) |template_name, template_i| {
                    const Template = @field(templates, template_name);

                    types[template_i] = std.MultiArrayList(Template);
                }

                return @Tuple(&types);
            }
        }

        fn getTemplateData(storage: *const StorageType(), comptime T: type, comptime template_name: [:0]const u8) *std.MultiArrayList(T) {
            return &@field(storage, template_name);
        }

        fn initTemplatesStorage() StorageType() {
            var storage: StorageType() = undefined;

            const storage_info = comptime getStructFields(StorageType());
            inline for (storage_info.names, 0..) |name, i| {
                getTemplateData(&storage, storage_info.types[i], name).* = .empty;
            }

            return storage;
        }

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .allocator = allocator,
                .storage = initTemplatesStorage(),
                .entity_locations = .init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            const storage_info = comptime getStructFields(StorageType());
            inline for (storage_info.names, 0..) |name, i| {
                getTemplateData(self.storage, storage_info.types[i], name)
                    .deinit(self.allocator);
            }

            self.entity_locations.deinit();
        }

        pub fn spawn(self: *@This(), data: anytype) !Entity {
            const Template = @TypeOf(data);

            comptime var template_info_len: usize = undefined;
            comptime var matched_i: ?TemplateIdx = null;
            inline for (ts_info, 0..) |template_name, i| {
                if (@field(templates, template_name) == Template) {
                    matched_i = i;

                    template_info_len = getStructFields(Template).len;
                    break;
                }
            }

            const template_i = matched_i orelse {
                @compileError(@typeName(Template) ++ ", used in spawn, does not match the type of any templates");
            };

            var template_data = getTemplateData(
                self.storage,
                ts_info.types[template_i],
                std.fmt.comptimePrint("{}", .{template_i}),
            );

            try template_data.append(self.allocator, data);

            const entity_pos_idx = template_data.len - 1;

            const entity = self.next_entity;

            try self.entity_locations.put(entity, .{
                .template_idx = template_i,
                .entity_idx = entity_pos_idx,
            });

            self.next_entity += 1;

            return entity;
        }

        pub fn QueryResult(comptime has: anytype, comptime maybe: anytype) type {
            const has_info = comptime getStructFields(@TypeOf(has));
            const maybe_info = comptime getStructFields(@TypeOf(maybe));
            const len = comptime has_info.len + maybe_info.len;

            comptime var names: [len][]const u8 = undefined;
            comptime var types: [len]type = undefined;
            comptime var attrs: [len]std.builtin.Type.StructField.Attributes = undefined;

            inline for (has_fs, 0..) |has_f, i| {
                const Component = @field(has, has_f.name);
                names[i] = comptime shortTypeName(Component);
                types[i] = ?*Component;
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

        /// returned from query function
        /// data_view - contains pointers to the data found in the query
        pub fn Query(comptime has: anytype, comptime maybe: anytype) type {
            const Result = QueryResult(has, maybe);

            return struct {
                data_view: std.MultiArrayList(Result) = std.MultiArrayList(Result).empty,

                pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
                    self.data_view.deinit(gpa);
                }

                /// number of entities sourced from by the query
                pub fn queryResultCount(self: @This()) usize {
                    return self.data_view.len;
                }

                pub fn getComponents(self: @This(), comptime Component: type) []?*Component {
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
        /// RETURNS - Query struct
        ///
        /// EX: query(.{Position, Velocity}, .{Attack}, .{Health})
        pub fn query(self: *Self, comptime has: anytype, comptime not: anytype, comptime maybe: anytype) !Query(has, maybe) {
            var query_result_soa = std.MultiArrayList(QueryResult(has, maybe)).empty;

            const has_fs = comptime getStructFields(@TypeOf(has)); // {Position, Velocity}
            const not_fs = comptime getStructFields(@TypeOf(not)); // {Attack}

            templates_for: inline for (templates_fs, 0..) |templates_f, templates_i| {
                const Template = @field(templates, templates_f.name); // Player
                const template_fs = comptime getStructFields(Template); // {Health, Position, Velocity, Attack, ...}

                comptime var matched: usize = 0;
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
                            matched += 1;
                            break;
                        }
                    }
                }
                if (matched != has_fs.len) {
                    continue :templates_for;
                }

                // get found data
                const template_data = @field(self.templates, std.fmt.comptimePrint("{}", .{templates_i}));
                for (0..template_data.len) |entity_i| {
                    var query_result: QueryResult(has, maybe) = undefined;

                    inline for (comptime getStructFields(QueryResult(has, maybe))) |query_result_f| {
                        const Component = std.meta.Child(std.meta.Child(query_result_f.type));

                        comptime var component_name: ?[]const u8 = null;
                        inline for (template_fs) |template_f| {
                            if (template_f.type == Component) {
                                component_name = template_f.name;
                            }
                        }

                        if (component_name and isComponentEnabled(templates_i, entity_i, Component)) |name| { // HAS field
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
    };
}
