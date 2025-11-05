defmodule Demo.Helpdesk.Ticket do
  @moduledoc false

  use Ash.Resource,
    domain: Demo.Helpdesk,
    data_layer: AshPostgres.DataLayer

  @status_options [:open, :closed]

  def status_options, do: @status_options

  postgres do
    repo Demo.Repo
    table "tickets"
  end

  actions do
    defaults [:read, :destroy]
    default_accept :*

    create :create do
      primary? true
      argument :contact_details, {:array, :map}, allow_nil?: true
      change manage_relationship(:contact_details, type: :direct_control)
    end

    update :update do
      accept :*
      primary? true
      require_atomic? false

      argument :contact_details, {:array, :map}, allow_nil?: true
      change manage_relationship(:contact_details, type: :direct_control)
    end
  end

  preparations do
    prepare fn query, _context ->
      Ash.Query.deselect(query, :generated_tsvector)
    end

    prepare build(load: [:contact_details])
  end

  changes do
    change manage_relationship(:contact_details, type: :direct_control)
  end

  attributes do
    uuid_primary_key :id
    attribute :generated_tsvector, AshPostgres.Tsvector
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true

    attribute :status, :atom do
      constraints one_of: @status_options

      default :open

      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    has_many :contact_details, Demo.Helpdesk.ContactDetails, public?: true
  end
end
