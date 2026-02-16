class CreateOdoos < ActiveRecord::Migration[7.1]
  def change
    create_table :odoos do |t|
      t.references :account, null: false, foreign_key: true
      t.string :database_name
      t.string :odoo_name
      t.string :odoo_uid
      t.string :odoo_password
      t.string :odoo_url
      t.timestamps
    end
  end
end
