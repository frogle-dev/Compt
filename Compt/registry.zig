const std = @import("std");

pub const ArchetypeIdx = usize;
pub const EntityIdx = usize;
pub const EntityID = u32;

pub const EntityPosition = struct {
    archetype_idx: ArchetypeIdx,
    entity_idx: EntityIdx,
};

// const ComponentsPosition = struct {
//     archetype_idx: ArchetypeIdx,
//     component_name: []const u8,
//     component_type: type,
// };

fn RequireStruct(comptime T: type, comptime name: []const u8) void {
    if (@typeInfo(T) != .@"struct")
        @compileError(@typeName(T) ++ " is not a struct: '" ++ name ++ "' must be a struct");
}

pub fn Component(comptime T: type) type {
    return struct {
        data: T,
        enabled: bool,
    };
}

pub fn ComponentizeEntity(comptime )

fn ArchetypeStorage(comptime archetypes: anytype) type {
    const arch_fields = @typeInfo(@TypeOf(archetypes)).@"struct".fields;
    comptime var types: [arch_fields.len]type = undefined;

    inline for (arch_fields, 0..) |field, i| {
        const ArchetypeTemplate = @field(archetypes, field.name);

        const archetype_template_fields = @typeInfo(ArchetypeTemplate).@"struct".fields;

        comptime var names: [archetype_template_fields.len][]const u8 = undefined;
        comptime var template_types: [archetype_template_fields.len]type = undefined;
        comptime var attrs: [archetype_template_fields.len]std.builtin.Type.StructField.Attributes = undefined;

        inline for (archetype_template_fields, 0..) |archetype_template_field, template_idx| {
            names[template_idx] = archetype_template_field.name;
            template_types[template_idx] = Component(archetype_template_field.type);
            attrs[template_idx] = std.builtin.Type.StructField.Attributes{
                .default_value_ptr = archetype_template_field.default_value_ptr,
                .@"align" = archetype_template_field.alignment,
                .@"comptime" = archetype_template_field.is_comptime,
            };
        }

        const ArchetypeTemplateComponentized = @Struct(.auto, null, &names, &template_types, &attrs);

        types[i] = std.MultiArrayList(ArchetypeTemplateComponentized);
    }

    return @Tuple(&types);
}

fn initArchetypeStorage(comptime archetypes: anytype) ArchetypeStorage(archetypes) {
    var storage: ArchetypeStorage(archetypes) = undefined;

    const fields = @typeInfo(ArchetypeStorage(archetypes)).@"struct".fields;
    inline for (fields) |field| {
        @field(storage, field.name) = .{};
    }

    return storage;
}

