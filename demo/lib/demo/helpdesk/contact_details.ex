defmodule Demo.Helpdesk.ContactDetails do
  use Ash.Resource,
    domain: Demo.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "contact_details"
    repo Demo.Repo

    references do
      reference :ticket, on_delete: :delete
    end
  end

  actions do
    defaults [:create, :read, :destroy]
    default_accept :*

    update :update do
      accept :*
      primary? true
      require_atomic? false
    end
  end

  validations do
    validate present([:name])
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
    attribute :phone, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :ticket, Demo.Helpdesk.Ticket, public?: true, allow_nil?: false
  end
end
