class AddSendedToOdooToContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :contacts, :sended_to_odoo, :boolean, default: false, null: false
  end
end
