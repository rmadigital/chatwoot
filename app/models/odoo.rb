# == Schema Information
#
# Table name: odoos
#
#  id            :bigint           not null, primary key
#  database_name :string
#  odoo_name     :string
#  odoo_password :string
#  odoo_uid      :string
#  odoo_url      :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_odoos_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Odoo < ApplicationRecord
  belongs_to :account

  encrypts :odoo_password
end
