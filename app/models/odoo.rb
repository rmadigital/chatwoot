class Odoo < ApplicationRecord
  belongs_to :account

  encrypts :odoo_password
end
