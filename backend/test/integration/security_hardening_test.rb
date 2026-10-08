
require "test_helper"

class SecurityHardeningTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Removido fixtures :all para evitar conflitos com arquivos ausentes
  # fixtures :all 

  setup do
    # Criamos os dados manualmente para garantir que o teste seja isolado e funcione
    @establishment_a = Establishment.create!(name: "Est A", slug: "est-a", email: "a@a.com")
    @establishment_b = Establishment.create!(name: "Est B", slug: "est-b", email: "b@b.com")
    
    @owner_a = User.create!(email: "owner@a.com", password: "password", role: "owner", confirmed_at: Time.current)
    @employee_a = User.create!(email: "emp@a.com", password: "password", role: "employee", confirmed_at: Time.current)
    
    EstablishmentMembership.create!(establishment: @establishment_a, user: @owner_a, role: 'owner')
    EstablishmentMembership.create!(establishment: @establishment_a, user: @employee_a, role: 'employee')

    @customer_b = Customer.create!(establishment: @establishment_b, name: "Cliente B", email: "b@cliente.com")
    
    # Criar um serviço para teste de agendamento
    @service_a = Service.create!(establishment: @establishment_a, name: "Corte", price: 50.0, duration_minutes: 30)
  end

  test "should not allow cross-tenant data access (Multitenancy Leakage)" do
    sign_in @owner_a
    
    # Tentando acessar um cliente do Estabelecimento B
    get "/api/admin/customers/#{@customer_b.id}"
    
    # Deve retornar 404 pois o controller filtra por @establishment.customers
    assert_response :not_found
  end

  test "should enforce financial permissions for employees" do
    # Garante que o employee não tem permissão financeira
    @employee_a.update!(can_manage_financial: false)
    sign_in @employee_a
    
    # Tentando acessar o dashboard financeiro
    get "/api/financial/dashboard"
    
    # Deve retornar 403 Forbidden (conforme implementado no ApplicationController)
    assert_response :forbidden
  end

  test "should allow financial access if employee has permission" do
    @employee_a.update!(can_manage_financial: true)
    sign_in @employee_a
    
    get "/api/financial/dashboard"
    assert_response :success
  end

  test "should prevent double-booking using pessimistic locking (Concurrency)" do
    # Simula o que o script de concorrência faz
    sign_in @owner_a
    
    params = {
      appointment: {
        customer_id: Customer.create!(establishment: @establishment_a, name: "Cli A").id,
        service_id: @service_a.id,
        employee_id: @employee_a.id,
        appointment_date: (Date.current + 1.day).to_s,
        start_time: "10:00",
        status: 'pending'
      }
    }

    # Primeiro agendamento
    post "/api/admin/appointments", params: params
    assert_response :created

    # Segundo agendamento no mesmo horário
    post "/api/admin/appointments", params: params
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Horário indisponível ou em conflito para este profissional."
  end
end
