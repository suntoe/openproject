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

require 'spec_helper'

describe CustomValue::ListStrategy do
  let(:custom_field) { FactoryGirl.create :list_wp_custom_field, possible_values: ["foo", "bar"] }
  let(:custom_value) do
    double("CustomField", value: value, custom_field: custom_field, customized: customized)
  end

  let(:customized) { double('customized') }

  let(:foo_value) { custom_field.custom_options.first.id.to_s }

  describe '#typed_value' do
    subject { described_class.new(custom_value).typed_value }

    context 'value is some string' do
      let(:value) { foo_value }
      it { is_expected.to eql("foo") }
    end

    context 'value is blank' do
      let(:value) { '' }
      it { is_expected.to be_nil }
    end

    context 'value is nil' do
      let(:value) { nil }
      it { is_expected.to be_nil }
    end
  end

  describe '#validate_type_of_value' do
    subject { described_class.new(custom_value).validate_type_of_value }

    context 'value is included' do
      let(:value) { foo_value }
      it 'accepts' do
        is_expected.to be_nil
      end
    end

    context 'value is not included' do
      let(:value) { 'cat' }
      it 'rejects' do
        is_expected.to eql(:inclusion)
      end
    end
  end
end
