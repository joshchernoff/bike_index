class CreateOwnershipClaims < ActiveRecord::Migration[5.2]
  def change
    create_table :ownership_claims do |t|
      t.references :impound_record, index: true
      t.references :stolen_record, index: true
      t.references :user, index: true

      t.text :message
      t.json :data

      t.integer :status
      t.datetime :submitted_at

      t.timestamps
    end

    # add_column :public_images, :kind, :integer, default: 0
  end
end