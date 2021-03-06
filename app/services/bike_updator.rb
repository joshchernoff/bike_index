class UserNotLoggedInError < StandardError
end

class BikeUpdatorError < StandardError
end

class BikeUpdator
  def initialize(creation_params = {})
    @user = creation_params[:user]
    @bike_params = creation_params[:b_params]
    @bike = creation_params[:bike] || find_bike
    @current_ownership = creation_params[:current_ownership]
    @currently_stolen = @bike.stolen
  end

  def find_bike
    Bike.unscoped.find(@bike_params["id"])
  rescue
    raise BikeUpdatorError, "Oh no! We couldn't find that bike"
  end

  def update_ownership
    # Because this is a mess, managed independently in ImpoundUpdateBikeWorker
    @bike.update_attribute :updator_id, @user.id if @user.present? && @bike.updator_id != @user.id
    new_owner_email = EmailNormalizer.normalize(@bike_params["bike"].delete("owner_email"))
    return false if new_owner_email.blank? || @bike.owner_email == new_owner_email
    # Since we've deleted the owner_email from the update hash, we have to assign it here
    # This is required because ownership_creator uses it :/ - not a big fan of this side effect though
    @bike.owner_email = new_owner_email
    # This is what we should've been doing a long time ago - we should migrate send_email to skip_email everywhere :/
    skip_email = ParamsNormalizer.boolean(@bike_params.dig("bike", "skip_email"))
    OwnershipCreator.new(owner_email: new_owner_email,
                         bike: @bike,
                         creator: @user,
                         send_email: !skip_email).create_ownership
    # If the bike is a unregistered_parking_notification, switch to being a normal bike, since it's been sent to a new owner
    @bike.update(status: "status_with_owner", marked_user_unhidden: true) if @bike.unregistered_parking_notification?
    @bike_params["bike"]["is_for_sale"] = false # Because, it's been given to a new owner
    @bike_params["bike"]["address_set_manually"] = false # Because we don't want the old owner address
  end

  def ensure_ownership!
    return true if @current_ownership && @current_ownership.owner == @user # So we can pass in ownership and skip query
    return true if @bike.authorized?(@user)
    raise BikeUpdatorError, "Oh no! It looks like you don't own that bike."
  end

  def update_api_components
    ComponentCreator.new(bike: @bike, b_param: @bike_params).update_components_from_params
  end

  def update_stolen_record
    @bike.reload
    if @bike_params["bike"] && @bike_params["bike"]["date_stolen"]
      StolenRecordUpdator.new(bike: @bike, date_stolen: @bike_params["bike"]["date_stolen"]).update_records
    elsif @bike_params["stolen_record"] || @bike_params["bike"]["stolen_records_attributes"]
      StolenRecordUpdator.new(bike: @bike, b_param: @bike_params).update_records
      @bike.reload
    elsif @currently_stolen != @bike.stolen
      StolenRecordUpdator.new(bike: @bike).update_records
    end
  end

  def set_protected_attributes
    @bike_params["bike"]["serial_number"] = @bike.serial_number
    @bike_params["bike"]["manufacturer_id"] = @bike.manufacturer_id
    @bike_params["bike"]["manufacturer_other"] = @bike.manufacturer_other
    @bike_params["bike"]["creation_organization_id"] = @bike.creation_organization_id
    @bike_params["bike"]["creator"] = @bike.creator
    @bike_params["bike"]["example"] = @bike.example
    @bike_params["bike"]["hidden"] = @bike.hidden
  end

  def remove_blank_components
    return false unless @bike.components.any?
    @bike.components.each do |c|
      c.destroy unless c.ctype_id.present? || c.description.present?
    end
  end

  def update_available_attributes
    ensure_ownership!
    set_protected_attributes
    update_ownership
    update_api_components if @bike_params["components"].present?
    update_attrs = @bike_params["bike"].except("stolen_records_attributes")
    if update_attrs.slice("street", "city", "zipcode").values.reject(&:blank?).any?
      @bike.address_set_manually = true
    end
    if @bike.update_attributes(update_attrs)
      update_stolen_record
    end
    AfterBikeSaveWorker.perform_async(@bike.id) if @bike.present? # run immediately
    remove_blank_components
    @bike
  end
end
