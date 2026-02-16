class Odoo < ApplicationRecord
  belongs_to :account

  has_secure_password

  encrypts :odoo_password
end
