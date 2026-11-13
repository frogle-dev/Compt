const std = @import("std");

pub const TemplateIdx = usize;
pub const Entity = u32;

pub const EntityLocation = struct {
    template_idx: TemplateIdx,
    idx: usize,
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

fn checkForDuplicateComponents(comptime templates: []const type) void {
    comptime {
        for (templates) |Template| {
            const template_info = structInfo(Template);

            for (template_info.types, 0..) |Component, component_i| {
                for (template_info.types, 0..) |Other, other_i| {
                    if (component_i != other_i and Component == Other) {
                        @compileError("Template '" ++ @typeName(Template) ++ "' has duplicate component type: " ++ @typeName(Component));
                    }
                }
            }
        }
    }
}

pub fn World(comptime templates: []const type) type {
    checkForDuplicateComponents(templates);

    return struct {
        allocator: std.mem.Allocator,

        storage: StorageType(),

        entity_locations: std.AutoHashMap(Entity, EntityLocation),
        next_entity: Entity = 0,

        fn StorageType() type {
            comptime {
                var types: [templates.len]type = undefined;

                for (templates, 0..) |Template, template_i| {
                    types[template_i] = std.MultiArrayList(Template);
                }

                return @Tuple(&types);
            }
        }

        fn getTemplateData(storage: *StorageType(), comptime T: type) *std.MultiArrayList(T) {
            const info = comptime structInfo(StorageType());
            inline for (info.names, info.types) |name, U| {
                if (std.MultiArrayList(T) == U) {
                    return &@field(storage, name);
                }
            }

            @compileError(@typeName(T) ++ " is not in any template");
        }

        fn getConstTemplateData(storage: *const StorageType(), comptime T: type) *const std.MultiArrayList(T) {
            const info = comptime structInfo(StorageType());
            inline for (info.names, info.types) |name, U| {
                if (std.MultiArrayList(T) == U) {
                    return &@field(storage, name);
                }
            }

            @compileError(@typeName(T) ++ " is not in any template");
        }

        fn initTemplatesStorage() StorageType() {
            var storage: StorageType() = undefined;

            inline for (templates) |Template| {
                getTemplateData(&storage, Template).* = .empty;
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
            inline for (templates) |Template| {
                getTemplateData(&self.storage, Template)
                    .deinit(self.allocator);
            }

            self.entity_locations.deinit();
        }

        pub fn isCorrectLengths(self: *const @This()) bool {
            var sum: usize = 0;
            inline for (templates) |Template| {
                sum += getConstTemplateData(&self.storage, Template).len;
            }

            return sum == self.entity_locations.count();
        }

        pub fn spawn(self: *@This(), data: anytype) !Entity {
            const T = @TypeOf(data);

            comptime var template_idx: TemplateIdx = undefined;
            comptime var matched = false;
            inline for (templates, 0..) |Template, i| {
                if (T == Template) {
                    matched = true;
                    template_idx = i;
                    break;
                }
            }
            if (!matched) {
                @compileError("data of type " ++ @typeName(T) ++ " does not match any template");
            }

            var template_data = getTemplateData(
                &self.storage,
                T,
            );

            try template_data.append(self.allocator, data);

            const pos_idx = template_data.len - 1;

            const entity = self.next_entity;

            try self.entity_locations.put(entity, .{
                .template_idx = template_idx,
                .idx = pos_idx,
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

        pub fn Query(comptime has: anytype, comptime not: anytype) type {
            const has_info = structInfo(@TypeOf(has)); // {Position, Velocity}
            const not_info = structInfo(@TypeOf(not)); // {Attack}

            const View = QueryView(has);

            comptime var matched_templates: [templates.len]type = undefined;
            comptime var matched_count: usize = 0;
            inline for (templates, 0..) |Template, i| {
                if (templateMatches(
                    not,
                    has,
                    not_info,
                    has_info,
                    Template,
                )) {
                    matched_templates[i] = Template;
                    matched_count = i;
                }
            }

            return struct {
                const matched: [matched_count]type = matched_templates[0..matched_count];

                data_view: [matched_count]View,

                pub fn len(self: *const @This()) usize {
                    // all the slices in the view are the same size
                    return self.data_view.@"0".len;
                }

                // TODO: get function that mirrors std.MultiArrayList get function

                pub fn getComponents(self: *@This(), comptime Component: type) [matched_count][]Component {
                    const info = comptime structInfo(View);

                    var components: [matched_count][]Component = undefined;

                    inline for (0..matched_count) |i| {
                        inline for (info.names, info.types) |name, ArrType| {
                            // slice must be removed for original type
                            const Type = std.meta.Child(ArrType);

                            if (Type == Component) {
                                components[i] = @field(self.data_view, name);
                            }
                        }

                        @compileError(@typeName(Component) ++ " does not match any components in the query");
                    }

                    return components;
                }
            };
        }

        /// queries for component types within the templates
        /// has - tuple of types, what components a template must have
        /// not - tuple of types, what components a template must not have
        ///
        /// EX: query(.{Position, Velocity}, .{Attack})
        pub fn query(self: *@This(), comptime has: anytype, comptime not: anytype) !Query(has, not) {
            const has_info = structInfo(@TypeOf(has));

            const Q = Query(has, not);

            const result_query: Q = .{};
            inline for (Q.matched, 0..) |Template, i| {
                var template_data = getTemplateData(
                    self.storage,
                    Template,
                );

                inline for (has_info.types) |C| {
                    (result_query.getComponents(C).*)[i] = template_data.items(C);
                }
            }

            return result_query;
        }
    };
}
