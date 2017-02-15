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
        module LinkValueGetter
          def self.new(custom_field, path_method)
            ->(*) do
              # we can't use the generated accessor (e.g. represented.send :custom_field_1) here,
              # because we need to generate a link even if the id does not belong to an existing
              # object (that behaviour is only required for form payloads)
              values = Methods.link_value_getter_values represented, custom_field, path_method

              if custom_field.multi_value?
                values
              else
                values.first
              end
            end
          end

          ##
          # Since the block returned by .new above is `instance_exec`'d some place else we need to refer
          # to this module in order to be able to split up the logic into methods.
          module Methods
            extend API::V3::Utilities::PathHelper

            module_function

            def link_value_getter_values(represented, custom_field, path_method)
              Array(represented.custom_value_for(custom_field)).map do |custom_value|
                if custom_value && custom_value.value.present?
                  title = link_value_title(custom_value)
                  params = link_value_params(title, custom_field, custom_value)

                  {
                    title: title,
                    href: api_v3_paths.send(path_method, params),
                  }
                else
                  { href: nil, title: nil }
                end
              end
            end

            def link_value_title(custom_value)
              if custom_value.typed_value.respond_to?(:name)
                custom_value.typed_value.name
              else
                custom_value.typed_value
              end
            end

            def link_value_params(title, custom_field, custom_value)
              if custom_field.list?
                # list custom_fields values use string objects which support and need titles
                [title, custom_value.value]
              else
                custom_value.value
              end
            end
          end
        end
      end
    end
  end
end