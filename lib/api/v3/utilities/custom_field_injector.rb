#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

module API
  module V3
    module Utilities
      class CustomFieldInjector
        TYPE_MAP = {
          'string' => 'String',
          'text' => 'Formattable',
          'int' => 'Integer',
          'float' => 'Float',
          'date' => 'Date',
          'bool' => 'Boolean',
          'user' => 'User',
          'version' => 'Version',
          'list' => 'StringObject'
        }.freeze

        LINK_FORMATS = ['list', 'user', 'version'].freeze

        PATH_METHOD_MAP = {
          'user' => :user,
          'version' => :version,
          'list' => :string_object
        }.freeze

        NAMESPACE_MAP = {
          'user' => 'users',
          'version' => 'versions',
          'list' => 'string_objects'
        }.freeze

        REPRESENTER_MAP = {
          'user' => Users::UserRepresenter,
          'version' => Versions::VersionRepresenter,
          'list' => StringObjects::StringObjectRepresenter
        }.freeze

        class << self
          def create_value_representer(customizable, representer, embed_links: true)
            new_representer_class_with(representer, customizable) do |injector|
              customizable.available_custom_fields.each do |custom_field|
                injector.inject_value(custom_field, embed_links: embed_links)
              end
            end
          end

          def create_schema_representer(customizable, representer)
            new_representer_class_with(representer, customizable) do |injector|
              customizable.available_custom_fields.each do |custom_field|
                injector.inject_schema(custom_field, customized: customizable)
              end
            end
          end

          def create_value_representer_for_property_patching(customizable, representer)
            property_fields = customizable.available_custom_fields.select { |cf|
              property_field?(cf)
            }

            new_representer_class_with(representer, customizable) do |injector|
              property_fields.each do |custom_field|
                injector.inject_value(custom_field)
              end
            end
          end

          def create_value_representer_for_link_patching(customizable, representer)
            linked_fields = customizable.available_custom_fields.select { |cf|
              linked_field?(cf)
            }

            new_representer_class_with(representer, customizable) do |injector|
              linked_fields.each do |custom_field|
                injector.inject_patchable_link_value(custom_field)
              end
            end
          end

          def linked_field?(custom_field)
            LINK_FORMATS.include?(custom_field.field_format)
          end

          def property_field?(custom_field)
            !linked_field?(custom_field)
          end

          def new_representer_class_with(representer, customizable, &block)
            injector = new(representer, customizable)

            block.call injector

            injector.modified_representer_class
          end
        end

        def initialize(representer_class, customizable)
          @class = Class.new(representer_class) do
            class << self
              attr_accessor :customizable
            end
          end

          @class.customizable = customizable

          @class
        end

        def modified_representer_class
          @class
        end

        def inject_schema(custom_field, customized: nil)
          case custom_field.field_format
          when 'version'
            inject_version_schema(custom_field, customized)
          when 'user'
            inject_user_schema(custom_field, customized)
          when 'list'
            inject_list_schema(custom_field, customized)
          else
            inject_basic_schema(custom_field)
          end
        end

        def inject_value(custom_field, embed_links: false)
          case custom_field.field_format
          when *LINK_FORMATS
            inject_link_value(custom_field)
            inject_embedded_link_value(custom_field) if embed_links
          else
            inject_property_value(custom_field)
          end
        end

        def inject_patchable_link_value(custom_field)
          property = property_name(custom_field.id)
          path = path_method_for(custom_field)
          expected_namespace = NAMESPACE_MAP[custom_field.field_format]

          @class.property property,
                          exec_context: :decorator,
                          getter: link_value_getter_for(custom_field, path),
                          setter: link_value_setter_for(custom_field, property, expected_namespace)
        end

        private

        def property_name(id)
          "customField#{id}".to_sym
        end

        def inject_version_schema(custom_field, customized)
          raise ArgumentError unless customized

          @class.schema_with_allowed_collection property_name(custom_field.id),
                                                type: 'Version',
                                                name_source: -> (*) { custom_field.name },
                                                values_callback: -> (*) {
                                                  customized
                                                    .assignable_custom_field_values(custom_field)
                                                },
                                                writable: true,
                                                value_representer: Versions::VersionRepresenter,
                                                link_factory: -> (version) {
                                                  {
                                                    href: api_v3_paths.version(version.id),
                                                    title: version.name
                                                  }
                                                },
                                                required: custom_field.is_required
        end

        def inject_user_schema(custom_field, customized)
          raise ArgumentError unless customized

          @class.schema_with_allowed_link property_name(custom_field.id),
                                          type: 'User',
                                          writable: true,
                                          name_source: -> (*) { custom_field.name },
                                          required: custom_field.is_required,
                                          href_callback: -> (*) {
                                            # for now we ASSUME that every customized that has a
                                            # user custom field, will also define a project...
                                            api_v3_paths.available_assignees(customized.project.id)
                                          }
        end

        def inject_list_schema(custom_field, customized)
          representer = StringObjects::StringObjectRepresenter
          type = custom_field.multi_value ? "[]StringObject" : "StringObject"
          name_source = -> (*) { custom_field.name }
          values_callback = -> (*) { customized.assignable_custom_field_values(custom_field) }
          link_factory = -> (value) do
            # allow both single values and tuples for
            # custom titles
            {
              href: api_v3_paths.string_object(value),
              title: Array(value).first
            }
          end

          @class.schema_with_allowed_collection(
            property_name(custom_field.id),
            type: type,
            name_source: name_source,
            values_callback: values_callback,
            value_representer: representer,
            writable: true,
            link_factory: link_factory,
            required: custom_field.is_required
          )
        end

        def inject_basic_schema(custom_field)
          @class.schema property_name(custom_field.id),
                        type: TYPE_MAP[custom_field.field_format],
                        name_source: -> (*) { custom_field.name },
                        required: custom_field.is_required,
                        has_default: (not custom_field.default_value.nil?),
                        writable: true,
                        min_length: (custom_field.min_length if custom_field.min_length > 0),
                        max_length: (custom_field.max_length if custom_field.max_length > 0),
                        regular_expression: (custom_field.regexp unless custom_field.regexp.blank?)
        end

        def path_method_for(custom_field)
          PATH_METHOD_MAP[custom_field.field_format]
        end

        def inject_link_value(custom_field)
          getter = link_value_getter_for(custom_field, path_method_for(custom_field))

          if custom_field.multi_value?
            @class.links property_name(custom_field.id) do
              instance_exec(&getter)
            end
          else
            @class.link property_name(custom_field.id) do
              instance_exec(&getter)
            end
          end
        end

        def link_value_getter_for(custom_field, path_method)
          LinkValueGetter.new custom_field, path_method
        end

        def link_value_setter_for(custom_field, property, expected_namespace)
          -> (link_object, *) {
            values = Array([link_object].flatten).flat_map do |link|
              href = link['href']
              value = if href
                ::API::Utilities::ResourceLinkParser.parse_id(
                  href,
                  property: property,
                  expected_version: '3',
                  expected_namespace: expected_namespace
                )
              end

              [value].compact
            end

            represented.custom_field_values = { custom_field.id => values }
          }
        end

        def inject_embedded_link_value(custom_field)
          getter = proc do
            value = represented.send custom_field.accessor_name

            if value
              if custom_field.field_format == "list"
                nil # do not embed multi select values
              else
                representer_class = REPRESENTER_MAP[custom_field.field_format]

                representer_class.new(value, current_user: current_user)
              end
            end
          end

          @class.property(
            property_name(custom_field.id),
            embedded: true,
            exec_context: :decorator,
            getter: getter
          )
        end

        def inject_property_value(custom_field)
          @class.property property_name(custom_field.id),
                          getter: property_value_getter_for(custom_field),
                          setter: property_value_setter_for(custom_field),
                          render_nil: true
        end

        def property_value_getter_for(custom_field)
          -> (*) {
            value = send custom_field.accessor_name

            if custom_field.field_format == 'text'
              ::API::Decorators::Formattable.new(value)
            else
              value
            end
          }
        end

        def property_value_setter_for(custom_field)
          -> (value, *) {
            value = value['raw'] if custom_field.field_format == 'text'
            self.custom_field_values = { custom_field.id => value }
          }
        end
      end
    end
  end
end
