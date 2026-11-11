const std = @import("std");

pub const TemplateIdx = usize;
pub const EntityIdx = usize;
pub const Entity = u32;

// TODO: use type instead of template_idx
pub const EntityLocation = struct {
    Template: type,
    entity_idx: EntityIdx,
};

pub const StructInfo = struct {
    names: []const [:0]const u8,
    types: []const type,
    attrs: []const std.builtin.Type.Struct.FieldAttributes,
    len: usize,
};

fn structInfo(comptime T: type) StructInfo {
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
            const template_info = structInfo(Template);

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
    const ts_info = comptime structInfo(@TypeOf(templates));

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

        fn getTemplateData(storage: *const StorageType(), comptime T: type) *std.MultiArrayList(T) {
            comptime {
                const info = structInfo(StorageType());
                for (info.names, info.types) |name, U| {
                    if (T == U) {
                        return &@field(storage, name);
                    }
                }

                @compileError(@typeName(T) ++ " is not in any template");
            }
        }

        fn initTemplatesStorage() StorageType() {
            var storage: StorageType() = undefined;

            const storage_info = comptime structInfo(StorageType());
            inline for (storage_info.types) |T| {
                getTemplateData(&storage, T).* = .empty;
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
            const storage_info = comptime structInfo(StorageType());
            inline for (storage_info.types) |T| {
                getTemplateData(self.storage, T)
                    .deinit(self.allocator);
            }

            self.entity_locations.deinit();
        }

        pub fn spawn(self: *@This(), data: anytype) !Entity {
            const Template = @TypeOf(data);

            comptime var matched = false;
            inline for (ts_info.types) |T| {
                if (T == Template) {
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                @compileError("data of type " ++ @typeName(Template) ++ " does not match any template");
            }

            var template_data = getTemplateData(
                self.storage,
                Template,
            );

            try template_data.append(self.allocator, data);

            const entity_pos_idx = template_data.len - 1;

            const entity = self.next_entity;

            try self.entity_locations.put(entity, .{
                .Template = Template,
                .entity_idx = entity_pos_idx,
            });

            self.next_entity += 1;

            return entity;
        }

        pub fn QueryView(comptime has: anytype) type {
            const has_info = comptime structInfo(@TypeOf(has));

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
                data_view: View, // TODO: make this an array of views for each matched archetype

                pub fn len(self: *const @This()) usize {
                    // all the slices in the view are the same size
                    return self.data_view.@"0".len;
                }

                pub fn getComponents(self: *@This(), comptime Component: type) []Component {
                    const info = comptime structInfo(View);

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
            comptime Template: type,
        ) bool {
            const template_info = structInfo(Template); // {Health, Position, Velocity, Attack, ...}

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
        ///
        /// EX: query(.{Position, Velocity}, .{Attack}, .{Health})
        pub fn query(self: *@This(), comptime has: anytype, comptime not: anytype) !Query(has) {
            const has_info = structInfo(@TypeOf(has)); // {Position, Velocity}
            const not_info = structInfo(@TypeOf(not)); // {Attack}

            const result_query: Query(has) = .{};
            inline for (ts_info.types) |Template| {
                comptime {
                    if (!templateMatches(
                        not,
                        has,
                        not_info,
                        has_info,
                        Template,
                    )) {
                        continue;
                    }
                }

                // get found data
                var template_data = getTemplateData(
                    self.storage,
                    Template,
                );

                inline for (has_info.types) |C| {
                    result_query.getComponents(C).* = template_data.items(C);
                }

                // for (0..template_data.len) |entity_i| {
                //     const Element = QueryElement(has);
                //     const element_info = comptime structInfo(Element);
                //
                //     var query_element: Element = undefined;
                //
                //     inline for (element_info.names, element_info.types) |name, QueryComponent| {
                //         // QueryComponent is an ?*, so those need to be removed to get the original type
                //         const Component = std.meta.Child(std.meta.Child(QueryComponent));
                //
                //         const query_data = @field(query_element, name);
                //
                //         // 'has' field
                //         if (query_data) {
                //             const FieldEnum = comptime std.meta.FieldEnum(Template);
                //             const field_tag = comptime std.meta.stringToEnum(FieldEnum, name).?;
                //             const slice = template_data.items(field_tag);
                //             query_data = &slice[entity_i];
                //         }
                //     }
                //
                //     try query_element_soa.append(self.allocator, query_element);
                // }
            }

            return result_query;
        }
    };
}
