class RemovePasswordDigestFromOdoo < ActiveRecord::Migration[7.0]
  def change
    remove_column :odoos, :password_digest, :string
  end
end
