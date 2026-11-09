const std = @import("std");

pub const TemplateIdx = usize;
pub const EntityIdx = usize;
pub const Entity = u32;

// TODO: use type instead of template_idx
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
    comptime {
        _, const after = std.mem.cutScalarLast(u8, name, '.') orelse return name;

        return after;
    }
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

        pub fn QueryView(comptime has: anytype) type {
            const has_info = comptime getStructFields(@TypeOf(has));

            comptime var types: [has_info.len]type = undefined;

            inline for (has_info.names, 0..) |name, i| {
                const Component: type = @field(has, name);
                types[i] = []Component;
            }

            return @Tuple(&types);
        }

        pub fn Query(comptime has: anytype) type {
            const View = QueryView(has);

            return struct {
                data_view: View = .empty,

                pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                    self.data_view.deinit(allocator);
                }

                pub fn len(self: *const @This()) usize {
                    return self.data_view.len;
                }

                pub fn getComponents(self: *@This(), comptime Component: type) []Component {
                    const info = comptime getStructFields(View);

                    inline for (info.names, info.types) |name, ArrType| {
                        // slice must be removed for original type
                        const Type = std.meta.Child(ArrType);

                        if (Type == Component) {
                            return @field(self.data_view, name);
                        }
                    }

                    @compileError(@typeName(Component) ++ " does not match any components in the query");
                }
            };
        }

        fn templateMatches(
            comptime not: anytype,
            comptime has: anytype,
            comptime not_info: StructInfo,
            comptime has_info: StructInfo,
            comptime template_name: [:0]const u8,
        ) bool {
            const Template: type = @field(templates, template_name); // Player
            const template_info = getStructFields(Template); // {Health, Position, Velocity, Attack, ...}

            var matched: usize = 0;

            for (template_info.types) |ComponentType| {
                // skip templates containing components in 'not'
                for (not_info.names) |name| {
                    const Not: type = @field(not, name);

                    if (ComponentType == Not) {
                        return false;
                    }
                }

                // skip templates not containing all components in 'has'
                for (has_info.names) |name| {
                    const Has: type = @field(has, name);

                    if (ComponentType == Has) {
                        matched += 1;
                        break;
                    }
                }
            }

            if (matched != has_info.len) {
                return false;
            }

            return true;
        }

        /// Queries for component types within the templates
        /// has - tuple of types, what components a template must have
        /// not - tuple of types, what components a template must not have
        /// maybe - tuple of types, what components a template could have
        ///
        /// EX: query(.{Position, Velocity}, .{Attack}, .{Health})
        pub fn query(self: *@This(), comptime has: anytype, comptime not: anytype) !Query(has) {
            var query_element_soa: std.MultiArrayList(QueryElement(has)) = .empty;

            const has_info = getStructFields(@TypeOf(has)); // {Position, Velocity}
            const not_info = getStructFields(@TypeOf(not)); // {Attack}

            inline for (ts_info.names, 0..) |template_name, template_i| {
                comptime {
                    if (!templateMatches(
                        not,
                        has,
                        not_info,
                        has_info,
                        template_name,
                    )) {
                        continue;
                    }
                }

                // get found data
                var template_data = getTemplateData(
                    self.storage,
                    ts_info.types[template_i],
                    std.fmt.comptimePrint("{}", .{template_i}),
                );

                for (0..template_data.len) |entity_i| {
                    const Element = QueryElement(has);
                    const element_info = comptime getStructFields(Element);

                    var query_element: Element = undefined;

                    inline for (element_info.names, element_info.types) |name, QueryComponent| {
                        // QueryComponent is an ?*, so those need to be removed to get the original type
                        const Component = std.meta.Child(std.meta.Child(QueryComponent));

                        const query_data = @field(query_element, name);

                        // 'has' field
                        if (query_data) {
                            const FieldEnum = comptime std.meta.FieldEnum(Template);
                            const field_tag = comptime std.meta.stringToEnum(FieldEnum, name).?;
                            const slice = template_data.items(field_tag);
                            query_data = &slice[entity_i];
                        }
                    }

                    try query_element_soa.append(self.allocator, query_element);
                }
            }

            return .{
                .data_view = query_element_soa,
            };
        }
    };
}