/// Registry stores and manages all the data of the ECS
pub fn Registry(comptime archetypes: anytype) type {
    return struct {
        allocator: std.mem.Allocator,

        archetypes: ArchetypeStorage(archetypes),
        entity_positions: std.AutoHashMap(EntityID, EntityPosition),
        next_id: EntityID = 0,
        // archetypes_entities: [@typeInfo(@TypeOf(archetypes)).@"struct".fields.len]EntityIdx,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .archetypes = initArchetypeStorage(archetypes),
                .entity_positions = std.AutoHashMap(EntityID, EntityPosition).init(allocator),
                // .archetypes_entities = std.mem.zeroes([@typeInfo(@TypeOf(archetypes)).@"struct".fields.len]std.ArrayList(usize)),
            };
        }

        pub fn deinit(self: *Self) void {
            const fields = @typeInfo(ArchetypeStorage(archetypes)).@"struct".fields;
            inline for (fields) |field| {
                @field(self.archetypes, field.name).deinit(self.allocator);
            }

            self.entity_positions.deinit();

            // for (self.archetypes_entities) |archetype_entities| {
            //     archetype_entities.deinit(self.allocator);
            // }
        }

        /// Registers a new entity: matches entity to the correct archetype and adds the data
        /// entity_data - struct instance containing data for an entity matching an archetype
        pub fn spawn(self: *Self, entity_data: anytype) !EntityID {
            const Entity_Type = @TypeOf(entity_data);
            RequireStruct(Entity_Type, "entity_data");

            const fields = @typeInfo(@TypeOf(archetypes)).@"struct".fields;
            comptime var archetype_idx: ?ArchetypeIdx = null;
            inline for (fields, 0..) |field, i| {
                if (@field(archetypes, field.name) == Entity_Type) {
                    archetype_idx = i;
                    break;
                }
            }

            const id = self.next_id;

            const arch_idx = archetype_idx orelse @compileError(@typeName(Entity_Type) ++ " does not match the type of any archetypes");

            const archetype_data = &@field(self.archetypes, std.fmt.comptimePrint("{}", .{arch_idx}));
            try archetype_data.append(self.allocator, Component(Entity_Type){ .data = entity_data, .enabled = true });
            const entity_pos_idx = archetype_data.len - 1;

            try self.entity_positions.put(id, .{
                .archetype_idx = arch_idx,
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
        pub fn query(self: Self, comptime has: anytype, comptime not: anytype, comptime maybe: anytype) !std.ArrayList(*Component(type)) {
            RequireStruct(@TypeOf(has), "has");
            RequireStruct(@TypeOf(not), "not");
            RequireStruct(@TypeOf(maybe), "maybe");

            // comptime var component_positions = std.ArrayList(ComponentsPosition);
            comptime var components = std.ArrayList(*Component(type)).empty;

            const has_fields = @typeInfo(@TypeOf(has)).@"struct".fields; // {Position, Velocity}
            const not_fields = @typeInfo(@TypeOf(not)).@"struct".fields; // {Attack}
            const maybe_fields = @typeInfo(@TypeOf(maybe)).@"struct".fields; // {Health}

            const archetypes_fields = @typeInfo(@TypeOf(archetypes)).@"struct".fields; // {Player, Tree, UI_Element, ...}
            archetype_for: inline for (archetypes_fields, 0..) |archetypes_field, archetype_idx| {
                const Archetype = @field(archetypes, archetypes_field.name); // Player
                const archetype_fields = @typeInfo(Archetype).@"struct".fields; // {Health, Position, Velocity, Attack, ...}

                inline for (archetype_fields) |arch_field| {
                    inline for (not_fields) |not_field| {
                        const Required = @field(not, not_field.name);

                        if (arch_field.type == Required) {
                            continue :archetype_for;
                        }
                    }

                    const archetype_data = @field(self.archetypes, std.fmt.comptimePrint("{}", .{archetype_idx}));

                    inline for (has_fields) |has_field| {
                        const Required = @field(has, has_field.name);
                        comptime var found = false;
                        if (arch_field.type == Required) {
                            // try component_positions.append(self.allocator, ComponentsPosition{
                            //     .component_name = arch_field.name,
                            //     .component_type = arch_field.type,
                            //     .archetype_idx = archetype_idx,
                            // });
                            for (0..archetype_data.len) |i| {
                                const component = &@field(archetype_data.get(i), arch_field.name);
                                try components.append(self.allocator, component);
                            }

                            found = true;
                            break;
                        }
                        if (!found) continue :archetype_for;
                    }

                    inline for (maybe_fields) |maybe_field| {
                        const Required = @field(maybe, maybe_field.name);

                        if (arch_field.type == Required) {
                            // try component_positions.append(self.allocator, ComponentsPosition{
                            //     .component_name = arch_field.name,
                            //     .component_type = arch_field.type,
                            //     .archetype_idx = archetype_idx,
                            // });
                            for (0..archetype_data.len) |idx| {
                                const component = &@field(archetype_data.get(idx), arch_field.name);
                                try components.append(self.allocator, component);
                            }

                            break;
                        }
                    }
                }
            }

            return components;
        }

        // /// Finds and returns the component in archetype component_pos.archetype_idx, then the entity in the archetype at entity_idx, and finally grabs the component by name
        // /// components_pos - position of a components arraylist
        // /// entity_idx - position of a specific entity in an archetype
        // /// RETURNS - pointer to the found component
        // ///
        // /// Emits a compile error if no component found
        // pub fn getComponent(self: Self, comptime components_pos: ComponentsPosition, comptime entity_idx: EntityIdx) *Component(components_pos.component_type) {
        //     if (components_pos.archetype_idx >= @typeInfo(@TypeOf(self.archetypes)).@"struct".fields.len)
        //         @compileError("components_pos.archetype_idx(" ++ components_pos.archetype_idx ++ ") is greater than the length of the archetypes tuple");
        //
        //     const archetype = @field(self.archetypes, std.fmt.comptimePrint("{}", components_pos.archetype_idx));
        //     const entity = comptime archetype.get(entity_idx);
        //
        //     if (!@hasField(@TypeOf(entity), components_pos.component_name))
        //         @compileError("no field in entity named components_pos.component_name(" ++ components_pos.component_name ++ ")");
        //     const component = &@field(entity, components_pos.component_name);
        //
        //     return component;
        // }
    };
}
