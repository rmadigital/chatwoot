class Api::V1::OdooController < Api::BaseController
  def index
    account_id = params[:account_id]
    Account.find(account_id)
    isAccount = Account.find(account_id).account_users.find_by(user_id: current_user.id)
    contact_id = params[:contact_id]

    unless contact_id.nil?
      contact = Contact.find(contact_id)
      if contact.sended_to_odoo?
        render json: { message: 'Contact already forwarded to Odoo' }, status: :unprocessable_entity
        return
      end
    end

    if isAccount.nil?
      render json: { message: 'Unauthorized access to account' }, status: :unauthorized
      return
    else
      list = params[:list]
      if list == 'odoo'
        odoos = Odoo.where(account_id: account_id).select(:id, :odoo_name)
        if odoos.nil?
          render json: { message: 'Odoo configuration not found for this account' }, status: :not_found
          return
        else
          render json: odoos, status: :ok
        end
      elsif list == 'contact'
        odoo_id = params[:odoo_id]
        odoo = Odoo.find(odoo_id)
        contacts = build_request_contact_list(odoo)
        response = HTTParty.post(
          odoo.odoo_url,
          body: contacts.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        if response.success?
          # ถ้าการส่งข้อมูลสำเร็จ
          render json: response.body, status: :ok
        else
          # ถ้าการส่งข้อมูลล้มเหลว
          render json: {
            message: 'Failed to forward contact'
          }, status: :unprocessable_entity
        end
      end
    end
  end

  def create
    # แปลง JSON string กลับมาเป็น Ruby Hash
    contact_id = params[:contact_id]
    odoo_id = params[:odoo_id]
    agent_id = params[:agent_id]
    comment = params[:comment]

    contact = Contact.find_by(id: contact_id || 0)
    if contact.nil?
      render json: { message: 'Contact not found' }, status: :not_found
      return
    elsif contact.sended_to_odoo?
      render json: { message: 'Contact already forwarded to Odoo' }, status: :unprocessable_entity
      return
    end

    if contact.name.empty?
      render json: { message: 'Please fill fullname' }, status: :not_found
      return
    end

    if contact.phone_number.nil?
      render json: { message: 'Please fill phone number or line' }, status: :bad_request
      return
    end

    if contact.phone_number.empty? && contact.additional_attributes['social_profiles']['line'].empty?
      render json: { message: 'Please fill phone number or line' }, status: :bad_request
      return
    end

    odoo = Odoo.find_by(id: odoo_id || 0)
    if odoo.nil?
      render json: { message: 'Odoo instance not found' }, status: :not_found
      return
    end

    body = build_request_country_id(odoo, contact.additional_attributes['country'])
    country = HTTParty.post(
      odoo.odoo_url,
      body: body.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    country_id = country['result'][0]['id'] unless country['result'].empty?
    body = build_request_create_contact(odoo, contact, agent_id, country_id, comment)

    odooContact = HTTParty.post(
      odoo.odoo_url,
      body: body.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    if odooContact.success?
      # ถ้าการส่งข้อมูลสำเร็จ
      newOdooContact = JSON.parse(odooContact.body)
      body = build_request_create_crm(odoo, contact, newOdooContact['result'], agent_id)

      crmResponse = HTTParty.post(
        odoo.odoo_url,
        body: body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      pp '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - '
      pp crmResponse.body
      pp '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - '

      contact.update_columns(sended_to_odoo: true)

      render json: {
        message: 'Contact forwarded successfully'
      }, status: :ok
    else
      # ถ้าการส่งข้อมูลล้มเหลว
      render json: {
        message: 'Failed to forward contact'
      }, status: :unprocessable_entity
    end

    # ส่ง object ที่แปลงแล้วกลับไปเพื่อยืนยัน
    # render json: { received_contact: contact_object }, status: :ok
  rescue JSON::ParserError => e
    # จัดการกรณีที่ string ที่ส่งมาไม่ใช่ JSON format ที่ถูกต้อง
    render json: {
      error: 'Invalid JSON format for contact parameter',
      message: e.message
    }, status: :bad_request
  rescue StandardError => e
    # จัดการ error อื่นๆ ที่อาจเกิดขึ้นระหว่างการส่ง request
    render json: {
      error: 'An unexpected error occurred',
      message: e.message
    }, status: :internal_server_error
  end

  private

  def build_request_create_contact(odoo_instance, contact, agent_id, country_id = nil, comment = '')
    {
      jsonrpc: '2.0',
      method: 'call',
      params: {
        service: 'object',
        method: 'execute_kw',
        args: [
          odoo_instance.database_name,
          odoo_instance.odoo_uid,
          odoo_instance.odoo_password,
          'res.partner',
          'create',
          [{
            name: contact.name,
            email: contact.email,
            phone: contact.phone_number,
            mobile: '',
            street: contact.additional_attributes['city'],
            country_id: country_id,
            user_id: agent_id,
            comment: 'comment : ' + (comment || '-') + '<br/>Line ID : ' + (contact.additional_attributes['social_profiles']['line'].to_s || '-')
          }]
        ]
      }
    }
  end

  def build_request_create_crm(odoo_instance, contact, _partner_id, agent_id)
    {
      jsonrpc: '2.0',
      method: 'call',
      params: {
        service: 'object',
        method: 'execute_kw',
        args: [
          odoo_instance.database_name,
          odoo_instance.odoo_uid,
          odoo_instance.odoo_password,
          'crm.lead',
          'create',
          [
            {
              name: contact.name,
              partner_id: contact.id,
              email_from: contact.email,
              phone: contact.phone_number,
              user_id: agent_id,
              type: 'opportunity'
            }
          ]
        ]
      }
    }
  end

  def build_request_contact_list(odoo_instance)
    {
      jsonrpc: '2.0',
      method: 'call',
      params: {
        service: 'object',
        method: 'execute_kw',
        args: [
          odoo_instance.database_name,
          odoo_instance.odoo_uid,
          odoo_instance.odoo_password,
          'res.users',
          'search_read',
          [[['employee_ids', '!=', false]]],
          { fields: %w[id name] }
        ]
      }
    }
  end

  def build_request_country_id(odoo_instance, country_name)
    {
      jsonrpc: '2.0',
      method: 'call',
      params: {
        service: 'object',
        method: 'execute_kw',
        args: [
          odoo_instance.database_name,
          odoo_instance.odoo_uid,
          odoo_instance.odoo_password,
          'res.country',
          'search_read',
          [[['name', 'ilike', country_name]]],
          { fields: %w[id name] }
        ]
      }
    }
  end
end
