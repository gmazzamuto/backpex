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
  end

  preparations do
    prepare fn query, _context ->
      Ash.Query.deselect(query, :generated_tsvector)
    end
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
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
