class ComponentSerializer < ActiveModel::Serializer
  attributes :description,
    :serial_number,
    :component_type,
    :component_group,
    :rear,
    :front,
    :manufacturer_name,
    :manufacturer_id,
    :model_name,
    :year
end
