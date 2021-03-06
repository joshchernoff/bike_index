class StolenRecordError < StandardError
end

class StolenRecordUpdator
  def initialize(creation_params = {})
    @bike = creation_params[:bike]
    @date_stolen = TimeParser.parse(creation_params[:date_stolen])
    @user = creation_params[:user]
    @b_param = creation_params[:b_param]
  end

  def mark_records_not_current
    stolen_records = StolenRecord.unscoped.where(bike_id: @bike.id)
    if stolen_records.any?
      stolen_records.each do |s|
        s.current = false
        s.save
      end
    end
    @bike.reload.update_attribute :current_stolen_record_id, nil
  end

  def update_records
    if @bike.stolen
      if @bike.fetch_current_stolen_record.blank?
        create_new_record
        @bike.reload
      elsif @date_stolen
        stolen_record = @bike.fetch_current_stolen_record
        stolen_record.update_attributes(date_stolen: @date_stolen)
      elsif @b_param && (@b_param["stolen_record"] || @b_param["bike"]["stolen_records_attributes"])
        stolen_record = @bike.fetch_current_stolen_record
        update_with_params(stolen_record).save
      end
    else
      @bike.update_attributes(abandoned: false) if @bike.abandoned == true
      mark_records_not_current
    end
  end

  def update_with_params(stolen_record)
    return stolen_record unless @b_param.present?

    sr = @b_param["stolen_record"]
    nested_params = @b_param.dig("bike", "stolen_records_attributes")
    sr = nested_params.values.reject(&:blank?).last if nested_params&.values&.first&.is_a?(Hash)
    return stolen_record unless sr.present?
    stolen_record.attributes = permitted_attributes(sr)

    stolen_record.date_stolen = TimeParser.parse(sr["date_stolen"], sr["timezone"]) || Time.current unless @date_stolen.present?

    if sr["country"].present?
      stolen_record.country = Country.fuzzy_find(sr["country"])
    end

    stolen_record.state_id = State.fuzzy_abbr_find(sr["state"])&.id if sr["state"].present?
    if sr["phone_no_show"]
      stolen_record.attributes = {
        phone_for_everyone: false,
        phone_for_users: false,
        phone_for_shops: false,
        phone_for_police: false
      }
    end
    stolen_record
  end

  def create_new_record
    mark_records_not_current
    new_stolen_record = StolenRecord.new(bike: @bike, current: true, date_stolen: @date_stolen || Time.current)
    new_stolen_record.phone = @bike.phone
    new_stolen_record.country_id = Country.united_states&.id
    stolen_record = update_with_params(new_stolen_record)
    stolen_record.creation_organization_id = @bike.creation_organization_id
    if stolen_record.save
      @bike.reload.update_attribute :current_stolen_record_id, stolen_record.id
      return true
    end
    raise StolenRecordError, "Awww shucks! We failed to mark this bike as stolen. Try again?"
  end

  def permitted_attributes(params)
    ActionController::Parameters.new(params).permit(*permitted_params)
  end

  private

  def permitted_params
    %w[phone secondary_phone street city zipcode country_id state_id
      police_report_number police_report_department estimated_value
      theft_description locking_description lock_defeat_description
      proof_of_ownership receive_notifications show_address]
  end
end
